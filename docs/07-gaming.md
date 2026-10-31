# 07 · Gaming

Steam is preinstalled on Bazzite. Sign in, and in *Steam → Settings → Compatibility* enable **Steam Play for all titles** (Proton). Check [ProtonDB](https://www.protondb.com) for any game that misbehaves.

## Switching between serving and gaming

The LLMs can hold up to ~100 GB of memory and keep the GPU busy, and a game wants the GPU to itself. There are three ways to switch, from most to least automatic:

1. **Per game, automatic.** Set Steam → game → *Properties → Launch options* to:
   ```
   evo run -- %command%
   ```
   Starting the game pauses llama-swap (unloads all models; API callers get "paused" until resume) and sets the performance power profile. Quitting the game restores whichever mode you were in before. To use it with other launch options, chain them: `evo run -- gamemoderun %command%`.
2. **One click.** Use the app-menu launchers **EVO: Game mode** / **EVO: Server mode**, or pin them to the taskbar.
3. **Terminal / SSH from your phone.** Run `evo mode game` or `evo mode server`.

> Why pause instead of keeping a small model loaded? Bandwidth. Any inference while you play steals memory bandwidth from the GPU and shows up as stutter. If you want the household chat to keep working during gaming sessions, use `evo profile multi` and skip `evo run`. Gemma 4 alone uses ~18 GB and little bandwidth when idle.

## Memory: why games "just work" with a 512 MB carve-out

With the BIOS frame buffer at 512 MB, the GPU gets almost all its memory from GTT. Mesa's RADV driver reports that pool to games (as on the Steam Deck), so they see plenty of "VRAM". If a specific Windows game under Proton refuses to start or picks low textures because it reads the dedicated-VRAM number:

- try a newer Proton (GE / Proton-EM via `ujust` → ProtonPlus), or
- as a last resort, raise the BIOS UMA to 4–8 GB (that memory is lost to LLMs, ~4–8 GB).

## Upscaling and frame generation

- **FSR 3.1 / FSR 4:** RDNA 3.5 has no FP8 hardware, but Proton forks can run FSR 4 in an FP8-emulation path: `ujust global-fsr4-rdna3 enable` (Proton GE/EM only). Compare quality and fps against FSR 3.1 per game.
- **Frame generation:** `ujust` has a framegen helper (`87-bazzite-framegen`), and Lossless Scaling's Linux layer also works.
- **Expectations:** reviews of this exact box on SteamOS show ~80 fps at 1440p high with FSR Quality in Cyberpunk 2077, Horizon Zero Dawn Remastered and Spider-Man 2. At your ultrawide 2560×1080 the pixel count is lower (~75% of 1440p), so expect a bit more.

## Living-room TV

- **Steam Gaming Mode** (the Steam Deck UI) is in the session picker at login, or under *Return to Gaming Mode* on the desktop. To make the machine boot into Game Mode by default: `ujust set-default-game-mode` (and `ujust set-default-desktop` to go back).
- **HDMI 2.1 / 4K120 / VRR on TVs:** AMD's open driver limits HDMI 2.1 features. Bazzite offers `ujust configure-amd-hdmi21` (sets `amdgpu.dcfeaturemask=0x402`), which can unlock FreeSync over HDMI but may flicker on some displays. Try it, and revert if your TV misbehaves. **USB4 → DisplayPort** gives full bandwidth if your TV or monitor has DP.
- Controllers: Xbox, PlayStation and 8BitDo pads work over Bluetooth or USB out of the box.

## Streaming to other screens (Sunshine → Moonlight)

```bash
ujust setup-sunshine        # choose: enable-flatpak (or enable-brew)
```

1. Open `https://evo-x3.local:47990`, create the Sunshine admin user, and pair with **Moonlight** on the TV / phone / laptop (enter the PIN shown by Moonlight).
2. On Wi-Fi, set Moonlight to 1080p60, 20–40 Mbps, and H.265/AV1 (the 8060S encodes AV1). Wired TVs can do 4K.
3. For headless streaming (no monitor plugged in), `ujust setup-sunshine virtual-monitor` creates a virtual display.
4. Remote play over Tailscale works the same; use the box's Tailscale IP in Moonlight.

Sunshine's ports are opened by the `ujust` recipe. Pair only devices you trust.

## Emulation

Bazzite offers **EmuDeck** / **RetroDECK** installers (see `ujust --choose`, apps section, or the Bazaar app store). The 8060S handles everything up to Switch/PS3/Wii U comfortably at 2–3× resolution.
