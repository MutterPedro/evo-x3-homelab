# 02 · Before you wipe Windows

About 20 minutes in Windows.

## 1. Note what you might need later

- **Windows license:** it's an OEM key embedded in the BIOS (MSDM table). If you ever reinstall Windows 11 Pro on this box, it activates automatically. There's nothing to save.
- **BIOS version:** `EVO-X3_V1.01` (2026-06-17). Check GMKtec's support/download page for a newer EVO-X3 BIOS *before* wiping, because BIOS updaters for this vendor are usually Windows `.exe` or EFI-shell tools. Update only if the release notes mention stability, memory or fan fixes.
- **Drivers:** none are needed on Linux. Everything (GPU, Wi-Fi 7, 2.5 GbE, audio, Bluetooth) is in the kernel.

## 2. Reserve an IP address on your router

The box will be on **Wi-Fi**, and every device will reach it by address, so give it a fixed one:

1. In Windows: *Settings → Network & internet → Wi-Fi → Hardware properties*. Note the **physical (MAC) address**.
   - On Linux, NetworkManager can randomise the MAC per network. Bazzite uses a *stable* MAC per network by default, but to be safe re-check the MAC after install with `nmcli -f GENERAL.HWADDR device show wlp*` and use that one.
2. In the router's admin page: *DHCP → Address reservation*. Bind that MAC to an address outside the dynamic range (e.g. `192.168.1.50`).

For reference, the wired port's MAC is `00:84:97:1A:9C:15`, in case you ever plug in a cable.

## 3. Make the Bazzite installer USB

You need a USB stick of **8 GB or more that can be erased**. (The 32 GB stick that was plugged in during the inventory is yours; only use it if nothing on it matters.)

1. Go to **https://bazzite.gg** → *Get Bazzite*. Choose:
   - Device: **Desktop / Mini PC**
   - GPU: **AMD**
   - Desktop: **KDE Plasma**
   - Steam Gaming Mode on boot: **No** (Desktop edition). You can still launch Game Mode from the desktop, and switch the default later.
2. Download the ISO (~8 GB) and verify its checksum if offered.
3. Write it with **Fedora Media Writer** (recommended by Bazzite) or **Rufus in DD mode**. *Ventoy is not supported* for Bazzite installs.

## 4. Optional: keep the factory recovery partition?

There's a 30 GB GMKtec recovery partition. Since you chose not to keep a Windows image, the installer will erase the whole disk, including it. If you change your mind, now is the moment to image the disk with Rescuezilla onto an external drive.

➡ Next: [03-bios](03-bios.md)
