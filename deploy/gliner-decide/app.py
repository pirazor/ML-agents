"""HTTP API for fastino/GLiNER2.5-Decide (zero-shot text classification)."""
import os
import secrets
import threading
from typing import Dict, List, Optional, Union

import torch
from fastapi import Depends, FastAPI, Header, HTTPException
from gliner2 import AutoExtractor
from pydantic import BaseModel, Field

MODEL_ID = os.environ.get("MODEL_ID", "fastino/GLiNER2.5-Decide")
API_KEY = os.environ.get("API_KEY", "")
MAX_TEXT_CHARS = int(os.environ.get("MAX_TEXT_CHARS", "20000"))
MAX_BATCH = int(os.environ.get("MAX_BATCH", "32"))

torch.set_num_threads(os.cpu_count() or 1)
model = AutoExtractor.from_pretrained(MODEL_ID)
model_lock = threading.Lock()  # one forward pass at a time on a small CPU box

app = FastAPI(title="GLiNER2.5-Decide API", version="1.0.0")

# A task is either a plain label list or {"labels": [...], "multi_label": bool, "cls_threshold": float, ...}
Tasks = Dict[str, Union[List[str], Dict]]


class ClassifyRequest(BaseModel):
    text: str = Field(..., max_length=MAX_TEXT_CHARS)
    tasks: Tasks
    threshold: float = 0.5
    include_confidence: bool = False


class BatchClassifyRequest(BaseModel):
    texts: List[str] = Field(..., min_length=1, max_length=MAX_BATCH)
    tasks: Tasks
    threshold: float = 0.5
    include_confidence: bool = False


def require_key(authorization: Optional[str] = Header(None), x_api_key: Optional[str] = Header(None)):
    if not API_KEY:
        return
    supplied = x_api_key or (authorization or "").removeprefix("Bearer ").strip()
    if not secrets.compare_digest(supplied, API_KEY):
        raise HTTPException(status_code=401, detail="invalid or missing API key")


def check_tasks(tasks: Tasks):
    if not tasks:
        raise HTTPException(status_code=422, detail="tasks must contain at least one task")
    for name, task in tasks.items():
        labels = task.get("labels") if isinstance(task, dict) else task
        if not isinstance(labels, list) or not labels or not all(isinstance(l, str) for l in labels):
            raise HTTPException(status_code=422,
                                detail=f"task '{name}' needs a non-empty list of string labels "
                                       "(either a list, or an object with a 'labels' list)")


@app.get("/")
def health():
    return {"status": "ok", "model": MODEL_ID, "auth_required": bool(API_KEY)}


@app.post("/classify", dependencies=[Depends(require_key)])
def classify(req: ClassifyRequest):
    check_tasks(req.tasks)
    try:
        with model_lock:
            return model.classify_text(req.text, req.tasks, threshold=req.threshold,
                                       include_confidence=req.include_confidence)
    except (ValueError, KeyError, TypeError) as e:
        raise HTTPException(status_code=422, detail=f"bad tasks schema: {e}")


@app.post("/classify/batch", dependencies=[Depends(require_key)])
def classify_batch(req: BatchClassifyRequest):
    check_tasks(req.tasks)
    if any(len(t) > MAX_TEXT_CHARS for t in req.texts):
        raise HTTPException(status_code=422, detail=f"each text must be <= {MAX_TEXT_CHARS} chars")
    try:
        with model_lock:
            return model.batch_classify_text(req.texts, req.tasks, threshold=req.threshold,
                                             include_confidence=req.include_confidence)
    except (ValueError, KeyError, TypeError) as e:
        raise HTTPException(status_code=422, detail=f"bad tasks schema: {e}")
