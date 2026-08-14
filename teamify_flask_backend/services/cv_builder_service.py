"""
CV Builder Service
==================
Wraps the ai_resume_builder AI pipeline to produce structured CV JSON
directly from live Teamify ORM data.

Loading order (first success wins):
  1. Import ``ai_resume_builder (3).py`` via importlib — full 7-stage pipeline.
     If reportlab is absent the module is imported with lightweight stubs so
     that ``update_cv()`` can still be called (PDF generation is never invoked
     from this service).
  2. Fall back to the ``CVBuilder`` stub from ``cv_builder.pkl``.
  3. If both fail, a minimal heuristic CV is returned so the endpoint never
     crashes.
"""

from __future__ import annotations

import importlib.util
import logging
import os
import types
import sys
from datetime import date, datetime, timedelta
from typing import Any

logger = logging.getLogger(__name__)

# ─── Paths ────────────────────────────────────────────────────────────────────

_CVBUILDER_DIR = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "ml_models", "CVBuilder")
)
_MODULE_FILE = os.path.join(_CVBUILDER_DIR, "ai_resume_builder (3).py")
_PKL_FILE    = os.path.join(_CVBUILDER_DIR, "cv_builder.pkl")

# ─── Module / model cache ─────────────────────────────────────────────────────

_cv_module:  Any       = None   # importlib-loaded ai_resume_builder module
_pkl_model:  Any       = None   # joblib-loaded CVBuilder stub
_load_error: str | None = None
_loaded:     bool      = False


# ─── reportlab stub (allows import even when reportlab is absent) ─────────────

def _inject_reportlab_stubs() -> None:
    """Install throwaway stub packages for reportlab.

    ``ai_resume_builder (3).py`` imports reportlab at module level, but only
    ``generate_pdf()`` actually uses it.  We only call ``update_cv()``, so the
    stubs are enough to satisfy the name bindings during import.
    """
    def _mod(name: str) -> types.ModuleType:
        if name not in sys.modules:
            sys.modules[name] = types.ModuleType(name)
        return sys.modules[name]

    _mod("reportlab")
    lib      = _mod("reportlab.lib")
    ps       = _mod("reportlab.lib.pagesizes")
    styles   = _mod("reportlab.lib.styles")
    units    = _mod("reportlab.lib.units")
    clrs     = _mod("reportlab.lib.colors")
    enums    = _mod("reportlab.lib.enums")
    platypus = _mod("reportlab.platypus")

    ps.A4 = (595.27, 841.89)

    _Noop = type("_Noop", (), {"__init__": lambda self, *a, **kw: None})
    styles.getSampleStyleSheet = lambda: {}
    styles.ParagraphStyle = _Noop
    units.cm = 28.3465
    clrs.HexColor = lambda h: h
    lib.colors = clrs
    enums.TA_LEFT = 0
    enums.TA_CENTER = 2
    for _cls in [
        "SimpleDocTemplate", "Paragraph", "Spacer",
        "HRFlowable", "Table", "TableStyle",
    ]:
        setattr(platypus, _cls, _Noop)


# ─── Pipeline loader ──────────────────────────────────────────────────────────

def _load_pipeline() -> None:
    """Attempt to load the AI resume builder (idempotent, cached)."""
    global _cv_module, _pkl_model, _load_error, _loaded
    if _loaded:
        return
    _loaded = True

    # ── Attempt 1: full ai_resume_builder module via importlib ───────────────
    try:
        _inject_reportlab_stubs()
        spec   = importlib.util.spec_from_file_location("ai_resume_builder", _MODULE_FILE)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        if callable(getattr(module, "update_cv", None)):
            _cv_module = module
            logger.info("CVBuilder: ai_resume_builder pipeline loaded from %s", _MODULE_FILE)
            return
        logger.warning("CVBuilder: ai_resume_builder has no update_cv(), skipping")
    except FileNotFoundError:
        logger.warning("CVBuilder: %s not found", _MODULE_FILE)
    except Exception as exc:
        logger.warning("CVBuilder: failed to import ai_resume_builder: %s", exc)

    # ── Attempt 2: cv_builder.pkl stub ───────────────────────────────────────
    try:
        import joblib  # noqa: PLC0415

        obj = joblib.load(_PKL_FILE)
        if callable(getattr(obj, "generate_cv_data", None)):
            _pkl_model = obj
            logger.info("CVBuilder: cv_builder.pkl stub loaded from %s", _PKL_FILE)
            return
        _load_error = "cv_builder.pkl is not a valid CVBuilder instance"
        logger.warning("CVBuilder: %s", _load_error)
    except FileNotFoundError:
        _load_error = f"cv_builder.pkl not found at {_PKL_FILE}"
        logger.warning("CVBuilder: %s", _load_error)
    except Exception as exc:
        _load_error = f"Failed to load cv_builder.pkl: {exc}"
        logger.error("CVBuilder: %s", _load_error, exc_info=True)

    logger.warning("CVBuilder: all backends unavailable — will use heuristic fallback")


