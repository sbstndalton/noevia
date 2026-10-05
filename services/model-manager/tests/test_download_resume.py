"""#799: a resumed single-stream download must never append a full body to a partial, must check
the 206 Content-Range offset, and must not install a file of the wrong size. HTTP is mocked."""
import asyncio

import httpx
import pytest

from app import downloader, hf

PAYLOAD = b"synthetic-gguf-bytes-0123456789"   # 31 bytes, below PARALLEL_MIN_SIZE


def _run(monkeypatch, tmp_path, respond, partial: bytes | None = None, total: int = 0):
    seen = []

    def wrapped(req):
        seen.append((req.method, req.headers.get("range")))
        return respond(req)

    real_client = httpx.AsyncClient
    monkeypatch.setattr(downloader.httpx, "AsyncClient",
                        lambda **kw: real_client(transport=httpx.MockTransport(wrapped), **kw))
    monkeypatch.setattr(hf, "get_token", lambda: None)
    monkeypatch.setattr(downloader.db, "record_download", lambda **kw: None)
    dest = tmp_path / "model.gguf"
    temp = tmp_path / "model.gguf.download"
    if partial is not None:
        temp.write_bytes(partial)
    job = downloader.DownloadJob("t", "fixture", "model.gguf", "https://example.test/model.gguf", dest, temp, total)
    asyncio.run(downloader.DownloadManager()._run(job))
    return job, seen


def _head(req, size=len(PAYLOAD)):
    # No accept-ranges: forces the single-stream path that resumes partials.
    return httpx.Response(200, headers={"content-length": str(size)})


def test_server_ignoring_range_restarts_instead_of_appending(monkeypatch, tmp_path):
    def respond(req):
        if req.method == "HEAD":
            return _head(req)
        return httpx.Response(200, content=PAYLOAD)          # ignores the Range header
    job, seen = _run(monkeypatch, tmp_path, respond, partial=PAYLOAD[:10])
    assert ("GET", "bytes=10-") in seen
    assert job.status == "done", job.error
    assert job.dest_path.read_bytes() == PAYLOAD
    assert job.downloaded_bytes == len(PAYLOAD)
    assert not job.temp_path.exists()


def test_valid_206_resume_appends_the_rest(monkeypatch, tmp_path):
    def respond(req):
        if req.method == "HEAD":
            return _head(req)
        start = int(req.headers["range"].removeprefix("bytes=").rstrip("-"))
        return httpx.Response(206, content=PAYLOAD[start:],
                              headers={"content-range": f"bytes {start}-{len(PAYLOAD) - 1}/{len(PAYLOAD)}"})
    job, seen = _run(monkeypatch, tmp_path, respond, partial=PAYLOAD[:10])
    assert job.status == "done", job.error
    assert job.dest_path.read_bytes() == PAYLOAD
    assert seen[-1] == ("GET", "bytes=10-")


@pytest.mark.parametrize("content_range", ["bytes 0-30/31", "bytes 12-30/31", "", "garbage"])
def test_206_for_the_wrong_offset_installs_nothing(monkeypatch, tmp_path, content_range):
    def respond(req):
        if req.method == "HEAD":
            return _head(req)
        headers = {"content-range": content_range} if content_range else {}
        return httpx.Response(206, content=PAYLOAD[10:], headers=headers)
    job, _ = _run(monkeypatch, tmp_path, respond, partial=PAYLOAD[:10])
    assert job.status == "error" and "Content-Range" in job.error
    assert not job.dest_path.exists()
    assert job.temp_path.read_bytes() == PAYLOAD[:10], "the good partial is kept for the next attempt"


def test_206_for_a_changed_file_discards_the_partial(monkeypatch, tmp_path):
    def respond(req):
        if req.method == "HEAD":
            return _head(req)
        return httpx.Response(206, content=b"x" * 40, headers={"content-range": "bytes 10-49/50"})
    job, _ = _run(monkeypatch, tmp_path, respond, partial=PAYLOAD[:10])
    assert job.status == "error" and "changed on the server" in job.error
    assert not job.dest_path.exists() and not job.temp_path.exists()


def test_short_body_is_not_installed_and_partial_is_kept(monkeypatch, tmp_path):
    def respond(req):
        if req.method == "HEAD":
            return _head(req)
        return httpx.Response(200, content=PAYLOAD[:20])     # connection ended early
    job, _ = _run(monkeypatch, tmp_path, respond)
    assert job.status == "error" and "incomplete" in job.error and "nothing was installed" in job.error
    assert not job.dest_path.exists()
    assert job.temp_path.read_bytes() == PAYLOAD[:20]


def test_oversized_body_is_not_installed_and_is_discarded(monkeypatch, tmp_path):
    def respond(req):
        if req.method == "HEAD":
            return _head(req)
        return httpx.Response(200, content=PAYLOAD + b"extra")
    job, _ = _run(monkeypatch, tmp_path, respond)
    assert job.status == "error" and "expected 31" in job.error
    assert not job.dest_path.exists() and not job.temp_path.exists()


def test_size_known_only_from_the_request_is_still_enforced(monkeypatch, tmp_path):
    # HEAD fails; the size Hugging Face listed when the job was queued is what is checked.
    def respond(req):
        if req.method == "HEAD":
            return httpx.Response(405)
        return httpx.Response(200, content=PAYLOAD[:20])
    job, _ = _run(monkeypatch, tmp_path, respond, total=len(PAYLOAD))
    assert job.status == "error" and not job.dest_path.exists()


def test_416_for_a_complete_partial_installs_it(monkeypatch, tmp_path):
    def respond(req):
        if req.method == "HEAD":
            return _head(req)
        return httpx.Response(416, headers={"content-range": f"bytes */{len(PAYLOAD)}"})
    job, _ = _run(monkeypatch, tmp_path, respond, partial=PAYLOAD)
    assert job.status == "done", job.error
    assert job.dest_path.read_bytes() == PAYLOAD


def test_416_for_a_stale_partial_starts_over(monkeypatch, tmp_path):
    def respond(req):
        if req.method == "HEAD":
            return httpx.Response(405)                        # size unknown up front
        if req.headers.get("range"):
            return httpx.Response(416, headers={"content-range": "bytes */20"})
        return httpx.Response(200, content=PAYLOAD[:20])
    job, seen = _run(monkeypatch, tmp_path, respond, partial=b"stale-partial-that-is-too-long-for-the-file")
    assert job.status == "done", job.error
    assert job.dest_path.read_bytes() == PAYLOAD[:20]
    assert [r for m, r in seen if m == "GET"] == ["bytes=43-", None]


def test_partial_larger_than_the_known_size_is_not_resumed(monkeypatch, tmp_path):
    def respond(req):
        if req.method == "HEAD":
            return _head(req)
        assert "range" not in req.headers
        return httpx.Response(200, content=PAYLOAD)
    job, _ = _run(monkeypatch, tmp_path, respond, partial=PAYLOAD + b"junk")
    assert job.status == "done", job.error
    assert job.dest_path.read_bytes() == PAYLOAD
