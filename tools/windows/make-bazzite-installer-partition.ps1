#Requires -RunAsAdministrator
<#
  make-bazzite-installer-partition.ps1
  Puts the Bazzite installer on the internal NVMe so it can be booted without a USB stick.

    1. Shrinks C: by 10 GB (Windows keeps working; nothing is deleted)
    2. Creates BZBOOT  (1 GB, FAT32)  -> boot files (shim + GRUB + kernel + initrd)
       and an ISO partition (~9 GB)   -> byte-for-byte copy of the Bazzite ISO
    3. Writes the ISO into the ISO partition and VERIFIES it (SHA-256 read-back)
    4. Copies the boot files to BZBOOT
    5. Adds "Bazzite Installer" to the firmware boot menu (F7)

  Every destructive step asks you to type YES first.
  Undo everything:   powershell -ExecutionPolicy Bypass -File <this file> -Undo
#>
param([switch]$Undo)
$ErrorActionPreference = 'Stop'

$Iso        = Join-Path $env:USERPROFILE 'Downloads\bazzite-stable-live-amd64.iso'
$IsoSize    = 8423129088
$DiskNumber = 0
$BootLabel  = 'BZBOOT'
$BootSize   = 1GB
$ShrinkBy   = 10GB
$EntryName  = 'Bazzite Installer'

function Say($m, $c = 'Cyan') { Write-Host $m -ForegroundColor $c }
function Confirm-Step($m) {
  Write-Host ''
  Write-Host $m -ForegroundColor Yellow
  if ((Read-Host 'Type YES to continue') -cne 'YES') { throw 'Stopped by user. Nothing further was changed.' }
}
function Get-BootPartition {
  Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue |
    Where-Object { $_.DriveLetter -and (Get-Volume -Partition $_ -ErrorAction SilentlyContinue).FileSystemLabel -eq $BootLabel }
}
function Get-IsoPartition($boot) {
  if (-not $boot) { return $null }
  Get-Partition -DiskNumber $DiskNumber | Where-Object {
    $_.PartitionNumber -eq ($boot.PartitionNumber + 1) -and $_.Size -ge $IsoSize -and $_.Size -le 12GB }
}
function Get-FirmwareEntryId {
  $txt = (bcdedit /enum firmware) -join "`n"
  foreach ($block in ($txt -split "`n`n")) {
    if ($block -match [regex]::Escape($EntryName) -and $block -match '\{[0-9a-fA-F\-]{36}\}') { return $Matches[0] }
  }
  return $null
}

# ---------------------------------------------------------------- safety checks
$disk = Get-Disk -Number $DiskNumber
if ($disk.FriendlyName -notmatch 'NQ790') { throw "Disk $DiskNumber is '$($disk.FriendlyName)', expected the Lexar NQ790. Aborting." }
$cPart = Get-Partition -DriveLetter C
if ($cPart.DiskNumber -ne $DiskNumber) { throw 'C: is not on disk 0. Aborting.' }

# ---------------------------------------------------------------- undo
if ($Undo) {
  $boot = Get-BootPartition; $isoP = Get-IsoPartition $boot; $id = Get-FirmwareEntryId
  Confirm-Step "UNDO: remove firmware entry ($id), delete BZBOOT + ISO partitions, give the space back to C:."
  if ($id) { bcdedit /delete $id | Out-Null; Say "removed boot entry $id" }
  if ($isoP) { Remove-Partition -DiskNumber $DiskNumber -PartitionNumber $isoP.PartitionNumber -Confirm:$false; Say 'deleted ISO partition' }
  if ($boot) { Remove-Partition -DiskNumber $DiskNumber -PartitionNumber $boot.PartitionNumber -Confirm:$false; Say 'deleted BZBOOT' }
  $max = (Get-PartitionSupportedSize -DriveLetter C).SizeMax
  Resize-Partition -DriveLetter C -Size $max; Say 'C: extended back. Undo complete.' 'Green'
  return
}

if (-not (Test-Path $Iso)) { throw "ISO not found: $Iso" }
if ((Get-Item $Iso).Length -ne $IsoSize) { throw "ISO size is $((Get-Item $Iso).Length), expected $IsoSize. Re-download it." }

Say "Disk:  $($disk.FriendlyName)  ($([math]::Round($disk.Size/1TB,2)) TB)"
Say "C:     $([math]::Round($cPart.Size/1GB)) GB"
Say "ISO:   $Iso"

