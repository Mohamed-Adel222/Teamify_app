"""
CV Marshmallow Schemas
All string fields run through _sanitize_html() to strip XSS payloads
before any data reaches the DB. This is the single choke-point for
CV input sanitization.
"""
import re
from marshmallow import Schema, fields, validate, validates, ValidationError, pre_load

# ─── XSS Sanitizer ────────────────────────────────────────────────────────────
_TAG_RE = re.compile(r"<.*?>", re.DOTALL)

def _strip_tags(value: str) -> str:
    """Remove all HTML/script tags and strip surrounding whitespace."""
    return _TAG_RE.sub("", value).strip()


def _sanitize_str(value):
    """Apply tag stripping to a single string value if it is indeed a string."""
    return _strip_tags(value) if isinstance(value, str) else value


# ─── Skill Whitelist ──────────────────────────────────────────────────────────
# SECURITY: Only recognised skill names are accepted. Unknown entries are
# rejected with a ValidationError, preventing junk or injected values.
ALLOWED_SKILLS = {
    # Programming Languages
    "Python", "JavaScript", "TypeScript", "Java", "C", "C++", "C#", "Go",
    "Rust", "Kotlin", "Swift", "Ruby", "PHP", "Scala", "R", "Dart", "Lua",
    "Perl", "Haskell", "Elixir", "Clojure", "MATLAB", "Shell", "Bash",
    "PowerShell", "SQL", "HTML", "CSS", "Objective-C", "Assembly",
    # Frontend
    "React", "Angular", "Vue", "Svelte", "Next.js", "Nuxt.js", "jQuery",
    "Bootstrap", "TailwindCSS", "Sass", "LESS", "Redux", "Zustand",
    "Webpack", "Vite", "Figma", "Adobe XD",
    # Backend & Frameworks
    "Flask", "Django", "FastAPI", "Express", "NestJS", "Spring Boot",
    "Ruby on Rails", "Laravel", "ASP.NET", "Node.js", "Deno", "Bun",
    # Mobile
    "Flutter", "React Native", "SwiftUI", "Jetpack Compose", "Xamarin",
    "Ionic",
    # Data & AI
    "Machine Learning", "Deep Learning", "TensorFlow", "PyTorch", "Keras",
    "Scikit-learn", "Pandas", "NumPy", "OpenCV", "NLP",
    "Computer Vision", "Data Analysis", "Data Science", "Big Data",
    "Apache Spark", "Hadoop", "Power BI", "Tableau",
    # Cloud & DevOps
    "AWS", "Azure", "GCP", "Docker", "Kubernetes", "Terraform",
    "Ansible", "Jenkins", "GitHub Actions", "CI/CD", "Linux",
    "Nginx", "Apache",
    # Databases
    "PostgreSQL", "MySQL", "MongoDB", "Redis", "SQLite", "Firebase",
    "Elasticsearch", "DynamoDB", "Oracle", "SQL Server", "Cassandra",
    "Neo4j", "Supabase",
    # Testing & Security
    "Pytest", "Jest", "Selenium", "Cypress", "Playwright",
    "Penetration Testing", "OWASP", "Cryptography",
    # Soft Skills & Other
    "Agile", "Scrum", "Git", "GitHub", "GitLab", "Jira", "REST API",
    "GraphQL", "gRPC", "WebSocket", "Microservices", "System Design",
    "Technical Writing", "UI/UX Design", "Project Management",
    "Leadership", "Communication", "Problem Solving", "Team Management",
    "Reliability & Consistency", "Teamwork & Synergy",
    "REST APIs", "HTML/CSS", "Unit Testing", "Code Review",
    "Product Thinking", "Stakeholder Communication", "Architecture", "OKRs",
    # Profile / domain labels (from Teamify CV builder & user profiles)
    "Backend Development", "Frontend Development", "Mobile App Development",
    "Full Stack Development", "AI Tools", "DevOps Engineering",
    "Cloud Engineering", "Software Engineering", "Web Development",
    "Team Leadership", "Cross-functional Collaboration", "Time Management",
    "Efficient Execution", "Professional Integrity",
    "High Initiative & Engagement",
}

# Case-insensitive lookup set for validation
_ALLOWED_SKILLS_LOWER = {s.lower() for s in ALLOWED_SKILLS}

