# 09 · Monitoring and backups

## Dashboards

| Where | What |
|---|---|
| **Grafana** `http://evo-x3.local:3001` (user `admin`, password `evo secret grafana`) | Two dashboards in the *EVO-X3* folder: **EVO-X3 LLM** (tokens/s, model comparison, money saved, machine health) and **EVO-X3** (hardware overview). 30 days of history |
| **llama-swap UI** `http://evo-x3.local:8080/ui` (any user, API key as password) | Loaded models, live logs per model, **tokens/s per request**, request inspector, playground, load/unload buttons, profile switcher |
| `evo status` | One-screen terminal summary |
| `nvtop` | Live GPU view in a terminal (preinstalled on Bazzite) |
| Cockpit (optional) | `ujust cockpit enable`, then `https://evo-x3.local:9090`: services, logs, terminal and updates from a browser |

How it's wired: node-exporter (with the `drm` and `hwmon` collectors), llama-swap's `/metrics` and `evo-exporter` are scraped by Prometheus every 15 s. Grafana provisions the data source and dashboard from `config/grafana/`, so it's reproducible. Dashboards you edit in the UI are saved in Grafana's database (`~/ai/grafana`, included in backups). Export them to the repo if you want them versioned.

### The "EVO-X3 LLM" dashboard

