"""
Task Pipeline Service
=====================
Provides two functions consumed by routes/ai.py:

  classify_task(text) → category, difficulty, required_skills
    Production path: keyword matching (no PyTorch). DistilBERT is optional
    and off by default — see docs/AI_MODELS.md.
    Label encoder (local opt-in only): cat_le(1).pkl (12 classes: ai_ml,
    backend, cloud, data_science, database, devops, frontend, mobile,
    project_management, security, testing, ui_ux).

  assign_best_members(task_info, members_list) → ranked member list
    Uses model2_assignment/model.pkl (GradientBoostingRegressor).
    4 features computed per candidate:
      domain_match_new  — 1 if task category == member primary domain
      skill_match_new   — fraction of task skills in member skills
      rating            — member rating (0-5)
      current_tasks     — member's active task count
    Falls back to a workload + availability heuristic if model absent.
"""
from __future__ import annotations

import ast
import logging
import os
from typing import Any, Optional

logger = logging.getLogger(__name__)

# ─── Paths ────────────────────────────────────────────────────────────────────

_CATEGORY_MODEL_DIR = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "ml_models", "model1_category")
)
_ASSIGNMENT_DIR = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "ml_models", "model2_assignment")
)
_ASSIGNMENT_MODEL_PATH    = os.path.join(_ASSIGNMENT_DIR, "model.pkl")
_ASSIGNMENT_FEATURES_PATH = os.path.join(_ASSIGNMENT_DIR, "features.pkl")

# ─── Cache ────────────────────────────────────────────────────────────────────

_cat_model_cache:     Any            = None
_cat_tokenizer_cache: Any            = None
_cat_le_cache:        Any            = None
_cat_load_error:      Optional[str]  = None

_assign_model_cache:    Any           = None   # GradientBoostingRegressor
_assign_features_cache: list | None   = None   # ordered list of feature names
_assign_load_error:     Optional[str] = None

_GIT_LFS_POINTER_PREFIX = b"version https://git-lfs.github.com/spec/v1"
_MIN_WEIGHT_BYTES = 1_000_000  # DistilBERT safetensors is ~268 MB; pointers are ~130 B

DISTILBERT_DISABLED_REASON = (
    "DistilBERT is not used in production. classify-task uses the keyword "
    "fallback. CPU-only PyTorch is still too large for typical Render RAM "
    "(Git LFS weights ~268MB plus torch CPU wheels). Set "
    "AI_ENABLE_DISTILBERT=true only on a machine with materialized weights "
    "and spare RAM. See docs/AI_MODELS.md."
)


def distilbert_enabled() -> bool:
    """Opt-in only. Production default is keyword fallback."""
    return os.getenv("AI_ENABLE_DISTILBERT", "false").strip().lower() in (
        "true",
        "1",
        "yes",
        "on",
    )


def is_usable_weight_file(path: str) -> bool:
    """True when path is a real weight file, not a missing or Git LFS pointer."""
    if not path or not os.path.isfile(path):
        return False
    try:
        size = os.path.getsize(path)
        with open(path, "rb") as fh:
            head = fh.read(64)
    except OSError:
        return False
    if head.startswith(_GIT_LFS_POINTER_PREFIX):
        return False
    return size >= _MIN_WEIGHT_BYTES


def category_weight_candidates() -> list[str]:
    return [
        os.path.join(_CATEGORY_MODEL_DIR, "model.safetensors"),
        os.path.join(_CATEGORY_MODEL_DIR, "pytorch_model.bin"),
    ]


def reset_category_model_cache() -> None:
    """Clear DistilBERT load state (tests / opt-in reload)."""
    global _cat_model_cache, _cat_tokenizer_cache, _cat_le_cache, _cat_load_error
    _cat_model_cache = None
    _cat_tokenizer_cache = None
    _cat_le_cache = None
    _cat_load_error = None


# ─────────────────────────────────────────────────────────────────────────────
# MODEL 1 — DistilBERT task classifier (optional; off in production)
# ─────────────────────────────────────────────────────────────────────────────

