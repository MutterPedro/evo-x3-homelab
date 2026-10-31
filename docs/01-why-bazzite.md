# 01 · Why Bazzite (decision record)

**Decision:** Bazzite (KDE desktop edition, AMD image), single-boot, Windows removed.

## The requirements

1. A 24/7 LLM server for the LAN, and later for remote access
2. Steam gaming: single-player AAA, multiplayer **without** kernel anti-cheat, emulation
3. Easy switching between the two
4. Flexible sharing of the 128 GB between GPU and system
5. Reproducible from a git repo

## Options considered

| | Bazzite | Fedora KDE / CachyOS | Ubuntu 26.04 | Proxmox + VMs | Windows 11 |
|---|---|---|---|---|---|
| GPU memory for LLMs | ~120 GB GTT, dynamic | same | same | iGPU passthrough to a VM is fragile and loses the host display | **96 GB max, fixed in BIOS, reboot to change** |
| llama.cpp backends | Vulkan RADV + ROCm 10 via containers | same | ROCm native (AMD's reference distro) | – | Vulkan only, slower; ROCm on Windows lags |
| Gaming | **Steam Game Mode session, gamescope, HDR/VRR, FSR4 helpers, Sunshine built in** | DIY | DIY, older Mesa | poor | best compatibility (anti-cheat) |
| Kernel / Mesa | 7.2 kernel, Mesa 26.2 (Oct 2026), well above the 6.18.4 minimum for Strix Halo | rolling (CachyOS) / 6-month (Fedora) | has the Strix Halo KFD fixes (per AMD) | – | – |
| Robustness 24/7 | **Atomic updates, rollback by picking the previous version at boot, read-only /usr** | a bad update can break the box | stable but older | excellent | forced reboots, background bloat |
| Server software | podman + quadlets (systemd-native containers) | same, more freedom | docker/podman | excellent | WSL/Docker Desktop |
| Reproducibility | base image + this repo | repo + package list | repo + package list | good | poor |

## Why Bazzite wins here

- **None of your games need Windows.** Kernel anti-cheat titles (Valorant, Fortnite, CoD, BF6, some EA games) are the only thing Linux can't run, and you don't play them.
- **Memory flexibility is a Linux-only feature.** Windows needs a BIOS (or AMD Adrenalin) change plus a reboot for every re-split, and stops at 96 GB.
- **Gaming polish is built in.** Plain Fedora or Ubuntu would need gamescope sessions, Steam tweaks, Sunshine and controller support set up by hand.
- **Atomic updates suit an always-on server.** If an update misbehaves, pick the previous version in the boot menu and you're back in a minute.
- **Everything AI runs in containers**, so the immutable base doesn't get in the way. That's how the Strix Halo community runs it anyway (kyuz0's toolboxes are Fedora-based and documented on Bazzite).

## Trade-offs we accept

- Installing host packages is discouraged (`rpm-ostree install` works but slows updates). We use containers and Homebrew (`uv`, `restic`, `rclone`, `jq`) instead.
- Bazzite's updates come from Universal Blue, a community project. If you ever want a "boring" server OS, the same repo would work on Fedora Atomic (Kinoite) with small changes, since only `ujust` recipes and TuneD profile names differ.
- No anti-cheat games. If that changes, add a second NVMe with Windows in the free M.2 slot (dual-boot, separate disk, no shared bootloader).

## Rejected: dual-boot now

The second slot is empty, so dual-boot would be cheap. But you play no anti-cheat titles and you chose not to keep a Windows image, so it would add maintenance (two OSes to update) for no gain. You can revisit it any time by adding a disk; nothing here needs to change.
