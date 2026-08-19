"""Helpers for loading sklearn joblib artifacts stored in Git LFS.

A path existing on disk is not enough: clones without `git lfs pull` leave
~130-byte pointer files. GradientBoosting pickles from sklearn 1.4–1.5 also
reference a top-level Cython module named `_loss` that newer sklearn ships
as `sklearn._loss._loss`.
"""
from __future__ import annotations

import logging
import os
import sys

logger = logging.getLogger(__name__)

GIT_LFS_POINTER_PREFIX = b"version https://git-lfs.github.com/spec/v1"
_SKLEARN_LFS_HINT = (
    "Run `git lfs pull --include='*.pkl' --exclude='*.safetensors,*.bin'` "
    "or set Render GIT_LFS_ENABLED=true and GIT_LFS_FETCH_INCLUDE=*.pkl."
)

_compat_applied = False


class ModelArtifactError(RuntimeError):
    """Raised when a .pkl is missing or still a Git LFS pointer."""


def is_git_lfs_pointer(path: str) -> bool:
    if not path or not os.path.isfile(path):
        return False
    try:
        with open(path, "rb") as fh:
            return fh.read(64).startswith(GIT_LFS_POINTER_PREFIX)
    except OSError:
        return False


def require_joblib_artifact(path: str, label: str) -> str:
    """Return an absolute path to a real (non-pointer) artifact, or raise."""
    abs_path = os.path.abspath(path)
    if not os.path.isfile(abs_path):
        raise ModelArtifactError(f"{label} not found at {abs_path}")
    if is_git_lfs_pointer(abs_path):
        raise ModelArtifactError(
            f"{label} at {abs_path} is a Git LFS pointer, not trained weights. "
            + _SKLEARN_LFS_HINT
        )
    return abs_path


def ensure_sklearn_unpickle_compat() -> None:
    """Allow GradientBoostingRegressor pickles that import top-level `_loss`."""
    global _compat_applied
    if _compat_applied:
        return
    if "_loss" not in sys.modules:
        try:
            import sklearn._loss._loss as sklearn_cy_loss  # type: ignore

            sys.modules["_loss"] = sklearn_cy_loss
        except Exception as exc:
            logger.debug("sklearn _loss unpickle shim skipped: %s", exc)
            return
    _compat_applied = True
