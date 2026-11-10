#!/usr/bin/env python3
"""Generates config/grafana/dashboards/evo-llm.json (the "EVO-X3 LLM" dashboard).

The dashboard is code so it can be reviewed and changed without hand-editing JSON:
edit this file, run `python3 tools/grafana/build_llm_dashboard.py`, commit both.
Standard library only. See docs/09-monitoring-and-backups.md for what each panel means.
"""
import json
import pathlib

DS = {"type": "prometheus", "uid": "prometheus"}
OUT = pathlib.Path(__file__).resolve().parents[2] / "config/grafana/dashboards/evo-llm.json"

_id = [0]
panels = []


def nid():
    _id[0] += 1
    return _id[0]


def target(expr, legend="", ref="A", fmt=None, instant=False, interval=None):
    t = {"refId": ref, "expr": expr, "legendFormat": legend}
    if fmt:
        t["format"] = fmt
    if instant:
        t["instant"] = True
    if interval:
        t["interval"] = interval
    return t


def steps(*pairs):
    return {"mode": "absolute", "steps": [{"color": c, "value": v} for c, v in pairs]}


def row(title, y):
    panels.append({"id": nid(), "type": "row", "title": title, "collapsed": False,
                   "gridPos": {"x": 0, "y": y, "w": 24, "h": 1}, "panels": []})


def stat(title, expr, x, y, w, h=4, unit="none", decimals=None, thr=None, text="auto", desc="",
         legend="", mappings=None, graph=True):
    d = {"unit": unit, "thresholds": thr or steps(("green", None))}
    if decimals is not None:
        d["decimals"] = decimals
    if mappings:
        d["mappings"] = mappings
    panels.append({"id": nid(), "type": "stat", "title": title, "description": desc, "datasource": DS,
                   "gridPos": {"x": x, "y": y, "w": w, "h": h},
                   "fieldConfig": {"defaults": d, "overrides": []},
                   "options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "colorMode": "value",
                               "graphMode": "area" if graph else "none", "textMode": text},
                   "targets": [target(expr, legend)]})


def ts(title, targets, x, y, w, h=8, unit="none", desc="", min_=None, max_=None, kind="line", stack=False,
       overrides=None, decimals=None):
    custom = {"lineWidth": 2, "fillOpacity": 15 if kind == "line" else 70, "spanNulls": False,
              "stacking": {"mode": "normal" if stack else "none"}}
    if kind == "bars":
        custom.update({"drawStyle": "bars", "lineWidth": 1})
    d = {"unit": unit, "custom": custom}
    if min_ is not None:
        d["min"] = min_
    if max_ is not None:
        d["max"] = max_
    if decimals is not None:
        d["decimals"] = decimals
    panels.append({"id": nid(), "type": "timeseries", "title": title, "description": desc, "datasource": DS,
                   "gridPos": {"x": x, "y": y, "w": w, "h": h},
                   "fieldConfig": {"defaults": d, "overrides": overrides or []},
                   "options": {"legend": {"displayMode": "list", "placement": "bottom"}, "tooltip": {"mode": "multi"}},
                   "targets": targets})


def bargauge(title, expr, legend, x, y, w, h=8, unit="none", desc="", max_=None):
    d = {"unit": unit, "min": 0, "thresholds": steps(("blue", None))}
    if max_ is not None:
        d["max"] = max_
    panels.append({"id": nid(), "type": "bargauge", "title": title, "description": desc, "datasource": DS,
                   "gridPos": {"x": x, "y": y, "w": w, "h": h},
                   "fieldConfig": {"defaults": d, "overrides": []},
                   "options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "orientation": "horizontal",
                               "displayMode": "gradient", "showUnfilled": True},
                   "targets": [target(expr, legend, instant=True)]})


# ---- expressions ---------------------------------------------------------------
M = 'model=~"$model"'
GEN = f'rate(llamacpp:tokens_predicted_total{{{M}}}[2m]) / rate(llamacpp:tokens_predicted_seconds_total{{{M}}}[2m])'
PRM = f'rate(llamacpp:prompt_tokens_total{{{M}}}[2m]) / rate(llamacpp:prompt_seconds_total{{{M}}}[2m])'
TOK = "suffix: tok/s"
PRICE_OUT = 'evo_cloud_price_usd_per_mtok{direction="output"}'
PRICE_IN = 'evo_cloud_price_usd_per_mtok{direction="input"}'


