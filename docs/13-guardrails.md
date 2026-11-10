# 13 · Guardrails: how this box protects itself

This machine is a 24/7 server and a desktop that share one 124 GiB pool of RAM. The GPU's memory is ordinary system RAM, so one greedy model can freeze everything. The rule for every failure we have seen or can foresee:

> **Prevent it in the config, catch it automatically if it happens anyway, make it diagnosable afterwards, and have a test that fails if someone reintroduces it.**

Each layer below catches what slips past the one before. None of them is optional "monitoring": they act without a human.

## The layers for memory

| # | Layer | What it does | Where |
|---|---|---|---|
| 1 | **Capacity router** | Only models whose declared sizes fit the pool (112 GiB) are loaded together; a new one evicts the cheapest others first. Prevents the problem. | `capacities.gpu` + `routing` in `config/llama-swap/config.yaml.tmpl` |
| 2 | **Regression test** | CI fails if a model's capacity is smaller than its weights, or a profile's resident set does not fit the pool. | `tests/render-test.sh` |
| 3 | **Memory guard** | Watches system-wide `MemAvailable` every second. Under 6 GiB for 3 s → unload all models; under 3 GiB or zram swap above 8 GiB → kill the model containers, 30 s cooldown. | `bin/evo-memguard`, `systemd/user/evo-memguard.service`, settings `EVO_MEMGUARD_*` in `evo.env` |
| 4 | **Hardware watchdog** | If the kernel stops responding for 60 s the board resets itself, so the server comes back unattended. Last resort; it loses whatever was in flight. | `system/systemd/system.conf.d/99-evo-watchdog.conf` |
| 5 | **`evo doctor`** | Reports whether the guard and watchdog are active, whether the pool leaves room below GTT, and how much RAM is free right now. | `evo doctor` → *Guardrails* |

### Why a custom guard and not systemd-oomd

`systemd-oomd` is enabled on Bazzite and watches cgroup memory *pressure* (80 % for 20 s). That misses this problem: GPU-pinned memory is charged to no cgroup (with Flash-Next loaded, `user@1000.service` is accounted ~50 GiB of the ~104 GiB in use), so `MemoryMax=` cannot limit it and the pressure it sees arrives too late. `MemAvailable` is the one number that does include pinned GPU memory, so the guard reads that. It needs no `sudo` and no reboot, and it is tested (below).

### Rules for sizing

- Size `capacities.gpu` from **`MemTotal - MemAvailable`** with the model loaded alone, after a long prompt, minus ~8 GiB for the desktop. **Never from GTT (`mem_info_gtt_used`) alone**: for Flash-Next it shows 70 GiB for a ~104 GiB footprint.
- Keep `EVO_GPU_POOL_GIB` at least 8 GiB below `EVO_GTT_GIB`, and the sum of what a profile keeps resident below the pool (`evo doctor` and CI check both).
- A new model gets a `models.tsv` row with its real GB size; CI then refuses a capacity below it.

### Testing the guard

Nothing here is trusted until it has been made to fire. Raise the thresholds above what is free, so the guard believes memory is low, and watch it act:

```bash
systemctl --user stop evo-memguard
set -a; source ~/.config/evo/secrets.env; set +a
# soft: load any model, then
EVO_MEMGUARD_SOFT_GIB=200 EVO_MEMGUARD_HARD_GIB=1 EVO_MEMGUARD_COOLDOWN=5 timeout 14 evo-memguard   # models unload
# hard: needs a victim, use a dummy container
podman run -d --rm --name evo-guardtest --entrypoint sleep "$EVO_IMG_VULKAN" 600
EVO_MEMGUARD_SOFT_GIB=200 EVO_MEMGUARD_HARD_GIB=200 EVO_MEMGUARD_COOLDOWN=5 timeout 4 evo-memguard   # container is killed
systemctl --user start evo-memguard
```

Both were run on this machine on 2026-11-10 (real Flash-Next unloaded, dummy container killed). Real events appear in `journalctl --user -u evo-memguard` and as a desktop notification.

### What it cannot do

If the machine stalls so hard that the guard itself is not scheduled, only layer 4 helps. The guard also cannot save a model that is half-way through a request: the client gets an error and has to retry.

## Applying the same pattern to other problems

Use this checklist when something new bites, or before it does:

1. **Prevent**: can a config value or a profile make the bad state impossible?
2. **Test**: can CI or `tests/render-test.sh` fail on the bad config?
3. **Guard**: can a small user service notice the bad state and do the safe thing (unload, stop, pause) without a human? Prefer `systemctl --user` units in `systemd/user/` and a script in `bin/`, with thresholds in `evo.env` and an env override so it can be tested by pretending the limit is lower.
4. **Diagnose**: is there a recipe in [10-operations](10-operations.md) that finds the cause from the journal and Prometheus?
5. **Surface**: does `evo doctor` show whether the guard is alive?

Candidates worth doing next, in rough order of likelihood on this box:

| Risk | Prevent | Guard (not built yet) |
|---|---|---|
| Disk full (`~/ai`, the btrfs root, Prometheus/Grafana data) | Prometheus retention is 30 d; `evo models du` | `evo-diskguard`: warn at 90 % used, pause model pulls and backups at 95 % |
| GPU hang or ROCm crash loop | Vulkan is the default backend | Alert when `llama-swap` restarts a model more than 3 times in 10 min; `evo mode game` as the manual brake |
| Thermal throttling or fan failure | BIOS fan mode Automatic | Grafana alert on package temp > 90 °C for 5 min → unload models |
| A service stuck "active" but not answering | `Restart=always` on every unit | Health checks in `evo doctor` plus a timer that restarts Open WebUI/llama-swap when `/health` fails 3 times |
| Wi-Fi drops (no Ethernet) | Wi-Fi power saving is off | Timer that reconnects and logs the outage; see the router/DHCP note in [05-bootstrap](05-bootstrap.md) |
| Backups silently stop | `evo-backup.timer` | `evo doctor` compares the latest snapshot's age to 36 h |

Tell me which of these you want next and they go through the same five steps.
