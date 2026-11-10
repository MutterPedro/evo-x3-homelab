#!/usr/bin/env bash
# Renders every template into a throw-away HOME and validates the results.
# Runs in CI (no GPU needed). Usage: tests/render-test.sh [path/to/llama-swap]
# When a llama-swap binary is given, it also boots llama-swap with the rendered
# config (no models are started) and exercises the API that `evo` relies on.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config"
mkdir -p "$HOME"

# shellcheck source=../install.sh
source "$REPO/install.sh"
load_settings >/dev/null
ensure_secrets >/dev/null
write_runtime_env >/dev/null

out="$T/out"; mkdir -p "$out"
render "$REPO/config/llama-swap/config.yaml.tmpl" "$out/llama-swap.yaml"
render "$REPO/config/open-webui.env" "$out/open-webui.env"
render "$REPO/config/searxng/settings.yml" "$out/searxng.yml"
render "$REPO/config/prometheus/prometheus.yml" "$out/prometheus.yml"
render "$REPO/config/grafana/provisioning/datasources/prometheus.yaml" "$out/ds.yaml"
render "$REPO/config/comfyui/extra_model_paths.yaml" "$out/comfy.yaml"
for f in "$REPO"/quadlets/* "$REPO"/systemd/user/* "$REPO"/desktop/*; do
  render "$f" "$out/$(basename "$f")"
done

# 1. no unrendered placeholders anywhere
if grep -rn '@[A-Z0-9_]\+@' "$out"; then echo "FAIL: unrendered placeholders"; exit 1; fi
echo "ok  all placeholders rendered"

# 2. YAML parses and the llama-swap config is internally consistent
python3 - "$out" "$REPO/config/models.tsv" <<'PY'
import sys, yaml, pathlib
d = pathlib.Path(sys.argv[1])
for f in ["llama-swap.yaml", "searxng.yml", "prometheus.yml", "ds.yaml", "comfy.yaml"]:
    yaml.safe_load((d / f).read_text())
cfg = yaml.safe_load((d / "llama-swap.yaml").read_text())
pool = cfg["routing"]["router"]["settings"]["capacity"]["pools"]["gpu"]
assert isinstance(pool, int), f"pool must be an int, got {pool!r}"
for name, m in cfg["models"].items():
    assert m["capacities"]["gpu"] <= pool, f"{name} needs more than the whole pool"
for p in cfg["profiles"].values():
    for target in p["pins"].values():
        assert target in cfg["models"], f"profile pin -> unknown model {target}"
assert cfg["hooks"]["on_startup"]["profile"] in cfg["profiles"]
print("ok  YAML valid, capacities fit, profile pins resolve")

# Guardrails against the 2026-11-10 out-of-memory reboot (docs/10, docs/13):
# 1. a model's capacity can never be smaller than its weights (models.tsv GB column);
#    sizing from GTT alone had declared a 93 GiB model as 72.
sizes = {}
for l in open(sys.argv[2]):
    if l.strip() and not l.startswith("#"):
        c = l.rstrip("\n").split("\t")
        sizes[c[0]] = float(c[3])
for name, m in cfg["models"].items():
    if name in sizes:
        need = sizes[name] * 1e9 / 2**30
        assert m["capacities"]["gpu"] >= need, f"{name}: capacity {m['capacities']['gpu']} GiB < weights {need:.0f} GiB"
# 2. whatever a profile keeps resident (its pinned models plus the embedder and
#    whisper that Open WebUI always uses) has to fit the pool together.
helpers = [n for n in ("qwen3-embedding-0.6b", "whisper-large-v3-turbo") if n in cfg["models"]]
for pname, p in cfg["profiles"].items():
    resident = set(p["pins"].values()) | set(helpers)
    total = sum(cfg["models"][n]["capacities"]["gpu"] for n in resident)
    assert total <= pool, f"profile {pname}: resident set needs {total} GiB, pool is {pool}"
print("ok  capacities cover model weights; every profile's resident set fits the pool")
PY
python3 -c "import json; json.load(open('$REPO/config/grafana/dashboards/evo-x3.json'))" && echo "ok  dashboard JSON valid"

# 3. every model file referenced by llama-swap can be downloaded via models.tsv
python3 - "$out/llama-swap.yaml" "$REPO/config/models.tsv" <<'PY'
import sys, re, fnmatch
cfg = open(sys.argv[1]).read()
paths = set(re.findall(r'\$\{m\}/(\S+)', cfg))
rows = [l.rstrip("\n").split("\t") for l in open(sys.argv[2]) if l.strip() and not l.startswith("#")]
missing = []
for p in paths:
    ok = any(
        p.startswith(r[1] + "/") and any(fnmatch.fnmatch(p[len(r[1]) + 1:], pat) for pat in r[2].split())
        for r in rows
    )
    if not ok:
        missing.append(p)
assert not missing, f"not covered by models.tsv: {missing}"
print(f"ok  {len(paths)} model files in config are downloadable via models.tsv")
PY

# 4. llama-swap itself accepts the config and the API behaves as evo expects
LS="${1:-}"
if [[ -n "$LS" && -x "$LS" ]]; then
  schema="$(dirname "$LS")/config-schema.json"
  if [[ -f "$schema" ]]; then
    python3 - "$out/llama-swap.yaml" "$schema" <<'PY'
import sys, yaml, json, jsonschema
cfg, schema = yaml.safe_load(open(sys.argv[1])), json.load(open(sys.argv[2]))
errs = list(jsonschema.validators.validator_for(schema)(schema).iter_errors(cfg))
for e in errs: print("schema:", list(e.path), e.message[:200])
assert not errs
print("ok  config matches llama-swap's JSON schema")
PY
  fi
  set -a
  # shellcheck disable=SC1091
  source "$EVO_CONFIG_DIR/runtime.env"
  # shellcheck disable=SC1091
  source "$EVO_CONFIG_DIR/secrets.env"
  set +a
  "$LS" -validate -config "$out/llama-swap.yaml" && echo "ok  llama-swap -validate"
  port=18080
  "$LS" -config "$out/llama-swap.yaml" -listen "127.0.0.1:$port" >"$T/ls.log" 2>&1 &
  pid=$!
  for _ in $(seq 1 30); do curl -fs "127.0.0.1:$port/health" >/dev/null 2>&1 && break; sleep 0.5; done
  if ! kill -0 "$pid" 2>/dev/null; then cat "$T/ls.log"; echo "FAIL: llama-swap rejected config"; exit 1; fi
  H="Authorization: Bearer $LLAMA_SWAP_KEY"
  curl -fs -H "$H" "127.0.0.1:$port/api/profiles" \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["active"]=="smart", d; print("ok  llama-swap loaded config; active profile:", d["active"])'
  curl -fs -H "$H" "127.0.0.1:$port/v1/models" \
    | python3 -c 'import json,sys; print("ok  /v1/models:", ", ".join(m["id"] for m in json.load(sys.stdin)["data"]))'
  code=$(curl -s -o /dev/null -w '%{http_code}' "127.0.0.1:$port/v1/models")
  [[ "$code" == 401 ]] && echo "ok  API key enforced (401 without key)" || { echo "FAIL: expected 401, got $code"; exit 1; }
  curl -fs -X PUT -H "$H" "127.0.0.1:$port/api/profiles/active" -d '{"name":"fast"}' >/dev/null && echo "ok  profile switch"
  curl -fs -X POST -H "$H" "127.0.0.1:$port/api/models/pause" >/dev/null \
    && curl -fs -X POST -H "$H" "127.0.0.1:$port/api/models/resume" >/dev/null && echo "ok  pause/resume"
  kill "$pid"; wait "$pid" 2>/dev/null || true
fi
echo "PASS"