def _load_category_model():
    """Lazy-load DistilBERT model + tokenizer + label encoder (idempotent)."""
    global _cat_model_cache, _cat_tokenizer_cache, _cat_le_cache, _cat_load_error

    if _cat_model_cache is not None:
        return _cat_model_cache, _cat_tokenizer_cache, _cat_le_cache
    if _cat_load_error:
        return None, None, None

    if not distilbert_enabled():
        _cat_load_error = DISTILBERT_DISABLED_REASON
        logger.info(_cat_load_error)
        return None, None, None

    weights_candidates = category_weight_candidates()
    usable = [p for p in weights_candidates if is_usable_weight_file(p)]
    if not usable:
        present = [p for p in weights_candidates if os.path.isfile(p)]
        if present:
            _cat_load_error = (
                f"{os.path.basename(present[0])} is a Git LFS pointer or too "
                "small to be DistilBERT weights (~268MB expected). "
                "Using keyword fallback. Run git lfs pull only on a machine "
                "that will set AI_ENABLE_DISTILBERT=true."
            )
        else:
            _cat_load_error = (
                "DistilBERT weights not found in model1_category/ "
                "(model.safetensors / pytorch_model.bin missing). "
                "Using keyword fallback."
            )
        logger.warning(_cat_load_error)
        return None, None, None

    try:
        import joblib
        from transformers import (
            DistilBertTokenizer,
            DistilBertForSequenceClassification,
        )
        import torch  # noqa: F401

        tokenizer = DistilBertTokenizer.from_pretrained(_CATEGORY_MODEL_DIR)
        model = DistilBertForSequenceClassification.from_pretrained(_CATEGORY_MODEL_DIR)
        model.eval()

        # Label encoder: prefer cat_le(1).pkl (valid 12-class version),
        # fall back to cat_le.pkl if cat_le(1).pkl is absent.
        le = None
        for le_name in ["cat_le(1).pkl", "cat_le.pkl"]:
            le_path = os.path.join(_CATEGORY_MODEL_DIR, le_name)
            if os.path.exists(le_path):
                try:
                    candidate = joblib.load(le_path)
                    if hasattr(candidate, "classes_") and len(candidate.classes_) > 0:
                        le = candidate
                        logger.info(
                            "Label encoder loaded from %s (%d classes)",
                            le_name, len(le.classes_),
                        )
                        break
                except Exception as le_exc:
                    logger.warning("Skipping %s: %s", le_name, le_exc)

        _cat_model_cache = model
        _cat_tokenizer_cache = tokenizer
        _cat_le_cache = le
        logger.info("DistilBERT category model loaded from %s", _CATEGORY_MODEL_DIR)
        return model, tokenizer, le

    except ImportError as exc:
        _cat_load_error = (
            f"transformers/torch not installed: {exc}. "
            "Keyword fallback is active. DistilBERT is opt-in "
            "(AI_ENABLE_DISTILBERT=true) and is not deployed on Render."
        )
        logger.warning(_cat_load_error)
    except Exception as exc:
        _cat_load_error = f"Failed to load DistilBERT category model: {exc}"
        logger.error(_cat_load_error, exc_info=True)

    return None, None, None


def _keyword_classify(text: str) -> dict:
    """Rule-based fallback: no ML dependencies required."""
    text_lower = text.lower()

    category_keywords = {
        "backend":            ["api", "server", "flask", "django", "node", "sql", "endpoint", "rest"],
        "frontend":           ["ui", "design", "css", "react", "html", "interface", "component", "button"],
        "mobile":             ["android", "ios", "mobile", "app", "flutter", "swift", "kotlin"],
        "data_science":       ["ml", "model", "data", "analysis", "predict", "train", "dataset", "notebook"],
        "cloud":              ["deploy", "docker", "kubernetes", "aws", "ci/cd", "pipeline", "terraform"],
        "security":           ["auth", "jwt", "encrypt", "security", "password", "token", "vulnerability", "owasp"],
        "database":           ["migration", "schema", "query", "index", "postgres", "mongo", "redis"],
        "testing":            ["test", "unit", "integration", "coverage", "pytest", "mock", "qa"],
        "devops":             ["ci", "cd", "build", "release", "infra", "helm", "ansible"],
        "ai_ml":              ["ai", "machine learning", "neural", "deep learning", "llm", "transformers"],
        "project_management": ["sprint", "backlog", "standup", "planning", "kanban", "scrum", "roadmap"],
        "ui_ux":              ["figma", "wireframe", "prototype", "user flow", "ux", "accessibility"],
    }
    difficulty_keywords = {
        "easy": ["fix", "update", "rename", "add field", "simple", "minor", "typo"],
        "hard": ["refactor", "migrate", "architecture", "integrate", "implement", "design", "scale"],
    }
    skills_keywords = {
        "Python":     ["python", "flask", "django", "fastapi"],
        "JavaScript": ["javascript", "js", "node", "react", "vue", "angular"],
        "SQL":        ["sql", "database", "query", "postgres", "mysql"],
        "Docker":     ["docker", "container", "kubernetes"],
        "Testing":    ["test", "pytest", "unit test"],
        "Security":   ["auth", "jwt", "encrypt", "security"],
    }

    best_cat, best_score = "general", 0
    for cat, kws in category_keywords.items():
        score = sum(1 for kw in kws if kw in text_lower)
        if score > best_score:
            best_score, best_cat = score, cat

    difficulty = "medium"
    for diff, kws in difficulty_keywords.items():
        if any(kw in text_lower for kw in kws):
            difficulty = diff
            break

    skills = [s for s, kws in skills_keywords.items() if any(kw in text_lower for kw in kws)]
    return {
        "category":        best_cat,
        "difficulty":      difficulty,
        "complexity":      difficulty,
        "required_skills": skills[:5],
        "source":          "keyword_fallback",
        "confidence":      0.72,
    }


