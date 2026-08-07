import re
from marshmallow import Schema, fields, validate, validates, ValidationError, pre_load

# At least 8 chars, 1 uppercase letter, 1 digit
PASSWORD_RE = re.compile(r'^(?=.*[A-Z])(?=.*\d).{8,}$')

VALID_ROLES = ["member", "guest", "admin"]
VALID_USER_TYPES = ["freelancer", "student", "admin"]


class RegisterSchema(Schema):
    # Legacy clients may still send display_name; registration ignores it and
    # assigns a temporary unique handle until the user sets a username in profile.
    display_name = fields.Str(load_default=None, validate=validate.Length(max=80))
    # Handle chosen on the signup form; used as display_name when still free.
    username = fields.Str(load_default=None, validate=validate.Length(max=30))
    email = fields.Email(required=True)
    password = fields.Str(required=True)
    full_name = fields.Str(required=True, validate=validate.Length(min=1, max=150))
    role = fields.Str(
        load_default="member",
        validate=validate.OneOf(VALID_ROLES, error="Invalid role")
    )
    user_type = fields.Str(
        load_default=None,
        validate=validate.OneOf(VALID_USER_TYPES, error="Invalid user_type")
    )
    professional_field = fields.Str(load_default=None)
    experience_level = fields.Str(load_default=None)
    availability = fields.Str(load_default=None)
    skills = fields.Str(load_default=None)
    current_level = fields.Str(load_default=None)
    major = fields.Str(load_default=None)
    looking_for_team = fields.Bool(load_default=None)
    reason_for_joining = fields.Str(load_default=None)
    university_id = fields.Str(load_default=None, validate=validate.Length(max=64))
    university_name = fields.Str(load_default=None, validate=validate.Length(max=200))
    is_custom_university = fields.Bool(load_default=False)

    @pre_load
    def sanitize_strings(self, data, **kwargs):
        """Sanitize string fields before validation (strip whitespace and block basic XSS)."""
        xss_re = re.compile(r'<.*?>')
        for key, value in data.items():
            if isinstance(value, str):
                sanitized = xss_re.sub("", value).strip()
                data[key] = sanitized
        return data

    @validates("password")
    def validate_password(self, value, **kwargs):
        from services.system_settings_service import validate_password as check_password

        ok, message = check_password(value)
        if not ok:
            raise ValidationError(message)


class LoginSchema(Schema):
    email = fields.Email(required=True)
    password = fields.Str(required=True)


class ProfileUpdateSchema(Schema):
    display_name = fields.Str(validate=validate.Length(min=3, max=30))
    full_name = fields.Str(validate=validate.Length(max=150))
    user_type = fields.Str(
        validate=validate.OneOf(VALID_USER_TYPES, error="Invalid user_type")
    )
    professional_field = fields.Str()
    experience_level = fields.Str()
    availability = fields.Str()
    skills = fields.Str()
    current_level = fields.Str()
    major = fields.Str()
    looking_for_team = fields.Bool()
    reason_for_joining = fields.Str()
    university_id = fields.Str(validate=validate.Length(max=64))
    university_name = fields.Str(validate=validate.Length(max=200))
    is_custom_university = fields.Bool()


# Schema singletons
register_schema = RegisterSchema()
login_schema = LoginSchema()
profile_update_schema = ProfileUpdateSchema()