# ---------------------------------------------------------------- 1+2. partitions
$boot = Get-BootPartition
if ($boot) {
  Say "BZBOOT already exists ($($boot.DriveLetter):). Skipping shrink/create." 'Green'
} else {
  Confirm-Step "STEP 1-2: shrink C: by 10 GB and create two new partitions in that space (BZBOOT 1 GB FAT32 + ~9 GB ISO partition). Windows and your files are not touched."
  Resize-Partition -DiskNumber $DiskNumber -PartitionNumber $cPart.PartitionNumber -Size ($cPart.Size - $ShrinkBy)
  Say 'C: shrunk by 10 GB'
  $boot = New-Partition -DiskNumber $DiskNumber -Size $BootSize -AssignDriveLetter
  Format-Volume -Partition $boot -FileSystem FAT32 -NewFileSystemLabel $BootLabel -Confirm:$false | Out-Null
  $boot = Get-Partition -DiskNumber $DiskNumber -PartitionNumber $boot.PartitionNumber
  Say "BZBOOT created as $($boot.DriveLetter):"
  New-Partition -DiskNumber $DiskNumber -UseMaximumSize | Out-Null
  Say 'ISO partition created (no drive letter, raw)'
}
$isoPart = Get-IsoPartition $boot
if (-not $isoPart) { throw 'Could not find the ISO partition right after BZBOOT (or it is too small). Run with -Undo and retry.' }
Say ("ISO partition: #{0}, {1:N0} bytes at offset {2:N0}" -f $isoPart.PartitionNumber, $isoPart.Size, $isoPart.Offset)
$volPath = ($isoPart.AccessPaths | Where-Object { $_ -like '\\?\Volume*' } | Select-Object -First 1)
if (-not $volPath) { throw 'ISO partition has no volume path.' }
$volPath = '\\.\' + $volPath.Substring(4).TrimEnd('\')

# ---------------------------------------------------------------- 3. raw write + verify
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using Microsoft.Win32.SafeHandles;

public static class RawVolume {
  [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
  static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr sa, uint disposition, uint flags, IntPtr template);
  [DllImport("kernel32.dll", SetLastError = true)]
  static extern bool DeviceIoControl(SafeFileHandle h, uint code, IntPtr inBuf, uint inSize, IntPtr outBuf, uint outSize, out uint returned, IntPtr overlapped);

  const uint GENERIC_READ = 0x80000000, GENERIC_WRITE = 0x40000000;
  const uint FSCTL_LOCK_VOLUME = 0x00090018, FSCTL_DISMOUNT_VOLUME = 0x00090020, FSCTL_ALLOW_EXTENDED_DASD_IO = 0x00090083;
  const int CHUNK = 8 * 1024 * 1024;

  static SafeFileHandle OpenLocked(string path) {
    SafeFileHandle h = CreateFile(path, GENERIC_READ | GENERIC_WRITE, 3, IntPtr.Zero, 3, 0, IntPtr.Zero);
    if (h.IsInvalid) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "Cannot open " + path);
    uint r;
    DeviceIoControl(h, FSCTL_ALLOW_EXTENDED_DASD_IO, IntPtr.Zero, 0, IntPtr.Zero, 0, out r, IntPtr.Zero);
    if (!DeviceIoControl(h, FSCTL_LOCK_VOLUME, IntPtr.Zero, 0, IntPtr.Zero, 0, out r, IntPtr.Zero))
      throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "Cannot lock volume (close any window using it)");
    DeviceIoControl(h, FSCTL_DISMOUNT_VOLUME, IntPtr.Zero, 0, IntPtr.Zero, 0, out r, IntPtr.Zero);
    return h;
  }

  static int ReadFull(Stream s, byte[] buf, int want) {
    int got = 0;
    while (got < want) { int n = s.Read(buf, got, want - got); if (n <= 0) break; got += n; }
    return got;
  }

  static string Hex(byte[] b) { return BitConverter.ToString(b).Replace("-", "").ToLowerInvariant(); }

  public static string HashFile(string path, long length) {
    using (FileStream fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, CHUNK))
      return HashStream(fs, length, "Hashing ISO");
  }

  static string HashStream(Stream s, long length, string label) {
    using (SHA256 sha = SHA256.Create()) {
      byte[] buf = new byte[CHUNK]; long done = 0;
      while (done < length) {
        int want = (int)Math.Min(CHUNK, length - done);
        int n = ReadFull(s, buf, want);
        if (n != want) throw new IOException("Short read at " + done);
        sha.TransformBlock(buf, 0, n, null, 0); done += n;
        Console.Write("\r  " + label + ": " + (done * 100 / length) + "%   ");
      }
      sha.TransformFinalBlock(buf, 0, 0); Console.WriteLine();
      return Hex(sha.Hash);
    }
  }

  public static string WriteAndVerify(string iso, string volume, long length) {
    using (SafeFileHandle h = OpenLocked(volume))
    using (FileStream vol = new FileStream(h, FileAccess.ReadWrite, 4096))
    using (FileStream src = new FileStream(iso, FileMode.Open, FileAccess.Read, FileShare.Read, CHUNK)) {
      byte[] buf = new byte[CHUNK]; long done = 0;
      while (done < length) {
        int want = (int)Math.Min(CHUNK, length - done);
        int n = ReadFull(src, buf, want);
        if (n != want) throw new IOException("Short read from ISO at " + done);
        vol.Write(buf, 0, n); done += n;
        Console.Write("\r  Writing: " + (done * 100 / length) + "%   ");
      }
      vol.Flush(true); Console.WriteLine();
      vol.Seek(0, SeekOrigin.Begin);
      return HashStream(vol, length, "Verifying partition");
    }
  }
}
'@

