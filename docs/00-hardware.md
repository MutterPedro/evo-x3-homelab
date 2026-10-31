# 00 · The hardware

This machine was inventoried on **31 Oct 2026**, using Windows System Information on the factory install, and the findings were combined with reviews and community research.

## The exact unit

| | |
|---|---|
| Model | GMKtec **EVO-X3** (SKU `EVO-X3-001`), vertical CNC aluminium chassis, 3 fans, triple heat pipes |
| BIOS | AMI `EVO-X3_V1.01`, dated 2026-06-17, EC 1.01, UEFI. **Secure Boot was off** from the factory |
| APU | **AMD Ryzen AI Max+ 395** ("Strix Halo"): 16 Zen 5 cores / 32 threads, up to 5.1 GHz |
| GPU | **Radeon 8060S**, 40 RDNA 3.5 CUs (`gfx1151`, PCI `1002:1586`). Windows driver 32.0.22029 |
| NPU | XDNA 2, 50 TOPS (unused here; see the IOMMU note below) |
| Memory | **128 GB LPDDR5X-8000**, soldered. About 256 GB/s theoretical bandwidth; Level1Techs measured ~118 GB/s CPU-side |
| Factory split | **64 GB VRAM / 64 GB system** (Windows showed 63.6 GB usable) |
| Storage | **Lexar NQ790 4 TB** NVMe (PCIe 4.0). **Second M.2 2280 slot is empty** (PCIe 4.0 x4, up to 8 TB) |
| Factory partitions | 100 MB EFI · 30 GB recovery · 3.61 TB Windows · 1.2 GB WinRE |
| Network | Realtek **RTL8125 2.5 GbE** (unplugged at inventory time) · **MediaTek MT7925 Wi-Fi 7** (160 MHz max) · BT 5.4 |
| I/O | Rear: HDMI 2.1, USB4 40 Gbps (with video), USB-A 10 Gbps, 2.5 GbE, **OCuLink** (PCIe 4.0 x4, *not hot-plug*). Front: USB-A 5 Gbps, USB 2.0, audio |
| Display at inventory | 2560×1080 @ 60 Hz ultrawide over HDMI |
| Power | Silent 54 W · Balanced 85 W · **Performance 140 W peak** (~115 W sustained). Wall: ~11 W idle, ~147 W in AAA games |

## What the numbers mean for this project

**Memory bandwidth decides LLM speed.** At ~256 GB/s, token generation is roughly *bandwidth ÷ bytes read per token*. That's why **MoE models**, which read only their active parameters per token, are the sweet spot:

| Model class | Size in memory | Typical generation speed on Strix Halo |
|---|---|---|
| 3–4B-active MoE (Qwen3.6-35B-A3B, Gemma 4 26B-A4B) | 15–25 GB | 50–100 tok/s |
| 5–6B-active MoE (gpt-oss-120b, Qwen3.8 Flash-Next) | 65–95 GB | 25–55 tok/s (MTP helps a lot) |
| Dense 27–32B | 20–35 GB | 7–15 tok/s |
| 200B+ MoE at 2–3 bit (MiniMax, DeepSeek-V4-Flash) | 90–100 GB | 12–30 tok/s |

**Prompt processing (prefill) is the weak spot**: a 40k-token prompt can take one to two minutes on the biggest models. Coding agents that resend large contexts feel this. Prompt caching (`--cache-reuse`) and smaller coder models help.

**Unified memory.** The GPU has no memory of its own. Two mechanisms share the 128 GB:

- *Carve-out ("UMA frame buffer"/"VRAM")*: reserved by the BIOS at boot and invisible to the OS. Changing it needs a reboot into the BIOS. Windows can only use this, up to 96 GB.
- *GTT*: normal RAM the GPU driver borrows on demand. On Linux the limit is a kernel parameter (`ttm.pages_limit`), and RAM is only used while the GPU actually holds data.

AMD's own ROCm guidance is to **keep the carve-out tiny (512 MB) and raise the GTT limit**. This repo does that (120 GB by default). The result is that **the "split" between GPU and system adjusts itself**: a game takes 8–16 GB, a model takes 95 GB, and nothing has to be repartitioned.

**IOMMU.** Disabling it (`amd_iommu=off`) measurably speeds up inference (5–12% in community tests), but it disables the NPU and DMA protection for USB4/OCuLink devices. This repo **disables the IOMMU by default** (`EVO_DISABLE_IOMMU=true`); set it to `false` if you ever want the NPU.

## Known quirks (from reviews and forums)

- The default fan curve doesn't reach full speed until **95 °C** (Level1Techs). Set a curve in the BIOS ([03-bios](03-bios.md)).
- The BIOS has **no AMD CBS menu**, so TDP can't be raised beyond the vendor's Performance mode.
- **OCuLink is not hot-plug.** Power off before connecting a future eGPU dock.
- Only **one 2.5 GbE port**, and Wi-Fi 7 is capped at 160 MHz channels.
- The MT7925 Wi-Fi driver has had reconnect regressions in some kernels. This repo disables Wi-Fi power saving, and `evo doctor` checks it. **A cable is strongly recommended for a server** if you can run one later.

## Sources

- [Notebookcheck review (ETA Prime data)](https://notebookcheck.net/GMKtec-s-most-powerful-Mini-PC-tested-GMKtec-EVO-X3-is-more-than-simple-AI-PC.1362611.0.html) · [SteamOS on the EVO-X3](https://www.notebookcheck.net/GMKtec-EVO-X3-Mini-PC-and-SteamOS-prove-to-be-match-made-in-heaven.1364494.0.html)
- [StarryHope EVO-X3 spec sheet](https://www.starryhope.com/minipcs/models/gmktec-evo-x3/) (includes Level1Techs measurements)
- [AMD ROCm: Strix Halo system optimization](https://rocm.docs.amd.com/en/docs-7.2.0/how-to/system-optimization/strixhalo.html)
- [Strix Halo AI Toolboxes host guide](https://strix-halo-toolboxes.com/) · [kyuz0/amd-strix-halo-toolboxes](https://github.com/kyuz0/amd-strix-halo-toolboxes)
- [Strix Halo benchmarks (slb350)](https://slb350.github.io/strix-benchmarks/) · [llamaperf Strix Halo 128GB](https://llamaperf.com/gpu/strix-halo-128gb)
- [Level1Techs: ROCm only using half the memory](https://forum.level1techs.com/t/rocm-can-only-use-half-of-the-unified-memory-on-my-strix-halo/253152)
