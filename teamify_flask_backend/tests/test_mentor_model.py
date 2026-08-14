"""AI Career Mentor model: ai_mentor_csv.py + courses.csv wired into APIs."""
from services.ai_mentor_service import (
    _recommend_courses,
    get_mentor_model_status,
    _load_course_catalog,
)


def test_course_catalog_loads_from_csv():
    catalog, source = _load_course_catalog()
    assert source == "mentor_model"
    assert len(catalog) >= 10
    assert any("System Design" in (c.get("skills_covered") or "") for c in catalog.values())


def test_recommend_courses_uses_mentor_catalog():
    recs = _recommend_courses(
        {
            "missing_skills": ["System Design", "AWS", "Docker"],
            "target_role": "Senior Developer",
        },
        top_n=3,
    )
    assert recs
    assert recs[0]["title"]
    assert recs[0]["source"] == "mentor_model"
    assert recs[0]["url"]
    titles = {r["title"] for r in recs}
    assert any("System Design" in t or "AWS" in t or "Docker" in t or "Microservices" in t for t in titles)


def test_mentor_model_status_is_real_when_catalog_present():
    status = get_mentor_model_status()
    assert status["file_exists"] is True
    assert status["catalog_source"] == "mentor_model"
    assert status["loaded"] is True
    assert status["inference_test"] is True
    assert status["mode"] == "REAL_MODEL"
    assert status["error"] is None
    assert status["catalog_size"] >= 10