# ─── ORM → pipeline input conversion ─────────────────────────────────────────

def _build_user_data(user: Any) -> dict:
    """Convert a SQLAlchemy User ORM object into the dict expected by
    ``ai_resume_builder.update_cv()``.

    Deliberately defensive: every field access is guarded so a partial or
    mock user object still produces a valid (possibly sparse) result.
    """
    from models import db  # noqa: PLC0415
    from models.project_member import ProjectMember  # noqa: PLC0415
    from models.project import Project  # noqa: PLC0415

    today = date.today()

    # ── User identity ─────────────────────────────────────────────────────────
    user_info = {
        "name":  getattr(user, "full_name", None) or getattr(user, "display_name", "Unknown"),
        "role":  getattr(user, "professional_field", None)
                 or getattr(user, "user_type", None)
                 or "Professional",
        "email": getattr(user, "email", ""),
    }

    # ── Projects membership ───────────────────────────────────────────────────
    try:
        memberships = (
            db.session.query(ProjectMember, Project)
            .join(Project, ProjectMember.project_id == Project.id)
            .filter(ProjectMember.user_id == user.id)
            .all()
        )
    except Exception:
        memberships = []

    projects_payload: list[dict] = []
    for pm, proj in memberships:
        # Technologies: collect unique ai_skills from all tasks in the project
        tech_set: set[str] = set()
        for task in getattr(proj, "tasks", []):
            raw_skills = getattr(task, "ai_skills", None)
            if raw_skills:
                if isinstance(raw_skills, list):
                    tech_set.update(str(s).strip() for s in raw_skills if str(s).strip())
                elif isinstance(raw_skills, str):
                    s = raw_skills.strip()
                    if s:
                        tech_set.add(s)

        # For owned projects also seed with the user's profile skills
        if getattr(pm, "role", "") == "owner":
            for skill in (getattr(user, "skills", None) or [])[:5]:
                tech_set.add(skill)

        # Rating: average review_score for this user's tasks in the project
        proj_scores = [
            t.review_score
            for t in getattr(proj, "tasks", [])
            if getattr(t, "assigned_to", None) == user.id
            and t.review_score is not None
        ]
        # review_score is 0-10 in the ORM; pipeline expects 0-5
        avg_rating = (sum(proj_scores) / len(proj_scores) / 2) if proj_scores else 4.0
        avg_rating = round(max(0.0, min(5.0, avg_rating)), 1)

        # Status mapping
        cv_status = (
            "completed"
            if getattr(proj, "status", "") in ("completed", "done", "archived")
            else "in_progress"
        )

        start_dt = getattr(proj, "start_date", None)
        end_dt   = getattr(proj, "end_date", None)
        start_iso = start_dt.isoformat() if start_dt else str(today - timedelta(days=60))
        end_iso   = end_dt.isoformat()   if end_dt   else str(today)

        projects_payload.append({
            "title":        proj.name,
            "description":  proj.description or "",
            "technologies": list(tech_set),
            "role":         "Project Lead" if pm.role == "owner" else "Team Member",
            "status":       cv_status,
            "rating":       avg_rating,
            "start_date":   start_iso,
            "end_date":     end_iso,
        })

    # ── Task aggregation ──────────────────────────────────────────────────────
    all_tasks   = list(getattr(user, "assigned_tasks", []))
    done_set    = {"done", "completed", "Completed"}
    completed_n = sum(1 for t in all_tasks if getattr(t, "status", "") in done_set)
    overdue_n   = sum(
        1 for t in all_tasks
        if getattr(t, "due_date", None)
        and t.due_date < today
        and getattr(t, "status", "") not in done_set
    )
    tasks_payload = {
        "total":     len(all_tasks),
        "completed": completed_n,
        "overdue":   overdue_n,
    }

    # ── Metrics ───────────────────────────────────────────────────────────────
    on_time_rate    = float(getattr(user, "member_on_time_rate", 1.0) or 1.0)
    attendance_rate = float(getattr(user, "attendance_rate", 0.0) or 0.0)

    # avg_rating from task review scores (0-10 → 0-5)
    scores   = [t.review_score for t in all_tasks if getattr(t, "review_score", None) is not None]
    avg_task_rating = round(max(0.0, min(5.0, (sum(scores) / len(scores) / 2) if scores else 4.0)), 2)

    metrics_payload = {
        "avg_rating":         avg_task_rating,
        "consistency_score":  round(on_time_rate * 100, 1),
        "trust_score":        round((on_time_rate * 0.6 + attendance_rate * 0.4) * 100, 1),
        "teamwork_score":     round(min(100.0, len(memberships) * 20.0 + 40.0), 1),
    }

    # ── Collaboration ─────────────────────────────────────────────────────────
    team_count = len({pm.project_id for pm, _ in memberships}) if memberships else 0
    meetings   = int(getattr(user, "meetings_attended", 0) or 0)
    collaboration_payload = {
        "messages_sent":    meetings * 5,   # proxy: each meeting ≈ 5 messages
        "comments_written": completed_n,    # proxy: each completed task ≈ 1 review
        "team_count":       team_count,
    }

    # ── Activity ──────────────────────────────────────────────────────────────
    exp_years       = int(getattr(user, "member_experience_years", 0) or 0)
    activity_payload = {
        "activity_count":  len(all_tasks) + meetings,
        "login_frequency": round(min(7.0, 2.0 + exp_years * 0.5), 1),
    }

    return {
        "user":          user_info,
        "projects":      projects_payload,
        "tasks":         tasks_payload,
        "metrics":       metrics_payload,
        "collaboration": collaboration_payload,
        "activity":      activity_payload,
    }


