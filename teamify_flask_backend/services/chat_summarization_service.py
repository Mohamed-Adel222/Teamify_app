"""
Chat Summarization Service
==========================
Wraps ml_models/Chat_Summarization.pkl — extracts key summaries, action
items, and participants from a meeting transcript or chat log.

The built-in extractive algorithm mirrors the notebook logic exactly and
is used as both the primary engine (if the pkl contains only the raw model
object) and a guaranteed fallback when the pkl is missing or corrupt.
"""
from __future__ import annotations

import logging
import os
import re
from collections import Counter
from typing import Any, Optional

logger = logging.getLogger(__name__)

_MODEL_PATH = os.path.join(
    os.path.dirname(__file__), "..", "ml_models", "Chat Summarization", "Chat_Summarization.pkl"
)

_STOP_WORDS = {
    "i", "we", "the", "a", "an", "is", "are", "was", "to",
    "and", "or", "but", "in", "on", "at", "by", "for", "of",
    "it", "let", "all", "you", "me", "my", "will", "can", "also",
    "good", "great", "okay", "perfect", "see", "morning", "everyone",
    "have", "has", "this", "that", "with", "from", "be", "do",
}

_ACTION_KEYWORDS = ["will", "going to", "should", "must", "need to", "have to"]


# ── ChatSummarizerModel ───────────────────────────────────────────────────────
# The pkl stores an *instance* of this class (saved from __main__ in the
# Jupyter notebook).  Defining it here (and injecting into sys.modules before
# joblib.load) lets Python resolve the class reference during unpickling.
# The instance carries a custom ``stop_words`` set from training; our methods
# use ``self.stop_words`` so the pkl's value is honoured automatically.

class ChatSummarizerModel:
    """Extractive meeting-transcript summarizer (mirrors notebook logic)."""

    def __init__(self):
        self.stop_words: set = set(_STOP_WORDS)

    # ── Low-level helpers ─────────────────────────────────────────────────────

    def get_participants(self, text: str) -> list:
        participants: set = set()
        for line in text.strip().split("\n"):
            line = line.strip()
            if ":" in line:
                person = line.split(":")[0].strip()
                if person and len(person) < 20 and person.replace(" ", "").isalpha():
                    participants.add(person)
        return sorted(participants)

    def extract_action_items(self, text: str) -> list:
        items = []
        for line in text.strip().split("\n"):
            line = line.strip()
            if not line or ":" not in line:
                continue
            if any(kw in line.lower() for kw in _ACTION_KEYWORDS):
                person = line.split(":")[0].strip()
                action = line.split(":", 1)[1].strip()
                if action:
                    items.append({"person": person, "action": action})
        return items

    def summarize(self, text: str, top_n: int = 3) -> dict:
        """Run the full summarization pipeline and return structured output."""
        sentences = []
        for line in text.strip().split("\n"):
            line = line.strip()
            if ":" in line:
                sentence = line.split(":", 1)[1].strip()
                if sentence:
                    sentences.append(sentence)

        word_freq: Counter = Counter()
        for s in sentences:
            for w in re.findall(r"\w+", s.lower()):
                if w not in self.stop_words and len(w) > 3:
                    word_freq[w] += 1

        scored = sorted(
            [
                (sum(word_freq.get(w, 0) for w in re.findall(r"\w+", s.lower())
                     if w not in self.stop_words), s)
                for s in sentences
            ],
            reverse=True,
        )
        key_points = [s for _, s in scored[:top_n] if len(s.strip()) >= 4]

        result = {
            "participants":  self.get_participants(text),
            "key_points":    key_points,
            "action_items":  self.extract_action_items(text),
            "word_count":    len(text.split()),
        }
        return _enrich_result(result, text)

    def run(self, text: str, top_n: int = 3) -> dict:
        return self.summarize(text, top_n=top_n)

    def predict(self, text: str, top_n: int = 3) -> dict:
        return self.summarize(text, top_n=top_n)


_model_cache: Any = None
_model_load_error: Optional[str] = None