def value(sel, window, by=""):
    """USD the cloud equivalent would have charged for the tokens in `window`."""
    b = f"sum {by}" if by else "sum"
    return (f'({b}(increase(evo_tokens_total{{kind="generated"{sel}}}[{window}]) * on(model) {PRICE_OUT}) / 1e6'
            f' + {b}(increase(evo_tokens_total{{kind="prompt"{sel}}}[{window}]) * on(model) {PRICE_IN}) / 1e6)')


LIFETIME = ('(sum(evo_tokens_total{kind="generated"} * on(model) ' + PRICE_OUT + ') / 1e6'
            ' + sum(evo_tokens_total{kind="prompt"} * on(model) ' + PRICE_IN + ') / 1e6)')
# electricity for the selected time range, USD: (APU power + overhead) x hours x tariff / fx
ELEC = ('((avg_over_time(sum(node_hwmon_power_average_watt)[$__range:5m]) + scalar(evo_power_overhead_watts))'
        ' * $__range_s / 3.6e6 * scalar(evo_electricity_price_brl_per_kwh) / scalar(evo_usd_brl))')
FX = "* scalar(evo_usd_brl)"

# ===== row 1: at a glance ===========================================================
row("At a glance", 0)
stat("Generating now", f'sum(rate(llamacpp:tokens_predicted_total[1m])) / sum(rate(llamacpp:tokens_predicted_seconds_total[1m])) > 0',
     0, 1, 4, unit=TOK, decimals=1, desc="Token generation speed of whatever is answering right now. Empty when idle.")
stat("Prompt speed now", 'sum(rate(llamacpp:prompt_tokens_total[1m])) / sum(rate(llamacpp:prompt_seconds_total[1m])) > 0',
     4, 1, 4, unit=TOK, decimals=0, desc="How fast the model reads a prompt right now. Empty when idle.")
stat("Models loaded", 'sum(evo_model_loaded) or vector(0)', 8, 1, 3, desc="Models resident in memory.", graph=False)
stat("Requests running", 'sum(llamacpp:requests_processing) or vector(0)', 11, 1, 3, graph=False,
     desc="Requests being processed by all loaded models.")
stat("Free RAM", 'node_memory_MemAvailable_bytes', 14, 1, 4, unit="bytes", decimals=1,
     thr=steps(("red", None), ("orange", 6 * 2**30), ("green", 12 * 2**30)),
     desc="The number the memory guard watches. Under 6 GiB it unloads models, under 3 GiB it kills them.")
stat("Mode", 'evo_mode', 18, 1, 3, text="name", legend="{{mode}}", graph=False, desc="evo mode game | server | quiet")
stat("Profile", 'evo_profile', 21, 1, 3, text="name", legend="{{profile}}", graph=False, desc="llama-swap profile: smart | fast | multi")

# ===== row 2: speed ================================================================
row("LLM speed (live usage)", 5)
ts("Generation speed per model", [target(GEN, "{{model}}")], 0, 6, 12, unit=TOK, min_=0,
   desc="Tokens generated per second while a request is running (gaps = idle). Depends on prompt and context length: for a fair comparison use the benchmark in 'Model comparison'.")
ts("Prompt processing speed per model", [target(PRM, "{{model}}")], 12, 6, 12, unit=TOK, min_=0,
   desc="How fast the model reads the prompt, per model.")
ts("Speculative decoding acceptance (MTP)",
   [target(f'rate(llamacpp:spec_decode_num_accepted_tokens_total{{{M}}}[5m]) / rate(llamacpp:spec_decode_num_draft_tokens_total{{{M}}}[5m])', "{{model}}")],
   0, 14, 8, h=7, unit="percentunit", min_=0, max_=1,
   desc="Share of the draft tokens the big model accepted. Higher = faster. Only models with an MTP draft (Flash-Next).")
ts("Prompt cache hit ratio",
   [target(f'rate(llamacpp:prompt_tokens_cached_total{{{M}}}[5m]) / (rate(llamacpp:prompt_tokens_cached_total{{{M}}}[5m]) + rate(llamacpp:prompt_tokens_total{{{M}}}[5m]))', "{{model}}")],
   8, 14, 8, h=7, unit="percentunit", min_=0, max_=1, desc="Share of prompt tokens reused instead of recomputed. High in long chats and coding agents.")
