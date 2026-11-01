# inspect-bazzite-iso.ps1  --  READ-ONLY. Changes nothing on the disk.
# Mounts the Bazzite ISO, records its boot layout and the current disk layout
# into Downloads\bazzite-iso-inspect.txt, then unmounts it.
$ErrorActionPreference = 'Continue'
$iso = Join-Path $env:USERPROFILE 'Downloads\bazzite-stable-live-amd64.iso'
$out = Join-Path $env:USERPROFILE 'Downloads\bazzite-iso-inspect.txt'

$img = Get-DiskImage -ImagePath $iso
if (-not $img.Attached) { Mount-DiskImage -ImagePath $iso | Out-Null; Start-Sleep 2 }
$vol = Get-DiskImage -ImagePath $iso | Get-Volume
$d = "$($vol.DriveLetter):\"

& {
  "ISO: $iso  ($((Get-Item $iso).Length) bytes)"
  "Mounted as $d  label='$($vol.FileSystemLabel)'  fs=$($vol.FileSystemType)"
  "`n--- top level"
  Get-ChildItem $d -Force | ForEach-Object { "{0,14}  {1}" -f $_.Length, $_.Name }
  "`n--- every file (size, path)"
  Get-ChildItem $d -Recurse -File -Force -ErrorAction SilentlyContinue |
    ForEach-Object { "{0,14}  {1}" -f $_.Length, $_.FullName.Substring(3) }
  foreach ($cfg in Get-ChildItem $d -Recurse -File -Force -Include grub.cfg, *.conf, isolinux.cfg -ErrorAction SilentlyContinue) {
    "`n===== $($cfg.FullName.Substring(3))"
    Get-Content $cfg.FullName
  }
  "`n--- disks"
  Get-Disk | Format-Table Number, FriendlyName, PartitionStyle, Size -AutoSize | Out-String -Width 250
  "--- partitions"
  Get-Partition | Format-Table DiskNumber, PartitionNumber, DriveLetter, Offset, Size, Type, GptType -AutoSize | Out-String -Width 250
  "--- C: shrink limits"
  try { Get-PartitionSupportedSize -DriveLetter C | Out-String } catch { "needs admin: $_" }
  "--- firmware boot entries"
  try { bcdedit /enum firmware } catch { "needs admin: $_" }
} *> $out

Dismount-DiskImage -ImagePath $iso | Out-Null
Write-Host "Done. Report saved to $out" -ForegroundColor Green
