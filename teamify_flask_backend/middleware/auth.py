from functools import wraps
from flask import current_app, jsonify
from flask_jwt_extended import verify_jwt_in_request, get_jwt_identity


# ─── RBAC helpers ─────────────────────────────────────────────────────────────

def get_project_role(user_id: int, project_id: int):
    """
    Return the effective role of *user_id* on *project_id*:
      'admin'  – user has global admin role (full access to everything)
      'owner'  – user created the project
      'member' – user was added to project_members with role 'member'
      'guest'  – user has global guest role; gets read-only access if added as member
      None     – no access
    """
    from models.user import User
    from models.project import Project
    from models.project_member import ProjectMember

    user = User.query.filter_by(id=user_id).first()
    if not user:
        return None
    if user.role == "admin":
        return "admin"

    project = Project.query.filter_by(id=project_id).first()
    if not project:
        return None
    if project.user_id == user_id:
        # guest users who somehow created a project are still read-only on others
        return "owner" if user.role != "guest" else "guest"

    pm = ProjectMember.query.filter_by(project_id=project_id, user_id=user_id).first()
    if pm:
        # guests are always capped at read-only regardless of their member role
        return "guest" if user.role == "guest" else pm.role

    return None


# Access-level constants
# guest = read-only (view projects/tasks, cannot mutate anything)
_READ_ROLES   = {"admin", "owner", "member", "guest"}   # can GET
_MEMBER_ROLES = {"admin", "owner", "member"}             # can update status/progress
_WRITE_ROLES  = {"admin", "owner"}                       # full write (create/update/delete)


def auth_required(fn):
    """
    Auth guard middleware decorator.
    Protects routes by requiring a valid JWT access token
    in the Authorization header: 'Bearer <token>'.

    - Returns 401 if token is missing, invalid, or expired.
    - On success, the route can access the current user via get_jwt_identity().
    """

    @wraps(fn)
    def wrapper(*args, **kwargs):
        try:
            verify_jwt_in_request()
        except Exception as e:
            return jsonify({
                "error": "Unauthorized",
                "message": "Missing or invalid token. Please log in."
            }), 401
        return fn(*args, **kwargs)

    return wrapper


def admin_required(fn):
    """
    Admin guard middleware decorator.
    Extends auth_required by also verifying the user has role='admin'.

    - Returns 401 if token is missing, invalid, or expired.
    - Returns 403 if the authenticated user is not an admin.
    """

    @wraps(fn)
    def wrapper(*args, **kwargs):
        # Step 1: verify token
        try:
            verify_jwt_in_request()
        except Exception:
            return jsonify({
                "error": "Unauthorized",
                "message": "Missing or invalid token. Please log in."
            }), 401

        # Step 2: check role in DB (import here to avoid circular imports)
        from models.user import User
        user_id = get_jwt_identity()
        user = User.query.filter_by(id=int(user_id)).first()

        if not user or user.role != "admin":
            return jsonify({
                "error": "Forbidden",
                "message": "Admin access required."
            }), 403

        if current_app.config.get("ADMIN_2FA_REQUIRED"):
            if not user.totp_enabled:
                return jsonify({
                    "error": "Admin 2FA required",
                    "message": "Enable two-factor authentication to access the admin panel.",
                    "requires_2fa_setup": True,
                }), 403

            from flask_jwt_extended import get_jwt
            claims = get_jwt() or {}
            if claims.get("admin_2fa_pending"):
                return jsonify({
                    "error": "Admin 2FA confirmation required",
                    "message": "Enter your authenticator code to access the admin panel.",
                    "requires_2fa_login": True,
                }), 403

        return fn(*args, **kwargs)

    return wrapper