# ─── Fallback CV (when all backends are unavailable) ─────────────────────────

def _fallback_cv(user_data: dict) -> dict:
    """Minimal structured CV built from raw user_data without any ML model."""
    user    = user_data.get("user", {})
    metrics = user_data.get("metrics", {})
    projs   = user_data.get("projects", [])

    def _tech_labels(raw) -> list[str]:
        if raw is None:
            return []
        if isinstance(raw, str):
            s = raw.strip()
            if not s:
                return []
            if "," in s:
                return [p.strip() for p in s.split(",") if p.strip()]
            return [s]
        if isinstance(raw, list):
            return [str(t).strip() for t in raw if str(t).strip()]
        return []

    # Collect unique technologies from projects preserving order
    seen_tech: list[str] = []
    seen_set:  set[str]  = set()
    for p in projs:
        for t in _tech_labels(p.get("technologies", [])):
            if t not in seen_set:
                seen_tech.append(t)
                seen_set.add(t)

    return {
        "generated_at": datetime.now().isoformat(),
        "user":         user,
        "summary": (
            f"{user.get('name', 'The user')} is a "
            f"{user.get('role', 'professional')} with hands-on project "
            "experience on the Teamify platform."
        ),
        "skills": {"technical": seen_tech[:12], "soft": []},
        "projects": [
            {
                "title":        p.get("title", ""),
                "role":         p.get("role", ""),
                "technologies": p.get("technologies", []),
                "status":       p.get("status", ""),
                "impact_score": 50,
                "duration_days": 30,
                "rating":       p.get("rating", 0),
                "bullets":      [p.get("description", "Project contribution.")],
                "start_date":   p.get("start_date"),
                "end_date":     p.get("end_date"),
            }
            for p in projs
        ],
        "achievements": ["Active contributor on the Teamify platform."],
        "metadata":     metrics,
        "source":       "fallback",
    }


# ─── Public API ───────────────────────────────────────────────────────────────

