# 04b · Installing without a USB stick (from a partition on the internal drive)

Used on 31 Oct 2026, when both available USB sticks turned out to be fake-capacity (Rufus bad-blocks test: a contiguous run of "corruption errors" right at the start of the stick means it is counterfeit, and the stick is useless for an 8.4 GB image). This works with Windows only, no extra hardware. Expect about an hour.

## How it works

The Bazzite live ISO (`bazzite-stable-live-amd64.iso`, 8.42 GB) boots like this:

```
EFI/fedora/shimx64.efi -> grubx64.efi -> grub.cfg
grub.cfg: search -l 'Bazzite-Live' ; linux /images/pxeboot/vmlinuz root=live:CDLABEL=Bazzite-Live rd.live.image
LiveOS/squashfs.img  (8.0 GB, too big for FAT32)
```

So the ISO is written **byte-for-byte onto its own partition** (which then *is* an ISO9660 volume labelled `Bazzite-Live`), and a small FAT32 partition `BZBOOT` holds the EFI boot files. A firmware boot entry points at `BZBOOT\EFI\fedora\shimx64.efi`.

## Steps (Windows, admin Terminal)

1. Download the ISO (bazzite.gg → Desktop → AMD → KDE) to `Downloads`.
2. Optional, read-only: `tools/windows/inspect-bazzite-iso.ps1` prints the ISO's file list, its `grub.cfg` and the disk layout, so you can check the layout still matches.
3. `tools/windows/make-bazzite-installer-partition.ps1`. It asks `YES` before each change:
   shrinks C: by 10 GB → creates `BZBOOT` (1 GB FAT32) + ISO partition (~9 GB) → writes the ISO and **verifies SHA-256** → copies boot files → adds the firmware entry. Use `-Undo` to revert everything.
   - If step 4 hangs while mounting the ISO, press Ctrl+C and run `tools/windows/finish-bazzite-installer-partition.ps1`, which runs only steps 4 and 5.

## Boot and install

1. BIOS: **Fast Boot → Disabled** (otherwise F7 never appears). Then *Save & Exit → Boot Override*, or Boot → *UEFI NVME Drive BBS Priorities* → pick **Fedora (Lexar…)**. The firmware names the entry after `EFI\fedora`.
2. At the GRUB menu press `e` on **Launch Bazzite Installer** and append ` rd.live.ram=1` to the `linux` line, then Ctrl+X. The 8 GB image is copied to RAM (about 30 s).
3. The installer still hides the whole NVMe ("No disks available"), because the live media lives on it. In the live session's Konsole:
   ```bash
   sudo pkill -f anaconda; sleep 3
   losetup -l | grep -i squash          # must show /run/initramfs/squashed.img (running from RAM)
   sudo umount -l /run/initramfs/live; sudo rm -f /run/initramfs/livedev
   findmnt /run/initramfs/live || echo RELEASED
   liveinst
   ```
   If the disk is still hidden: `sudo pkill -f anaconda; sleep 3; sudo wipefs -a /dev/nvme0n1p6 && liveinst` (p6 = the ISO partition; check with `lsblk -f`).
4. Installer: Lexar 4 TB → **Use entire disk**, no encryption. This also deletes Windows and the temporary `BZBOOT` and ISO partitions, so nothing needs cleaning up.
5. After the first boot, the old "Fedora" firmware entries pointing at `BZBOOT` are dead. Remove them with `sudo efibootmgr` (list), then `sudo efibootmgr -b XXXX -B`.

Lesson learned: **buy a branded USB stick** (SanDisk, Kingston, Samsung) from a real store, and keep it as the rebuild stick.
