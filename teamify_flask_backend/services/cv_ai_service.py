"""
AI CV Enhancement Service
Mockable service layer that:
  1. Generates a professional summary from raw CV data.
  2. Re-ranks experience and projects by relevance (most recent / most impactful first).

In production, replace _call_ai_api() with a real LLM call (OpenAI, Gemini, etc.).
The function signature and return contract are kept stable so the route layer
never needs to change when you swap the underlying model.
"""
from __future__ import annotations
import logging
import os
import datetime
from typing import Any

logger = logging.getLogger(__name__)


# ─── Internal mock / live dispatcher ──────────────────────────────────────────

def _call_ai_api(prompt: str) -> str:
    """
    Send a prompt to the configured AI provider.
    Returns the model's plain-text response.

    Currently returns a deterministic mock so the whole feature works
    without an API key. Set AI_PROVIDER=openai + OPENAI_API_KEY in .env
    to activate the real model.
    """
    provider = os.getenv("AI_PROVIDER", "mock").lower()

    if provider == "openai":                       # ── Optional OpenAI path ──
        api_key = (os.getenv("OPENAI_API_KEY") or "").strip()
        if not api_key:
            logger.warning(
                "AI_PROVIDER=openai but OPENAI_API_KEY is missing; using mock summary"
            )
        else:
            try:
                import openai

                client = openai.OpenAI(api_key=api_key)
                resp = client.chat.completions.create(
                    model=os.getenv("OPENAI_MODEL", "gpt-4o-mini"),
                    messages=[{"role": "user", "content": prompt}],
                    max_tokens=400,
                    temperature=0.7,
                )
                content = (resp.choices[0].message.content or "").strip()
                if content:
                    return content
            except Exception as exc:
                logger.warning("OpenAI CV summary failed (%s); using mock", exc)

    # ── Mock path (default) ──────────────────────────────────────────────────
    name = "the candidate"
    if "full_name" in prompt:
        try:
            name = prompt.split("full_name")[1].split('"')[2].strip()
        except Exception:
            pass
    return (
        f"A highly motivated and results-driven professional, {name} brings a "
        f"strong technical background and a proven record of delivering impactful "
        f"solutions. Adept at collaborating in cross-functional teams and driving "
        f"projects from conception to completion."
    )


# ─── Public API ───────────────────────────────────────────────────────────────

def generate_ai_summary(cv_data: dict) -> str:
    """
    Build a concise professional summary from the CV payload.
    Returns a single paragraph string suitable for the CV header.
    """
    personal   = cv_data.get("personal_info", {})
    skills     = [s.get("name", "") for s in cv_data.get("skills", [])][:10]
    experience = cv_data.get("experience", [])
    latest_job = experience[0] if experience else {}

    prompt = (
        f"Write a 3-sentence professional CV summary for:\n"
        f"  full_name: \"{personal.get('full_name', 'the candidate')}\"\n"
        f"  latest_role: \"{latest_job.get('title', '')} at {latest_job.get('company', '')}\"\n"
        f"  top_skills: {skills}\n"
        f"Keep it factual, concise, and written in third person."
    )
    return _call_ai_api(prompt)


def rank_by_relevance(cv_data: dict) -> dict:
    """
    Reorder 'experience' and 'projects' arrays by relevance.

    Ranking heuristic (no API call needed — deterministic):
      - Experience: sort descending by start_date (most recent first).
      - Projects:   sort descending by start_date, then by tech_stack length
                    (richer stack = more substantial project).

    Returns a shallow copy of cv_data with sorted lists.
    """
    def parse_date(date_str: str | None) -> datetime.date:
        """Convert 'YYYY-MM' or 'YYYY' to a sortable date. Missing → epoch."""
        if not date_str:
            return datetime.date.min
        for fmt in ("%Y-%m", "%Y"):
            try:
                return datetime.datetime.strptime(date_str, fmt).date()
            except ValueError:
                continue
        return datetime.date.min

    ranked = dict(cv_data)

    # Sort experience: newest start_date first
    ranked["experience"] = sorted(
        cv_data.get("experience", []),
        key=lambda e: parse_date(e.get("start_date")),
        reverse=True,
    )

    # Sort projects: newest first, then by tech stack richness
    ranked["projects"] = sorted(
        cv_data.get("projects", []),
        key=lambda p: (
            parse_date(p.get("start_date")),
            len(p.get("tech_stack", [])),
        ),
        reverse=True,
    )

    return ranked


def enhance_cv(cv_data: dict) -> dict:
    """
    Master function: rank sections then generate AI summary.
    Returns an enhanced copy of cv_data ready to persist.
    """
    enhanced = rank_by_relevance(cv_data)
    enhanced["summary"] = generate_ai_summary(enhanced)
    return enhanced
