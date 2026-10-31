# 05 · Bootstrap with this repo

```bash
git clone https://github.com/MutterPedro/evo-x3-homelab.git ~/evo-x3-homelab
cd ~/evo-x3-homelab
```

All settings live in **`~/.config/evo/evo.env`**, which is created from [`config/evo.env.example`](../config/evo.env.example) on the first run. Defaults are sensible; read through it once.

## Step 1: `./install.sh system` (sudo, then reboot)

| Action | Detail |
|---|---|
| Hostname | `evo-x3`, reachable as `evo-x3.local` (mDNS) |
| Kernel arguments | `ttm.pages_limit=31457280 ttm.page_pool_size=31457280 amdgpu.gttsize=122880` (GPU can borrow up to 120 GiB) and `amd_iommu=off`. Applied with `rpm-ostree kargs` as a new boot entry, so the previous one stays bootable |
| Groups | Adds you to `video` and `render` (copied from `/usr/lib/group` first, the Fedora Atomic quirk), so rootless containers can use `/dev/dri` and `/dev/kfd` even when nobody is logged in |
| No sleep | Masks `sleep/suspend/hibernate` targets |
| Wi-Fi | `wifi.powersave = 2` (off) for NetworkManager |
| Firewall | Opens 8080 (API), 3000 (chat) and 3001 (Grafana). SearXNG, Prometheus and node-exporter listen on localhost only |
| Linger | `loginctl enable-linger`, so your user services start at boot without a login |
| Watchdog | systemd pets the AMD hardware watchdog; a hung kernel reboots itself after 60 s |
| SSH / Tailscale | `sshd` and `tailscaled` enabled (Tailscale login happens in [08-remote-access](08-remote-access.md)) |

Then `systemctl reboot`.

## Step 2: `./install.sh user` (no sudo, safe to re-run; restarts the services, so loaded models reload)

| Action | Detail |
|---|---|
| Secrets | Generates `~/.config/evo/secrets.env` (mode 600): API key, Open WebUI secret, SearXNG secret, Grafana and restic passwords |
| Configs | Renders templates into `~/.config/evo/` (llama-swap, Open WebUI, Prometheus, Grafana, ComfyUI paths) |
| Tools | Homebrew: `uv` (for `hf` downloads), `restic`, `rclone`, `jq`. The latest **llama-swap** binary goes into `~/.local/bin` |
| Services | Rootless podman **quadlets** in `~/.config/containers/systemd/` (Open WebUI, SearXNG, Prometheus, node-exporter, Grafana) and the `llama-swap.service` user unit |
| Images | Pulls the Vulkan inference image and service images (~15 GB). ROCm and ComfyUI images are pulled on first use |
| Auto-update | `podman-auto-update.timer`: service containers update themselves daily |
| Launchers | *EVO: Game / Server / Quiet mode* in the app menu |

## Step 3: `./install.sh models` (~200 GB download)

Downloads the default set from Hugging Face into `~/ai/models/<repo>/`:

| Model | Size |
|---|---|
| Qwen3.8 Flash-Next UD-IQ4_XS + vision + MTP head | ~100 GB |
| gpt-oss-120b (MXFP4) | 65 GB |
| Qwen3.6 35B-A3B UD-Q4_K_XL + vision | 23 GB |
| Gemma 4 26B-A4B QAT + vision | 16 GB |
| Qwen3 Embedding 0.6B, Whisper large-v3-turbo | 2 GB |

On Wi-Fi this takes a while. It resumes if interrupted; just re-run it. A free Hugging Face token makes it faster: `export HF_TOKEN=hf_...` before running.

## Step 4: verify

```bash
evo doctor
```

Expect all green: GTT ~120 GiB, VRAM carve-out ≤ 1 GiB, groups, linger, services, models, GPU visible in a container, suspend disabled.

Then open `http://evo-x3.local:3000` and **create the first account, which becomes the admin**. Other people who sign up wait as *pending* until you approve them in *Admin Panel → Users*.

## Re-running and changing settings

- Change something in `~/.config/evo/evo.env` (e.g. `EVO_GTT_GIB`, ports, default profile), then:
  - kernel-level settings (GTT, IOMMU): `./install.sh system && systemctl reboot`
  - everything else: `./install.sh user`
- Edit a model or profile: change `config/llama-swap/config.yaml.tmpl` in the repo, then `./install.sh user`. llama-swap watches its config and reloads automatically.

➡ Next: [06-llm-server](06-llm-server.md)
