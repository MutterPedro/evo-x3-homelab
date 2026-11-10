#!/usr/bin/env python3
"""Runs every panel and annotation query of a dashboard against the live Prometheus and reports
errors (bad PromQL) and empty results. Use after changing a dashboard:
    python3 tools/grafana/check_queries.py [config/grafana/dashboards/evo-llm.json] [prometheus-url]
Empty is normal for panels that need traffic (tok/s while idle); an ERROR never is."""
import json, sys, urllib.parse, urllib.request

path = sys.argv[1] if len(sys.argv) > 1 else "config/grafana/dashboards/evo-llm.json"
prom = sys.argv[2] if len(sys.argv) > 2 else "http://127.0.0.1:9091"
d = json.load(open(path))
subs = {"$model": ".*", "$__range_s": "21600", "$__range": "6h", "$__interval": "5m", "$__rate_interval": "5m"}


def sub(e):
    for k in sorted(subs, key=len, reverse=True):
        e = e.replace(k, subs[k])
    return e


qs = [(p["title"], t["expr"]) for p in d["panels"] for t in p.get("targets", [])]
qs += [("annotation: " + a["name"], a["expr"]) for a in d.get("annotations", {}).get("list", []) if "expr" in a]
bad = empty = 0
for title, expr in qs:
    url = prom + "/api/v1/query?" + urllib.parse.urlencode({"query": sub(expr)})
    try:
        r = json.load(urllib.request.urlopen(url, timeout=60))
    except Exception as e:
        body = getattr(e, "read", lambda: b"")().decode()[:200]
        r = {"status": "error", "error": f"{e} {body}"}
    if r.get("status") != "success":
        bad += 1
        print(f"ERROR  {title}: {r.get('error')}\n       {sub(expr)[:200]}")
    elif not r["data"]["result"]:
        empty += 1
        print(f"empty  {title}")
print(f"{len(qs)} queries: {len(qs) - bad - empty} with data, {empty} empty, {bad} errors")
sys.exit(1 if bad else 0)
