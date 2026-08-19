#!/usr/bin/env bash
# Render / production build: sklearn .pkl weights then Python deps.
# Do not install torch. DistilBERT stays opt-in and off by default.
set -euo pipefail

cd "$(dirname "$0")/.."

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if command -v git-lfs >/dev/null 2>&1 || git lfs version >/dev/null 2>&1; then
    bash "$(dirname "$0")/fetch_sklearn_lfs.sh" || echo "WARN: Git LFS pkl pull failed; sklearn models will use fallbacks"
  else
    echo "WARN: git-lfs not installed; sklearn models will use fallbacks unless GIT_LFS_ENABLED pulled them"
  fi
fi

pip install -r requirements-deploy.txt