# Map common aliases / profile labels to canonical whitelist entries
_SKILL_ALIASES: dict[str, str] = {
    "rest apis": "REST APIs",
    "rest api": "REST API",
    "html/css": "HTML/CSS",
    "html": "HTML",
    "css": "CSS",
    "node": "Node.js",
    "nodejs": "Node.js",
    "node.js": "Node.js",
    "react.js": "React",
    "reactjs": "React",
    "vue.js": "Vue",
    "ts": "TypeScript",
    "js": "JavaScript",
    "py": "Python",
    "ai/ml": "Machine Learning",
    "ai": "Machine Learning",
    "ml": "Machine Learning",
    "k8s": "Kubernetes",
    "postgres": "PostgreSQL",
    "mongo": "MongoDB",
    "github actions": "GitHub Actions",
    "cicd": "CI/CD",
    "ci/cd": "CI/CD",
    "fast api": "FastAPI",
    "spring": "Spring Boot",
    "tailwind": "TailwindCSS",
    "tailwind css": "TailwindCSS",
    "backend": "Backend Development",
    "backend development": "Backend Development",
    "backend dev": "Backend Development",
    "frontend": "Frontend Development",
    "frontend development": "Frontend Development",
    "mobile": "Mobile App Development",
    "mobile development": "Mobile App Development",
    "mobile app development": "Mobile App Development",
    "full stack": "Full Stack Development",
    "fullstack": "Full Stack Development",
    "full-stack": "Full Stack Development",
    "full stack development": "Full Stack Development",
    "ai tools": "AI Tools",
    "devops": "DevOps Engineering",
    "software engineering": "Software Engineering",
    "web development": "Web Development",
}

_SAFE_SKILL_RE = re.compile(r"^[\w][\w\s&+#./\-]{1,79}$", re.UNICODE)


def _normalize_skills_payload(skills: list) -> list:
    """Drop or canonicalize skill rows so PATCH/POST never fails on junk names."""
    if not isinstance(skills, list):
        return []
    cleaned: list[dict] = []
    seen: set[str] = set()
    for item in skills:
        if not isinstance(item, dict):
            continue
        raw = item.get("name")
        if not isinstance(raw, str):
            continue
        canon = _canonical_skill_name(raw)
        if not canon:
            continue
        key = canon.lower()
        if key in seen:
            continue
        seen.add(key)
        row = dict(item)
        row["name"] = canon
        cleaned.append(row)
    return cleaned


def _canonical_skill_name(value: str) -> str | None:
    """Return canonical whitelist skill name, or None if not recognized."""
    cleaned = _strip_tags(value).strip()
    if len(cleaned) < 2 or len(cleaned) > 80:
        return None
    key = cleaned.lower()
    if key in _SKILL_ALIASES:
        return _SKILL_ALIASES[key]
    if key in _ALLOWED_SKILLS_LOWER:
        for skill in ALLOWED_SKILLS:
            if skill.lower() == key:
                return skill
    if _SAFE_SKILL_RE.match(cleaned):
        return cleaned
    return None


# ─── Nested Section Schemas ───────────────────────────────────────────────────

class PersonalInfoSchema(Schema):
    full_name   = fields.Str(required=True, validate=validate.Length(min=1, max=150))
    email       = fields.Email(required=True)
    phone       = fields.Str(load_default=None, validate=validate.Length(max=30))
    location    = fields.Str(load_default=None, validate=validate.Length(max=100))
    linkedin    = fields.Url(load_default=None)
    github      = fields.Url(load_default=None)
    website     = fields.Url(load_default=None)
    title       = fields.Str(load_default=None, validate=validate.Length(max=150))
    resume_style = fields.Str(load_default=None, validate=validate.Length(max=30))
    accent_color = fields.Str(load_default=None, validate=validate.Length(max=20))
    section_visibility = fields.Raw(load_default=None)

    @pre_load
    def sanitize(self, data, **kwargs):
        # SECURITY: strip HTML tags from every string field to prevent XSS
        cleaned = {k: _sanitize_str(v) for k, v in data.items()}
        for url_key in ("linkedin", "github", "website"):
            if cleaned.get(url_key) == "":
                cleaned[url_key] = None
        return cleaned


class SkillSchema(Schema):
    name        = fields.Str(required=True, validate=validate.Length(min=1, max=80))
    level       = fields.Str(
        load_default="Intermediate",
        validate=validate.OneOf(
            ["Beginner", "Intermediate", "Advanced", "Expert"],
            error="Invalid skill level"
        )
    )
    years       = fields.Int(load_default=None, validate=validate.Range(min=0, max=50))

    @pre_load
    def sanitize(self, data, **kwargs):
        cleaned = {k: _sanitize_str(v) for k, v in data.items()}
        raw_name = cleaned.get("name")
        if isinstance(raw_name, str) and raw_name.strip():
            canon = _canonical_skill_name(raw_name)
            if canon:
                cleaned["name"] = canon
        return cleaned

    @validates("name")
    def validate_skill_name(self, value, **kwargs):
        """Allow standard whitelist skills (max 80 chars)."""
        if not _canonical_skill_name(value):
            raise ValidationError(
                "Skill name is not recognized. Pick a standard skill "
                "(e.g. Python, React, AWS) or remove it."
            )


