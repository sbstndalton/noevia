"""#886: a model-manager restart must not forget a llama-bench container it started. Startup
finds sweep containers by their label, stops them, and keeps reporting the benchmark as active
if one cannot be stopped. Containers without the label are never touched. Fake docker client."""
from __future__ import annotations

import pytest

from app import bench, services


class _NotFound(Exception):
    pass


_NotFound.__name__ = "NotFound"


class FakeContainer:
    def __init__(self, name, status="running", labels=None, kill_fails=0):
        self.name, self.status, self.labels = name, status, labels or {}
        self.kill_fails, self.killed, self.removed = kill_fails, 0, False

    def reload(self):
        if self.removed:
            raise _NotFound(self.name)

    def kill(self):
        if self.kill_fails > 0:
            self.kill_fails -= 1
            raise RuntimeError("permission denied")
        self.killed += 1
        self.status = "exited"

    def remove(self, force=False):
        if self.status == "running" and not force:
            raise RuntimeError("container is running")
        self.removed = True


class FakeContainers:
    def __init__(self, all_containers):
        self.all = all_containers
        self.queries = []

    def list(self, all=False, filters=None):
        self.queries.append(filters)
        want = (filters or {}).get("label")
        if want is None:
            return list(self.all)
        k, _, v = want.partition("=")
        return [c for c in self.all if c.labels.get(k) == v and not c.removed]


class FakeClient:
    def __init__(self, *containers):
        self.containers = FakeContainers(list(containers))


LABEL = {bench.SWEEP_LABEL: "1"}


@pytest.fixture(autouse=True)
def _idle(monkeypatch):
    bench._STATE = bench.JobState()
    monkeypatch.setattr(bench, "ORPHAN_RETRY_S", 0.01)
    yield
    t = bench._THREAD
    if t is not None and t.is_alive():
        t.join(3)
    bench._STATE = bench.JobState()


def _client(monkeypatch, *containers):
    client = FakeClient(*containers)
    monkeypatch.setattr(services, "_docker_client", lambda: client)
    return client


def test_a_running_orphan_is_killed_and_removed_and_nothing_else_is_touched(monkeypatch):
    orphan = FakeContainer("bench-1", labels=LABEL)
    done = FakeContainer("bench-2", status="exited", labels=LABEL)
    other = FakeContainer("cowork-llama-1", labels={"com.docker.compose.service": "llama"})
    lookalike = FakeContainer("bench-lookalike", labels={"noevia.model-manager.bench": "0"})
    unlabelled = FakeContainer("some-llama-bench")
    client = _client(monkeypatch, orphan, done, other, lookalike, unlabelled)
    out = bench.reap_orphans()
    assert out == {"reaped": 2, "stuck": 0}
    assert orphan.killed == 1 and orphan.removed
    assert done.killed == 0 and done.removed          # finished: just cleaned up
    for untouched in (other, lookalike, unlabelled):
        assert untouched.killed == 0 and not untouched.removed and untouched.status in ("running",)
    assert client.containers.queries == [{"label": f"{bench.SWEEP_LABEL}=1"}]
    assert not bench.state().active


def test_an_orphan_that_cannot_be_stopped_keeps_the_benchmark_active_until_it_is(monkeypatch):
    stubborn = FakeContainer("bench-1", labels=LABEL, kill_fails=3)
    _client(monkeypatch, stubborn)
    out = bench.reap_orphans()
    assert out == {"reaped": 0, "stuck": 1}
    assert bench.state().active                       # web keeps its maintenance hold
    ok, msg = bench.start_sweep(backend="b", aliases=["a"])
    assert not ok and "already running" in msg        # and no second run starts on top of it
    bench._THREAD.join(5)
    assert stubborn.removed and stubborn.killed == 1
    assert not bench.state().active and bench.state().status == "error"
    assert "restart" in bench.state().error


def test_a_run_owned_by_this_process_is_not_reaped(monkeypatch):
    mine = FakeContainer("bench-mine", labels=LABEL)
    _client(monkeypatch, mine)
    bench._STATE = bench.JobState(status="running")
    assert bench.reap_orphans() == {"reaped": 0, "stuck": 0}
    assert mine.killed == 0 and not mine.removed


def test_no_docker_or_a_docker_error_never_stops_startup(monkeypatch):
    monkeypatch.setattr(services, "_docker_client", lambda: None)
    assert bench.reap_orphans() == {"reaped": 0, "stuck": 0}

    class Broken:
        class containers:
            @staticmethod
            def list(**kw):
                raise RuntimeError("daemon went away")
    monkeypatch.setattr(services, "_docker_client", lambda: Broken())
    assert bench.reap_orphans() == {"reaped": 0, "stuck": 0}
    assert not bench.state().active


def test_sweep_containers_are_created_with_the_label(monkeypatch):
    captured = {}

    class Cont:
        status = "exited"

        def reload(self): pass
        def logs(self, **kw): return b"[]"
        def remove(self, force=False): pass

    class Containers:
        def run(self, **kw):
            captured.update(kw)
            return Cont()
    monkeypatch.setattr(services, "_docker_client", lambda: type("C", (), {"containers": Containers()})())
    monkeypatch.setattr(bench, "_sweep_runtime", lambda b: ("img:1", {}, False, ""))
    entries, err = bench.run_sweep_once("b", "/models/x.gguf", [], 1, 1, "", 1)
    assert err == "" and entries == []
    assert captured["labels"] == {bench.SWEEP_LABEL: "1"}


def test_startup_hook_calls_the_reaper_and_survives_its_failure(monkeypatch):
    from app import main
    calls = []
    monkeypatch.setattr(bench, "reap_orphans", lambda: calls.append(1) or (_ for _ in ()).throw(RuntimeError("x")))
    monkeypatch.setattr(main.hw, "start_sampler", lambda: None)
    main._startup()
    assert calls == [1]