def build_cv_for_user(user_id: int) -> dict:
    """Generate a full AI CV for ``user_id``.

    Reads live ORM data, runs the ai_resume_builder pipeline, and returns a
    structured CV dict.  Never raises — errors are captured and returned as
    ``{"error": ...}`` dicts or trigger the heuristic fallback.

    Returns:
        dict with keys: generated_at, user, summary, skills, projects,
        achievements, metadata, source.
    """
    from models import db       # noqa: PLC0415
    from models.user import User  # noqa: PLC0415

    user = db.session.get(User, user_id)
    if not user:
        return {"error": f"User {user_id} not found"}

    # Build the pipeline's expected input format from ORM
    try:
        user_data = _build_user_data(user)
    except Exception as exc:
        logger.error(
            "CVBuilder: failed to build user_data for user %s: %s",
            user_id, exc, exc_info=True,
        )
        return {"error": f"Failed to prepare CV data: {exc}"}

    _load_pipeline()

    # ── Attempt 1: full ai_resume_builder pipeline ────────────────────────────
    cv: dict | None = None
    if _cv_module is not None:
        try:
            cv = _cv_module.update_cv(user_data)
            cv["source"] = "ai_pipeline"
        except Exception as exc:
            logger.error(
                "CVBuilder pipeline error for user %s: %s", user_id, exc, exc_info=True
            )

    # ── Attempt 2: cv_builder.pkl stub ────────────────────────────────────────
    if cv is None and _pkl_model is not None:
        try:
            cv = _pkl_model.generate_cv_data(user_data)
            cv["source"] = "pkl_stub"
        except Exception as exc:
            logger.error(
                "CVBuilder pkl stub error for user %s: %s", user_id, exc, exc_info=True
            )

    # ── Heuristic fallback ────────────────────────────────────────────────────
    if cv is None:
        cv = _fallback_cv(user_data)

    # ── Always merge user profile skills ─────────────────────────────────────
    profile_skills: list[str] = list(getattr(user, "skills", None) or [])
    if profile_skills:
        existing = cv.get("skills", {})
        if isinstance(existing, dict):
            tech: list = list(existing.get("technical") or [])
            seen = {s.lower() for s in tech}
            for s in profile_skills:
                if s and s.lower() not in seen:
                    tech.append(s)
                    seen.add(s.lower())
            cv["skills"] = dict(existing, technical=tech)
        elif isinstance(existing, list):
            seen_list = {s.lower() for s in existing}
            for s in profile_skills:
                if s and s.lower() not in seen_list:
                    existing.append(s)
                    seen_list.add(s.lower())
            cv["skills"] = existing
        else:
            cv["skills"] = {"technical": profile_skills, "soft": []}

    return cv


def persist_cv_from_ai_build(user_id: int, ai_result: dict) -> None:
    """Upsert the user's saved CV row from an AI build result (no Marshmallow)."""
    from models import db  # noqa: PLC0415
    from models.cv import CV  # noqa: PLC0415
    from models.user import User  # noqa: PLC0415

    user = db.session.get(User, user_id)
    if not user:
        return

    skills: list[dict] = []
    skills_raw = ai_result.get("skills") or {}
    if isinstance(skills_raw, dict):
        names = (skills_raw.get("technical") or []) + (skills_raw.get("soft") or [])
    elif isinstance(skills_raw, list):
        names = skills_raw
    else:
        names = []
    for name in names:
        label = str(name).strip()
        if label:
            skills.append({"name": label, "level": "Intermediate"})

    projects: list[dict] = []
    for entry in ai_result.get("projects") or []:
        if not isinstance(entry, dict):
            continue
        bullets = entry.get("bullets") or []
        desc = (
            "\n".join(str(b) for b in bullets)
            if bullets
            else str(entry.get("description") or "")
        )
        projects.append({
            "name": str(entry.get("title") or entry.get("name") or "Project"),
            "description": desc,
            "role": str(entry.get("role") or ""),
        })

    personal_info = {
        "full_name": (
            getattr(user, "full_name", None)
            or getattr(user, "display_name", None)
            or "User"
        ),
        "email": getattr(user, "email", "") or "",
    }

    cv = CV.query.filter_by(user_id=user_id).first()
    if cv is None:
        cv = CV(user_id=user_id)
        db.session.add(cv)

    cv.personal_info = personal_info
    cv.summary = ai_result.get("summary") or ""
    cv.skills = skills
    cv.projects = projects
    cv.experience = []
    db.session.commit()


def probe_cv_builder_inference(user_data: dict) -> dict:
    """Run CV generation on in-memory sample data. Never reads or writes the DB."""
    _load_pipeline()
    if _cv_module is not None:
        cv = _cv_module.update_cv(user_data)
        if not isinstance(cv, dict):
            raise TypeError("ai_resume_builder.update_cv() did not return a dict")
        return {"ok": True, "backend": "pipeline", "source": "ai_pipeline"}
    if _pkl_model is not None:
        cv = _pkl_model.generate_cv_data(user_data)
        if not isinstance(cv, dict):
            raise TypeError("cv_builder.pkl generate_cv_data() did not return a dict")
        return {"ok": True, "backend": "pkl", "source": "pkl_stub"}
    raise RuntimeError(_load_error or "CV builder backends unavailable")


def get_cv_builder_status() -> dict:
    """Report CV builder pipeline / pkl availability without forcing a load."""
    module_present = os.path.isfile(_MODULE_FILE)
    pkl_present = os.path.isfile(_PKL_FILE)
    return {
        "file_present": module_present or pkl_present,
        "loaded": _cv_module is not None or _pkl_model is not None,
        "error": _load_error,
        "path": _MODULE_FILE if module_present else _PKL_FILE,
        "backend": (
            "pipeline"
            if _cv_module is not None
            else ("pkl" if _pkl_model is not None else "unloaded")
        ),
    }
