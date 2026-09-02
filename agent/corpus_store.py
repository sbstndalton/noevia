"""CorpusStore — owns the diary corpus: WebDAV reads/writes + write-ahead journal.

Every mutation is: enqueue in journal → apply via ETag-guarded WebDAV PUT → mark applied.
Replays after crashes are safe: month appends dedupe on the xid marker; index edits
dedupe on bullet-text equality.
"""
from __future__ import annotations

import logging
import uuid
from datetime import date, datetime
from pathlib import Path
from typing import Callable, Optional, Tuple

from . import corpus as fmt
from .config import Config
from .journal import Journal, JournalEntry
from .webdav import WebDAVClient

log = logging.getLogger(__name__)


class CorpusError(RuntimeError):
    pass


class CorpusStore:
    def __init__(self, cfg: Config, dav: WebDAVClient, journal: Journal):
        self.cfg = cfg
        self.dav = dav
        self.journal = journal
        self.remote_root = (cfg.get("corpus.webdav.remote_root") or "").strip("/")
        self.monthly_prefix = cfg.get("corpus.monthly_prefix") or ""
        self.index_file = cfg.get("corpus.index_file") or "INDEX.md"

    # ---------------- paths ----------------

    def month_filename(self, day: date) -> str:
        return f"{day.year}-{day.month:02d}.md"

    def _join(self, *parts: str) -> str:
        return "/".join(p.strip("/") for p in [self.remote_root, *parts] if p)

    def month_path(self, day: date) -> str:
        return self._join(self.monthly_prefix, self.month_filename(day))

    def index_path(self) -> str:
        return self._join(self.monthly_prefix, self.index_file)

    # ---------------- reads ----------------

    def read_month(self, day: date) -> Tuple[Optional[str], Optional[str]]:
        return self.dav.get_text(self.month_path(day))

    def read_index(self) -> Tuple[Optional[str], Optional[str]]:
        return self.dav.get_text(self.index_path())

    def month_label(self, day: date) -> str:
        return day.strftime("%B %Y")

    # ---------------- guarded remote writes ----------------

    def _guarded_write(
        self,
        path: str,
        mutate: Callable[[Optional[str]], Tuple[Optional[str], bool]],
        max_attempts: int = 5,
    ) -> Tuple[bool, Optional[str]]:
        """ETag-guarded create/modify loop. mutate(current_text) -> (new_text, changed).

        On 412 (concurrent change), re-GETs and re-runs mutate against fresh content —
        the mutate function must be idempotent w.r.t. already-applied content.
        Returns (applied, final_etag).
        """
        for attempt in range(max_attempts):
            text, etag = self.dav.get_text(path)
            new_text, changed = mutate(text)
            if not changed:
                return True, etag  # nothing to do (already applied)
            ok, new_etag, status = self.dav.put(
                path,
                (new_text or "").encode("utf-8"),
                if_match=etag,
            )
            if ok:
                return True, new_etag
            log.warning("write conflict on %s (status %s), attempt %d", path, status, attempt + 1)
        raise CorpusError(f"could not write {path} after {max_attempts} attempts (persistent conflict)")

    # ---------------- exchange logging ----------------

    def log_exchange(
        self,
        day: date,
        sub_header: str,
        me_text: str,
        claude_text: str,
        now: Optional[datetime] = None,
    ) -> str:
        """Durably record the intent to log an exchange, then apply it. Returns the xid."""
        xid = str(uuid.uuid4())
        body = fmt.render_exchange(me_text, claude_text, xid)
        rendered_header = fmt.render_subsection_header(now=now, topic=sub_header)
        # store the header TEXT (no '### ' prefix) — the appender adds the prefix
        header_text = rendered_header[4:] if rendered_header.startswith("### ") else rendered_header
        self.journal.enqueue(
            "exchange",
            {
                "xid": xid,
                "day": day.isoformat(),
                "sub_header": header_text,
                "body": body,
                "month": self.month_filename(day),
                "month_label": self.month_label(day),
            },
        )
        # Register the month link too (applier dedupes; harmless if the link exists).
        self.journal.enqueue(
            "index_month",
            {"month": self.month_filename(day), "label": self.month_label(day)},
        )
        self.apply_pending()
        return xid

    def update_standing_sections(self, open_question_ops: list, timeline_ops: list, today: str) -> Optional[str]:
        """Enqueue + apply INDEX.md standing-section edits. Returns journal id."""
        if not open_question_ops and not timeline_ops:
            return None
        jid = self.journal.enqueue(
            "index_update",
            {"open_questions": open_question_ops, "timeline": timeline_ops, "today": today},
        )
        self.apply_pending()
        return jid

    # ---------------- appliers ----------------

    def apply_pending(self, limit: int = 100) -> int:
        """Apply all unapplied journal entries in order. Returns count applied now."""
        applied = 0
        for entry in self.journal.unapplied(limit=limit):
            try:
                self._apply_entry(entry)
                self.journal.mark_applied(entry.id)
                applied += 1
            except Exception as exc:  # noqa: BLE001 — keep trying remaining entries
                log.error("journal entry %s failed: %s", entry.id, exc)
                self.journal.mark_failed(entry.id, str(exc))
        return applied

    def _apply_entry(self, entry: JournalEntry) -> None:
        if entry.kind == "exchange":
            self._apply_exchange(entry)
        elif entry.kind == "index_month":
            self._apply_month_registration(entry)
        elif entry.kind == "index_update":
            self._apply_index_update(entry)
        else:
            raise CorpusError(f"unknown journal kind: {entry.kind}")

    def _apply_exchange(self, entry: JournalEntry) -> None:
        p = entry.payload
        day = date.fromisoformat(p["day"])
        xid = p["xid"]
        sub_header = p["sub_header"]
        body = p["body"]
        path = self.month_path(day)

        def mutate(current: Optional[str]) -> Tuple[Optional[str], bool]:
            if current is not None and fmt.has_marker(current, xid):
                return current, False  # already applied — replay safe
            return fmt.append_to_month_text(current, day, sub_header, body), True

        self._guarded_write(path, mutate)
        log.info("exchange %s logged to %s", xid, path)

    def _apply_month_registration(self, entry: JournalEntry) -> None:
        p = entry.payload

        def mutate(current: Optional[str]) -> Tuple[Optional[str], bool]:
            idx = fmt.parse_index(current)
            if fmt.register_month(idx, p["label"], p["month"]):
                return idx.render(), True
            return current, False

        self._guarded_write(self.index_path(), mutate)

    def _apply_index_update(self, entry: JournalEntry) -> None:
        p = entry.payload

        def mutate(current: Optional[str]) -> Tuple[Optional[str], bool]:
            idx = fmt.parse_index(current)
            changed = fmt.apply_index_edits(
                idx,
                open_question_ops=p.get("open_questions") or [],
                timeline_ops=p.get("timeline") or [],
                today=p.get("today"),
            )
            return (idx.render(), True) if changed else (current, False)

        self._guarded_write(self.index_path(), mutate)

    # ---------------- context helpers ----------------

    def get_day_text(self, day: date, max_chars: Optional[int] = None) -> str:
        """The current day's log section, markers stripped, for the model context.

        If over max_chars, the earliest exchanges are dropped (recency matters most
        within a day); a truncation notice is prepended.
        """
        month_text, _ = self.read_month(day)
        if not month_text:
            return ""
        header = fmt.canonical_day_header(day)
        for d in fmt.parse_diary(month_text):
            if d.header == header:
                parts = [d.header, ""]
                for sub in d.subsections:
                    parts.append(f"### {sub.header}")
                    parts.append("")
                    for ex in sub.exchanges:
                        if ex.me:
                            parts.append(f"**Me:** {ex.me}")
                            parts.append("")
                        if ex.claude:
                            parts.append(f"**Claude:** {ex.claude}")
                            parts.append("")
                text = "\n".join(parts).strip()
                if max_chars and len(text) > max_chars:
                    text = "(earlier exchanges today truncated)\n…" + text[-max_chars:]
                return text
        return ""

    def get_standing_sections_text(self, max_chars: Optional[int] = None) -> str:
        index_text, _ = self.read_index()
        idx = fmt.parse_index(index_text)
        out = fmt.IndexFile(
            preamble=idx.preamble, month_links=idx.month_links, sections=idx.sections
        ).render()
        if max_chars and len(out) > max_chars:
            out = out[:max_chars] + "\n…(standing sections truncated)"
        return out

    def month_registered(self, day: date) -> bool:
        index_text, _ = self.read_index()
        idx = fmt.parse_index(index_text)
        return any(self.month_filename(day) in link for link in idx.month_links)

    def new_xid(self) -> str:
        return str(uuid.uuid4())
