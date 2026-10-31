# 09 · Monitoring and backups

## Dashboards

| Where | What |
|---|---|
| **Grafana** `http://evo-x3.local:3001` (user `admin`, password `evo secret grafana`) | The *EVO-X3* dashboard: GPU memory (GTT) vs RAM, GPU busy %, APU power, all temperatures, CPU, network, disk. 30 days of history |
| **llama-swap UI** `http://evo-x3.local:8080/ui` (any user, API key as password) | Loaded models, live logs per model, **tokens/s per request**, request inspector, playground, load/unload buttons, profile switcher |
| `evo status` | One-screen terminal summary |
| `nvtop` | Live GPU view in a terminal (preinstalled on Bazzite) |
| Cockpit (optional) | `ujust cockpit enable`, then `https://evo-x3.local:9090`: services, logs, terminal and updates from a browser |

How it's wired: node-exporter (with the `drm` and `hwmon` collectors) and llama-swap's `/metrics` are scraped by Prometheus every 15 s. Grafana provisions the data source and dashboard from `config/grafana/`, so it's reproducible. Dashboards you edit in the UI are saved in Grafana's database (`~/ai/grafana`, included in backups). Export them to the repo if you want them versioned.

What to watch:
- **GTT used close to the limit** with swapping starting means a model set doesn't fit. Lower `capacities.gpu` sums, or reduce context.
- **Hottest sensor > 90 °C** under sustained load means the fan curve is too lazy ([03-bios](03-bios.md)).
- **Package power stuck at ~85 W in game mode** means the BIOS is not in Performance mode, or there's no platform profile ([03-bios](03-bios.md#how-power-control-works-on-linux-and-why-the-bios-mode-matters)).

## Backups: restic → Google Drive (encrypted)

**What's backed up nightly (04:30):** `~/.config/evo` (configs and secrets), Open WebUI data (users, chats, uploaded documents, settings), Grafana data, ComfyUI outputs and `evo` state. Open WebUI stops for a few seconds so its database is consistent.

**What's not backed up:** models (re-download with `./install.sh models`), container images, and the OS (it's an image; this repo rebuilds the rest).

### One-time setup

```bash
# 1. connect Google Drive (opens a browser for Google login)
rclone config
#   n) New remote → name: gdrive → storage: drive → leave client_id/secret empty
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
