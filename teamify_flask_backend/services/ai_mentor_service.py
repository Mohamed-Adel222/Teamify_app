"""
AI Mentor Service
=================
Generates career progression and mentoring reports for a user.

Adapts the ai_mentor_csv.py pipeline from ml_models/ to read live data
from the SQLAlchemy ORM instead of per-user CSV files. Course ranking
uses the model's recommend_courses() against ml_models/data/courses.csv.

  Layer 1 — Rule-based career scoring and weakness/strength detection
  Layer 2 — Simple sentiment analysis on feedback text
  Layer 3 — Career report generation (Claude API if key set, else fallback)
  Extra   — Course recommendations based on skill gaps

Also attempts to load Profiles&AI Rating/teamify_model.pkl for a
GradientBoosting-based rating prediction. Falls back to formula if
the model is unavailable.
"""
from __future__ import annotations

import csv
import importlib.util
import logging
import os
import time
from collections import defaultdict
from datetime import date, datetime, timezone
from typing import Any, Optional

logger = logging.getLogger(__name__)

from utils.skills import normalize_skills_list

_ML_MODELS_DIR = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "ml_models")
)
_MENTOR_MODULE_FILE = os.path.join(_ML_MODELS_DIR, "ai_mentor_csv.py")
_COURSES_CSV = os.path.join(_ML_MODELS_DIR, "data", "courses.csv")
_RATING_MODEL_PATH = os.path.abspath(
    os.path.join(_ML_MODELS_DIR, "Profiles&AI Rating", "teamify_model.pkl")
)

_REPORT_CACHE: dict[int, tuple[float, dict]] = {}
_REPORT_TTL_SECONDS = 600
_mentor_csv_mod: Any = None
_course_catalog_cache: dict[str, dict] | None = None
_course_catalog_error: str | None = None


def invalidate_mentor_cache(user_id: int | None = None) -> None:
    """Drop cached mentor report(s) after profile-affecting writes."""
    if user_id is None:
        _REPORT_CACHE.clear()
        return
    _REPORT_CACHE.pop(int(user_id), None)


# ── Career scoring constants (mirror ai_mentor_csv.py) ────────────────────────

THRESHOLDS = {
    "commitment": {"warn": 75, "danger": 60},
    "teamwork":   {"warn": 70, "danger": 55},
    "quality":    {"warn": 75, "danger": 58},
}

ROLE_REQUIREMENTS = {
    "Junior Developer":    {"skills": ["Python", "Git", "SQL", "HTML/CSS", "REST APIs"],               "min_prof": 2},
    "Mid-level Developer": {"skills": ["React", "FastAPI", "Docker", "TypeScript", "PostgreSQL", "Unit Testing"], "min_prof": 3},
    "Senior Developer":    {"skills": ["System Design", "AWS", "GraphQL", "CI/CD", "Code Review", "Microservices"], "min_prof": 3},
    "Tech Lead":           {"skills": ["Architecture", "Team Management", "OKRs", "Product Thinking", "Stakeholder Communication"], "min_prof": 3},
}

LEVEL_NEXT = {
    "Junior Developer":    "Mid-level Developer",
    "Mid-level Developer": "Senior Developer",
    "Senior Developer":    "Tech Lead",
    "Tech Lead":           "Tech Lead",
}

# Profile experience_level (Beginner/Intermediate/Expert) → career ladder
_PROFILE_LEVEL_MAP: dict[str, str] = {
    "beginner": "Junior Developer",
    "intermediate": "Mid-level Developer",
    "expert": "Senior Developer",
    "junior": "Junior Developer",
    "mid-level": "Mid-level Developer",
    "mid level": "Mid-level Developer",
    "senior": "Senior Developer",
    "lead": "Tech Lead",
    "tech lead": "Tech Lead",
}


def _resolve_career_level(user, computed_level: str) -> str:
    """Prefer stored profile level when it maps to the career ladder."""
    for raw in (
        getattr(user, "experience_level", None),
        getattr(user, "professional_field", None),
    ):
        if not raw:
            continue
        key = str(raw).strip().lower()
        if key in _PROFILE_LEVEL_MAP:
            return _PROFILE_LEVEL_MAP[key]
        if raw in LEVEL_NEXT or raw in ROLE_REQUIREMENTS:
            return str(raw)
    return computed_level


def _build_db_career_summary(
    user,
    scores: dict,
    gaps: dict,
    perf_snapshot: dict,
    tasks: list,
) -> str:
    """Plain-language summary built only from live DB fields (no static copy)."""
    name = user.display_name or getattr(user, "username", None) or "You"
    level = scores.get("level", "Developer")
    total = scores.get("total_score", 0)
    done = len([t for t in tasks if getattr(t, "status", None) == "done"])
    assigned = len(tasks)
    fb = int(perf_snapshot.get("feedback_count") or 0)
    rat = int(perf_snapshot.get("rating_count") or 0)
    target = gaps.get("target_role") or "your next role"
    missing = gaps.get("missing_skills") or []
    owned = gaps.get("owned_skills") or []
    profile_skills = normalize_skills_list(user.skills)

    lines = [
        f"{name} is currently a {level} with an overall career score of {total}%.",
        f"From your Teamify records: {done} of {assigned} assigned tasks completed, "
        f"{fb} peer feedback entries, and {rat} ratings.",
    ]
    if profile_skills:
        lines.append(
            f"Profile skills ({len(profile_skills)}): {', '.join(profile_skills[:8])}"
            + ("…" if len(profile_skills) > 8 else "")
            + "."
        )
    if owned:
        lines.append(
            f"Already aligned for {target}: {', '.join(owned[:5])}."
        )
    if missing:
        lines.append(
            f"Priority gaps for {target}: {', '.join(missing[:5])}."
        )
    else:
        lines.append(f"Next target role: {target}.")
    return " ".join(lines)

SKILL_DEMAND = {
    "System Design": 0.95, "Python": 0.92, "AWS": 0.90, "Docker": 0.88,
    "React": 0.87, "TypeScript": 0.85, "SQL": 0.82, "GraphQL": 0.80,
    "REST APIs": 0.80, "FastAPI": 0.78, "PostgreSQL": 0.75, "CI/CD": 0.88,
    "Git": 0.70, "Microservices": 0.93, "Unit Testing": 0.78,
}

def _course_enroll_url(platform: str, title: str) -> str:
    from urllib.parse import quote_plus

    q = quote_plus(title)
    platform_l = (platform or "").lower()
    if "coursera" in platform_l:
        return f"https://www.coursera.org/search?query={q}"
    if "udemy" in platform_l:
        return f"https://www.udemy.com/courses/search/?q={q}"
    if "cloud guru" in platform_l or "acloud" in platform_l:
        return f"https://learn.acloud.guru/catalog?query={q}"
    if "youtube" in platform_l:
        return f"https://www.youtube.com/results?search_query={q}"
    if "pluralsight" in platform_l:
        return f"https://www.pluralsight.com/search?q={q}"
    if "frontend masters" in platform_l:
        return f"https://frontendmasters.com/search/?q={q}"
    return f"https://www.google.com/search?q={q}+online+course"