def _load_model() -> Any:
    """Lazy-load the pkl model once per process.

    ``Chat_Summarization.pkl`` was pickled from a Jupyter notebook's
    ``__main__`` namespace, so Python cannot resolve ``ChatSummarizerModel``
    during a normal joblib.load.  We inject our own definition into
    ``sys.modules['__main__']`` before loading; the loaded instance then
    carries the custom ``stop_words`` set that was saved during training.
    """
    global _model_cache, _model_load_error

    if _model_cache is not None:
        return _model_cache
    if _model_load_error:
        return None

    try:
        import sys
        import joblib

        path = os.path.abspath(_MODEL_PATH)

        # Register our class in __main__ so pickle can resolve the reference
        main_module = sys.modules.get("__main__")
        if main_module is not None and not hasattr(main_module, "ChatSummarizerModel"):
            main_module.ChatSummarizerModel = ChatSummarizerModel

        obj = joblib.load(path)

        # Guard: pickled notebooks look like dicts with a 'cells' key
        if isinstance(obj, dict) and "cells" in obj:
            _model_load_error = (
                "Chat_Summarization.pkl still contains a Jupyter notebook. "
                "Using built-in extractive summarizer."
            )
            logger.info(_model_load_error)
            return None

        if not hasattr(obj, "summarize"):
            _model_load_error = "Chat_Summarization.pkl has no summarize() method"
            logger.warning(_model_load_error)
            return None

        _model_cache = obj
        logger.info(
            "Chat summarization model loaded from %s (stop_words: %d)",
            path, len(getattr(obj, "stop_words", [])),
        )
        return _model_cache

    except FileNotFoundError:
        _model_load_error = f"Chat_Summarization.pkl not found at {_MODEL_PATH}"
        logger.warning(_model_load_error)
    except Exception as exc:
        _model_load_error = f"Failed to load Chat_Summarization.pkl: {exc}"
        logger.error(_model_load_error, exc_info=True)

    return None


def get_chat_summarization_model_status() -> dict:
    """Report whether Chat_Summarization.pkl is present and usable."""
    model = _load_model()
    return {
        "file_present": os.path.exists(os.path.abspath(_MODEL_PATH)),
        "loaded": model is not None,
        "error": _model_load_error,
        "path": os.path.abspath(_MODEL_PATH),
    }


def startup_check() -> None:
    """Log a structured warning at boot when the chat summarization pkl is missing."""
    _load_model()
    if _model_load_error:
        logger.warning("AI startup: chat summarization unavailable — %s", _model_load_error)
    else:
        logger.info("AI startup: chat summarization model loaded")


# ── Built-in extractive summarizer (mirrors notebook; always available) ───────

def _get_participants(text: str) -> list:
    participants: set = set()
    for line in text.strip().split("\n"):
        line = line.strip()
        if ":" in line:
            person = line.split(":")[0].strip()
            if person and len(person) < 20 and person.replace(" ", "").isalpha():
                participants.add(person)
    return sorted(participants)


def _extract_sentences(text: str) -> list:
    """Pull speaker content from chat lines formatted as 'Name: message'."""
    sentences = []
    for line in text.strip().split("\n"):
        line = line.strip()
        if ":" in line:
            sentence = line.split(":", 1)[1].strip()
            if sentence:
                sentences.append(sentence)
    return sentences


def _score_sentences(sentences: list, top_n: int) -> list:
    word_freq: Counter = Counter()
    for s in sentences:
        for w in re.findall(r"\w+", s.lower()):
            if w not in _STOP_WORDS and len(w) > 3:
                word_freq[w] += 1

    scored = []
    for s in sentences:
        score = sum(
            word_freq.get(w, 0)
            for w in re.findall(r"\w+", s.lower())
            if w not in _STOP_WORDS
        )
        scored.append((score, s))

    scored.sort(reverse=True)
    return [s for _, s in scored[:top_n] if len(s.strip()) >= 4]


def _parse_transcript_lines(text: str) -> list:
    """Parse 'Speaker: message' lines from a meeting transcript."""
    lines = []
    for line in text.strip().split("\n"):
        line = line.strip()
        if ":" not in line:
            continue
        speaker, content = line.split(":", 1)
        speaker = speaker.strip()
        content = content.strip()
        if speaker and content:
            lines.append({"speaker": speaker, "content": content})
    return lines