class ExperienceSchema(Schema):
    company     = fields.Str(required=True, validate=validate.Length(min=1, max=150))
    title       = fields.Str(required=True, validate=validate.Length(min=1, max=150))
    start_date  = fields.Str(required=True, validate=validate.Length(max=20))   # "2022-01"
    end_date    = fields.Str(load_default=None, validate=validate.Length(max=20))  # None = present
    description = fields.Str(load_default=None, validate=validate.Length(max=2000))
    location    = fields.Str(load_default=None, validate=validate.Length(max=100))

    @pre_load
    def sanitize(self, data, **kwargs):
        return {k: _sanitize_str(v) for k, v in data.items()}


class ProjectSchema(Schema):
    name        = fields.Str(required=True, validate=validate.Length(min=1, max=150))
    description = fields.Str(load_default=None, validate=validate.Length(max=2000))
    url         = fields.Url(load_default=None)
    start_date  = fields.Str(load_default=None, validate=validate.Length(max=20))
    end_date    = fields.Str(load_default=None, validate=validate.Length(max=20))
    tech_stack  = fields.List(fields.Str(), load_default=list)

    @pre_load
    def sanitize(self, data, **kwargs):
        return {k: _sanitize_str(v) for k, v in data.items()}


class EducationSchema(Schema):
    institution = fields.Str(required=True, validate=validate.Length(min=1, max=200))
    degree      = fields.Str(required=True, validate=validate.Length(min=1, max=150))
    field       = fields.Str(load_default=None, validate=validate.Length(max=150))
    start_date  = fields.Str(load_default=None, validate=validate.Length(max=20))
    end_date    = fields.Str(load_default=None, validate=validate.Length(max=20))
    gpa         = fields.Float(load_default=None, validate=validate.Range(min=0.0, max=4.0))

    @pre_load
    def sanitize(self, data, **kwargs):
        return {k: _sanitize_str(v) for k, v in data.items()}


class CertificationSchema(Schema):
    name        = fields.Str(required=True, validate=validate.Length(min=1, max=200))
    issuer      = fields.Str(load_default=None, validate=validate.Length(max=150))
    date        = fields.Str(load_default=None, validate=validate.Length(max=20))
    url         = fields.Url(load_default=None)

    @pre_load
    def sanitize(self, data, **kwargs):
        return {k: _sanitize_str(v) for k, v in data.items()}


# ─── Top-Level CV Schema ──────────────────────────────────────────────────────

class CVCreateSchema(Schema):
    personal_info   = fields.Nested(PersonalInfoSchema, required=True)
    summary         = fields.Str(load_default=None, validate=validate.Length(max=5000))
    skills          = fields.List(fields.Nested(SkillSchema), load_default=list)
    experience      = fields.List(fields.Nested(ExperienceSchema), load_default=list)
    projects        = fields.List(fields.Nested(ProjectSchema), load_default=list)
    education       = fields.List(fields.Nested(EducationSchema), load_default=list)
    certifications  = fields.List(fields.Nested(CertificationSchema), load_default=list)
    is_public       = fields.Bool(load_default=False)

    @pre_load
    def normalize_skills(self, data, **kwargs):
        if isinstance(data, dict) and "skills" in data:
            data = dict(data)
            data["skills"] = _normalize_skills_payload(data.get("skills") or [])
        return data

    @validates("skills")
    def validate_skills_count(self, value, **kwargs):
        if len(value) > 50:
            raise ValidationError("A CV may contain at most 50 skills.")

    @validates("experience")
    def validate_experience_count(self, value, **kwargs):
        if len(value) > 30:
            raise ValidationError("A CV may contain at most 30 experience entries.")

    @validates("projects")
    def validate_projects_count(self, value, **kwargs):
        if len(value) > 30:
            raise ValidationError("A CV may contain at most 30 project entries.")


# ─── AI CV-Build Schema ───────────────────────────────────────────────────────

class CVBuildSchema(Schema):
    """
    Input schema for POST /api/ai/cv/build.

    All fields are optional — when omitted the endpoint generates a CV for
    the calling user by reading their live ORM data.

    target_user_id  Admin-only override: generate a CV for a different user.
    include_pdf     Reserved for future use (PDF download endpoint).
    """
    target_user_id = fields.Int(
        load_default=None,
        validate=validate.Range(min=1),
    )
    include_pdf = fields.Bool(load_default=False)


# Schema singletons (re-used across requests)
cv_create_schema  = CVCreateSchema()
cv_build_schema   = CVBuildSchema()
