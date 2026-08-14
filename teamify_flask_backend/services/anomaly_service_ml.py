"""
ML-Based Login Anomaly Detection Service
=========================================
Wraps ml_models/SecurityModel/security_model.pkl — an IsolationForest +
StandardScaler bundle trained on 21 behavioral login features.

The pkl is expected to be a dict: {"model": IsolationForest, "scaler": StandardScaler}

IsolationForest returns:
   predict()      → 1 = normal, -1 = anomaly
   score_samples() → more negative = more anomalous (contamination boundary ≈ 0)
"""
from __future__ import annotations

import logging
import os
from typing import Any, Optional

logger = logging.getLogger(__name__)

_MODEL_PATH = os.path.join(
    os.path.dirname(__file__), "..", "ml_models", "SecurityModel", "security_model.pkl"
)

# The saved security_model.pkl was trained on the numeric columns from
# teamify_login_logs_final.csv, which are: user_id, failed_attempts.
# (select_dtypes(include=['number']) in save_security_model.py)
_FEATURE_COLS = ["user_id", "failed_attempts"]

_bundle_cache: Any = None
_load_error: Optional[str] = None


def _load_bundle() -> Any:
    """Lazy-load the pkl bundle once per process."""
    global _bundle_cache, _load_error

    if _bundle_cache is not None:
        return _bundle_cache
    if _load_error:
        return None

    try:
        import joblib
        path = os.path.abspath(_MODEL_PATH)
        bundle = joblib.load(path)
        if not isinstance(bundle, dict) or "model" not in bundle or "scaler" not in bundle:
            raise ValueError(
                "security_model.pkl must be a dict with 'model' and 'scaler' keys"
            )
        _bundle_cache = bundle
        logger.info("Security anomaly model loaded from %s", path)
        return _bundle_cache
    except FileNotFoundError:
        _load_error = f"security_model.pkl not found at {_MODEL_PATH}"
        logger.warning(_load_error)
    except Exception as exc:
        _load_error = f"Failed to load security_model.pkl: {exc}"
        logger.error(_load_error, exc_info=True)

    return None


def score_login_features(features: dict) -> dict:
    """
    Score a login attempt using the IsolationForest model.

    Parameters
    ----------
    features : dict
        Must contain 'user_id' and 'failed_attempts'.
        Additional keys are silently ignored.

    Returns
    -------
    dict with keys:
        model_available (bool)
        is_anomaly      (bool | None)
        anomaly_score   (float | None)  — raw IF score; ≤ 0 = anomalous
        source          ("ml_model" | "fallback")
        error           (str, only on failure)
    """
    bundle = _load_bundle()
    if bundle is None:
        return {
            "model_available": False,
            "is_anomaly": None,
            "anomaly_score": None,
            "source": "fallback",
            "error": _load_error or "Model not loaded",
        }

    try:
        import pandas as pd
        row = {col: float(features.get(col, 0)) for col in _FEATURE_COLS}
        df = pd.DataFrame([row])[_FEATURE_COLS]
        X_scaled = bundle["scaler"].transform(df)
        raw_score = float(bundle["model"].score_samples(X_scaled)[0])
        prediction = int(bundle["model"].predict(X_scaled)[0])

        return {
            "model_available": True,
            "is_anomaly": prediction == -1,
            "anomaly_score": round(raw_score, 4),
            "source": "ml_model",
        }

    except Exception as exc:
        logger.error("Security anomaly scoring failed: %s", exc, exc_info=True)
        return {
            "model_available": True,
            "is_anomaly": None,
            "anomaly_score": None,
            "source": "fallback",
            "error": str(exc),
        }


def score_login_from_context(
    user_id: int,
    ip_address: str,
    *,
    device: str = "",
    browser: str = "",
    location: str = "",
    failed_attempts: int = 0,
) -> dict:
    """
    High-level helper: builds the 2-feature vector (user_id, failed_attempts)
    that the saved security_model.pkl was trained on, then calls
    score_login_features().

    Returns the same shape as score_login_features().
    """
    features = {
        "user_id": float(user_id),
        "failed_attempts": float(failed_attempts),
    }
    return score_login_features(features)


def detect_anomaly(data: dict) -> dict:
    """
    Compatibility wrapper used by routes/ai.py.
    Accepts a flat dict with optional keys: user_id, ip_address,
    device, browser, location, failed_attempts.

    Returns the same shape as score_login_features().
    """
    user_id = data.get("user_id")
    ip_address = str(data.get("ip_address", "127.0.0.1"))
    device = str(data.get("device", ""))
    browser = str(data.get("browser", ""))
    location = str(data.get("location", ""))
    failed_attempts = int(data.get("failed_attempts", 0))

    if user_id is not None:
        return score_login_from_context(
            int(user_id),
            ip_address,
            device=device,
            browser=browser,
            location=location,
            failed_attempts=failed_attempts,
        )

    # No user_id — score from raw features if provided, otherwise return fallback
    has_features = any(col in data for col in _FEATURE_COLS)
    if has_features:
        return score_login_features(data)

    return {
        "model_available": False,
        "is_anomaly": None,
        "anomaly_score": None,
        "source": "fallback",
        "error": "user_id or explicit feature values are required",
    }


def get_security_model_status() -> dict:
    """Report whether security_model.pkl is present and loaded."""
    bundle = _load_bundle()
    return {
        "file_present": os.path.exists(os.path.abspath(_MODEL_PATH)),
        "loaded": bundle is not None,
        "error": _load_error,
        "path": os.path.abspath(_MODEL_PATH),
    }