def classify_task(text: str) -> dict:
    """
    Classify a task by its text description.

    Returns
    -------
    dict with keys: category, difficulty, required_skills, source.
    Production always uses keyword_fallback unless AI_ENABLE_DISTILBERT=true
    and DistilBERT was warmed at startup. source is "ml_model" only then.
    """
    if not text or not text.strip():
        return {
            "category": "general", "difficulty": "medium",
            "required_skills": [], "source": "fallback", "error": "Empty text",
        }

    # Only run ML if the model was warmed at startup — never load weights on a
    # live HTTP request (that blocks gevent workers and causes client timeouts).
    model = _cat_model_cache
    tokenizer = _cat_tokenizer_cache
    le = _cat_le_cache

    if model is not None and tokenizer is not None:
        try:
            import torch

            inputs = tokenizer(
                text, return_tensors="pt",
                truncation=True, max_length=128, padding=True,
            )
            with torch.no_grad():
                logits = model(**inputs).logits
            pred_id = int(torch.argmax(logits, dim=1).item())

            # Safe label resolution: LE has 12 classes, config has 13 IDs.
            # If pred_id falls outside LE range, return the raw LABEL_n string.
            if le is not None and pred_id < len(le.classes_):
                label = str(le.inverse_transform([pred_id])[0])
            elif le is not None:
                label = f"LABEL_{pred_id}"
                logger.warning(
                    "pred_id=%d outside LE range (0-%d); using raw label",
                    pred_id, len(le.classes_) - 1,
                )
            else:
                label = f"LABEL_{pred_id}"

            return {
                "category":        label,
                "difficulty":      "medium",
                "complexity":      "medium",
                "required_skills": [],
                "source":          "ml_model",
                "confidence":      0.92,
            }
        except Exception as exc:
            logger.error("DistilBERT inference failed: %s", exc, exc_info=True)

    return _keyword_classify(text)


# ─────────────────────────────────────────────────────────────────────────────
# MODEL 2 — GradientBoosting member assignment scorer
# ─────────────────────────────────────────────────────────────────────────────

def _load_assignment_model():
    """
    Lazy-load model2_assignment/model.pkl (GradientBoostingRegressor)
    and features.pkl (ordered list of 4 column names).

    Returns (model, feature_names) or (None, None) on failure.
    """
    global _assign_model_cache, _assign_features_cache, _assign_load_error

    if _assign_model_cache is not None:
        return _assign_model_cache, _assign_features_cache
    if _assign_load_error:
        return None, None

    try:
        import joblib

        from services.ml_artifacts import (
            ensure_sklearn_unpickle_compat,
            require_joblib_artifact,
        )

        require_joblib_artifact(_ASSIGNMENT_MODEL_PATH, "assignment model.pkl")
        require_joblib_artifact(_ASSIGNMENT_FEATURES_PATH, "assignment features.pkl")
        ensure_sklearn_unpickle_compat()

        # Load the GradientBoostingRegressor
        mdl = joblib.load(_ASSIGNMENT_MODEL_PATH)
        if not hasattr(mdl, "predict"):
            raise ValueError("model.pkl has no predict() — not a sklearn estimator")

        # Load the feature name list
        feat_names = joblib.load(_ASSIGNMENT_FEATURES_PATH)
        if not isinstance(feat_names, list):
            raise ValueError("features.pkl is not a list of column names")

        _assign_model_cache    = mdl
        _assign_features_cache = feat_names
        logger.info(
            "Assignment model loaded from %s (features: %s)",
            _ASSIGNMENT_MODEL_PATH, feat_names,
        )
        return _assign_model_cache, _assign_features_cache

    except FileNotFoundError as exc:
        _assign_load_error = f"Assignment model file not found: {exc}"
        logger.warning(_assign_load_error)
    except Exception as exc:
        _assign_load_error = f"Failed to load assignment model: {exc}"
        logger.error(_assign_load_error, exc_info=True)

    return None, None


def _parse_skills(raw) -> set:
    """Parse member_skills from string repr or list into a lowercase set."""
    if isinstance(raw, list):
        return {s.lower() for s in raw if isinstance(s, str)}
    if isinstance(raw, str):
        try:
            parsed = ast.literal_eval(raw)
            if isinstance(parsed, list):
                return {s.lower() for s in parsed if isinstance(s, str)}
        except Exception:
            pass
        return {raw.lower()}
    return set()


