# 03 · BIOS settings

Enter the BIOS by pressing **`Del`** (or `Esc`) repeatedly right after power-on. `F7` usually opens the one-time boot menu.

> The EVO-X3 BIOS is an AMI Aptio build with GMKtec's own menus, and menu names move between versions. If a setting isn't where this says, look under *Advanced*, *Chipset* or *Power*. **Take phone photos of every menu the first time**, so the repo can be updated with exact paths.

## Must change

| Setting | Typical location | Set to | Why |
|---|---|---|---|
| **UMA Frame Buffer Size** (also "iGPU Memory", "VRAM Size", "GFX Configuration → UMA") | Advanced → *GFX Configuration* / *Chipset* | **the minimum (512M, or 1G if 512M isn't offered)**. If there's a mode selector, pick `UMA_SPECIFIED` | The factory setting reserves **64 GB** that Linux can never get back. With the minimum, the GPU borrows RAM dynamically (GTT), up to 120 GB. `evo doctor` will flag it if this is wrong |
| **Restore on AC Power Loss** ("AC Back", "Power On after Power Failure") | Advanced → *Power* / *Chipset → South Bridge* | **Power On** (or *Last State*) | After a power cut the server comes back by itself |
| **Power mode / Performance mode** | Advanced → *Power Mode* / main page | **Performance** (140 W) | Idle draw stays ~11 W regardless. This only lifts the ceiling for long LLM runs and games. If the BIOS mode is the only real TDP control (see below), this is how you get "max when needed" |
| **Fan curve** ("Smart Fan") | Advanced → *Hardware Monitor* / *Smart Fan* | Custom curve, see below | The stock curve waits until 95 °C to reach full speed |
| **Boot order** | Boot | USB first for the install, then **Bazzite** (the installer creates the entry) | |

## Recommended

| Setting | Set to | Why |
|---|---|---|
| Fast Boot | Disabled | More reliable USB booting and a usable BIOS hotkey window |
| Secure Boot | **Leave disabled** (factory state) | Bazzite supports Secure Boot, but it needs a key-enrolment step (MOK) after install. Turn it on later if you want; see [10-operations](10-operations.md) |
| CSM / Legacy boot | Disabled (UEFI only) | |
| SVM (AMD-V virtualisation) | Enabled | Needed for Waydroid / VMs, harmless otherwise |
| IOMMU | Leave on (Auto) in BIOS | Linux handles it via `amd_iommu=off` (see [00-hardware](00-hardware.md)) |
| Wake on LAN | Irrelevant on Wi-Fi | Only works on the wired port |

## Suggested fan curve (quiet idle, cool under load)

| APU temp | Fan duty |
|---|---|
| ≤ 50 °C | 25–30 % (near-silent idle) |
| 65 °C | 45 % |
| 75 °C | 65 % |
| 85 °C | 100 % |

Under sustained LLM load the package sits around 70–80 °C at 115–140 W. This curve keeps it below the throttle point without screaming at idle. If you prefer silence over speed during inference, use `evo mode quiet` (lower OS power profile) instead of a lazier curve.

## How power control works on Linux (and why the BIOS mode matters)

Linux has two levers:

1. **TuneD profiles** (`balanced-bazzite`, `throughput-performance-bazzite`, `powersave-bazzite`). They set CPU frequency policy and energy hints. `evo mode` switches them.
2. **ACPI platform profile** (`/sys/firmware/acpi/platform_profile`). On machines where the firmware exposes it (via AMD PMF), changing the profile **changes the actual TDP**. TuneD and `evo` drive it automatically when present.

After installing, run `cat /sys/firmware/acpi/platform_profile_choices`.

- If it lists `low-power balanced performance`, `evo mode quiet/server/game` really changes the power limit (roughly 54/85/140 W).
- If the file doesn't exist, **the BIOS power mode is the only TDP control**, and `evo mode` only changes CPU policy. Keep the BIOS on *Performance* so games and big models get full power; idle draw is unaffected.

Please report which case you have. The repo can then document it properly or add a `ryzenadj` fallback.

➡ Next: [04-install-bazzite](04-install-bazzite.md)
