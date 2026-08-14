# AI models in production

## DistilBERT task classifier — not required

`POST /api/ai/classify-task` and deferred task classification
(`ai_category` / `ai_difficulty` / `ai_skills`) **do not need DistilBERT**
in production.

The supported production path is the **keyword fallback** in
`services/task_pipeline_service.py` (`source: "keyword_fallback"`).
It returns category, difficulty, and required skills with no PyTorch.

DistilBERT stays an **opt-in local experiment**:

| Setting | Production (Render) | Local experiment |
|---|---|---|
| `AI_ENABLE_DISTILBERT` | unset / `false` (default) | `true` |
| Install | `requirements-deploy.txt` (no torch) | CPU torch + transformers, then `git lfs pull` |
| Runtime | keyword fallback | DistilBERT only if weights materialized and RAM allows |

Do not set `AI_ENABLE_DISTILBERT=true` on a typical Render instance.

## Why CPU-only PyTorch is not added to Render

CPU wheels (`pip install torch --index-url https://download.pytorch.org/whl/cpu`)
are smaller than the CUDA build, but they are still the wrong fit here:

1. **RAM** — Render’s common 512 MB plan cannot hold Flask + gevent +
   sklearn `.pkl` models **and** torch + DistilBERT in one gunicorn worker.
   DistilBERT weights alone are ~268 MB (`model.safetensors` Git LFS oid
   `8d537d226e3a3eab071dfcfb743abd75fb8c4216efdccfbbc676ec30cceb61b4`).
2. **Weights are not in git** — `ml_models/model1_category/model.safetensors`
   is a Git LFS pointer (~130 bytes) unless `git lfs pull` ran. Render
   clones do not materialize LFS objects by default.
3. **Boot cost** — `startup_check()` would load the net at process start
   and can miss Render’s deploy timeout or OOM-kill the worker.
4. **Product coverage** — DistilBERT only fills `category` (difficulty is
   hardcoded `medium`, `required_skills` is empty). The keyword fallback
   already fills all three fields the AI Hub and task APIs use.
5. **Full `torch` CUDA wheels are worse** — do not add `torch>=2.2.0` from
   PyPI to `requirements-deploy.txt`.

sklearn / joblib / pandas **are** required in production for the `.pkl`
models (assignment, delay, profile rating, security). Those stay in
`requirements-deploy.txt`.

## Other flags

- `AI_ENABLE_LOCAL_MODELS` — sklearn `.pkl` inference (delay, assignment
  helpers). Independent of DistilBERT.
- `AI_ENABLE_DISTILBERT` — DistilBERT only. Default `false`.

## Local DistilBERT (optional)

Only on a machine with several GB of RAM:

```bash
git lfs pull
pip install torch --index-url https://download.pytorch.org/whl/cpu
pip install transformers
export AI_ENABLE_DISTILBERT=true
```

If the safetensors file is still an LFS pointer, the loader will not treat
it as a real model and will keep the keyword fallback.