def _build_summary_text(
    text: str,
    key_points: list,
    participants: list,
    action_items: list,
) -> str:
    """Build a readable paragraph summary for the meeting summary UI."""
    transcript_lines = _parse_transcript_lines(text)
    utterances = [ln["content"] for ln in transcript_lines]

    if not utterances and not key_points:
        return "No speech or chat content was captured in this meeting."

    who = ", ".join(participants[:5]) if participants else "Participants"

    substantive = [kp for kp in key_points if len(str(kp).strip()) >= 12]
    if substantive:
        body = ". ".join(k.rstrip(".") for k in substantive)
        summary = f"In this meeting, {who} discussed: {body}."
    elif utterances:
        spoken = "; ".join(utterances[:10])
        summary = (
            f"{who} spoke during this session. "
            f"Transcribed speech: \"{spoken}\"."
        )
    else:
        body = ". ".join(str(k).rstrip(".") for k in key_points)
        summary = f"{who} covered: {body}."

    if action_items:
        actions = "; ".join(
            f"{ai.get('person', 'Someone')} will {ai.get('action', '').lstrip('will ')}"
            for ai in action_items[:3]
            if ai.get("action")
        )
        if actions:
            summary += f" Action items: {actions}."

    return summary


def _enrich_result(result: dict, text: str) -> dict:
    """Attach narrative summary and formatted speech transcript lines."""
    transcript_lines = _parse_transcript_lines(text)
    key_points = [
        kp for kp in result.get("key_points", []) if len(str(kp).strip()) >= 4
    ]
    participants = result.get("participants") or []
    action_items = result.get("action_items") or []

    result["key_points"] = key_points
    result["summary"] = _build_summary_text(text, key_points, participants, action_items)
    if not result.get("speech_transcript"):
        result["speech_transcript"] = [
            f"{ln['speaker']}: {ln['content']}" for ln in transcript_lines
        ]
    return result


def _extract_action_items(text: str) -> list:
    items = []
    for line in text.strip().split("\n"):
        line = line.strip()
        if not line or ":" not in line:
            continue
        if any(kw in line.lower() for kw in _ACTION_KEYWORDS):
            person = line.split(":")[0].strip()
            action = line.split(":", 1)[1].strip()
            if action:
                items.append({"person": person, "action": action})
    return items


def _builtin_summarize(text: str, top_n: int) -> dict:
    participants = _get_participants(text)
    sentences = _extract_sentences(text)
    key_points = _score_sentences(sentences, top_n)
    action_items = _extract_action_items(text)
    result = {
        "participants": participants,
        "key_points": key_points,
        "action_items": action_items,
        "word_count": len(text.split()),
    }
    return _enrich_result(result, text)


# ── Public API ────────────────────────────────────────────────────────────────

def summarize_chat(text: str, top_n: int = 3) -> dict:
    """
    Summarize a chat transcript or meeting log.

    Parameters
    ----------
    text : str
        Raw transcript in "Name: message" per-line format.
    top_n : int
        Number of key sentences to surface as key_points.

    Returns
    -------
    dict with keys:
        participants   (list[str])
        key_points     (list[str])
        action_items   (list[dict]  — {person, action})
        word_count     (int)
        source         ("ml_model" | "built_in" | "fallback")
        error          (str, only on failure)
    """
    if not text or not text.strip():
        return _enrich_result({
            "participants": [],
            "key_points": [],
            "action_items": [],
            "word_count": 0,
            "source": "fallback",
            "error": "Empty text provided",
        }, text)

    model = _load_model()

    try:
        # If the pkl contains an object with a .summarize() method, delegate to it
        if model is not None and hasattr(model, "summarize"):
            result = model.summarize(text, top_n=top_n)
            result["source"] = "ml_model"
            return _enrich_result(result, text)

        # Otherwise use the built-in algorithm (same logic as notebook)
        source = "ml_model" if model is not None else "built_in"
        result = _builtin_summarize(text, top_n)
        result["source"] = source
        return result

    except Exception as exc:
        logger.error("Chat summarization failed: %s", exc, exc_info=True)
        return _enrich_result({
            "participants": [],
            "key_points": [],
            "action_items": [],
            "word_count": 0,
            "source": "fallback",
            "error": str(exc),
        }, text)
