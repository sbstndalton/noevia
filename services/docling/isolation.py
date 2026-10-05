"""Run conversions in a child process the parent can kill (#854).

Why a process and not a thread: Docling's own `document_timeout` is honoured by
the PDF pipelines only, between batches of pages. The Office, HTML, Markdown,
CSV and image-backend paths never look at it, and no thread can be interrupted
from outside. So a dense spreadsheet or a pathological HTML file used to hold
the worker's single slot until the web client gave up (65 minutes) or the 6 GB
limit killed the whole container, and every other upload got 503 meanwhile.
Giving up on the client side did not stop the work either.

A process can be killed. The child here is long-lived and lazily started: it
holds the Docling converter, so the 669 MB of models are loaded once, exactly
as when the conversion ran inside the server process. It is killed (SIGKILL to
its whole process group, which also takes out any tesseract it spawned) when

  * the per-document deadline passes,
  * the client that asked has gone away, or
  * it dies by itself (OOM), which is reported as a failure.

The next request starts a fresh child; that costs one model load and happens
only after something went wrong. The parent never imports Docling.
"""
import json
import os
import select
import signal
import struct
import subprocess
import sys
import time

POLL_SECONDS = 0.25


class DocumentTimeout(Exception):
    """The conversion ran past its deadline and the child was killed."""


class ClientGone(Exception):
    """The requester disconnected; the child was killed to free the slot."""


class ConversionFailed(Exception):
    """The conversion raised or the child died. Carries no document content."""


class IsolatedExtractor:
    def __init__(self, target="extract:extract"):
        self.target = target
        self._proc = None
        self._replies = None  # read end of the reply pipe

    # -- lifecycle ---------------------------------------------------------
    def _start(self):
        read_fd, write_fd = os.pipe()
        try:
            self._proc = subprocess.Popen(
                [sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), "isolated_worker.py"),
                 str(write_fd), self.target],
                stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
                pass_fds=(write_fd,),
                # Own session: one killpg() reaches the child and anything it forked.
                start_new_session=True,
                cwd=os.path.dirname(os.path.abspath(__file__)))
        except BaseException:
            os.close(read_fd)
            raise
        finally:
            os.close(write_fd)
        self._replies = read_fd

    def kill(self):
        proc, self._proc = self._proc, None
        replies, self._replies = self._replies, None
        if proc is not None:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                try:
                    proc.kill()
                except OSError:
                    pass
            try:
                proc.stdin.close()
            except OSError:
                pass
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                pass
        if replies is not None:
            try:
                os.close(replies)
            except OSError:
                pass

    close = kill

    @property
    def pid(self):
        return self._proc.pid if self._proc else None

    # -- one conversion ----------------------------------------------------
    def _read_exact(self, count, deadline, gone):
        buffer = b""
        while len(buffer) < count:
            if time.monotonic() >= deadline:
                raise DocumentTimeout()
            if gone():
                raise ClientGone()
            wait = min(POLL_SECONDS, max(0.0, deadline - time.monotonic()))
            ready, _, _ = select.select([self._replies], [], [], wait)
            if not ready:
                continue
            chunk = os.read(self._replies, count - len(buffer))
            if not chunk:
                raise ConversionFailed()  # the child closed the pipe: it died
            buffer += chunk
        return buffer

    def run(self, path, name, timeout, gone=lambda: False):
        """Convert `path`; return the target's result or raise one of the three above.

        Not re-entrant: callers hold the worker's single slot.
        """
        deadline = time.monotonic() + timeout
        if self._proc is not None and self._proc.poll() is not None:
            self.kill()  # died while idle (e.g. OOM-killed between jobs)
        if self._proc is None:
            self._start()
        try:
            try:
                self._proc.stdin.write(json.dumps({"path": path, "name": name}).encode() + b"\n")
                self._proc.stdin.flush()
            except OSError:
                raise ConversionFailed()
            (length,) = struct.unpack(">I", self._read_exact(4, deadline, gone))
            reply = json.loads(self._read_exact(length, deadline, gone))
        except (DocumentTimeout, ClientGone, ConversionFailed):
            self.kill()
            raise
        except BaseException:
            self.kill()
            raise ConversionFailed()
        if "ok" in reply:
            return reply["ok"]
        # The target raised; the child is still healthy and keeps its models.
        raise ConversionFailed()
