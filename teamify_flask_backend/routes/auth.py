import logging
import re
from typing import Any, cast

from flask import Blueprint, current_app, request, jsonify, make_response
from flask_bcrypt import Bcrypt
from flask_jwt_extended import (
    create_access_token, create_refresh_token,
    verify_jwt_in_request, get_jwt_identity, jwt_required, get_jwt,
    set_access_cookies, set_refresh_cookies, unset_jwt_cookies,
)
from datetime import datetime, timezone, timedelta
from models import db
from models.user import User
from models.log import Log
from models.login_log import LoginLog
from services.anomaly import check_login_anomalies
from services.audit_log_service import log_security_event
from services.email_service import send_password_reset_email
from app import limiter

logger = logging.getLogger(__name__)

# ─── Lockout constants ────────────────────────────────────────────────────────────
MAX_FAILED_ATTEMPTS = 5         # lock after this many consecutive failures
LOCKOUT_DURATION_MINUTES = 15   # lock duration in minutes


def _record_login_attempt(user_id, status: str) -> None:
    """Persist a LoginLog row. Never raises (logging failure must not block auth)."""
    try:
        ip = request.remote_addr or "unknown"
        ua = (request.headers.get("User-Agent") or "")[:512]
        entry = LoginLog(
            user_id=user_id,
            status=status,
            ip_address=ip,
            device_info=ua,
        )
        db.session.add(entry)
        db.session.commit()
    except Exception:
        db.session.rollback()

