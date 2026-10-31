# 04 · Install Bazzite

About 20 minutes.

1. Plug in the installer USB, power on, press **`F7`** (boot menu) and choose the USB (UEFI) entry.
2. The live environment boots into the Anaconda installer.
   - **Language / keyboard:** your choice. Your Windows used *ENG-INTL*, so choose *English (US, intl., with dead keys)* if you type Portuguese accents that way. `ujust configure-us-intl-dead-keys` can fix it later.
   - **Installation destination:** select the **Lexar NQ790 4 TB** disk only. Choose **Automatic** storage and tick *"Free up space by removing or recycling existing partitions"* → **Delete all**. This removes Windows, WinRE and the GMKtec recovery partition.
     - Leave encryption **off**. A server that must come back by itself after a power cut can't stop at a LUKS passphrase prompt. If you want encryption, use TPM2 auto-unlock later (`ujust` / `systemd-cryptenroll`).
     - Bazzite uses **btrfs** with `/var` (where your home, models and containers live) on the same pool, so all 3.6 TB is available.
   - **Network:** connect to your Wi-Fi here. The connection is saved for the installed system.
   - **User:** create your account and tick *Make this user administrator* (sudo). Use a strong password, since SSH will be enabled.
3. Install, reboot and remove the USB.
4. On first boot the Bazzite **portal** (setup wizard) offers optional apps. Skip anything you don't need; the installer script handles the server parts.
5. Let Bazzite finish its first update: *System Settings → Software Update*, or `ujust update` in a terminal, then reboot.

### Quick sanity checks (Konsole)

```bash
rpm-ostree status          # shows the booted Bazzite image (stable, Fedora 44)
uname -r                   # 7.x kernel
cat /sys/class/drm/card*/device/mem_info_vram_total 2>/dev/null | head -1  # ~536870912 if UMA=512M
nmcli device               # Wi-Fi connected
```

If `mem_info_vram_total` shows ~68 719 476 736 (64 GiB), the BIOS UMA setting didn't stick. Go back to [03-bios](03-bios.md).

➡ Next: [05-bootstrap](05-bootstrap.md)