ts("Requests running / deferred",
   [target(f'llamacpp:requests_processing{{{M}}}', "{{model}} running", "A"),
    target(f'llamacpp:requests_deferred{{{M}}}', "{{model}} waiting", "B")], 16, 14, 8, h=7, min_=0,
   desc="Waiting requests mean a model's parallel slots are all busy.")
ts("Tokens generated per hour",
   [target(f'sum by (model)(increase(evo_tokens_total{{kind="generated",{M}}}[1h]))', "{{model}}", interval="1h")],
   0, 21, 12, h=7, kind="bars", stack=True, desc="Output tokens produced per hour, per model.")
ts("Longest context seen", [target(f'llamacpp:n_tokens_max{{{M}}}', "{{model}}")], 12, 21, 12, h=7, min_=0,
   desc="Largest prompt+answer a loaded model has handled since it started.")

# ===== row 3: comparison ============================================================
row("Model comparison (side by side)", 28)
bargauge("Average generation speed (selected time range)",
         f'avg by (model)(avg_over_time(({GEN} > 0)[$__range:1m]))', "{{model}}", 0, 29, 8, unit=TOK,
         desc="Mean tokens/s over the dashboard's time range while generating. Real usage: mixes easy and hard prompts.")
bargauge("Benchmark: generation speed", 'sum by (model)(evo_bench_tokens_per_second{kind="generation"})', "{{model}}",
         8, 29, 8, unit=TOK, desc="Same ~10k-token prompt on every model. Refresh it with `evo bench --all` (about 5 minutes).")
bargauge("Benchmark: prompt processing", 'sum by (model)(evo_bench_tokens_per_second{kind="prompt"})', "{{model}}",
         16, 29, 8, unit=TOK, desc="How fast each model reads the same ~10k-token prompt.")
cols = [
    ("A", f'avg by (model)(avg_over_time(({GEN} > 0)[$__range:1m]))', "Gen tok/s (usage)"),
    ("B", f'avg by (model)(avg_over_time(({PRM} > 0)[$__range:1m]))', "Prompt tok/s (usage)"),
    ("C", 'sum by (model)(evo_bench_tokens_per_second{kind="generation"})', "Gen tok/s (bench)"),
    ("D", 'sum by (model)(evo_bench_tokens_per_second{kind="prompt"})', "Prompt tok/s (bench)"),
    ("E", 'sum by (model)(increase(evo_tokens_total{kind="generated"}[$__range]))', "Tokens generated"),
    ("F", 'sum by (model)(increase(llamacpp:spec_decode_num_accepted_tokens_total[$__range])) / sum by (model)(increase(llamacpp:spec_decode_num_draft_tokens_total[$__range]))', "MTP acceptance"),
    ("G", value("", "$__range", "by (model)"), "Cloud value (USD)"),
    ("H", 'sum by (model)(evo_model_loaded)', "Loaded"),
]
panels.append({
    "id": nid(), "type": "table", "title": "Models at a glance (selected time range)", "datasource": DS,
    "gridPos": {"x": 0, "y": 37, "w": 24, "h": 8},
    "fieldConfig": {"defaults": {"custom": {"align": "auto"}}, "overrides": [
        {"matcher": {"id": "byName", "options": "Gen tok/s (usage)"}, "properties": [{"id": "decimals", "value": 1}]},
        {"matcher": {"id": "byName", "options": "Gen tok/s (bench)"}, "properties": [{"id": "decimals", "value": 1}]},
        {"matcher": {"id": "byName", "options": "Prompt tok/s (usage)"}, "properties": [{"id": "decimals", "value": 0}]},
        {"matcher": {"id": "byName", "options": "Prompt tok/s (bench)"}, "properties": [{"id": "decimals", "value": 0}]},
        {"matcher": {"id": "byName", "options": "Tokens generated"}, "properties": [{"id": "unit", "value": "short"}, {"id": "decimals", "value": 0}]},
        {"matcher": {"id": "byName", "options": "MTP acceptance"}, "properties": [{"id": "unit", "value": "percentunit"}, {"id": "decimals", "value": 0}]},
        {"matcher": {"id": "byName", "options": "Cloud value (USD)"}, "properties": [{"id": "unit", "value": "currencyUSD"}, {"id": "decimals", "value": 2}]},
        {"matcher": {"id": "byName", "options": "Loaded"}, "properties": [{"id": "mappings", "value": [
            {"type": "value", "options": {"1": {"text": "yes", "color": "green"}, "0": {"text": "-"}}}]}]},
    ]},
    "options": {"showHeader": True, "sortBy": [{"displayName": "Gen tok/s (bench)", "desc": True}]},
    "transformations": [
        {"id": "merge", "options": {}},
        {"id": "organize", "options": {
            "excludeByName": {"Time": True},
            "renameByName": dict({"model": "Model"}, **{f"Value #{r}": n for r, _, n in cols}),
            "indexByName": {"model": 0, **{f"Value #{r}": i + 1 for i, (r, _, _) in enumerate(cols)}}}}],
    "targets": [target(e, "", r, fmt="table", instant=True) for r, e, _ in cols]})

