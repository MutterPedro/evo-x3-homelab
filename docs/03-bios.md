# 03 · BIOS settings

Enter the BIOS by pressing **`Del`** (or `Esc`) repeatedly right after power-on. `F7` usually opens the one-time boot menu.


## Must change (exact paths, verified on BIOS EVO-X3_V1.01)

| Setting | Path | Factory | Set to | Why |
|---|---|---|---|---|
| **iGPU Configuration** | Advanced → GFX Configuration | `Auto` (= 64 GB carve-out) | **`UMA_SPECIFIED`** | Unlocks the size option below |
| **UMA Frame buffer Size** | Advanced → GFX Configuration (appears after the above) | – | **smallest offered (512M if listed, else 1G)** | The GPU then borrows RAM dynamically (GTT, up to 120 GB). `evo doctor` flags it if wrong |
| **Auto Power On** | Advanced (top of the page) | `Power Off` | **`Power On`** | The server comes back by itself after a power cut |
| **Power Mode Select** (TDP) | Main (bottom of the page) | | **`Performance`** | 140 W ceiling for long LLM runs and games; idle draw stays low |
| Power Mode Select (**fans**) | Advanced → Hardware Monitor | `Automatic Mode` | **`Automatic Mode`** (keep) | Despite the same name, this is the *fan* mode: `Automatic` or `Manual PWM`. Automatic stops the fans at idle (silent server) and ramps them up under load |
| Boot order | Boot | | USB first for the install, then the Bazzite entry | |

Leave *Wake on lan*, *USB Boot* and *Trusted Computing* as they are.

**Fans:** *Advanced → Hardware Monitor* shows temperatures, two fan speeds (0 RPM at idle) and the fan mode. `Automatic Mode` is the vendor curve; `Manual PWM Mode` exposes a fixed/custom duty instead. Start with Automatic. Only try Manual PWM if temperatures under sustained LLM load go above ~90 °C (watch Grafana), and photograph its options so they can be documented here.

## Recommended

| Setting | Set to | Why |
|---|---|---|
| Fast Boot | Disabled | More reliable USB booting and a usable BIOS hotkey window |
| Secure Boot | **Leave disabled** (factory state) | Bazzite supports Secure Boot, but it needs a key-enrolment step (MOK) after install. Turn it on later if you want; see [10-operations](10-operations.md) |
| CSM / Legacy boot | Disabled (UEFI only) | |
| SVM (AMD-V virtualisation) | Enabled | Needed for Waydroid / VMs, harmless otherwise |
| IOMMU | Leave on (Auto) in BIOS | Linux handles it via `amd_iommu=off` (see [00-hardware](00-hardware.md)) |
| Wake on LAN | Irrelevant on Wi-Fi | Only works on the wired port |

## How power control works on Linux (and why the BIOS mode matters)

Linux has two levers:

1. **TuneD profiles** (`balanced-bazzite`, `throughput-performance-bazzite`, `powersave-bazzite`). They set CPU frequency policy and energy hints. `evo mode` switches them.
2. **ACPI platform profile** (`/sys/firmware/acpi/platform_profile`). On machines where the firmware exposes it (via AMD PMF), changing the profile **changes the actual TDP**. TuneD and `evo` drive it automatically when present.

After installing, run `cat /sys/firmware/acpi/platform_profile_choices`.

- If it lists `low-power balanced performance`, `evo mode quiet/server/game` really changes the power limit (roughly 54/85/140 W).
- If the file doesn't exist, **the BIOS power mode is the only TDP control**, and `evo mode` only changes CPU policy. Keep the BIOS on *Performance* so games and big models get full power; idle draw is unaffected.

Please report which case you have. The repo can then document it properly or add a `ryzenadj` fallback.

➡ Next: [04-install-bazzite](04-install-bazzite.md)
