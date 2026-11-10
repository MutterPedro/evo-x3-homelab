"""Unit test for bin/evo-exporter with a fake llama-swap (no network, no GPU).
Run: python3 tests/exporter_test.py   (standard library only)"""
import sys
sys.dont_write_bytecode = True  # do not leave bin/__pycache__ behind
import importlib.machinery
import importlib.util
import json
import pathlib
import tempfile

root = pathlib.Path(__file__).resolve().parent.parent
loader = importlib.machinery.SourceFileLoader("evo_exporter", str(root / "bin" / "evo-exporter"))
spec = importlib.util.spec_from_loader("evo_exporter", loader)
mod = importlib.util.module_from_spec(spec)
loader.exec_module(mod)

tmp = pathlib.Path(tempfile.mkdtemp())
(tmp / "cfg").mkdir()
(tmp / "state").mkdir()
(tmp / "cfg" / "cloud-prices.tsv").write_text(
    "model\tcloud_model\tinput\toutput\tnote\ngemma\tclaude-haiku-5-5\t0.10\t0.50\tx\n")
(tmp / "state" / "state.env").write_text("MODE=server\n")
(tmp / "state" / "memguard.events").write_text("100 soft\n200 hard\n300 soft\n")
(tmp / "state" / "last-backup").write_text("1700000000\n")
(tmp / "state" / "bench.json").write_text(json.dumps({"gemma": {"generation": 60.5, "prompt": 1500, "ts": 5}}))

prompt, gen = [1000.0], [200.0]
running = {"running": [{"model": "gemma", "state": "ready", "proxy": "http://localhost:10002"}]}


def fetch(url, auth=True):
    if url.endswith("/running"):
        return json.dumps(running)
    if url.endswith("/v1/models"):
        return json.dumps({"data": [{"id": "gemma"}, {"id": "chat"}, {"id": "other"}]})
    if url.endswith("/api/profiles"):
        return json.dumps({"active": "smart"})
    if url.endswith("/metrics"):
        return (f"# HELP llamacpp:prompt_tokens_total x\n# TYPE llamacpp:prompt_tokens_total counter\n"
                f"llamacpp:prompt_tokens_total {prompt[0]}\nllamacpp:tokens_predicted_total {gen[0]}\n"
                f"llamacpp:prompt_tokens_cached_total 5\nllamacpp:requests_processing 1\nunrelated 1\n")
    return None


def new():
    return mod.Collector(fetch, tmp / "state", tmp / "cfg", {"EVO_KWH_PRICE_BRL": "1.25"})


def val(text, prefix):
    return [l for l in text.splitlines() if l.startswith(prefix)]


c = new()
t = c.collect()
assert 'llamacpp:prompt_tokens_total{model="gemma"} 1000.0' in t, t
assert 'llamacpp:requests_processing{model="gemma"} 1' in t
assert "unrelated" not in t, "only llamacpp:* passes through"
assert 'evo_model_loaded{model="gemma"} 1' in t and 'evo_model_loaded{model="other"} 0' in t
assert 'evo_model_loaded{model="chat"}' not in t, "profile names are not models"
assert 'evo_tokens_total{model="gemma",kind="generated"} 200.0' in t
assert 'evo_mode{mode="server"} 1' in t and 'evo_profile{profile="smart"} 1' in t
assert 'evo_memguard_events_total{level="soft"} 2' in t and 'evo_memguard_events_total{level="hard"} 1' in t
assert "evo_last_backup_timestamp_seconds 1700000000" in t
assert 'evo_bench_tokens_per_second{model="gemma",kind="generation"} 60.5' in t
assert 'evo_cloud_price_usd_per_mtok{model="gemma",cloud_model="claude-haiku-5-5",direction="output"} 0.5' in t
assert "evo_electricity_price_brl_per_kwh 1.25" in t and "evo_usd_brl 5.5" in t

gen[0] = 500.0                      # normal growth: +300
t = c.collect()
assert 'evo_tokens_total{model="gemma",kind="generated"} 500.0' in t, val(t, "evo_tokens_total")

gen[0] = 50.0                       # container restarted: counter back to a lower value
t = c.collect()
assert 'evo_tokens_total{model="gemma",kind="generated"} 550.0' in t, val(t, "evo_tokens_total")

t = new().collect()                 # exporter restarted: persisted state, no double counting
assert 'evo_tokens_total{model="gemma",kind="generated"} 550.0' in t, val(t, "evo_tokens_total")

running["running"] = []             # model unloaded, next load starts from zero
t = c.collect()
assert 'evo_model_loaded{model="gemma"} 0' in t
assert 'evo_tokens_total{model="gemma",kind="generated"} 550.0' in t
running["running"] = [{"model": "gemma", "state": "ready", "proxy": "http://localhost:10002"}]
gen[0] = 30.0
t = c.collect()
assert 'evo_tokens_total{model="gemma",kind="generated"} 580.0' in t, val(t, "evo_tokens_total")
print("ok  exporter: pass-through, lifetime totals survive resets and restarts, config metrics")