# ===== row 4: money =================================================================
row("Money saved vs the cloud (estimate)", 45)
gross = value("", "$__range")
tip = ("What the cloud equivalent in config/cloud-prices.tsv would have charged for the tokens served in the "
       "selected time range (uncached prompt + generated tokens).")
for y, cur, mult, unit in ((46, "US$", "", "currencyUSD"), (50, "R$", " " + FX, "currencyBRL")):
    stat(f"Cloud cost avoided ({cur})", f"({gross}){mult}", 0, y, 6, unit=unit, decimals=2, desc=tip, graph=False)
    stat(f"Electricity used ({cur})", f"({ELEC}){mult}", 6, y, 6, unit=unit, decimals=2, graph=False,
         desc="Energy cost of keeping the machine on in the selected range: APU power sensor + the overhead estimate, "
              "x your tariff (evo.env). Counts idle time too, so it is a conservative figure.")
    stat(f"Net saved ({cur})", f"({gross} - {ELEC}){mult}", 12, y, 6, unit=unit, decimals=2, graph=False,
         thr=steps(("red", None), ("green", 0)),
         desc="Cloud cost avoided minus all electricity. Negative means the cloud would have been cheaper for this usage.")
    stat(f"Since install ({cur}, cloud value)", f"({LIFETIME}){mult}", 18, y, 6, unit=unit, decimals=2, graph=False,
         desc="Lifetime cloud value of every token ever served (kept by evo-exporter across restarts). Before electricity.")
ts("Cloud cost avoided per day, by model (US$)", [target(value(f',{M}', "1d", "by (model)"), "{{model}}", interval="1d")],
   0, 54, 12, unit="currencyUSD", kind="bars", stack=True, decimals=2,
   desc="Each bar is one day: what the cloud equivalent would have charged for that model's tokens.")
ts("Cost per 1M generated tokens: local electricity vs cloud (US$)",
   [target(f'((scalar(sum(node_hwmon_power_average_watt)) + scalar(evo_power_overhead_watts)) / ({GEN})) * 1e6 / 3.6e6 '
           f'* scalar(evo_electricity_price_brl_per_kwh) / scalar(evo_usd_brl)', "{{model}} (local electricity)", "A"),
    target(f'evo_cloud_price_usd_per_mtok{{direction="output",{M}}}', "{{model}} (cloud: {{cloud_model}})", "B")],
   12, 54, 12, unit="currencyUSD", min_=0, decimals=2,
   desc="Marginal cost of an output token: electricity while generating (local, solid) against the cloud price (flat lines). "
        "Where the local line rises above the cloud line, the cloud is cheaper.")
panels.append({
    "id": nid(), "type": "table", "title": "Price assumptions (edit config/cloud-prices.tsv, evo.env)", "datasource": DS,
    "gridPos": {"x": 0, "y": 62, "w": 24, "h": 5},
    "fieldConfig": {"defaults": {}, "overrides": []}, "options": {"showHeader": True},
    "transformations": [{"id": "organize", "options": {
        "excludeByName": {"Time": True, "__name__": True, "job": True, "instance": True},
        "renameByName": {"model": "Local model", "cloud_model": "Cloud equivalent", "direction": "Direction", "Value": "US$ per 1M tokens"}}}],
    "targets": [target("evo_cloud_price_usd_per_mtok", "", "A", fmt="table", instant=True)]})