def _build_assignment_features(task_info: dict, member: dict) -> dict:
    """
    Compute the 4 features the GradientBoostingRegressor was trained on.

    domain_match_new  : 1.0 if task category matches member's primary domain
    skill_match_new   : fraction of task skills present in member skills (0-1)
    rating            : member's platform rating
    current_tasks     : member's active task count
    """
    # domain match
    task_cat    = str(task_info.get("category") or task_info.get("ai_category") or "").lower()
    member_dom  = str(member.get("member_primary_domain", "")).lower()
    domain_match = 1.0 if task_cat and task_cat == member_dom else 0.0

    # skill match
    task_skills   = task_info.get("required_skills") or []
    member_skills = _parse_skills(member.get("member_skills", []))
    if task_skills:
        overlap     = sum(1 for s in task_skills if str(s).lower() in member_skills)
        skill_match = round(overlap / len(task_skills), 4)
    else:
        skill_match = 0.5   # neutral: no task skills specified

    return {
        "domain_match_new": domain_match,
        "skill_match_new":  skill_match,
        "rating":           float(member.get("rating", 3.0)),
        "current_tasks":    float(member.get("current_tasks", 2)),
    }


def _heuristic_score(member: dict) -> float:
    """Workload + availability + rating fallback when model is absent."""
    workload = float(member.get("workload_score", 0.5))
    avail    = float(member.get("availability_encoded", 1))
    rating   = float(member.get("rating", 3.0)) / 5.0
    return round(workload * 0.5 + avail * 0.3 + rating * 0.2, 4)


def assign_best_members(task_info: dict, members_list: list) -> list:
    """
    Score and rank candidate members for a task.

    Parameters
    ----------
    task_info    : dict — task metadata; expected keys: category, required_skills
    members_list : list of dicts — member profiles from the caller or ORM

    Returns
    -------
    List of member dicts augmented with 'score', 'score_source', and 'rank',
    sorted by score descending (highest = best fit).
    """
    if not members_list:
        return []

    model, feature_names = _load_assignment_model()
    use_ml = model is not None and feature_names is not None

    scored = []
    for member in members_list:
        if use_ml:
            try:
                import pandas as pd

                feats = _build_assignment_features(task_info, member)
                # Respect feature order the model was trained with
                row   = {col: feats.get(col, 0.0) for col in feature_names}
                df    = pd.DataFrame([row])[feature_names]
                score = round(float(model.predict(df)[0]), 4)
                src   = "ml_model"
            except Exception as exc:
                logger.warning("ML scoring failed for member %s: %s", member.get("id"), exc)
                score = _heuristic_score(member)
                src   = "heuristic"
        else:
            score = _heuristic_score(member)
            src   = "heuristic"

        scored.append({**member, "score": score, "score_source": src})

    scored.sort(key=lambda m: m["score"], reverse=True)
    for rank, m in enumerate(scored, start=1):
        m["rank"] = rank

    return scored


def get_category_model_status() -> dict:
    """Report DistilBERT task-category weights without forcing a torch load."""
    weights_candidates = [
        os.path.join(_CATEGORY_MODEL_DIR, "model.safetensors"),
        os.path.join(_CATEGORY_MODEL_DIR, "pytorch_model.bin"),
    ]
    present = [p for p in weights_candidates if os.path.exists(p)]
    return {
        "file_present": bool(present),
        "loaded": _cat_model_cache is not None,
        "error": _cat_load_error,
        "path": present[0] if present else weights_candidates[0],
    }


def get_assignment_model_status() -> dict:
    """Report assignment GBR model file + whether it loaded."""
    _load_assignment_model()
    return {
        "file_present": os.path.exists(_ASSIGNMENT_MODEL_PATH),
        "loaded": _assign_model_cache is not None,
        "error": _assign_load_error,
        "path": os.path.abspath(_ASSIGNMENT_MODEL_PATH),
        "feature_count": len(_assign_features_cache or []),
    }


def startup_check() -> None:
    """Log DistilBERT availability. Production stays on keyword fallback."""
    if not distilbert_enabled():
        logger.info(
            "Task category model using keyword fallback by design (%s)",
            DISTILBERT_DISABLED_REASON,
        )
        return
    model, tokenizer, le = _load_category_model()
    if model is not None and tokenizer is not None:
        logger.info(
            "Task category model ready (%d labels)",
            len(le.classes_) if le is not None else 0,
        )
    else:
        logger.info("Task category model using keyword fallback (%s)", _cat_load_error)
