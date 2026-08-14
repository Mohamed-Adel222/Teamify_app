"""
Strict Input Validation Schemas (Week 3 & 4)

Uses marshmallow for strict schema validation on AI and Delay endpoints.
- Strips whitespace and special characters to prevent prompt/SQL injection.
- Enforces type safety and field length limits.
"""
import re
from marshmallow import Schema, fields, validate, validates, ValidationError, pre_load

# ─── Sanitization helper ──────────────────────────────────────────────────────

# Strip characters that could be part of SQL injection or prompt injection attacks.
# Allows: alphanumeric, spaces, hyphens, underscores, periods, commas.
_SAFE_TEXT_RE = re.compile(r"[^\w\s\-_.,]", re.UNICODE)


def _sanitize(value: str) -> str:
    """Remove potentially malicious characters from a string field."""
    return _SAFE_TEXT_RE.sub("", value).strip()


# ─── AI Auto-Assign Schema ────────────────────────────────────────────────────

class AssignTaskSchema(Schema):
    """
    Validates the request body for POST /api/ai/assign.
    Prevents prompt injection via strict character filtering and length caps.
    """

    project_id = fields.Int(
        required=True,
        metadata={"description": "ID of the project to assign within"},
    )

    task_id = fields.Int(
        load_default=None,
        metadata={"description": "Optional task ID to auto-assign immediately"},
    )

    priority = fields.Str(
        load_default="medium",
        validate=validate.OneOf(
            ["low", "medium", "high"],
            error="priority must be one of: low, medium, high",
        ),
    )

    # Optional hint text — aggressively sanitized to prevent prompt injection
    hint = fields.Str(
        load_default=None,
        validate=validate.Length(max=200, error="hint must be 200 characters or fewer"),
    )

    @pre_load
    def strip_strings(self, data, **kwargs):
        """Sanitize all string fields before validation."""
        if isinstance(data.get("priority"), str):
            data["priority"] = data["priority"].strip().lower()
        if isinstance(data.get("hint"), str):
            data["hint"] = _sanitize(data["hint"])
        return data

    @validates("project_id")
    def validate_project_id(self, value, **kwargs):
        if value <= 0:
            raise ValidationError("project_id must be a positive integer")

    @validates("task_id")
    def validate_task_id(self, value, **kwargs):
        if value is not None and value <= 0:
            raise ValidationError("task_id must be a positive integer")


# ─── Delay Prediction Schema ──────────────────────────────────────────────────

class DelayRequestSchema(Schema):
    """
    Validates the request body for POST /api/ai/delay (delay prediction).
    Requires at least one of project_id or task_id, enforces integer IDs.
    """

    project_id = fields.Int(
        load_default=None,
        metadata={"description": "Project ID for project-level delay prediction"},
    )

    task_id = fields.Int(
        load_default=None,
        metadata={"description": "Task ID for task-level delay prediction"},
    )

    from marshmallow import validates_schema

    @validates_schema
    def require_at_least_one(self, data, **kwargs):
        if data.get("project_id") is None and data.get("task_id") is None:
            raise ValidationError(
                "At least one of 'project_id' or 'task_id' must be provided."
            )

    @validates("project_id")
    def validate_project_id(self, value, **kwargs):
        if value is not None and value <= 0:
            raise ValidationError("project_id must be a positive integer")

    @validates("task_id")
    def validate_task_id(self, value, **kwargs):
        if value is not None and value <= 0:
            raise ValidationError("task_id must be a positive integer")


# ─── Schema instances (singletons for performance) ────────────────────────────
assign_task_schema = AssignTaskSchema()
delay_request_schema = DelayRequestSchema()
