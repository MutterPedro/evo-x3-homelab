# 10 · Operations: updates, rollback, troubleshooting, rebuild

## Updating

| What | How | When |
|---|---|---|
| **Bazzite (OS, kernel, Mesa)** | Downloads automatically in the background and applies on the next reboot. Force it with `ujust update` | Reboot weekly-ish, e.g. `systemctl reboot` at a quiet hour |
| **Service containers** (Open WebUI, SearXNG, Grafana…) | `podman-auto-update.timer`, daily | automatic |
| **Inference images, llama-swap, configs** | `evo update` | when you want newer llama.cpp (new model support, speedups) |
| **This repo** | `git pull` (also done by `evo update`) | |

## Rolling back

- **The OS update broke something:** reboot, and in the boot menu pick the **previous deployment** (the second entry). Once you're happy, `sudo rpm-ostree rollback` makes it the default. You can also pin a known-good deployment: `sudo ostree admin pin 0`.
- **Rebase to a specific older image:** `bazzite-rollback-helper rebase` (lists the images from the last 90 days).
- **A container update broke something:** `podman auto-update --rollback` happens automatically if the new container fails to start. For inference images, pin a tag in `evo.env` (e.g. `EVO_IMG_VULKAN=docker.io/kyuz0/amd-strix-halo-toolboxes:vulkan-radv-<date>`) and run `./install.sh user`.
- **A config change broke llama-swap:** `git -C ~/evo-x3-homelab diff` / `git checkout`, then `./install.sh user`.

## Troubleshooting

Start with **`evo doctor`**. It checks kernel args, GTT size, BIOS carve-out, groups, linger, services, models, GPU visibility in containers, Wi-Fi power saving and suspend.

| Symptom | Likely cause → fix |
|---|---|
| Model fails to load, "out of memory", or GTT shows ~64 GB | Kernel args not applied (`cat /proc/cmdline`), or the BIOS UMA is still 64 GB. Run `./install.sh system`, reboot, check [03-bios](03-bios.md) |
| Model loads but is very slow, or the system freezes during load | Model + context exceeds GTT and the system is swapping. Lower `-c`, use a smaller quant, or check that nothing else holds GPU memory (`evo status`) |
| `evo-<model>` container exits immediately | `journalctl --user -u llama-swap -n 200`. Common causes: model file missing (`evo models pull <id>`), a flag the current image doesn't know (pin an older image or drop the flag), no `/dev/kfd` access for ROCm (group membership, reboot) |
| ROCm model crashes, Vulkan works | Known ROCm/firmware regressions (e.g. `linux-firmware-20251125` on Strix Halo). Switch that model to `${vulkan}`, check [kyuz0's firmware notes](https://github.com/kyuz0/amd-strix-halo-toolboxes/blob/main/docs/troubleshooting-firmware.md) |
| Open WebUI shows no models | Is llama-swap up (`evo status`)? Is `OPENAI_API_KEYS` in `~/.config/evo/open-webui.env` the same as `evo secret api-key`? Open WebUI keeps connections in its DB after first start, so fix it in *Admin → Settings → Connections* |
| API returns 503 "paused" | You're in game mode. Run `evo mode server` |
| Web search returns nothing | `systemctl --user status searxng`. Some engines rate-limit; adjust engines in `~/ai/searxng/settings.yml` and restart |
| Wi-Fi drops / box unreachable | `nmcli`, `journalctl -b -u NetworkManager`. Try `sudo modprobe -r mt7925e && sudo modprobe mt7925e`. Consider a cable; Tailscale still reaches it if the LAN IP changed |
| Services didn't start after reboot | `loginctl show-user $USER -p Linger` must be `yes`; `systemctl --user --failed` |
| Fans loud | `evo mode quiet` overnight or for long jobs; BIOS fan mode is under Advanced → Hardware Monitor |
| A game stutters | `evo mode game` (or `evo run -- %command%`), check `evo status` shows no models loaded |

Logs: `evo logs` (llama-swap) · `evo logs open-webui` · `journalctl --user -u <service>` · `journalctl -b -p err` (system).

## Rebuild from scratch (the whole point of this repo)

1. BIOS settings ([03-bios](03-bios.md)), about 5 min
2. Install Bazzite ([04-install-bazzite](04-install-bazzite.md)), about 20 min
3. ```bash
   git clone https://github.com/MutterPedro/evo-x3-homelab.git ~/evo-x3-homelab && cd ~/evo-x3-homelab
   ./install.sh system && systemctl reboot
   ```
4. Restore `~/.config/evo` from backup if you have one ([09](09-monitoring-and-backups.md#restore-new-install-or-disaster)); otherwise new secrets are generated
5. `./install.sh user && ./install.sh models && evo doctor`
6. `sudo tailscale up --ssh`, `ujust setup-sunshine`, Steam login

## Secure Boot (optional, later)

Bazzite signs its kernel and modules with the Universal Blue key. To turn Secure Boot on, first enrol that key with `mokutil` (the exact command and one-time password are in Bazzite's docs: https://docs.bazzite.gg, search "Secure Boot"). Reboot, choose *Enroll MOK* in the blue MOK manager, then enable Secure Boot in the BIOS. If you enable Secure Boot without enrolling the key, the machine won't boot Bazzite until you disable it again.

## Uninstall the homelab parts

```bash
systemctl --user disable --now llama-swap evo-backup.timer
systemctl --user stop open-webui searxng grafana prometheus node-exporter
rm -f ~/.config/containers/systemd/{open-webui,searxng,grafana,prometheus,node-exporter}.container \
      ~/.config/systemd/user/{llama-swap.service,evo-backup.*} ~/.local/bin/{evo,evo-notify,llama-swap}
systemctl --user daemon-reload
# data: ~/ai (models, chats), ~/.config/evo (settings, secrets) -- delete if you want
# kernel args: sudo rpm-ostree kargs --delete-if-present=amd_iommu=off ... (see install.sh)
```