| Row | What you see | Source |
|---|---|---|
| **At a glance** | Generation and prompt tok/s right now, models loaded, running requests, free RAM (coloured against the memory guard's limits), evo mode and profile | llama-server metrics via `evo-exporter` |
| **LLM speed** | tok/s per model over time, prompt speed, speculative-decoding (MTP) acceptance, prompt-cache hit ratio, running/waiting requests, tokens per hour, longest context | same |
| **Model comparison** | Bar charts of average speed over the chosen time range, a **controlled benchmark** (same 10k-token prompt on every model) and a table with one row per model | usage metrics + `evo bench --all` |
| **Money saved** | Cloud cost avoided, electricity used, **net saved** and lifetime cloud value, in US$ and R$; cost per day by model; electricity vs cloud price per 1M output tokens | `evo-exporter` + `node-exporter` |
| **Machine health** | Free RAM and swap with the guard thresholds, memory pressure, power, temperatures, clocks, last backup age, uptime, memory-guard interventions | node-exporter + `evo-exporter` |

Vertical markers on every chart show models loading and unloading, reboots and memory-guard interventions. The *Models* dropdown at the top filters the charts. The queries are checked with `python3 tools/grafana/check_queries.py`.

**Live usage vs benchmark.** Live tok/s depends on the prompt and context length (a short chat reads faster than a 100k-token coding session), so a model that mostly gets hard prompts looks slower. For a fair comparison refresh the benchmark (`evo bench --all`, about 5 minutes; it unloads everything first, so run it when nobody is chatting). Not available: time to first token or latency percentiles, because llama-server does not export them (llama-swap's UI has per-request timings).

**How the money-saved estimate works**, so you know how far to trust it:
- *Cloud cost avoided* = tokens served x the price of a cloud model you pick as the equivalent. Prompt tokens that were served from the cache are not counted (cloud caching is cheaper, so counting them would flatter the local box). The mapping and prices are in `config/cloud-prices.tsv` (Anthropic list prices checked 2026-11-03: Flash-Next compared with Claude Sonnet 5.5, the smaller models with Claude Haiku 5.5). Which cloud model is "equivalent" is a judgement call: edit the file and run `./install.sh user`, and update the prices when they change.
- *Electricity* = (APU power sensor + `EVO_POWER_OVERHEAD_W`) x hours x `EVO_KWH_PRICE_BRL`, converted with `EVO_USD_BRL` (all in `evo.env`; the defaults are placeholders: **set your real tariff and exchange rate**). It counts the machine's idle hours too, so the net figure is conservative.
- *Net saved* = avoided cost minus electricity. It can be negative: with a cheap cloud model like Haiku, light usage does not pay for a machine that is on 24/7. The "cost per 1M generated tokens" chart shows where the local marginal cost sits against each cloud price.
- Not counted: the hardware's purchase price, your time, and what the cloud models do better. It only prices tokens.
- Tokens are read every half second while a model is loaded, so real usage is counted even when the model is unloaded later. A request followed by an unload within a fraction of a second (as `evo bench --all` does) can be missed, which is fine: benchmark traffic is not usage.
- Lifetime totals live in `~/.local/state/evo/exporter.json` (backed up with the rest of the state), so they survive reboots and model reloads.

### How the data gets there

`evo-exporter` (a user service on `127.0.0.1:9102`) asks llama-swap which models are *running*, scrapes only those and re-labels their metrics with the model name; it can never wake an unloaded model. It also exports the evo mode and profile, the last backup, memory-guard events, benchmark results and the prices above. Dashboards are generated by `tools/grafana/build_llm_dashboard.py`: change the script, run it, commit both files.

What to watch:
- **GTT used close to the limit** with swapping starting means a model set doesn't fit. Lower `capacities.gpu` sums, or reduce context.
- **Hottest sensor > 90 °C** under sustained load means it is running hot: try `evo mode quiet` for long jobs, or the BIOS *Manual PWM* fan mode ([03-bios](03-bios.md)).
- **Package power stuck at ~85 W in game mode** means the BIOS is not in Performance mode, or there's no platform profile ([03-bios](03-bios.md#how-power-control-works-on-linux-and-why-the-bios-mode-matters)).

## Backups: restic → Google Drive (encrypted)

**What's backed up nightly (04:30):** `~/.config/evo` (configs and secrets), Open WebUI data (users, chats, uploaded documents, settings), Grafana data, ComfyUI outputs and `evo` state. Open WebUI stops for a few seconds so its database is consistent.

**What's not backed up:** models (re-download with `./install.sh models`), container images, and the OS (it's an image; this repo rebuilds the rest).

### One-time setup

```bash
# 1. connect Google Drive (opens a browser for Google login)
rclone config
#   n) New remote → name: gdrive → storage: drive → client_id/secret: use your own (see below)
#   scope: 1 (full) or 3 (drive.file) → auto config: y → login in the browser
rclone lsd gdrive:            # should list your Drive folders

# 2. create the encrypted restic repository at gdrive:evo-x3-backups
evo backup init

# 3. first backup now, then check
evo backup run
evo backup list
```

**Save the restic password somewhere outside this machine** (password manager): `evo secret restic`. Without it the backup can't be decrypted. `~/.config/evo/secrets.env` is inside the backup, which is no help if the disk dies.

Retention: 7 daily, 4 weekly, 6 monthly (`EVO_BACKUP_KEEP_*` in `evo.env`). Status: `systemctl --user list-timers evo-backup.timer` and `journalctl --user -u evo-backup`.

> **Use your own Google client_id.** rclone's built-in shared client_id is being retired during 2026 (`rclone lsd` prints a NOTICE about it), after which the remote stops working. Create one in the [Google Cloud console](https://rclone.org/drive/#making-your-own-client-id) (OAuth client, type Desktop app) and set `client_id` / `client_secret` with `rclone config update gdrive client_id=… client_secret=…`, then re-authorize with `rclone config reconnect gdrive:`.
>
> **Save the restic password somewhere off this machine** (`evo secret restic`, e.g. in your password manager). Without it the encrypted repository on Drive is unrecoverable, and it lives only in `~/.config/evo/secrets.env`, which is not in the backup.
>
> Verified on this box: init, backup (~50 MiB: config, Open WebUI, Grafana, state) and a full restore of the Open WebUI database all work; a daily timer runs the backup at ~04:30.

### Restore (new install or disaster)

```bash
# after reinstalling Bazzite and running ./install.sh system + reboot:
rclone config                 # re-create the gdrive remote
export RESTIC_REPOSITORY=rclone:gdrive:evo-x3-backups RESTIC_PASSWORD='<saved password>'
restic restore latest --target ~/evo-restore
mkdir -p ~/.config/evo && cp -a ~/evo-restore/var/home/$USER/.config/evo/. ~/.config/evo/
cd ~/evo-x3-homelab && ./install.sh user            # uses the restored secrets/settings
systemctl --user stop open-webui grafana
cp -a ~/evo-restore/var/home/$USER/ai/open-webui/. ~/ai/open-webui/
cp -a ~/evo-restore/var/home/$USER/ai/grafana/.    ~/ai/grafana/
systemctl --user start open-webui grafana
./install.sh models
```

(restic stores absolute paths. On Bazzite, home is `/var/home/<user>`.)