Confirm-Step "STEP 3: write the Bazzite ISO byte-for-byte into the new ISO partition ($volPath). Only that new partition is written."
$isoHash = [RawVolume]::HashFile($Iso, $IsoSize)
$volHash = [RawVolume]::WriteAndVerify($Iso, $volPath, $IsoSize)
Say "ISO       sha256: $isoHash"
Say "Partition sha256: $volHash"
if ($isoHash -ne $volHash) { throw 'VERIFY FAILED: the partition does not match the ISO. Do not boot it; run -Undo.' }
Say 'Verified: partition is an exact copy of the ISO.' 'Green'

# ---------------------------------------------------------------- 4. boot files
$b = "$($boot.DriveLetter):"
Say "STEP 4: copying boot files to BZBOOT ($b)"
Mount-DiskImage -ImagePath $Iso | Out-Null
Start-Sleep 2
try {
  $isoDrive = "$((Get-DiskImage -ImagePath $Iso | Get-Volume).DriveLetter):"
  robocopy "$isoDrive\EFI" "$b\EFI" /E /NFL /NDL /NJH /NJS /NP | Out-Null
  robocopy "$isoDrive\images\pxeboot" "$b\images\pxeboot" /E /NFL /NDL /NJH /NJS /NP | Out-Null
  attrib -r "$b\*" /s /d | Out-Null   # files copied from an ISO are read-only
} finally {
  Dismount-DiskImage -ImagePath $Iso | Out-Null
}
foreach ($f in 'EFI\fedora\shimx64.efi', 'EFI\fedora\grubx64.efi', 'images\pxeboot\vmlinuz', 'images\pxeboot\initrd.img') {
  if (-not (Test-Path "$b\$f")) { throw "Missing $b\$f after copy." }
}

# Same menu as the ISO, plus a fallback entry that loads the kernel from BZBOOT itself.
$grub = @'
set timeout=10
set default="0"
set menu_auto_hide=false

function load_video {
  insmod all_video
}

load_video
set gfxpayload=keep
insmod gzio
insmod part_gpt
insmod fat
insmod iso9660

search --no-floppy --set=root -l 'Bazzite-Live'
menuentry 'Launch Bazzite Installer' {
  linux /images/pxeboot/vmlinuz quiet rhgb root=live:CDLABEL=Bazzite-Live enforcing=0 rd.live.image
  initrd /images/pxeboot/initrd.img
}
menuentry 'Launch Bazzite Installer (Basic Graphics Mode)' {
  linux /images/pxeboot/vmlinuz quiet rhgb root=live:CDLABEL=Bazzite-Live enforcing=0 rd.live.image nomodeset
  initrd /images/pxeboot/initrd.img
}
menuentry 'Launch Bazzite Installer (fallback: kernel from BZBOOT)' {
  search --no-floppy --set=root -l 'BZBOOT'
  linux /images/pxeboot/vmlinuz quiet rhgb root=live:CDLABEL=Bazzite-Live enforcing=0 rd.live.image
  initrd /images/pxeboot/initrd.img
}
'@ -replace "`r`n", "`n"
$utf8 = New-Object System.Text.UTF8Encoding($false)
foreach ($cfg in "$b\EFI\fedora\grub.cfg", "$b\EFI\BOOT\grub.cfg") { [IO.File]::WriteAllText($cfg, $grub, $utf8) }
Say 'Boot files copied and boot menu written.' 'Green'

# ---------------------------------------------------------------- 5. firmware entry
$id = Get-FirmwareEntryId
if ($id) {
  Say "Firmware entry '$EntryName' already exists ($id)." 'Green'
} else {
  Confirm-Step "STEP 5: add '$EntryName' to the firmware boot menu (F7). Windows Boot Manager stays the default."
  $copy = bcdedit /copy '{bootmgr}' /d $EntryName
  if (-not (($copy -join ' ') -match '\{[0-9a-fA-F\-]{36}\}')) { throw "bcdedit /copy failed: $copy" }
  $id = $Matches[0]
  bcdedit /set $id device "partition=$b" | Out-Null
  bcdedit /set $id path '\EFI\fedora\shimx64.efi' | Out-Null
  bcdedit /set '{fwbootmgr}' displayorder $id /addlast | Out-Null
  Say "Added firmware entry $id -> $b\EFI\fedora\shimx64.efi" 'Green'
}

Write-Host ''
Say 'ALL DONE.' 'Green'
Say 'Next: reboot, press F7 repeatedly, choose "Bazzite Installer" (or "UEFI OS"/BZBOOT if named differently).'
Say 'Windows is untouched and still boots by default.'
