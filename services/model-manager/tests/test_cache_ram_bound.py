"""#697: every section write leaves an explicit, bounded prompt cache (--cache-ram), autoconfig
never suggests one above the cap, and autoconfig sizes against noevia's inference budget."""
import pytest
from fastapi.testclient import TestClient

from conftest import INI, ROOT, _gguf
from app import api, autoconfig, gguf_meta, ini
from app.config import settings
from app.main import app


@pytest.fixture(scope="module")
def client():
    with TestClient(app) as c:
        yield c


@pytest.fixture(autouse=True)
def reset_ini():
    (ROOT / "models" / "models.ini").write_text(INI)


def _save(client, values, extras=""):
    current = client.get("/api/v1/sections/tiny").json()
    r = client.put("/api/v1/sections/tiny", json={"baseRevision": current["revision"], "values": {**current["values"], **values}, "extras": extras})
    assert r.status_code == 200, r.text
    return r.json()["section"]


def test_limits_default_to_1024_and_2048_and_the_cap_never_exceeds_the_maximum(monkeypatch):
    assert settings.cache_ram_limits == (1024, 2048)
    monkeypatch.setattr(settings, "llamacpp_autoconfig_cache_ram_max_mib", 4096)
    assert settings.cache_ram_limits == (2048, 2048)


def test_clamp_turns_unbounded_and_oversized_values_into_the_hard_maximum():
    assert ini.clamp_cache_ram("8192") == "2048"
    assert ini.clamp_cache_ram("-1") == "2048"
    assert ini.clamp_cache_ram(" 512 ") == "512"
    assert ini.clamp_cache_ram("0") == "0"
    assert ini.clamp_cache_ram("lots") == "lots"  # not ours to reinterpret


def test_a_saved_section_without_cache_ram_gets_the_cap(client):
    assert "cache-ram" not in ini.get_section("tiny")
    assert _save(client, {"ctx-size": "8192"})["cache-ram"] == "1024"


@pytest.mark.parametrize("given,stored", [("8192", "2048"), ("-1", "2048"), ("2048", "2048"), ("512", "512"), ("0", "0")])
def test_a_saved_cache_ram_is_clamped_to_the_hard_maximum(client, given, stored):
    assert _save(client, {"cache-ram": given})["cache-ram"] == stored


def test_extras_cannot_slip_an_unbounded_cache_past_the_clamp(client):
    assert _save(client, {"cache-ram": ""}, extras="cache-ram = 16384")["cache-ram"] == "2048"


def test_a_bounded_global_default_is_inherited_instead_of_duplicated(client):
    (ROOT / "models" / "models.ini").write_text("version = 1\n\n[*]\ncache-ram = 512\n" + INI.split("version = 1\n", 1)[1])
    assert "cache-ram" not in _save(client, {"ctx-size": "8192"})
    (ROOT / "models" / "models.ini").write_text("version = 1\n\n[*]\ncache-ram = 8192\n" + INI.split("version = 1\n", 1)[1])
    assert _save(client, {"ctx-size": "8192"})["cache-ram"] == "1024"


def test_safe_defaults_registration_writes_the_cap(client):
    folder = ROOT / "models" / "fresh-Q4"
    folder.mkdir(exist_ok=True)
    (folder / "fresh-Q4.gguf").write_bytes(_gguf({
        "general.architecture": "llama", "llama.context_length": 32768, "llama.embedding_length": 256,
        "llama.block_count": 4, "llama.attention.head_count": 4, "llama.attention.head_count_kv": 2,
        "tokenizer.chat_template": "{{ messages }}"}) + b"\0" * 4096)
    r = client.post("/api/v1/sections/fresh-Q4/safe-defaults")
    assert r.status_code == 200, r.text
    assert r.json()["section"]["cache-ram"] == "1024"


def test_autoconfig_never_suggests_a_cache_above_the_cap():
    path = ROOT / "models" / "tiny" / "tiny-Q4_K_M.gguf"
    summary = gguf_meta.summarize(gguf_meta.read_raw(path))
    # Plenty of host RAM: before #697 this suggested llama-server's 8192 MiB default or more.
    backend = [{"name": "engine", "vendor": "unknown", "vram_gb": 14.0, "gpu_count": 1, "card_vram_gb": [14.0], "host_ram_gb": 128.0, "baseline": {}}]
    rec = autoconfig.analyze(summary=summary, file_size=4096, backends=backend, vision=False)
    assert rec.values.get("cache-ram") and int(rec.values["cache-ram"]) <= 1024


def test_autoconfig_backends_are_sized_against_the_budget_less_the_prompt_cache():
    backends = [{"name": "engine", "vram_gb": 30.0, "card_vram_gb": [20.0, 10.0], "host_ram_gb": 64.0}]
    sized = api.budget_backends(backends, 16)
    assert sized[0]["vram_gb"] == 15.0                       # 16 GiB less the 1 GiB cache cap
    assert sized[0]["card_vram_gb"] == [10.0, 5.0]
    assert backends[0]["vram_gb"] == 30.0                    # the discovered list is not mutated
    assert api.budget_backends(backends, 0) is backends      # no budget sent: unchanged
    assert api.budget_backends(backends, "junk") is backends
    small = api.budget_backends([{"name": "e", "vram_gb": 8.0}], 16)
    assert small[0]["vram_gb"] == 8.0                        # never raised above the hardware