# ===== row 5: machine health ========================================================
row("Machine health", 67)
ts("Free RAM vs the memory guard limits",
   [target("node_memory_MemAvailable_bytes", "free RAM", "A"),
    target(f"vector({6 * 2**30})", "soft limit: unload models (6 GiB)", "B"),
    target(f"vector({3 * 2**30})", "hard limit: kill models (3 GiB)", "C"),
    target("node_memory_SwapTotal_bytes - node_memory_SwapFree_bytes", "swap used", "D")],
   0, 68, 12, unit="bytes", min_=0,
   desc="GPU memory is system RAM, so this is the headroom that keeps the machine alive (docs/13).")
ts("Memory pressure (stall time)",
   [target("rate(node_pressure_memory_waiting_seconds_total[1m]) * 100", "some tasks waiting", "A"),
    target("rate(node_pressure_memory_stalled_seconds_total[1m]) * 100", "all tasks stalled", "B")],
   12, 68, 12, unit="percent", min_=0, desc="Above a few percent the system is thrashing. The 2026-11-10 freeze reached tens of percent.")
ts("Power draw (APU sensor)", [target("sum(node_hwmon_power_average_watt)", "APU / GPU power")], 0, 76, 8, unit="watt", min_=0,
   desc="What the chip reports. Wall power is somewhat higher (see evo.env EVO_POWER_OVERHEAD_W).")
ts("Temperatures", [target("node_hwmon_temp_celsius", "{{chip}} {{sensor}}")], 8, 76, 8, unit="celsius",
   desc="Sustained 90+ means it is running hot.")
ts("Clocks", [target("node_hwmon_freq_freq_mhz", "{{chip}} {{sensor}}")], 16, 76, 8, unit="rotmhz", min_=0, desc="GPU and fabric clocks.")
stat("Last backup", 'time() - evo_last_backup_timestamp_seconds', 0, 84, 6, unit="s", decimals=0, graph=False,
     thr=steps(("green", None), ("orange", 36 * 3600), ("red", 72 * 3600)), desc="Age of the last successful `evo backup run`. The timer runs daily.")
stat("Uptime", 'time() - node_boot_time_seconds', 6, 84, 6, unit="s", decimals=0, graph=False, desc="Since the last (re)boot.")
stat("Memory guard interventions", 'sum(evo_memguard_events_total)', 12, 84, 6, graph=False,
     thr=steps(("green", None), ("orange", 1)), desc="Times evo-memguard had to unload or kill models. Should stay 0.")
stat("Monitoring targets up", 'count(up == 1)', 18, 84, 6, graph=False,
     thr=steps(("red", None), ("green", 3)), desc="Prometheus targets answering (should be 3: node, llama-swap, evo).")

dashboard = {
    "uid": "evo-llm", "title": "EVO-X3 LLM", "tags": ["evo-x3", "llm"], "schemaVersion": 39, "version": 1,
    "time": {"from": "now-24h", "to": "now"}, "refresh": "30s", "timezone": "browser",
    "graphTooltip": 1,
    "templating": {"list": [{
        "name": "model", "label": "Models", "type": "query", "datasource": DS,
        "query": {"query": "label_values(evo_model_loaded, model)", "refId": "model"},
        "definition": "label_values(evo_model_loaded, model)", "refresh": 2, "multi": True, "includeAll": True,
        "allValue": ".*", "current": {"selected": True, "text": ["All"], "value": ["$__all"]}, "sort": 1}]},
    "annotations": {"list": [
        {"name": "Model loaded", "datasource": DS, "enable": True, "iconColor": "green",
         "expr": '(evo_model_loaded == 1) and (evo_model_loaded offset 1m == 0)', "step": "30s",
         "titleFormat": "{{model}} loaded"},
        {"name": "Model unloaded", "datasource": DS, "enable": True, "iconColor": "gray",
         "expr": '(evo_model_loaded == 0) and (evo_model_loaded offset 1m == 1)', "step": "30s",
         "titleFormat": "{{model}} unloaded"},
        {"name": "Reboot", "datasource": DS, "enable": True, "iconColor": "red",
         "expr": "changes(node_boot_time_seconds[2m]) > 0", "step": "60s", "titleFormat": "reboot"},
        {"name": "Memory guard", "datasource": DS, "enable": True, "iconColor": "orange",
         "expr": "changes(evo_memguard_events_total[1m]) > 0", "step": "30s",
         "titleFormat": "memory guard {{level}}"}]},
    "panels": panels,
}
OUT.write_text(json.dumps(dashboard, indent=1) + "\n")
print(f"wrote {OUT.relative_to(OUT.parents[3])}: {len(panels)} panels")