EMAIL_RE = re.compile(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
# At least 8 chars, 1 uppercase letter, 1 digit
PASSWORD_RE = re.compile(r'^(?=.*[A-Z])(?=.*\d).{8,}$')

auth_bp = Blueprint("auth", __name__, url_prefix="/api/auth")
bcrypt = Bcrypt()


def _session_access_token(user_id, additional_claims: dict | None = None) -> str:
    from services.system_settings_service import get_session_timeout_minutes

    kwargs: dict[str, Any] = {
        "identity": str(user_id),
        "expires_delta": timedelta(minutes=get_session_timeout_minutes()),
    }
    if additional_claims:
        kwargs["additional_claims"] = additional_claims
    return create_access_token(**kwargs)


def _track_session(user_id: int, access_token: str) -> None:
    from services.security_session_service import register_session

    ip = request.remote_addr or "unknown"
    ua = (request.headers.get("User-Agent") or "")[:512]
    register_session(user_id, access_token, ip_address=ip, device_info=ua)


@auth_bp.route("/public-settings", methods=["GET"])
def public_settings():
    """Public platform settings for clients (registration gate, upload limits)."""
    from services.system_settings_service import get_public_settings

    return jsonify(get_public_settings()), 200


def _request_json() -> dict[str, Any]:
    """Return the JSON body as a dict (empty dict when missing or invalid)."""
    payload = request.get_json(silent=True, force=True)
    return payload if isinstance(payload, dict) else {}


def _format_validation_errors(err) -> list[str]:
    """Flatten Marshmallow ValidationError messages into a string list."""
    error_msgs: list[str] = []
    messages = err.messages
    if isinstance(messages, dict):
        for field_msgs in messages.values():
            if isinstance(field_msgs, (list, tuple)):
                error_msgs.extend(str(msg) for msg in field_msgs)
            else:
                error_msgs.append(str(field_msgs))
    elif isinstance(messages, (list, tuple)):
        error_msgs.extend(str(msg) for msg in messages)
    else:
        error_msgs.append(str(messages))
    return error_msgs


@auth_bp.route("/register", methods=["POST"])
@limiter.limit("5 per minute")
def register():
    """
    Register a new user.
    ---
    tags:
      - Auth
    parameters:
      - in: body
        name: body
        required: true
        schema:
          type: object
          required:
            - display_name
            - email
            - password
          properties:
            display_name:
              type: string
              example: johndoe
              description: Unique display name shown in the app
            email:
              type: string
              example: john@example.com
            password:
              type: string
              example: Password1
              minLength: 8
              description: Min 8 chars, must include at least 1 uppercase letter and 1 digit
            full_name:
              type: string
              example: John Doe
              description: Optional real full name
            role:
              type: string
              enum: [member, guest]
              example: member
              description: |
                System permission level. Defaults to 'member'.
                - member  → standard user (default)
                - guest   → read-only access
                - admin   → admin-only, requires existing admin JWT
            user_type:
              type: string
              enum: [freelancer, student, employee, business]
              example: freelancer
              description: |
                How the user describes themselves (optional).
                - freelancer → independent contractor / remote worker
                - student    → currently studying
                - employee   → works at a company
                - business   → owns or runs a business
    responses:
      201:
        description: User registered successfully
        schema:
          type: object
          properties:
            message:
              type: string
            user:
              type: object
              properties:
                id:
                  type: string
                display_name:
                  type: string
                full_name:
                  type: string
                email:
                  type: string
                role:
                  type: string
                user_type:
                  type: string
            access_token:
              type: string
      400:
        description: Validation errors
        schema:
          type: object
          properties:
            error:
              type: string
              example: Validation failed
            messages:
              type: array
              items:
                type: string
      409:
        description: Display name or email already exists
        schema:
          type: object
          properties:
            error:
              type: string
              example: Conflict
            message:
              type: string
              example: Display name already exists
    """
    data = _request_json()

    if not data:
        return jsonify({"error": "Request body is required"}), 400

    from services.system_settings_service import is_registration_enabled, validate_password

    from marshmallow import ValidationError
    from validators.auth_validator import register_schema

    try:
        data = cast(dict[str, Any], register_schema.load(data))
    except ValidationError as err:
        return jsonify({
            "error": "Validation failed",
            "messages": _format_validation_errors(err),
        }), 400

    from utils.user_names import generate_unique_display_name, validate_username

    full_name = (data.get("full_name") or "").strip()
    email = data.get("email")
    password = data.get("password")
    role = data.get("role")
    user_type = data.get("user_type")

    # Honour the handle picked on the signup form when it is valid and free;
    # otherwise fall back to a generated one the user can change in profile.
    requested_username = (data.get("username") or "").strip()
    display_name = None
    if requested_username and not validate_username(requested_username):
        if not User.query.filter_by(display_name=requested_username).first():
            display_name = requested_username
    if not display_name:
        display_name = generate_unique_display_name()

    # Check if an authenticated admin is making the request
    is_admin_caller = False
    try:
        verify_jwt_in_request(optional=True)
        caller_id = get_jwt_identity()
        if caller_id:
            caller = User.query.filter_by(id=int(caller_id)).first()
            if caller and caller.role == "admin":
                is_admin_caller = True
    except Exception:
        pass

    if not is_admin_caller and not is_registration_enabled():
        return jsonify({
            "error": "Registration disabled",
            "message": "New user registration is currently disabled by the administrator.",
        }), 403

    ok, pw_msg = validate_password(str(password or ""))
    if not ok:
        return jsonify({"error": "Validation failed", "messages": [pw_msg]}), 400

    PUBLIC_ROLES = {"member", "guest"}
    allowed_roles = {"member", "guest", "admin"} if is_admin_caller else PUBLIC_ROLES
    if role not in allowed_roles:
        return jsonify({
            "error": "Validation failed", 
            "messages": [f"Role '{role}' is not allowed. " + 
                         (f"Allowed: {', '.join(sorted(allowed_roles))}" if is_admin_caller
                          else f"Allowed for self-registration: {', '.join(sorted(PUBLIC_ROLES))}")]
        }), 400

    # --- Check duplicates ---
    if User.query.filter_by(email=email).first():
        return jsonify({"error": "Conflict", "message": "Email already exists"}), 409

    # --- Hash password with bcrypt ---
    hashed_password = bcrypt.generate_password_hash(password).decode("utf-8")

    # --- Create user ---
    new_user = User(
        display_name=display_name,
        full_name=full_name or None,
        email=email,
        password=hashed_password,
        role=role,
        user_type=user_type,
        professional_field=data.get("professional_field") or None,
        experience_level=data.get("experience_level") or None,
        availability=data.get("availability") or None,
        skills=data.get("skills") or None,
        current_level=data.get("current_level") or None,
        major=data.get("major") or None,
        looking_for_team=data.get("looking_for_team"),
        reason_for_joining=data.get("reason_for_joining") or None,
        university_id=(data.get("university_id") or None),
        university_name=(data.get("university_name") or None),
        is_custom_university=bool(data.get("is_custom_university")),
    )
    db.session.add(new_user)
    db.session.flush()  # get new_user.id without committing yet

    # --- Log the registration (single commit) ---
    log = Log(
        action="REGISTER",
        entity="User",
        entity_id=new_user.id,
        details=f"User '{display_name}' registered with role '{role}'",
        user_id=new_user.id,
    )
    db.session.add(log)
    db.session.commit()

    # --- Generate JWT access + refresh tokens ---
    access_token = _session_access_token(new_user.id)
    _track_session(new_user.id, access_token)
    refresh_token = create_refresh_token(identity=str(new_user.id))

    # ── VULN-002 FIX ─────────────────────────────────────────────────────────
    # Tokens are set as HttpOnly cookies so they are never accessible via JS,
    # protecting against XSS token theft. The JSON body still returns user
    # data (but NOT the raw token strings) so Flutter can read user info.
    response = make_response(jsonify({
        "message": "User registered successfully",
        "user": new_user.to_dict(),
        # access_token also included in JSON for backward-compat with mobile
        # clients that cannot read cookies (native Android/iOS).
        "access_token": access_token,
        "refresh_token": refresh_token,
    }), 201)
    set_access_cookies(response, access_token)
    set_refresh_cookies(response, refresh_token)
    return response


@auth_bp.route("/login", methods=["POST"])
@limiter.limit("5 per minute")
def login():
    """
    Log in an existing user.
    ---
    tags:
      - Auth
    parameters:
      - in: body
        name: body
        required: true
        schema:
          type: object
          required:
            - email
            - password
          properties:
            email:
              type: string
              example: john@example.com
            password:
              type: string
              example: password123
    responses:
      200:
        description: Login successful
        schema:
          type: object
          properties:
            message:
              type: string
            user:
              type: object
              properties:
                id:
                  type: string
                display_name:
                  type: string
                email:
                  type: string
                role:
                  type: string
            access_token:
              type: string
            refresh_token:
              type: string
      400:
        description: Validation errors
        schema:
          type: object
          properties:
            error:
              type: string
              example: Email and password are required
      401:
        description: Invalid email or password
        schema:
          type: object
          properties:
            error:
              type: string
              example: Invalid email or password
    """
    data = _request_json()

    if not data:
        return jsonify({"error": "Request body is required"}), 400

    from marshmallow import ValidationError
    from validators.auth_validator import login_schema

    try:
        data = cast(dict[str, Any], login_schema.load(data))
    except ValidationError as err:
        return jsonify({"error": "Email and password are required", "messages": err.messages}), 400

    email = data.get("email")
    password = data.get("password")

    ip = request.remote_addr or "unknown"

    # --- Find user ---
    user = User.query.filter_by(email=email).first()

    # ─── Task 4: Brute-Force Lockout Check ─────────────────────────────────────
    # Before checking the password, verify the account isn't temporarily locked.
    if user and user.locked_until:
        now_utc = datetime.now(timezone.utc)
        locked_until_aware = (
            user.locked_until.replace(tzinfo=timezone.utc)
            if user.locked_until.tzinfo is None
            else user.locked_until
        )
        if now_utc < locked_until_aware:
            remaining = int((locked_until_aware - now_utc).total_seconds() // 60) + 1
            log_security_event(
                "ACCOUNT_LOCKED",
                user_id=user.id, ip=ip, severity="WARNING",
                details={"remaining_minutes": remaining},
            )
            return jsonify({
                "error": "Account temporarily locked",
                "message": f"Too many failed attempts. Try again in {remaining} minute(s).",
            }), 429
        else:
            # Lock window expired — clear the lockout state
            user.locked_until = None
            user.failed_login_attempts = 0
            db.session.commit()

    # --- Validate credentials ---
    if not user or not bcrypt.check_password_hash(user.password, password):
        # ─── Task 4: Increment failure counter ────────────────────────────────────
        if user:
            user.failed_login_attempts = (user.failed_login_attempts or 0) + 1
            if user.failed_login_attempts >= MAX_FAILED_ATTEMPTS:
                # Trigger account lockout
                user.locked_until = datetime.now(timezone.utc) + timedelta(minutes=LOCKOUT_DURATION_MINUTES)
                db.session.commit()
                log_security_event(
                    "ACCOUNT_LOCKED",
                    user_id=user.id, ip=ip, severity="WARNING",
                    details={"attempts": user.failed_login_attempts},
                )
                return jsonify({
                    "error": "Account temporarily locked",
                    "message": f"Account locked for {LOCKOUT_DURATION_MINUTES} minutes due to too many failed attempts.",
                }), 429
            db.session.commit()

        # Audit + brute-force anomaly detection (IP-level)
        _record_login_attempt(user.id if user else None, "fail")
        log_security_event(
            "LOGIN_FAILED",
            user_id=user.id if user else None, ip=ip, severity="WARNING",
            details={"email": email},
        )
        try:
            check_login_anomalies(ip)
        except Exception:
            pass
        return jsonify({"error": "Invalid email or password"}), 401

    # ─── Task 4: Reset counter on successful login ──────────────────────────────
    user.failed_login_attempts = 0
    user.locked_until = None

    # ─── Approval Gate ───
    if getattr(user, "account_status", "approved") == "pending":
        db.session.commit()
        return jsonify({
            "error": "Account Pending Approval",
            "message": "Your account is awaiting admin approval. You will be notified once approved.",
        }), 403
    if getattr(user, "account_status", "approved") == "rejected":
        db.session.commit()
        reason = user.account_status_note or "Please contact support."
        return jsonify({
            "error": "Account Rejected",
            "message": f"Your account has been rejected. Reason: {reason}",
        }), 403

    # ─── Admin 2FA enforcement ─────────────────────────────────────────────────
    requires_2fa_setup = False
    requires_2fa_login = False
    token_claims = {}
    if (user.role or "").lower() == "admin" and current_app.config.get(
        "ADMIN_2FA_REQUIRED"
    ):
        if not user.totp_enabled or not user.totp_secret:
            requires_2fa_setup = True
        else:
            totp_code = (data.get("totp_code") or data.get("token") or "").strip()
            if not totp_code:
                requires_2fa_login = True
                token_claims["admin_2fa_pending"] = True
            else:
                from services.totp_service import verify_totp
                if not verify_totp(user.totp_secret, str(totp_code)):
                    log_security_event(
                        "ADMIN_2FA_FAILED",
                        user_id=user.id, ip=ip, severity="WARNING",
                    )
                    return jsonify({"error": "Invalid 2FA code"}), 401

    # --- Log the login ---
    log = Log(
        action="LOGIN",
        entity="User",
        entity_id=user.id,
        details=f"User '{user.display_name}' logged in",
        user_id=user.id,
    )
    db.session.add(log)
    db.session.commit()
    _record_login_attempt(user.id, "success")
    log_security_event(
        "LOGIN_SUCCESS",
        user_id=user.id, ip=ip,
        details={"display_name": user.display_name},
    )

    # --- Generate JWT access + refresh tokens ---
    access_token = _session_access_token(user.id, token_claims or None)
    _track_session(user.id, access_token)
    refresh_token = create_refresh_token(identity=str(user.id))

    # ── VULN-002 FIX ─────────────────────────────────────────────────────────
    # Tokens are delivered in HttpOnly cookies AND in the JSON body.
    # Web clients benefit from cookies (XSS-safe); native mobile clients
    # can fall back to reading access_token from the JSON body.
    response = make_response(jsonify({
        "message": "Login successful",
        "user": user.to_dict(),
        "access_token": access_token,
        "refresh_token": refresh_token,
        "requires_2fa_setup": requires_2fa_setup,
        "requires_2fa_login": requires_2fa_login,
    }), 200)
    set_access_cookies(response, access_token)
    set_refresh_cookies(response, refresh_token)
    return response


# ─── GET /api/auth/me ─────────────────────────────────────────────────────────

@auth_bp.route("/me", methods=["GET"])
def me():
    """
    Get the currently authenticated user from the JWT token.
    ---
    tags:
      - Auth
    security:
      - Bearer: []
    responses:
      200:
        description: Current user data
        schema:
          type: object
          properties:
            user:
              type: object
      401:
        description: Missing or invalid token
        schema:
          type: object
          properties:
            error:
              type: string
              example: Unauthorized
      404:
        description: User not found
        schema:
          type: object
          properties:
            error:
              type: string
              example: Not Found
    """
    from middleware.auth import auth_required as _guard
    from flask_jwt_extended import verify_jwt_in_request
    try:
        verify_jwt_in_request()
    except Exception:
        return jsonify({"error": "Unauthorized", "message": "Missing or invalid token"}), 401

    user_id = get_jwt_identity()
    user = User.query.filter_by(id=int(user_id)).first()
    if not user:
        return jsonify({"error": "Not Found", "message": "User not found"}), 404

    return jsonify({"user": user.to_dict()}), 200


# ─── POST /api/auth/refresh ───────────────────────────────────────────────────

@auth_bp.route("/refresh", methods=["POST"])
@jwt_required(refresh=True)
def refresh():
    """
    Get a new access token using a valid refresh token.
    ---
    tags:
      - Auth
    security:
      - Bearer: []
    responses:
      200:
        description: New access token issued
        schema:
          type: object
          properties:
            access_token:
              type: string
      401:
        description: Missing or invalid refresh token
    """
    user_id = get_jwt_identity()
    new_access_token = _session_access_token(user_id)
    _track_session(int(user_id), new_access_token)
    # ── VULN-002 FIX: refresh the cookie as well ───────────────────────────
    response = make_response(jsonify({"access_token": new_access_token}), 200)
    set_access_cookies(response, new_access_token)
    return response


# ─── POST /api/auth/logout ────────────────────────────────────────────────────

@auth_bp.route("/logout", methods=["POST"])
@jwt_required()
def logout():
    """
    Revoke the current access token (logout).
    ---
    tags:
      - Auth
    security:
      - Bearer: []
    responses:
      200:
        description: Successfully logged out
        schema:
          type: object
          properties:
            message:
              type: string
              example: Successfully logged out
      401:
        description: Missing or invalid token
        schema:
          type: object
          properties:
            msg:
              type: string
              example: Missing Authorization Header
    """
    jwt_data = get_jwt()
    jti = jwt_data["jti"]
    from datetime import datetime, timezone
    exp_ts = jwt_data.get("exp")
    expires_at = (
        datetime.fromtimestamp(exp_ts, tz=timezone.utc) if exp_ts else None
    )
    from services.security_session_service import revoke_session_jti

    revoke_session_jti(jti, expires_at=expires_at)
    # ── VULN-002 FIX: clear JWT cookies on logout ──────────────────────────
    response = make_response(jsonify({"message": "Successfully logged out"}), 200)
    unset_jwt_cookies(response)
    return response


# ─── POST /api/auth/forgot-password ───────────────────────────────────────────

@auth_bp.route("/forgot-password", methods=["POST"])
@limiter.limit("3 per minute")
def forgot_password():
    """
    Request a password-reset OTP. The OTP is emailed via Resend when configured.
    ---
    tags:
      - Auth
    parameters:
      - in: body
        name: body
        required: true
        schema:
          type: object
          required:
            - email
          properties:
            email:
              type: string
              example: john@example.com
    responses:
      200:
        description: OTP request received
        schema:
          type: object
          properties:
            message:
              type: string
              example: If an account exists with this email, an OTP has been sent
      400:
        description: Email is required
        schema:
          type: object
          properties:
            error:
              type: string
              example: Email is required
    """
    data = request.get_json(silent=True, force=True) or {}
    email = data.get("email", "").strip()

    if not email:
        return jsonify({"error": "Email is required"}), 400

    user = User.query.filter_by(email=email).first()
    if not user:
        # Return same response to prevent user enumeration
        return jsonify({"message": "If an account exists with this email, an OTP has been sent"}), 200

    otp = user.generate_otp()
    recipient = user.email
    recipient_name = (user.full_name or user.display_name or "").strip()
    user_id = user.id
    db.session.commit()

    try:
        from services.notification_email_service import record_standalone_email

        result = send_password_reset_email(
            to=recipient,
            recipient_name=recipient_name,
            otp=otp,
            expires_minutes=10,
        )
        record_standalone_email(
            user_id=user_id,
            recipient_email=recipient,
            email_type="password_reset_otp",
            result=result,
        )
        if not result.success:
            logger.warning(
                "Password reset email was not delivered user_id=%s status=%s",
                user_id,
                result.status,
            )
    except Exception:
        logger.warning("Password reset email failed user_id=%s", user_id, exc_info=True)
    return jsonify({
        "message": "If an account exists with this email, an OTP has been sent",
    }), 200


# ─── POST /api/auth/verify-otp ────────────────────────────────────────────────

@auth_bp.route("/verify-otp", methods=["POST"])
@limiter.limit("5 per minute")
def verify_otp():
    """
    Verify the OTP code. Returns a short-lived reset token on success.
    ---
    tags:
      - Auth
    parameters:
      - in: body
        name: body
        required: true
        schema:
          type: object
          required:
            - email
            - otp
          properties:
            email:
              type: string
              example: john@example.com
            otp:
              type: string
              example: "1234"
    responses:
      200:
        description: OTP verified, reset_token returned
        schema:
          type: object
          properties:
            message:
              type: string
              example: OTP verified successfully
            reset_token:
              type: string
              example: eyJhbGci...
      400:
        description: Invalid or expired OTP
        schema:
          type: object
          properties:
            error:
              type: string
              example: Invalid or expired OTP
    """
    data = request.get_json(silent=True, force=True) or {}
    email = data.get("email", "").strip()
    
    otp_raw = data.get("otp")
    if not isinstance(otp_raw, str):
        return jsonify({"error": "OTP must be a string"}), 400
        
    otp = otp_raw.strip()

    if not email or not otp:
        return jsonify({"error": "Email and OTP are required"}), 400

    user = User.query.filter_by(email=email).first()
    if not user:
        return jsonify({"error": "Invalid email or OTP"}), 400

    if not user.verify_otp(otp):
        return jsonify({"error": "Invalid or expired OTP"}), 400

    # Create a short-lived token that authorises the password reset
    reset_token = create_access_token(
        identity=str(user.id),
        expires_delta=__import__('datetime').timedelta(minutes=5),
        additional_claims={"purpose": "password_reset"},
    )

    return jsonify({
        "message": "OTP verified successfully",
        "reset_token": reset_token,
    }), 200


# ─── POST /api/auth/reset-password ────────────────────────────────────────────

@auth_bp.route("/reset-password", methods=["POST"])
@limiter.limit("5 per minute")
def reset_password():
    """
    Reset the user's password using the reset token from verify-otp.
    ---
    tags:
      - Auth
    parameters:
      - in: body
        name: body
        required: true
        schema:
          type: object
          required:
            - reset_token
            - new_password
          properties:
            reset_token:
              type: string
            new_password:
              type: string
              minLength: 8
    responses:
      200:
        description: Password reset successfully
        schema:
          type: object
          properties:
            message:
              type: string
              example: Password reset successfully
      400:
        description: Validation error
        schema:
          type: object
          properties:
            error:
              type: string
              example: reset_token and new_password are required
      401:
        description: Invalid or expired reset token
        schema:
          type: object
          properties:
            error:
              type: string
              example: Invalid or expired reset token
      404:
        description: User not found
        schema:
          type: object
          properties:
            error:
              type: string
              example: User not found
    """
    data = request.get_json(silent=True, force=True) or {}
    reset_token = data.get("reset_token", "").strip()
    new_password = data.get("new_password", "")

    from services.system_settings_service import validate_password

    if not reset_token or not new_password:
        return jsonify({"error": "reset_token and new_password are required"}), 400

    ok, pw_msg = validate_password(new_password)
    if not ok:
        return jsonify({"error": pw_msg}), 400

    # Decode the reset token
    from flask_jwt_extended import decode_token
    try:
        token_data = decode_token(reset_token)
    except Exception:
        return jsonify({"error": "Invalid or expired reset token"}), 401

    if token_data.get("purpose") != "password_reset":
        return jsonify({"error": "Invalid token purpose"}), 401

    user_id = token_data.get("sub")
    if not user_id:
        return jsonify({"error": "Invalid reset token"}), 401

    user = User.query.filter_by(id=int(user_id)).first()
    if not user:
        return jsonify({"error": "User not found"}), 404

    user.password = bcrypt.generate_password_hash(new_password).decode("utf-8")
    user.clear_otp()
    db.session.commit()

    return jsonify({"message": "Password reset successfully"}), 200

# ─── POST /api/auth/google ────────────────────────────────────────────────────
# BUG-002 FIX: Google OAuth backend endpoint.
# Receives the Google ID token from the Flutter frontend (via google_sign_in
# package), verifies it server-side, then issues app JWTs.

@auth_bp.route("/google", methods=["POST"])
@limiter.limit("10 per minute")
def google_login():
    """
    Authenticate via Google OAuth ID token.
    ---
    tags:
      - Auth
    parameters:
      - in: body
        name: body
        required: true
        schema:
          type: object
          required:
            - id_token
          properties:
            id_token:
              type: string
              description: Google ID token from the frontend google_sign_in SDK
            user_type:
              type: string
              enum: [freelancer, student, guest]
              description: Optional self-description for new accounts
    responses:
      200:
        description: Login or account creation successful
      400:
        description: id_token missing
      401:
        description: Invalid or expired Google token
    """
    from services.oauth_user_service import (
        extract_oauth_profile,
        find_or_create_google_user,
        normalize_user_type,
        verify_google_id_token,
    )

    data = _request_json()
    raw_token = str(data.get("id_token", "")).strip()

    if not raw_token:
        return jsonify({"error": "Bad Request", "message": "id_token is required"}), 400

    try:
        id_info = verify_google_id_token(raw_token)
    except RuntimeError as exc:
        logger.exception("Google sign-in is not configured")
        return jsonify({"error": "Service Unavailable", "message": str(exc)}), 503
    except ValueError as exc:
        return jsonify({"error": "Unauthorized", "message": f"Invalid Google token: {exc}"}), 401
    except Exception as exc:
        logger.exception("Google token verification failed")
        return jsonify({
            "error": "Unauthorized",
            "message": f"Google sign-in failed: {exc}",
        }), 401

    google_email = str(id_info.get("email", "")).strip()
    google_name = (
        str(id_info.get("name", "")).strip()
        or google_email.split("@")[0]
    )
    google_sub = str(id_info.get("sub", "")).strip()

    if not google_email or not google_sub:
        return jsonify({
            "error": "Unauthorized",
            "message": "Could not retrieve email from Google token",
        }), 401

    user_type = normalize_user_type(data.get("user_type"))
    profile = extract_oauth_profile(data)

    try:
        user, is_new = find_or_create_google_user(
            email=google_email,
            full_name=google_name,
            google_sub=google_sub,
            user_type=user_type,
            bcrypt=bcrypt,
            profile=profile if profile else None,
        )
    except Exception as exc:
        db.session.rollback()
        return jsonify({
            "error": "Internal Server Error",
            "message": f"Could not save Google account: {exc}",
        }), 500

    if not is_new:
        log = Log(
            action="LOGIN_GOOGLE",
            entity="User",
            entity_id=user.id,
            details=f"User '{user.display_name}' logged in via Google OAuth",
            user_id=user.id,
        )
        db.session.add(log)
        db.session.commit()
        _record_login_attempt(user.id, "success")

    access_token = _session_access_token(user.id)
    _track_session(user.id, access_token)
    refresh_token = create_refresh_token(identity=str(user.id))

    status_code = 201 if is_new else 200
    response = make_response(jsonify({
        "message": "Google login successful",
        "user": user.to_dict(),
        "access_token": access_token,
        "refresh_token": refresh_token,
        "is_new_user": is_new,
    }), status_code)
    set_access_cookies(response, access_token)
    set_refresh_cookies(response, refresh_token)
    return response


# ─── POST /api/auth/2fa/setup ─────────────────────────────────────────────────
# Task 1: TOTP 2FA — Step 1: Generate a new TOTP secret and return a QR code.
# The secret is saved (unconfirmed) on the user row. 2FA is only activated
# after the user verifies with a valid token via /api/auth/2fa/verify.

@auth_bp.route("/2fa/setup", methods=["POST"])
@jwt_required()
def setup_2fa():
    """
    Generate a TOTP secret and QR code for the authenticated user.
    ---
    tags:
      - Auth
    security:
      - Bearer: []
    responses:
      200:
        description: QR code PNG (base64) and the raw secret for manual entry
        schema:
          type: object
          properties:
            secret:
              type: string
              example: JBSWY3DPEHPK3PXP
            qr_code:
              type: string
              description: data:image/png;base64,... string
            message:
              type: string
      409:
        description: 2FA already enabled
    """
    from services.totp_service import generate_totp_secret, generate_qr_code_base64
    from services.audit_log_service import log_security_event

    user_id = int(get_jwt_identity())
    user = User.query.filter_by(id=user_id).first()
    if not user:
        return jsonify({"error": "User not found"}), 404

    if user.totp_enabled:
        claims = get_jwt() or {}
        if not claims.get("admin_2fa_pending"):
            return jsonify({"error": "Conflict", "message": "2FA is already enabled for this account."}), 409
        user.totp_enabled = False

    # Generate a new secret (not yet confirmed / enabled)
    secret = generate_totp_secret()
    user.totp_secret = secret
    db.session.commit()

    qr_code = generate_qr_code_base64(secret, user.email)

    log_security_event(
        "2FA_SETUP_INITIATED",
        user_id=user_id,
        ip=request.remote_addr or "unknown",
    )

    return jsonify({
        "message": "Scan the QR code with your authenticator app, then call /2fa/verify to activate.",
        "secret": secret,    # expose for manual entry in authenticator apps
        "qr_code": qr_code,  # base64 PNG for display in the frontend
    }), 200


# ─── POST /api/auth/2fa/verify ────────────────────────────────────────────────
# Task 1: TOTP 2FA — Step 2: Confirm the first valid TOTP token to activate 2FA.

@auth_bp.route("/2fa/verify", methods=["POST"])
@jwt_required()
def verify_2fa():
    """
    Verify a TOTP token and activate (or check) 2FA for the authenticated user.
    ---
    tags:
      - Auth
    security:
      - Bearer: []
    parameters:
      - in: body
        name: body
        required: true
        schema:
          type: object
          required:
            - token
          properties:
            token:
              type: string
              example: "123456"
              description: 6-digit code from the authenticator app
    responses:
      200:
        description: 2FA verified (and enabled if it wasn't already)
        schema:
          type: object
          properties:
            message:
              type: string
      400:
        description: Invalid or expired TOTP token
      412:
        description: 2FA setup not initiated (no secret stored)
    """
    from services.totp_service import verify_totp
    from services.audit_log_service import log_security_event

    user_id = int(get_jwt_identity())
    user = User.query.filter_by(id=user_id).first()
    if not user:
        return jsonify({"error": "User not found"}), 404

    if not user.totp_secret:
        return jsonify({
            "error": "Precondition Failed",
            "message": "Call /2fa/setup first to generate a TOTP secret.",
        }), 412

    data = request.get_json(silent=True, force=True) or {}
    token = data.get("token", "")

    if not verify_totp(user.totp_secret, str(token)):
        log_security_event(
            "2FA_VERIFY_FAILED",
            user_id=user_id,
            ip=request.remote_addr or "unknown",
            severity="WARNING",
        )
        return jsonify({"error": "Invalid or expired TOTP token"}), 400

    # First successful verification activates 2FA
    if not user.totp_enabled:
        user.totp_enabled = True
        db.session.commit()

    log_security_event(
        "2FA_VERIFIED",
        user_id=user_id,
        ip=request.remote_addr or "unknown",
    )

    db.session.refresh(user)

    access_token = _session_access_token(user.id)
    _track_session(user.id, access_token)
    refresh_token = create_refresh_token(identity=str(user.id))
    payload = {
        "message": "2FA verified successfully. Two-factor authentication is now active.",
        "user": user.to_dict(),
        "access_token": access_token,
        "refresh_token": refresh_token,
    }
    response = make_response(jsonify(payload), 200)
    set_access_cookies(response, access_token)
    set_refresh_cookies(response, refresh_token)
    return response


# ─── POST /api/auth/2fa/confirm-login ─────────────────────────────────────────
# Admin login step 2: confirm TOTP after password login issued a pending token.

@auth_bp.route("/2fa/confirm-login", methods=["POST"])
@jwt_required()
def confirm_2fa_login():
    """Verify admin TOTP after password login and issue a full admin session."""
    from services.totp_service import verify_totp
    from services.audit_log_service import log_security_event

    user_id = int(get_jwt_identity())
    user = User.query.filter_by(id=user_id).first()
    if not user:
        return jsonify({"error": "User not found"}), 404

    if (user.role or "").lower() != "admin":
        return jsonify({"error": "Forbidden", "message": "Admin access required."}), 403

    if not user.totp_enabled or not user.totp_secret:
        return jsonify({
            "error": "Bad Request",
            "message": "Complete 2FA setup before confirming login.",
            "requires_2fa_setup": True,
        }), 400

    data = request.get_json(silent=True, force=True) or {}
    token = (data.get("token") or data.get("totp_code") or "").strip()
    if not token:
        return jsonify({"error": "Bad Request", "message": "Authenticator code is required."}), 400

    if not verify_totp(user.totp_secret, str(token)):
        log_security_event(
            "ADMIN_2FA_FAILED",
            user_id=user_id,
            ip=request.remote_addr or "unknown",
            severity="WARNING",
        )
        return jsonify({"error": "Invalid or expired TOTP token"}), 400

    access_token = _session_access_token(user.id)
    _track_session(user.id, access_token)
    refresh_token = create_refresh_token(identity=str(user.id))

    log_security_event(
        "ADMIN_2FA_LOGIN_CONFIRMED",
        user_id=user_id,
        ip=request.remote_addr or "unknown",
    )

    response = make_response(jsonify({
        "message": "Admin login confirmed.",
        "user": user.to_dict(),
        "access_token": access_token,
        "refresh_token": refresh_token,
    }), 200)
    set_access_cookies(response, access_token)
    set_refresh_cookies(response, refresh_token)
    return response


# ─── DELETE /api/auth/2fa/disable ────────────────────────────────────────────
# Task 1: Allow a user to turn off 2FA by supplying one final valid token.

@auth_bp.route("/2fa/disable", methods=["DELETE"])
@jwt_required()
def disable_2fa():
    """
    Disable 2FA for the authenticated user (requires a valid current TOTP token).
    ---
    tags:
      - Auth
    security:
      - Bearer: []
    parameters:
      - in: body
        name: body
        required: true
        schema:
          type: object
          required:
            - token
          properties:
            token:
              type: string
              example: "123456"
    responses:
      200:
        description: 2FA disabled
      400:
        description: Invalid TOTP token or 2FA not enabled
    """
    from services.totp_service import verify_totp
    from services.audit_log_service import log_security_event

    user_id = int(get_jwt_identity())
    user = User.query.filter_by(id=user_id).first()
    if not user:
        return jsonify({"error": "User not found"}), 404

    if not user.totp_enabled or not user.totp_secret:
        return jsonify({"error": "Bad Request", "message": "2FA is not enabled on this account."}), 400

    data = request.get_json(silent=True, force=True) or {}
    token = data.get("token", "")

    if not verify_totp(user.totp_secret, str(token)):
        return jsonify({"error": "Invalid or expired TOTP token"}), 400

    user.totp_secret = None
    user.totp_enabled = False
    db.session.commit()

    log_security_event(
        "2FA_DISABLED",
        user_id=user_id,
        ip=request.remote_addr or "unknown",
        severity="WARNING",
    )
    return jsonify({"message": "Two-factor authentication has been disabled."}), 200


# ─── POST /api/auth/github ────────────────────────────────────────────────────
# Receives a GitHub OAuth code from the client, exchanges it for a GitHub
# access token, fetches the GitHub user profile, and issues app JWTs.

@auth_bp.route("/github", methods=["POST"])
@limiter.limit("10 per minute")
def github_login():
    """
    GitHub OAuth login — exchange code for app JWT.
    ---
    tags:
      - Auth
    parameters:
      - in: body
        name: body
        required: true
        schema:
          type: object
          required: [code]
          properties:
            code:
              type: string
              description: OAuth code received from GitHub callback
    responses:
      200:
        description: Login successful
      400:
        description: Missing code or GitHub error
      500:
        description: GitHub API error
    """
    import os
    import requests as _req
    from flask import current_app
    from services.oauth_user_service import (
        extract_oauth_profile,
        find_or_create_github_user,
        normalize_user_type,
    )

    data = request.get_json(silent=True, force=True) or {}
    code = data.get("code", "").strip()
    if not code:
        return jsonify({"error": "code is required"}), 400

    client_id = current_app.config.get("GITHUB_CLIENT_ID") or os.getenv("GITHUB_CLIENT_ID", "")
    client_secret = current_app.config.get("GITHUB_CLIENT_SECRET") or os.getenv("GITHUB_CLIENT_SECRET", "")

    if not client_id or not client_secret:
        return jsonify({
            "error": "Service Unavailable",
            "message": (
                "GitHub OAuth is not configured on the server. "
                "Set GITHUB_CLIENT_ID and GITHUB_CLIENT_SECRET in .env"
            ),
        }), 503

    user_type = normalize_user_type(data.get("user_type"))
    profile = extract_oauth_profile(data)

    redirect_uri = (data.get("redirect_uri") or "").strip()
    token_payload: dict[str, str] = {
        "client_id": client_id,
        "client_secret": client_secret,
        "code": code,
    }
    if redirect_uri:
        token_payload["redirect_uri"] = redirect_uri

    try:
        token_resp = _req.post(
            "https://github.com/login/oauth/access_token",
            json=token_payload,
            headers={"Accept": "application/json"},
            timeout=10,
        )
    except Exception as exc:
        logger.exception("GitHub token exchange failed")
        return jsonify({
            "error": "Bad Gateway",
            "message": f"Could not reach GitHub: {exc}",
        }), 502
    if token_resp.status_code != 200:
        return jsonify({"error": "Failed to reach GitHub token endpoint"}), 502

    try:
        token_data = token_resp.json()
    except Exception:
        return jsonify({"error": "Failed to reach GitHub token endpoint"}), 502
    github_token = token_data.get("access_token")
    if not github_token:
        err = token_data.get("error_description", token_data.get("error", "Unknown error"))
        return jsonify({"error": f"GitHub OAuth error: {err}"}), 400

    try:
        profile_resp = _req.get(
            "https://api.github.com/user",
            headers={"Authorization": f"Bearer {github_token}", "Accept": "application/json"},
            timeout=10,
        )
    except Exception as exc:
        logger.exception("GitHub profile fetch failed")
        return jsonify({
            "error": "Bad Gateway",
            "message": f"Could not reach GitHub: {exc}",
        }), 502
    if profile_resp.status_code != 200:
        return jsonify({"error": "Failed to fetch GitHub user profile"}), 502

    try:
        gh_user = profile_resp.json()
    except Exception:
        return jsonify({"error": "Failed to fetch GitHub user profile"}), 502
    if not isinstance(gh_user, dict):
        return jsonify({"error": "Failed to fetch GitHub user profile"}), 502
    github_id = str(gh_user.get("id", ""))
    gh_email = gh_user.get("email") or ""
    gh_name = gh_user.get("name") or gh_user.get("login") or "github_user"
    gh_login = gh_user.get("login") or f"gh_{github_id}"

    if not gh_email:
        try:
            emails_resp = _req.get(
                "https://api.github.com/user/emails",
                headers={"Authorization": f"Bearer {github_token}", "Accept": "application/json"},
                timeout=10,
            )
        except Exception:
            emails_resp = None
        if emails_resp is not None and emails_resp.status_code == 200:
            try:
                email_rows = emails_resp.json()
            except Exception:
                email_rows = []
            if isinstance(email_rows, list):
                for em in email_rows:
                    if isinstance(em, dict) and em.get("primary") and em.get("verified"):
                        gh_email = em.get("email", "")
                        break

    if not github_id:
        return jsonify({"error": "Could not retrieve GitHub user ID"}), 400

    try:
        user, is_new = find_or_create_github_user(
            github_id=github_id,
            email=gh_email,
            full_name=gh_name,
            gh_login=gh_login,
            user_type=user_type,
            bcrypt=bcrypt,
            profile=profile if profile else None,
        )
    except Exception as exc:
        db.session.rollback()
        return jsonify({
            "error": "Internal Server Error",
            "message": f"Could not save GitHub account: {exc}",
        }), 500

    if not is_new:
        db.session.add(Log(
            action="GITHUB_LOGIN",
            entity="User",
            entity_id=user.id,
            details=f"User '{user.display_name}' logged in via GitHub OAuth",
            user_id=user.id,
        ))
        db.session.commit()

    access_token = _session_access_token(user.id)
    _track_session(user.id, access_token)
    refresh_token = create_refresh_token(identity=str(user.id))

    ip = request.remote_addr or "unknown"
    _record_login_attempt(user.id, "success")
    log_security_event(
        "GITHUB_LOGIN_SUCCESS",
        user_id=user.id,
        ip=ip,
        details={"github_login": gh_login, "is_new_user": is_new},
    )

    status_code = 201 if is_new else 200
    response = make_response(jsonify({
        "message": "GitHub login successful",
        "user": user.to_dict(),
        "access_token": access_token,
        "refresh_token": refresh_token,
        "is_new_user": is_new,
    }), status_code)
    set_access_cookies(response, access_token)
    set_refresh_cookies(response, refresh_token)
    return response