def _load_mentor_csv_module():
    """Import ml_models/ai_mentor_csv.py (the career-mentor model)."""
    global _mentor_csv_mod
    if _mentor_csv_mod is not None:
        return _mentor_csv_mod
    if not os.path.isfile(_MENTOR_MODULE_FILE):
        raise FileNotFoundError(_MENTOR_MODULE_FILE)
    spec = importlib.util.spec_from_file_location(
        "teamify_ai_mentor_csv", _MENTOR_MODULE_FILE
    )
    if spec is None or spec.loader is None:
        raise ImportError("Cannot load ai_mentor_csv.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    _mentor_csv_mod = module
    return module


def _load_course_catalog() -> tuple[dict[str, dict], str]:
    """Load the mentor model's courses.csv; fall back to the built-in list."""
    global _course_catalog_cache, _course_catalog_error
    if _course_catalog_cache is not None:
        source = "mentor_model" if not _course_catalog_error else "fallback_catalog"
        return _course_catalog_cache, source

    catalog: dict[str, dict] = {}
    if os.path.isfile(_COURSES_CSV):
        try:
            with open(_COURSES_CSV, encoding="utf-8") as fh:
                for row in csv.DictReader(fh):
                    cid = (row.get("course_id") or row.get("id") or "").strip()
                    if not cid:
                        continue
                    catalog[cid] = {
                        "id": cid,
                        "course_id": cid,
                        "title": row.get("title") or "",
                        "platform": row.get("platform") or "",
                        "skills_covered": row.get("skills_covered") or "",
                        "rating": row.get("rating") or "0",
                        "market_demand": row.get("market_demand") or "0",
                        "duration_hrs": row.get("duration_hrs") or "0",
                        "level": row.get("level") or "Recommended",
                    }
            if catalog:
                _course_catalog_cache = catalog
                _course_catalog_error = None
                logger.info(
                    "Mentor course catalog loaded from %s (%d courses)",
                    _COURSES_CSV,
                    len(catalog),
                )
                return catalog, "mentor_model"
        except Exception as exc:
            _course_catalog_error = str(exc)
            logger.warning("Failed to load mentor courses.csv: %s", exc)

    _course_catalog_error = _course_catalog_error or "courses.csv missing or empty"
    catalog = {
        c["id"]: {
            "id": c["id"],
            "course_id": c["id"],
            "title": c["title"],
            "platform": c["platform"],
            "skills_covered": c["skills_covered"],
            "rating": c["rating"],
            "market_demand": c["market_demand"],
            "duration_hrs": c["duration_hrs"],
            "level": "Recommended",
        }
        for c in COURSE_CATALOG
    }
    _course_catalog_cache = catalog
    return catalog, "fallback_catalog"


def get_mentor_model_status() -> dict:
    """Runtime status of the AI mentor pipeline (no user/DB writes)."""
    module_ok = os.path.isfile(_MENTOR_MODULE_FILE)
    csv_ok = os.path.isfile(_COURSES_CSV)
    catalog, source = _load_course_catalog()
    loaded = False
    inference_ok = False
    error: str | None = None
    try:
        _load_mentor_csv_module()
        loaded = module_ok and bool(catalog)
        sample_gaps = {
            "missing_skills": ["System Design", "AWS", "Docker"],
            "target_role": "Senior Developer",
        }
        recs = _recommend_courses(sample_gaps, top_n=3)
        inference_ok = bool(recs) and source == "mentor_model"
        if not recs:
            error = "Mentor catalog produced no course matches for sample gaps"
    except Exception as exc:
        error = str(exc)
        loaded = False
        inference_ok = False

    real = bool(module_ok and csv_ok and loaded and inference_ok)
    return {
        "id": "ai_mentor",
        "name": "AI Career Mentor",
        "file_exists": module_ok and csv_ok,
        "file_present": module_ok and csv_ok,
        "path": os.path.relpath(_MENTOR_MODULE_FILE, os.path.join(_ML_MODELS_DIR, "..")),
        "catalog_path": os.path.relpath(_COURSES_CSV, os.path.join(_ML_MODELS_DIR, "..")),
        "catalog_size": len(catalog),
        "catalog_source": source,
        "loaded": loaded,
        "inference_test": inference_ok,
        "mode": "REAL_MODEL" if real else "FALLBACK",
        "status": "loaded" if real else "fallback",
        "error": error,
        "endpoint": "GET /api/ai/mentor/insights/<user_id>",
    }


COURSE_CATALOG = [
    {"id": "system-design-dev", "title": "System Design for Developers",  "platform": "Coursera",    "skills_covered": "Microservices|System Design", "rating": "4.8", "duration_hrs": "24", "market_demand": 0.95},
    {"id": "microservices-arch", "title": "Microservices Architecture",    "platform": "Coursera",    "skills_covered": "AWS|Microservices",           "rating": "4.8", "duration_hrs": "35", "market_demand": 0.93},
    {"id": "aws-certified-dev", "title": "AWS Certified Developer",       "platform": "A Cloud Guru","skills_covered": "CI/CD|AWS",                  "rating": "4.7", "duration_hrs": "40", "market_demand": 0.90},
    {"id": "docker-k8s", "title": "Docker & Kubernetes Mastery",   "platform": "Udemy",       "skills_covered": "CI/CD|Docker",               "rating": "4.6", "duration_hrs": "20", "market_demand": 0.88},
    {"id": "cicd-gha", "title": "CI/CD with GitHub Actions",     "platform": "A Cloud Guru","skills_covered": "CI/CD",                      "rating": "4.6", "duration_hrs": "15", "market_demand": 0.88},
    {"id": "react-complete", "title": "React - The Complete Guide",    "platform": "Udemy",       "skills_covered": "React|TypeScript",           "rating": "4.7", "duration_hrs": "45", "market_demand": 0.87},
    {"id": "fastapi-full", "title": "FastAPI Full Course",           "platform": "YouTube",     "skills_covered": "FastAPI|REST APIs",          "rating": "4.5", "duration_hrs": "10", "market_demand": 0.78},
    {"id": "postgres-tuning", "title": "PostgreSQL Performance Tuning", "platform": "Pluralsight", "skills_covered": "PostgreSQL|SQL",             "rating": "4.4", "duration_hrs": "12", "market_demand": 0.75},
    {"id": "pytest", "title": "Python Testing with pytest",    "platform": "Pragmatic",   "skills_covered": "Unit Testing",               "rating": "4.5", "duration_hrs": "8",  "market_demand": 0.78},
    {"id": "graphql-prod", "title": "GraphQL in Production",         "platform": "Frontend Masters", "skills_covered": "GraphQL",              "rating": "4.6", "duration_hrs": "6",  "market_demand": 0.80},
]

POS_WORDS = {"great", "excellent", "good", "reliable", "delivers", "communicates",
             "helpful", "strong", "clean", "positive", "proactive", "responsive"}
NEG_WORDS = {"poor", "missing", "needs", "improvement", "incomplete", "rushed",
             "lacks", "weak", "inconsistent", "issues", "problems", "delay"}


# ── Layer 1: Rule-based scoring ────────────────────────────────────────────────

def _compute_career_score(user, tasks, feedback_sentiment: float = 0.5) -> dict:
    skills = normalize_skills_list(user.skills)
    skill_score = (sum(3 for _ in skills) / max(len(skills) * 5, 1)) * 100 if skills else 0.0

    all_tasks = tasks
    done = [t for t in all_tasks if t.status == "done"]
    proj_score = (len(done) / max(len(all_tasks), 1)) * 100

    on_time = (user.member_on_time_rate or 0.75) * 100
    quality = (user.quality_score if hasattr(user, "quality_score") else 0.75) * 100
    teamwork = (user.teamwork_score if hasattr(user, "teamwork_score") else 0.75) * 100
    perf_score = (on_time + quality + teamwork) / 3

    course_score = 0.0  # no course data in ORM yet
    sent_score = feedback_sentiment * 100

    total = (
        skill_score  * 0.30
        + perf_score * 0.25
        + proj_score * 0.20
        + course_score * 0.15
        + sent_score * 0.10
    )

    level = (
        "Junior Developer"    if total < 26 else
        "Mid-level Developer" if total < 51 else
        "Senior Developer"    if total < 76 else
        "Tech Lead"
    )

    return {
        "total_score": round(total, 1),
        "level": level,
        "breakdown": {
            "skill_mastery":   round(skill_score,  1),
            "performance_avg": round(perf_score,   1),
            "project_rate":    round(proj_score,   1),
            "course_score":    round(course_score, 1),
            "sentiment_score": round(sent_score,   1),
        },
    }


def _detect_weaknesses(user, perf_scores: Optional[dict] = None) -> list:
    perf = perf_scores or {
        "commitment": (user.member_on_time_rate or 0.75) * 100,
        "teamwork":   (user.teamwork_score if hasattr(user, "teamwork_score") else 0.75) * 100,
        "quality":    (user.quality_score if hasattr(user, "quality_score") else 0.75) * 100,
    }
    results = []
    for metric, bounds in THRESHOLDS.items():
        score = perf.get(metric, 75.0)
        if score < bounds["danger"]:
            sev = "high"
        elif score < bounds["warn"]:
            sev = "medium"
        else:
            continue
        results.append({
            "area": metric,
            "score": round(score, 1),
            "severity": sev,
            "message": f"{metric.capitalize()} is {score:.1f}/100 — below threshold of {bounds['warn']}.",
        })
    return sorted(results, key=lambda x: 0 if x["severity"] == "high" else 1)


def _detect_strengths(user, perf_scores: Optional[dict] = None) -> list:
    base = perf_scores or {
        "commitment": (user.member_on_time_rate or 0.75) * 100,
        "quality":    (user.quality_score if hasattr(user, "quality_score") else 0.75) * 100,
    }
    perf = {
        "commitment": base.get("commitment", 75),
        "quality": base.get("quality", 75),
        "teamwork": base.get("teamwork", 75),
    }
    strengths = []
    for m, score in perf.items():
        if score >= 85:
            strengths.append({
                "area": m,
                "score": round(score, 1),
                "message": f"{m.capitalize()} is well above average.",
            })
    return strengths


def _detect_skill_gaps(user, career_level: Optional[str] = None) -> dict:
    if not career_level:
        career_level = (
            getattr(user, "career_level", None)
            or user.experience_level
            or "Junior Developer"
        )
    career_level = _resolve_career_level(user, str(career_level))
    target = LEVEL_NEXT.get(career_level, "Senior Developer")
    req = ROLE_REQUIREMENTS.get(target, {})
    required = set(req.get("skills", []))
    user_skills = set(normalize_skills_list(user.skills))
    owned = user_skills & required
    missing = sorted(required - owned, key=lambda s: SKILL_DEMAND.get(s, 0.5), reverse=True)
    gap_pct = round(len(missing) / max(len(required), 1) * 100, 1)

    skill_details: list[dict[str, Any]] = []
    n_miss = max(len(missing), 1)
    for i, skill in enumerate(missing):
        demand = SKILL_DEMAND.get(skill, 0.5)
        priority = round(min(98, 55 + demand * 43 - i * (40 / n_miss)), 1)
        skill_details.append({
            "name": skill,
            "owned": False,
            "gap_score": priority,
            "market_demand": round(demand * 100, 1),
            "severity": "high" if i == 0 else "medium",
            "message": f"Required for {target}",
        })
    for skill in sorted(owned):
        demand = SKILL_DEMAND.get(skill, 0.5)
        skill_details.append({
            "name": skill,
            "owned": True,
            "gap_score": 100.0,
            "market_demand": round(demand * 100, 1),
            "severity": "owned",
            "message": "Listed on your profile",
        })

    return {
        "target_role":     target,
        "current_level":   career_level,
        "required_skills": sorted(required),
        "owned_skills":    sorted(owned),
        "missing_skills":  missing,
        "skill_details":   skill_details,
        "gap_pct":         gap_pct,
        "priority_skill":  missing[0] if missing else None,
    }


# ── Layer 2: Sentiment analysis ────────────────────────────────────────────────

def _analyse_feedback(feedback_rows) -> dict:
    if not feedback_rows:
        return {"avg_sentiment_score": 0.5, "sentiment_label": "neutral",
                "top_keywords": [], "feedback_count": 0}

    scores = []
    for row in feedback_rows:
        text = (
            getattr(row, "feedback_text", None)
            or getattr(row, "comment", None)
            or getattr(row, "text", None)
            or ""
        ).lower()
        sentiment = getattr(row, "sentiment", None)
        if sentiment == "positive":
            scores.append(0.85)
        elif sentiment == "negative":
            scores.append(0.25)
        else:
            pos = sum(1 for w in POS_WORDS if w in text)
            neg = sum(1 for w in NEG_WORDS if w in text)
            total = pos + neg
            scores.append((pos / total) if total > 0 else 0.5)

    avg = round(sum(scores) / len(scores), 3)
    label = "positive" if avg > 0.6 else "negative" if avg < 0.4 else "neutral"

    career_kw = ["delivery", "communication", "teamwork", "code quality",
                 "documentation", "testing", "reliability", "leadership"]
    word_freq: dict = defaultdict(int)
    for row in feedback_rows:
        text = (
            getattr(row, "feedback_text", None)
            or getattr(row, "comment", None)
            or getattr(row, "text", None)
            or ""
        ).lower()
        for kw in career_kw:
            if kw in text:
                word_freq[kw] += 1
    top_kw = sorted(word_freq, key=word_freq.get, reverse=True)[:4]

    return {
        "avg_sentiment_score": avg,
        "sentiment_label": label,
        "top_keywords": top_kw,
        "feedback_count": len(feedback_rows),
    }


# ── Layer 3: Report generation ─────────────────────────────────────────────────

def _generate_report(user, scores, weaknesses, strengths, nlp, gaps, tasks=None) -> str:
    api_key = os.getenv("ANTHROPIC_API_KEY", "")
    name = user.display_name or (user.full_name or "").split()[0] or "User"
    tasks = tasks or []

    task_lines = []
    for t in tasks[:5]:
        title = getattr(t, "title", "Task")
        status = getattr(t, "status", "unknown")
        task_lines.append(f"- {title} ({status})")
    task_history = "\n".join(task_lines) if task_lines else "No recent tasks on record."

    project_domains: set[str] = set()
    try:
        from models.project import Project

        for t in tasks[:8]:
            pid = getattr(t, "project_id", None)
            if not pid:
                continue
            proj = Project.query.get(pid)
            category = getattr(proj, "category", None) if proj else None
            if category:
                project_domains.add(str(category))
    except Exception:
        pass
    domains_text = ", ".join(sorted(project_domains)) if project_domains else "Not specified"

    on_time_pct = round((user.member_on_time_rate or 0.75) * 100, 1)

    if api_key:
        try:
            import anthropic
            client = anthropic.Anthropic(api_key=api_key)
            system = (
                "You are an expert AI career mentor for tech freelancers. "
                "Given structured career data, write a concise report as JSON with keys: "
                "career_summary, strengths, areas_to_improve, next_step. "
                "Each list field should contain short strings. "
                "Use the user's first name. Mention at least 2 scores. Under 250 words total."
            )
            prompt = (
                f"Name: {name} | Level: {scores['level']} | Target: {gaps['target_role']}\n"
                f"Career Score: {scores['total_score']}%\n"
                f"On-time delivery rate: {on_time_pct}%\n"
                f"Recent tasks:\n{task_history}\n"
                f"Project domains: {domains_text}\n"
                f"Weaknesses: {[w['area'] + ' (' + str(w['score']) + ')' for w in weaknesses]}\n"
                f"Strengths: {[s['area'] + ' (' + str(s['score']) + ')' for s in strengths]}\n"
                f"Missing skills: {gaps['missing_skills']}\n"
                f"Feedback sentiment: {nlp['sentiment_label']} | Themes: {nlp['top_keywords']}\n"
            )
            r = client.messages.create(
                model="claude-sonnet-4-20250514",
                max_tokens=600,
                temperature=0.3,
                system=system,
                messages=[{"role": "user", "content": prompt}],
            )
            text = r.content[0].text.strip()
            if text.startswith("{"):
                import json
                try:
                    data = json.loads(text)
                    sections = []
                    if data.get("career_summary"):
                        sections.append(f"## Career Summary\n{data['career_summary']}")
                    if data.get("strengths"):
                        bullets = "\n".join(f"- {s}" for s in data["strengths"])
                        sections.append(f"## Strengths\n{bullets}")
                    if data.get("areas_to_improve"):
                        bullets = "\n".join(f"- {a}" for a in data["areas_to_improve"])
                        sections.append(f"## Areas to Improve\n{bullets}")
                    if data.get("next_step"):
                        sections.append(f"## Your Next Step\n{data['next_step']}")
                    if sections:
                        return "\n\n".join(sections)
                except json.JSONDecodeError:
                    pass
            return text
        except Exception as e:
            logger.warning("Claude API error in mentor report: %s — using fallback.", e)

    # Built-in fallback report
    total = scores["total_score"]
    target = gaps["target_role"]
    pri = gaps["priority_skill"] or "a key skill"
    s_list = "\n".join(
        f"- {s['area'].capitalize()}: {s['score']}/100"
        for s in strengths
    ) or "- Consistent project delivery"
    w_list = "\n".join(
        f"- {w['area'].capitalize()}: {w['score']}/100 — {w['severity']} priority"
        for w in weaknesses
    ) or "- Continue monitoring all areas"
    missing = ", ".join(gaps["missing_skills"][:3]) or "N/A"

    return (
        f"## Career Summary\n"
        f"{name} is currently a {scores['level']} with an overall career score of {total}%.\n"
        f"{'Strong collaboration scores reflect reliable team contribution.' if total > 55 else 'There is meaningful room for growth across several areas.'}\n"
        f"The next target role is {target}.\n\n"
        f"## Strengths\n{s_list}\n\n"
        f"## Areas to Improve\n{w_list}\n"
        f"- Skill gaps for {target}: {missing}\n\n"
        f"## Your Next Step\n"
        f"Prioritise learning **{pri}** — it is the highest-demand missing skill\n"
        f"for the {target} role. Enroll in a structured course this week and\n"
        f"apply it in a real side project to build verifiable experience.\n"
    )


# ── Course recommendations ─────────────────────────────────────────────────────

def _recommend_courses(gaps, top_n=5) -> list:
    """Score courses with the mentor model (ai_mentor_csv.recommend_courses)."""
    catalog, source = _load_course_catalog()
    recs: list[dict] = []
    try:
        mod = _load_mentor_csv_module()
        raw = mod.recommend_courses(gaps, catalog, top_n=top_n)
        recs = list(raw or [])
    except Exception as exc:
        logger.warning("ai_mentor_csv.recommend_courses failed: %s", exc)

    if not recs:
        recs = _heuristic_course_recs(gaps, catalog, top_n)

    enriched = []
    for c in recs:
        title = c.get("title") or ""
        platform = c.get("platform") or ""
        hours = str(c.get("hours") or c.get("duration_hrs") or "")
        relevance = float(c.get("relevance") or 0)
        enriched.append({
            **c,
            "id": c.get("id") or c.get("course_id") or title,
            "url": c.get("url") or _course_enroll_url(platform, title),
            "match_percent": c.get("match_percent") or round(relevance * 100, 1),
            "match": c.get("match") or round(relevance * 100),
            "progress": c.get("progress") or 0,
            "hours": hours,
            "duration": c.get("duration") or (f"{hours} hrs" if hours else "Self-paced"),
            "level": c.get("level") or "Recommended",
            "source": source,
        })
    return enriched


def _heuristic_course_recs(gaps, catalog: dict, top_n: int) -> list:
    missing = {s.lower() for s in (gaps.get("missing_skills") or [])}
    recs = []
    for c in catalog.values():
        covered = {s.strip().lower() for s in str(c.get("skills_covered") or "").split("|") if s.strip()}
        overlap = covered & missing
        if not overlap:
            continue
        gap_match = len(overlap) / max(len(missing), 1)
        rating_norm = float(c.get("rating") or 0) / 5
        demand = float(c.get("market_demand") or 0)
        relevance = gap_match * 0.50 + rating_norm * 0.30 + demand * 0.20
        recs.append({
            "id": c.get("id") or c.get("course_id"),
            "title": c.get("title"),
            "platform": c.get("platform"),
            "relevance": round(relevance, 3),
            "fills": sorted(overlap),
            "rating": c.get("rating"),
            "hours": c.get("duration_hrs"),
            "level": c.get("level") or "Recommended",
            "market_demand": demand,
        })
    recs.sort(key=lambda x: x["relevance"], reverse=True)
    return recs[:top_n]


# ── DB-backed performance snapshot ────────────────────────────────────────────

def _score_to_100(value: float | int | None) -> Optional[float]:
    """Map a 0–5 peer score to a 0–100 display value."""
    if value is None:
        return None
    try:
        return round(float(value) * 20, 1)
    except (TypeError, ValueError):
        return None


def _task_commitment_score(user_id: int) -> Optional[float]:
    """Task completion rate (0–100) when no peer feedback exists yet."""
    from datetime import date

    from models.task import Task

    assigned = Task.query.filter_by(assigned_to=user_id).all()
    if not assigned:
        return None
    done = [
        t for t in assigned
        if (t.status or "").lower() in {"done", "completed"}
    ]
    if not done:
        return round(len(done) / len(assigned) * 100, 1)
    today = date.today()
    on_time = sum(
        1
        for t in done
        if t.due_date is None
        or (t.completed_date and t.completed_date.date() <= t.due_date)
        or (not t.completed_date and t.due_date >= today)
    )
    return round(on_time / len(done) * 100, 1)


def get_db_performance_snapshot(user_id: int) -> dict:
    """Aggregate commitment/teamwork/quality and history from Feedback + Rating rows."""
    from collections import defaultdict

    from models import db
    from models.feedback import Feedback
    from models.rating import Rating
    from models.user import User

    user = db.session.get(User, user_id)
    feedbacks = (
        Feedback.query.filter_by(user_id=user_id)
        .order_by(Feedback.created_at.asc())
        .all()
    )
    ratings = (
        Rating.query.filter_by(ratee_id=user_id)
        .order_by(Rating.created_at.asc())
        .all()
    )

    def _avg(vals: list[float]) -> Optional[float]:
        return round(sum(vals) / len(vals), 1) if vals else None

    quality_vals = [
        v for f in feedbacks
        if (v := _score_to_100(f.quality_score)) is not None
    ]
    teamwork_vals = [
        v for f in feedbacks
        if (v := _score_to_100(f.teamwork_score)) is not None
    ]
    peer_overall_vals = [
        v for f in feedbacks
        if (v := _score_to_100(f.avg_rating)) is not None
    ]
    rating_vals = [v for r in ratings if (v := _score_to_100(r.score)) is not None]

    has_peer_data = bool(feedbacks or ratings)

    quality = _avg(quality_vals) or _avg(peer_overall_vals) or _avg(rating_vals)
    teamwork = _avg(teamwork_vals) or _avg(peer_overall_vals) or quality
    commitment = (
        _avg(peer_overall_vals)
        or _avg(rating_vals)
        or _avg([v for v in (quality, teamwork) if v is not None])
    )

    if commitment is None and not has_peer_data:
        commitment = _task_commitment_score(user_id)
    if commitment is None and user:
        commitment = round((user.member_on_time_rate or 0.75) * 100, 1)

    scores = {
        "commitment": commitment if commitment is not None else 0.0,
        "teamwork": teamwork if teamwork is not None else (commitment or 0.0),
        "quality": quality if quality is not None else (teamwork if teamwork is not None else (commitment or 0.0)),
    }

    if has_peer_data:
        peer_keys = [k for k, v in scores.items() if v > 0]
        overall = round(sum(scores[k] for k in peer_keys) / max(len(peer_keys), 1), 1)
    else:
        overall = 0.0

    by_month: dict[str, list[float]] = defaultdict(list)
    for fb in feedbacks:
        if not fb.created_at:
            continue
        pts: list[float] = []
        for raw in (fb.quality_score, fb.teamwork_score, fb.avg_rating):
            if (pt := _score_to_100(raw)) is not None:
                pts.append(pt)
        if pts:
            by_month[fb.created_at.strftime("%Y-%m")].append(sum(pts) / len(pts))

    for rating in ratings:
        if not rating.created_at:
            continue
        if (pt := _score_to_100(rating.score)) is not None:
            by_month[rating.created_at.strftime("%Y-%m")].append(pt)

    history = [
        {"period": period, "score": round(sum(vals) / len(vals), 1)}
        for period, vals in sorted(by_month.items())
    ][-12:]

    recent_feedback = [
        fb.to_dict()
        for fb in sorted(
            feedbacks,
            key=lambda f: f.created_at or datetime.min.replace(tzinfo=timezone.utc),
            reverse=True,
        )[:8]
    ]

    return {
        "scores": scores,
        "overall": overall,
        "history": history,
        "feedback_count": len(feedbacks),
        "rating_count": len(ratings),
        "recent_feedback": recent_feedback,
        "source": "peer_feedback" if has_peer_data else "tasks_or_profile",
    }


# ── Public API ─────────────────────────────────────────────────────────────────

def generate_mentor_report(user_id: int) -> dict:
    """
    Generate a full AI career mentor report for a user by reading from the DB.

    Returns the same shape as ai_mentor_csv.py's analyse_user() output.
    """
    cached = _REPORT_CACHE.get(user_id)
    if cached and (time.time() - cached[0]) < _REPORT_TTL_SECONDS:
        return cached[1]

    report = _generate_mentor_report_uncached(user_id)
    if "error" not in report:
        _REPORT_CACHE[user_id] = (time.time(), report)
    return report


def _generate_mentor_report_uncached(user_id: int) -> dict:
    from models import db
    from models.user import User
    from models.task import Task
    from models.feedback import Feedback
    from models.project import Project

    user = db.session.get(User, user_id)
    if not user:
        return {"error": f"User {user_id} not found"}

    fixed_skills = normalize_skills_list(user.skills)
    if fixed_skills != (user.skills or []):
        user.skills = fixed_skills
        try:
            db.session.commit()
        except Exception:
            db.session.rollback()

    try:
        tasks = Task.query.filter_by(assigned_to=user_id).all()
    except Exception:
        tasks = []
    try:
        feedback_rows = Feedback.query.filter_by(user_id=user_id).all()
    except Exception:
        feedback_rows = []

    try:
        perf_snapshot = get_db_performance_snapshot(user_id)
    except Exception:
        perf_snapshot = {
            "scores": {"commitment": 75, "teamwork": 75, "quality": 75},
            "overall": 75,
            "history": [],
            "feedback_count": 0,
            "rating_count": 0,
        }
    nlp = _analyse_feedback(feedback_rows)
    scores = _compute_career_score(user, tasks, nlp["avg_sentiment_score"])
    scores["level"] = _resolve_career_level(user, scores["level"])
    if perf_snapshot["feedback_count"] or perf_snapshot["rating_count"]:
        scores["total_score"] = perf_snapshot["overall"]
        scores["breakdown"]["performance_avg"] = perf_snapshot["overall"]

    weaknesses = _detect_weaknesses(user, perf_snapshot["scores"])
    strengths = _detect_strengths(user, perf_snapshot["scores"])
    gaps = _detect_skill_gaps(user, scores["level"])
    report = _generate_report(user, scores, weaknesses, strengths, nlp, gaps, tasks=tasks)
    course_recs = _recommend_courses(gaps)

    done = [t for t in tasks if getattr(t, "status", None) == "done"]
    recent_tasks: list[dict[str, Any]] = []
    try:
        rows = (
            db.session.query(Task, Project)
            .outerjoin(Project, Task.project_id == Project.id)
            .filter(Task.assigned_to == user_id)
            .order_by(Task.created_at.desc())
            .limit(8)
            .all()
        )
        for t, proj in rows:
            proj_name = getattr(proj, "name", None) if proj else None
            recent_tasks.append({
                "title": proj_name or t.title,
                "task": t.title,
                "status": t.status,
            })
    except Exception:
        recent_tasks = [
            {"title": t.title, "task": t.title, "status": t.status}
            for t in tasks[:8]
        ]

    db_summary = _build_db_career_summary(user, scores, gaps, perf_snapshot, tasks)
    user_profile = {
        "skills": normalize_skills_list(user.skills),
        "experience_level": user.experience_level,
        "professional_field": getattr(user, "professional_field", None),
        "member_experience_years": getattr(user, "member_experience_years", None),
        "availability": getattr(user, "availability", None),
        "tasks_assigned": len(tasks),
        "tasks_completed": len(done),
        "feedback_count": perf_snapshot.get("feedback_count", 0),
        "rating_count": perf_snapshot.get("rating_count", 0),
        "recent_tasks": recent_tasks,
        "career_level": scores["level"],
        "target_role": gaps.get("target_role"),
    }

    ai_summary = report.split("##")[1].strip() if "##" in report else report[:280]
    summary = db_summary if db_summary else ai_summary

    return {
        "user_id": user_id,
        "user_name": user.display_name,
        "career_level": scores["level"],
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "summary": summary,
        "db_summary": db_summary,
        "user_profile": user_profile,
        "overall_score": scores["total_score"],
        "career_progress": {
            "score":          scores["total_score"],
            "level":          scores["level"],
            "next_milestone": gaps["priority_skill"],
            "breakdown":      scores["breakdown"],
        },
        "weaknesses":    weaknesses,
        "strengths":     strengths,
        "skill_gaps":    gaps,
        "feedback_nlp":  nlp,
        "top_courses":   course_recs,
        "mentor_report": report,
        "performance_snapshot": perf_snapshot,
        "ml_rating": _safe_ml_rating(user_id),
        "mentor_model": get_mentor_model_status(),
    }


def _safe_ml_rating(user_id: int) -> dict:
    try:
        return _predict_ml_rating_for_user(user_id)
    except Exception as exc:
        logger.warning("ML rating skipped for user %s: %s", user_id, exc)
        return {
            "predicted_rating": 3.0,
            "performance_label": "Good",
            "percentile_label": "Good",
            "source": "default",
        }


def build_user_ml_stats(user_id: int) -> dict:
    """Build feature dict for Profiles&AI Rating teamify_model.pkl from live DB."""
    from models import db
    from models.feedback import Feedback
    from models.project import Project
    from models.project_member import ProjectMember
    from models.rating import Rating
    from models.task import Task
    from models.user import User
    from services.ai_features import calc_availability_score, calc_project_similarity

    user = db.session.get(User, user_id)
    if not user:
        return {}

    tasks = Task.query.filter_by(assigned_to=user_id).all()
    assigned = len(tasks)
    completed = sum(1 for t in tasks if (t.status or "").lower() == "done")
    now = datetime.now(timezone.utc)
    overdue = 0
    for t in tasks:
        if (t.status or "").lower() == "done":
            continue
        due = getattr(t, "due_date", None)
        if due is not None:
            if isinstance(due, date) and not isinstance(due, datetime):
                due_dt = datetime.combine(due, datetime.min.time(), tzinfo=timezone.utc)
            elif isinstance(due, datetime):
                due_dt = due if due.tzinfo else due.replace(tzinfo=timezone.utc)
            else:
                continue
            if due_dt < now:
                overdue += 1

    feedbacks = Feedback.query.filter_by(user_id=user_id).all()
    ratings = Rating.query.filter_by(ratee_id=user_id).all()

    q_scores = [f.quality_score for f in feedbacks if f.quality_score is not None]
    t_scores = [f.teamwork_score for f in feedbacks if f.teamwork_score is not None]
    r_scores = [r.score for r in ratings]

    quality = round(sum(q_scores) / len(q_scores), 2) if q_scores else 3.5
    teamwork = round(sum(t_scores) / len(t_scores), 2) if t_scores else 3.5
    avg_rating = round(sum(r_scores) / len(r_scores), 2) if r_scores else 3.5
    skills = normalize_skills_list(user.skills)

    project_ids = {pm.project_id for pm in ProjectMember.query.filter_by(user_id=user_id).all()}
    similarities: list[float] = []
    for pid in project_ids:
        project = db.session.get(Project, pid)
        if project:
            similarities.append(float(calc_project_similarity(user, project)))
    project_similarity = (
        round(sum(similarities) / len(similarities), 2) if similarities else 0.0
    )

    return {
        "tasks_assigned": assigned or max(completed, 1),
        "tasks_completed": completed,
        "overdue_tasks": overdue,
        "quality_score": quality,
        "teamwork_score": teamwork,
        "attendance_rate": float(user.member_on_time_rate or 0.85),
        "skill_match_score": min(len(skills) / 8.0, 1.0),
        "avg_rating": avg_rating,
        "availability_score": calc_availability_score(user),
        "project_similarity": project_similarity,
    }


def _predict_ml_rating_for_user(user_id: int) -> dict:
    from services.profile_rating_service import predict_user_rating

    stats = build_user_ml_stats(user_id)
    if not stats:
        return {"predicted_rating": 3.0, "performance_label": "Good", "source": "default"}
    return predict_user_rating(stats)


def _areas_from_report(mentor_data: dict) -> tuple[list[str], list[str], list[dict], str, float]:
    strengths_raw = mentor_data.get("strengths") or []
    courses = mentor_data.get("top_courses") or []
    progress = mentor_data.get("career_progress") or {}
    level = progress.get("level", "Developer")
    score = float(
        mentor_data.get("overall_score")
        or progress.get("score", 0)
    )

    gaps_data = mentor_data.get("skill_gaps") or {}
    skill_gaps = list(gaps_data.get("missing_skills") or [])
    if not skill_gaps:
        skill_gaps = [
            str(d.get("name"))
            for d in (gaps_data.get("skill_details") or [])
            if isinstance(d, dict) and d.get("name") and not d.get("owned")
        ]

    strength_list = [
        s.get("area") for s in strengths_raw
        if isinstance(s, dict) and s.get("area")
    ]
    return skill_gaps, strength_list, courses, level, score


def generate_feedback_draft(
    *,
    rating: int,
    teammate_name: str = "your teammate",
    project_name: str = "the project",
) -> dict:
    """Build peer-feedback comment text from rating and context (no external API)."""
    name = (teammate_name or "your teammate").strip()
    project = (project_name or "the project").strip()
    r = max(1, min(5, int(rating)))

    drafts = {
        1: (
            f"Working with {name} on {project} was difficult. Communication was inconsistent "
            f"and deadlines were often missed. Clearer updates and more reliable follow-through "
            f"would help the team."
        ),
        2: (
            f"{name} contributed to {project}, but there is room to improve collaboration. "
            f"Tasks were sometimes delayed and expectations were not always clear. "
            f"More proactive communication would make a big difference."
        ),
        3: (
            f"{name} was a solid teammate on {project}. They completed assigned work and "
            f"participated in discussions. With sharper prioritization and faster responses, "
            f"they could have an even stronger impact."
        ),
        4: (
            f"{name} was a strong collaborator on {project}. They delivered quality work, "
            f"communicated well, and supported the team during key milestones. "
            f"Their reliability made the project smoother."
        ),
        5: (
            f"{name} was an outstanding partner on {project}. They consistently delivered "
            f"high-quality work, communicated clearly, and proactively helped unblock the team. "
            f"I would gladly work with them again."
        ),
    }
    draft = drafts[r]
    tip = (
        "Consider mentioning specific achievements or areas for improvement "
        "to make your feedback more actionable."
    )
    return {"draft": draft, "suggestion": tip}


def generate_mentor_chat_reply(
    user_id: int,
    question: str,
    mentor_data: dict,
    skill_context: dict | None = None,
) -> tuple[str, list[str], dict]:
    """
    ML-backed mentor reply using teamify_model.pkl + career report from DB.
    Returns (reply_text, suggestions, ml_metadata).
    """
    ml = mentor_data.get("ml_rating") or _predict_ml_rating_for_user(user_id)
    skill_gaps, strength_list, courses, level, career_score = _areas_from_report(mentor_data)
    name = mentor_data.get("user_name") or "there"
    q_lower = question.lower().strip()

    skill_name = (skill_context or {}).get("name") if skill_context else None
    if skill_name:
        skill_reply, skill_suggestions = _skill_focus_reply(
            str(skill_name),
            skill_context or {},
            q_lower,
            name,
            level,
            career_score,
            skill_gaps,
            strength_list,
            courses,
            ml,
            mentor_data,
        )
        if skill_reply:
            meta = {
                "source": ml.get("source", "formula"),
                "predicted_rating": ml.get("predicted_rating"),
                "performance_label": ml.get("percentile_label") or ml.get("performance_label"),
                "career_score": career_score,
                "career_level": level,
                "model": "Profiles&AI Rating/teamify_model.pkl",
                "skill_focus": skill_name,
            }
            return skill_reply, skill_suggestions, meta

    reply = _ml_intent_reply(
        q_lower, name, level, career_score, skill_gaps, strength_list, courses, ml, mentor_data
    )

    suggestions: list[str] = []
    if skill_gaps:
        suggestions.append(f"How do I improve my {skill_gaps[0]}?")
    if courses:
        suggestions.append(f"Tell me about '{courses[0].get('title', '')}'")
    if ml.get("source") == "ml_model":
        suggestions.append("What does my ML performance rating mean?")
    suggestions.append("What should I focus on this week?")

    meta = {
        "source": ml.get("source", "formula"),
        "predicted_rating": ml.get("predicted_rating"),
        "performance_label": ml.get("percentile_label") or ml.get("performance_label"),
        "career_score": career_score,
        "career_level": level,
        "model": "Profiles&AI Rating/teamify_model.pkl",
    }
    return reply, suggestions[:3], meta


def _courses_for_skill(courses: list[dict], skill_name: str) -> list[dict]:
    needle = skill_name.lower().strip()
    if not needle:
        return courses[:4]
    matched = [
        c for c in courses
        if needle in f"{c.get('title', '')} {c.get('skills_covered', '')} {c.get('skill', '')}".lower()
    ]
    return matched if matched else courses[:4]


def _skill_focus_reply(
    skill_name: str,
    skill_context: dict,
    q_lower: str,
    name: str,
    level: str,
    career_score: float,
    skill_gaps: list[str],
    strengths: list[str],
    courses: list[dict],
    ml: dict,
    mentor_data: dict,
) -> tuple[str | None, list[str]]:
    """Skill-scoped mentor replies when user opens Explore Skill."""
    pred = float(ml.get("predicted_rating") or 3.0)
    label = ml.get("percentile_label") or ml.get("performance_label") or "Good"
    ml_tag = (
        f"Our ML model (teamify_model.pkl) rates your performance **{pred:.1f}/5** ({label})."
        if ml.get("source") == "ml_model"
        else f"Your estimated performance is **{pred:.1f}/5** ({label})."
    )
    skill_level = skill_context.get("level") or "Intermediate"
    relevance = skill_context.get("score")
    rel_txt = f" Relevance for you: **{relevance}/100**." if relevance is not None else ""
    skill_courses = _courses_for_skill(courses, skill_name)

    suggestions = [
        f"What courses help me master {skill_name}?",
        f"How do I improve my {skill_name}?",
        f"How does {skill_name} affect promotion?",
    ]

    if any(kw in q_lower for kw in ("course", "learn", "study", "recommend", "another")):
        offset = 0
        if "another" in q_lower or "more" in q_lower:
            offset = min(2, max(0, len(skill_courses) - 2))
        picked = skill_courses[offset:offset + 4] or skill_courses[:4]
        if picked:
            lines = [
                f"• **{c.get('title', 'Course')}** ({c.get('platform', 'Online')}, "
                f"{c.get('hours', '?')} hrs, relevance {c.get('relevance', '—')})"
                for c in picked
            ]
            return (
                f"For **{skill_name}** ({skill_level}), here are targeted courses:\n"
                + "\n".join(lines)
                + f"\n\n{ml_tag}{rel_txt}",
                suggestions,
            )
        return (
            f"I don't have course matches for **{skill_name}** yet — add it to your profile "
            f"and complete related tasks. {ml_tag}",
            suggestions,
        )

    if any(kw in q_lower for kw in ("improve", "focus", "practice", "gap", "weak")):
        detail = f"Build **{skill_name}** through deliberate practice and visible project work."
        for w in mentor_data.get("weaknesses") or []:
            if isinstance(w, dict) and skill_name.lower() in str(w.get("area", "")).lower():
                detail = w.get("message") or detail
                break
        return (
            f"To strengthen **{skill_name}** ({skill_level}): {detail}\n\n"
            f"{ml_tag} Aim for career score **75+** (currently {career_score:.0f}).{rel_txt}",
            suggestions,
        )

    if any(kw in q_lower for kw in ("project", "experience", "build")):
        return (
            f"Pick a team project where **{skill_name}** is central — ship a small feature, "
            f"document trade-offs, and request peer feedback.\n\n"
            f"{ml_tag} Level: **{level}**.{rel_txt}",
            suggestions,
        )

    if any(kw in q_lower for kw in ("promot", "career", "level up", "senior")):
        return (
            f"**{skill_name}** at **{skill_level}** supports your path from **{level}** "
            f"toward the next role. Pair it with mentorship and code/design reviews.\n\n"
            f"{ml_tag} Career score **{career_score:.0f}/100**.{rel_txt}",
            suggestions,
        )

    # Default skill exploration opener / general question within skill thread
    course_hint = ""
    if skill_courses:
        c = skill_courses[0]
        course_hint = (
            f"\n\nStart with **{c.get('title', 'a recommended course')}** "
            f"({c.get('platform', 'Online')})."
        )
    return (
        f"You're exploring **{skill_name}** — **{skill_level}** level.{rel_txt}\n\n"
        f"{ml_tag} Career score **{career_score:.0f}/100** ({level})."
        f"{course_hint}\n\n"
        f"Ask about courses, practice plans, or how **{skill_name}** fits promotion.",
        suggestions,
    )


def _ml_intent_reply(
    q_lower: str,
    name: str,
    level: str,
    career_score: float,
    skill_gaps: list[str],
    strengths: list[str],
    courses: list[dict],
    ml: dict,
    mentor_data: dict,
) -> str:
    pred = float(ml.get("predicted_rating") or 3.0)
    label = ml.get("percentile_label") or ml.get("performance_label") or "Good"
    ml_tag = (
        f"Our ML model (teamify_model.pkl) rates your performance **{pred:.1f}/5** ({label})."
        if ml.get("source") == "ml_model"
        else f"Your estimated performance is **{pred:.1f}/5** ({label})."
    )

    if any(g in q_lower for g in ("hi", "hello", "hey", "allo", "salut", "bonjour", "good morning", "good evening")):
        gaps_txt = ", ".join(skill_gaps[:2]) if skill_gaps else "building core skills"
        return (
            f"Hi {name}! I'm your AI Career Mentor, powered by Teamify's ML rating model.\n\n"
            f"{ml_tag} You're at **{level}** with a career score of **{career_score:.0f}/100**.\n"
            f"Top focus areas: {gaps_txt}. Ask me about courses, promotion, or your skill gaps."
        )

    if any(kw in q_lower for kw in ("rating", "score", "performance", "how am i", "doing")):
        snap = mentor_data.get("performance_snapshot") or {}
        sc = snap.get("scores") or {}
        return (
            f"{ml_tag}\n\n"
            f"Career score: **{career_score:.0f}/100** ({level}).\n"
            f"From your database records — Commitment: **{sc.get('commitment', career_score):.0f}**, "
            f"Teamwork: **{sc.get('teamwork', career_score):.0f}**, "
            f"Quality: **{sc.get('quality', career_score):.0f}**.\n"
            f"Peer feedback entries: {snap.get('feedback_count', 0)}, "
            f"ratings: {snap.get('rating_count', 0)}."
        )

    if any(kw in q_lower for kw in ("ml", "model", "predict")):
        return (
            f"Teamify uses **GradientBoosting** in `ml_models/Profiles&AI Rating/teamify_model.pkl` "
            f"trained on profile features (tasks, quality, teamwork, attendance, ratings).\n\n"
            f"{ml_tag} Career score from your live tasks and feedback: **{career_score:.0f}/100**."
        )

    if any(kw in q_lower for kw in ("course", "learn", "study", "recommend")):
        if courses:
            lines = [
                f"• **{c.get('title', 'Course')}** ({c.get('platform', 'Online')}, "
                f"{c.get('hours', '?')} hrs, relevance {c.get('relevance', '—')})"
                for c in courses[:4]
            ]
            return (
                f"Based on your skill gaps ({', '.join(skill_gaps[:3]) or 'profile'}), "
                f"the ML mentor recommends:\n" + "\n".join(lines) + f"\n\n{ml_tag}"
            )
        return f"I don't have course matches yet — add skills to your profile. {ml_tag}"

    if any(kw in q_lower for kw in ("focus", "improve", "next", "should i", "gap")):
        if skill_gaps:
            w_msgs = [
                w.get("message", "") for w in (mentor_data.get("weaknesses") or [])
                if isinstance(w, dict) and w.get("area") in skill_gaps[:2]
            ]
            detail = w_msgs[0] if w_msgs else f"Strengthen {skill_gaps[0]} through deliberate practice."
            return (
                f"Priority focus: **{skill_gaps[0]}**. {detail}\n\n"
                f"{ml_tag} Target **75+** career score for your next level ({level})."
            )
        return (
            f"Keep completing tasks on time and collect peer feedback to refine your ML rating. {ml_tag}"
        )

    if any(kw in q_lower for kw in ("promot", "level up", "senior", "lead")):
        target = (mentor_data.get("skill_gaps") or {}).get("target_role", "next role")
        return (
            f"To move from **{level}** toward **{target}**, close gaps in "
            f"{', '.join(skill_gaps[:3]) or 'technical leadership'}.\n\n"
            f"{ml_tag} Aim for career score **75+** (currently {career_score:.0f})."
        )

    if any(kw in q_lower for kw in ("strength", "good at")):
        if strengths:
            return (
                f"Your strengths: **{', '.join(strengths[:3])}**. "
                f"Use them on visible project work.\n\n{ml_tag}"
            )
        return f"Strengths are still forming — deliver consistently to build your ML profile. {ml_tag}"

    if len(q_lower) <= 4:
        return (
            f"I heard you! Ask something specific — e.g. courses, promotion, or your ML rating.\n\n"
            f"{ml_tag} Career level: **{level}**."
        )

    return (
        f"Here's personalized guidance for **{name}**:\n\n"
        f"{ml_tag} Level: **{level}**, career score **{career_score:.0f}/100**.\n"
        f"Develop: {', '.join(skill_gaps[:3]) or 'technical depth'}. "
        f"Strengths: {', '.join(strengths[:3]) or 'emerging'}.\n\n"
        f"Try: \"Recommend courses\", \"What's my ML rating?\", or \"What should I focus on?\""
    )
