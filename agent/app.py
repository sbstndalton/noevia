"""Diary Companion Agent — FastAPI application.

Single-user, LAN-only web UI (port 8010) for chatting with the companion and observing
the automatic diary-logging pipeline (✓ logged / ⊘ skipped, with manual re-log).

Run:  uvicorn agent.app:app --host 0.0.0.0 --port 8010
"""
from __future__ import annotations

import logging
import threading
from contextlib import asynccontextmanager
from datetime import datetime
from pathlib import Path
from typing import Dict, Optional

import yaml
from fastapi import FastAPI
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from .config import load_config
from .context import ContextAssembler
from .corpus_store import CorpusStore
from .journal import Journal
from .llm import LLMClient
from .pipeline import LoggingPipeline
from .retrieval import Retriever
from .webdav import WebDAVClient

log = logging.getLogger("diary")

# ---------------- state ----------------


class AppState:
    def __init__(self, cfg):
        self.cfg = cfg
        self.journal = Journal(Path(cfg.get("retrieval.db_path")))
        self.dav = WebDAVClient(
            base_url=cfg.get("corpus.webdav.base_url"),
            username=cfg.get("corpus.webdav.username"),
            password=cfg.get("corpus.webdav.password") or "",
            timeout_s=float(cfg.get("corpus.webdav.timeout_s", 60)),
        )
        self.llm_main = LLMClient(
            base_url=cfg.get("llm.base_url"),
            api_key=cfg.get("llm.api_key") or "",
            chat_model=cfg.get("llm.chat_model"),
            embed_model=cfg.get("llm.embed_model"),
            timeout_s=float(cfg.get("llm.timeout_s", 300)),
            max_retries=int(cfg.get("llm.max_retries", 3)),
        )
        self.llm_aux = LLMClient(
            base_url=cfg.get("llm.aux.base_url"),
            api_key=cfg.get("llm.aux.api_key") or "",
            chat_model=cfg.get("llm.aux.model"),
            embed_model=cfg.get("llm.embed_model"),
            timeout_s=float(cfg.get("llm.timeout_s", 300)),
            max_retries=int(cfg.get("llm.max_retries", 3)),
        )
        self.store = CorpusStore(cfg, self.dav, self.journal)
        self.retrieval = Retriever(
            Path(cfg.get("retrieval.db_path")),
            self.llm_main,
            embed_batch_size=int(cfg.get("retrieval.embed_batch_size", 8)),
        )
        self.assembler = ContextAssembler(self.store, self.retrieval, cfg)
        templates_path = Path(__file__).resolve().parent.parent / "config" / "prompts" / "logging.md"
        templates = yaml.safe_load(templates_path.read_text(encoding="utf-8"))
        self.pipeline = LoggingPipeline(self.store, self.llm_main, self.llm_aux, templates)


_state: Optional[AppState] = None


def get_state() -> AppState:
    global _state
    if _state is None:
        _state = AppState(load_config())
    return _state


@asynccontextmanager
async def lifespan(_app: FastAPI):
    st = get_state()
    applied = st.store.apply_pending()
    log.info("startup: applied %d pending journal entries (%d still pending)", applied, st.journal.pending_count())
    yield
    st.dav.close()
    st.llm_main.close()
    st.llm_aux.close()
    st.retrieval.close()
    st.journal.close()


app = FastAPI(title="Diary Companion", lifespan=lifespan, docs_url=None, redoc_url=None)
app.mount("/static", StaticFiles(directory=str(Path(__file__).parent / "static")), name="static")


# ---------------- in-memory session (single user) ----------------

SESSIONS: Dict[str, dict] = {}


def _session(session_id: str) -> dict:
    if session_id not in SESSIONS:
        SESSIONS[session_id] = {"turns": [], "log_status": []}
    return SESSIONS[session_id]


# ---------------- request/response models ----------------


class ChatRequest(BaseModel):
    message: str
    session_id: str = "default"


class RelogRequest(BaseModel):
    index: int
    session_id: str = "default"


# ---------------- pages ----------------


@app.get("/", response_class=HTMLResponse)
def index() -> str:
    template_path = Path(__file__).parent / "static" / "index.html"
    return template_path.read_text(encoding="utf-8")


# ---------------- API ----------------


@app.post("/api/chat")
def api_chat(req: ChatRequest) -> JSONResponse:
    st = get_state()
    sess = _session(req.session_id)
    message = req.message.strip()
    if not message:
        return JSONResponse({"error": "empty message"}, status_code=400)

    day = datetime.now().date()
    messages = st.assembler.build(day, message, session_turns=sess["turns"])
    try:
        reply = st.llm_main.chat(messages, temperature=0.7)
    except Exception as exc:  # noqa: BLE001
        log.exception("chat failed")
        return JSONResponse({"error": f"model error: {exc}"}, status_code=502)

    visible, decision = LLMClient.strip_log_marker(reply)
    if decision is None:
        # Model omitted the marker — default to logging (never silently lose content).
        decision = "ok"

    outcome = st.pipeline.log_exchange(user_message=message, assistant_message=visible, now=datetime.now())

    sess["turns"].extend([
        {"role": "user", "content": message},
        {"role": "companion", "content": visible},
    ])
    sess["log_status"].append({
        "decision": outcome.decision,
        "xid": outcome.xid,
        "reason": outcome.reason,
        "user": message,
        "assistant": visible,
    })

    # Opportunistic background reindex of today's month file (new content becomes searchable).
    threading.Thread(target=_reindex_today, args=(st, day), daemon=True).start()

    return JSONResponse({
        "reply": visible,
        "decision": outcome.decision,
        "xid": outcome.xid,
        "reason": outcome.reason,
        "marker_decision": decision,
    })


def _reindex_today(st: AppState, day) -> None:
    try:
        month_text, _ = st.store.read_month(day)
        st.retrieval.reindex_file(st.store.month_filename(day), month_text)
    except Exception as exc:  # noqa: BLE001
        log.warning("background reindex failed: %s", exc)


@app.post("/api/relog")
def api_relog(req: RelogRequest) -> JSONResponse:
    st = get_state()
    sess = _session(req.session_id)
    try:
        item = sess["log_status"][req.index]
    except IndexError:
        return JSONResponse({"error": "no such exchange"}, status_code=404)
    outcome = st.pipeline.relog_last(
        user_message=item["user"],
        assistant_message=item["assistant"],
        now=datetime.now(),
    )
    item["decision"] = outcome.decision
    item["xid"] = outcome.xid
    return JSONResponse({"decision": outcome.decision, "xid": outcome.xid, "reason": outcome.reason})


@app.get("/api/day")
def api_day() -> JSONResponse:
    st = get_state()
    day = datetime.now().date()
    return JSONResponse({
        "day": day.isoformat(),
        "today_log": st.store.get_day_text(day, max_chars=12000),
        "standing": st.store.get_standing_sections_text(max_chars=4000),
    })


@app.get("/api/health")
def api_health() -> JSONResponse:
    st = get_state()
    return JSONResponse({
        "ok": True,
        "journal_pending": st.journal.pending_count(),
        "retrieval": st.retrieval.stats(),
        "model": st.cfg.get("llm.chat_model"),
    })
