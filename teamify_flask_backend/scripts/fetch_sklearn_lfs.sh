#!/usr/bin/env bash
# Materialize sklearn .pkl weights from Git LFS.
# Skips DistilBERT safetensors (~268MB) — not used in production.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${ROOT}" ]]; then
  echo "fetch_sklearn_lfs.sh: not inside a git checkout" >&2
  exit 1
fi

cd "$ROOT"

if ! command -v git-lfs >/dev/null 2>&1 && ! git lfs version >/dev/null 2>&1; then
  echo "fetch_sklearn_lfs.sh: git-lfs is not installed" >&2
  exit 1
fi

# Don't rewrite git hooks in hosted agents; filters are enough to smudge.
git lfs install --skip-repo >/dev/null 2>&1 || true

echo "Fetching Git LFS *.pkl objects (excluding DistilBERT weights)..."
git lfs pull --include="*.pkl" --exclude="*.safetensors,*.bin"

python3 - <<'PY'
import os, sys
root = os.environ.get("REPO_ROOT") or os.getcwd()
files = [
    "teamify_flask_backend/ml_models/model2_assignment/model.pkl",
    "teamify_flask_backend/ml_models/model2_assignment/features.pkl",
    "teamify_flask_backend/ml_models/Delay Predictor/Delay_Predictor.pkl",
    "teamify_flask_backend/ml_models/Profiles&AI Rating/teamify_model.pkl",
    "teamify_flask_backend/ml_models/Chat Summarization/Chat_Summarization.pkl",
    "teamify_flask_backend/ml_models/SecurityModel/security_model.pkl",
]
prefix = b"version https://git-lfs.github.com/spec/v1"
failed = []
for rel in files:
    path = os.path.join(root, rel)
    if not os.path.isfile(path):
        failed.append(f"missing {rel}")
        continue
    with open(path, "rb") as fh:
        head = fh.read(64)
    if head.startswith(prefix):
        failed.append(f"still a pointer ({os.path.getsize(path)}B) {rel}")
        continue
    print(f"OK {os.path.getsize(path):8d}B  {rel}")
if failed:
    print("FAILED:", file=sys.stderr)
    for item in failed:
        print(" ", item, file=sys.stderr)
    sys.exit(1)
PY
