"""Unit tests for freelancer/student profile-completion helpers."""
from types import SimpleNamespace

from utils.profile_completion import (
    is_freelancer_profile_complete,
    is_student_profile_complete,
    needs_profile_setup,
)


def _freelancer(**overrides):
    data = dict(
        user_type="freelancer",
        role="member",
        full_name="Mohamed Adel",
        display_name="m_adel",
        professional_field="Frontend Development",
        experience_level="Beginner",
        availability="Full Time",
        skills=["Flutter"],
        major=None,
        current_level=None,
    )
    data.update(overrides)
    return SimpleNamespace(**data)


def test_new_google_freelancer_is_incomplete():
    user = _freelancer(
        professional_field=None,
        experience_level=None,
        availability=None,
        skills=[],
    )
    assert is_freelancer_profile_complete(user) is False
    assert needs_profile_setup(user) is True


def test_google_freelancer_without_name_is_incomplete():
    user = _freelancer(full_name="")
    assert is_freelancer_profile_complete(user) is False
    assert needs_profile_setup(user) is True


def test_complete_freelancer_profile():
    user = _freelancer()
    assert is_freelancer_profile_complete(user) is True
    assert needs_profile_setup(user) is False


def test_existing_google_account_stays_incomplete_until_skills_saved():
    user = _freelancer(skills=None)
    assert needs_profile_setup(user) is True


def test_student_requirements_unchanged():
    student = SimpleNamespace(
        user_type="student",
        role="member",
        full_name="Jane",
        display_name="jane_doe",
        professional_field=None,
        experience_level=None,
        availability=None,
        skills=[],
        major="",
        current_level="",
    )
    assert is_student_profile_complete(student) is False
    assert needs_profile_setup(student) is True

    student.major = "Computer Science"
    student.current_level = "Beginner"
    student.skills = ["Python"]
    assert is_student_profile_complete(student) is True
    assert needs_profile_setup(student) is False


def test_admin_never_needs_freelancer_profile_setup():
    admin = SimpleNamespace(
        user_type="admin",
        role="admin",
        full_name="",
        display_name="admin_user",
        professional_field=None,
        experience_level=None,
        availability=None,
        skills=[],
        major=None,
        current_level=None,
    )
    assert needs_profile_setup(admin) is False
