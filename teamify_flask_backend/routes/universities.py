from __future__ import annotations

import re

from flask import Blueprint, jsonify, request

from data.universities import EGYPTIAN_UNIVERSITIES, OTHER_UNIVERSITY_ID
from models.user import User

universities_bp = Blueprint("universities", __name__, url_prefix="/api/universities")


def normalize_university_name(value: str) -> str:
    """Mirrors UniversityOption.normalizeUniversityName on the Flutter side."""
    cleaned = re.sub(r"[^\w\s]", "", (value or "").lower())
    return re.sub(r"\s+", " ", cleaned).strip()


def _custom_universities() -> list[dict]:
    """Custom institutions previously entered by users, deduplicated by name."""
    rows = (
        User.query.with_entities(User.university_id, User.university_name)
        .filter(User.is_custom_university.is_(True))
        .filter(User.university_name.isnot(None))
        .distinct()
        .all()
    )
    seen: set[str] = set()
    items: list[dict] = []
    for uid, name in rows:
        norm = normalize_university_name(name)
        if not norm or norm in seen:
            continue
        seen.add(norm)
        items.append(
            {
                "id": uid or f"custom_{norm.replace(' ', '_')}",
                "name": name,
                "city": None,
                "type": None,
                "aliases": [],
                "is_custom": True,
            }
        )
    return items


@universities_bp.route("", methods=["GET"])
def list_universities():
    """Public catalog of universities used by the student signup and profile forms.

    Returns the built-in Egyptian catalog, any custom institutions other users
    have registered, and the trailing "Other" sentinel option.
    """
    query = normalize_university_name(request.args.get("q", ""))

    builtin = [{**uni, "is_custom": False} for uni in EGYPTIAN_UNIVERSITIES]
    items = builtin + _custom_universities()

    if query:
        def matches(uni: dict) -> bool:
            haystack = [uni["name"], *(uni.get("aliases") or [])]
            if uni.get("city"):
                haystack.append(uni["city"])
            return any(query in normalize_university_name(h) for h in haystack)

        items = [uni for uni in items if matches(uni)]

    items.sort(key=lambda uni: uni["name"].lower())
    items.append(
        {
            "id": OTHER_UNIVERSITY_ID,
            "name": "Other",
            "city": None,
            "type": None,
            "aliases": [],
            "is_custom": True,
        }
    )

    return jsonify({"universities": items, "total": len(items)}), 200
