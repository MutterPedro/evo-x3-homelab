#Requires -RunAsAdministrator
# finish-bazzite-installer-partition.ps1
# Runs only steps 4-5 (boot files + firmware entry). Steps 1-3 are already done and verified.
$ErrorActionPreference = 'Stop'
$Iso       = Join-Path $env:USERPROFILE 'Downloads\bazzite-stable-live-amd64.iso'
$BootLabel = 'BZBOOT'
$EntryName = 'Bazzite Installer'
function Say($m, $c = 'Cyan') { Write-Host $m -ForegroundColor $c }

$bootVol = Get-Volume -FileSystemLabel $BootLabel
if (-not $bootVol.DriveLetter) { throw 'BZBOOT has no drive letter.' }
$b = "$($bootVol.DriveLetter):"
Say "BZBOOT is $b"

# --- mount the ISO (reuse it if the previous run left it mounted)
Say '[1/5] mounting ISO...'
$img = Get-DiskImage -ImagePath $Iso
if (-not $img.Attached) { Mount-DiskImage -ImagePath $Iso -StorageType ISO | Out-Null }
$isoLetter = $null
for ($i = 0; $i -lt 30 -and -not $isoLetter; $i++) {
  Start-Sleep 1
  $isoLetter = (Get-DiskImage -ImagePath $Iso | Get-Volume -ErrorAction SilentlyContinue).DriveLetter
}
if (-not $isoLetter) { throw 'ISO mounted but got no drive letter. Open it in File Explorer once, then re-run.' }
$src = "${isoLetter}:"
Say "      ISO is mounted as $src"

try {
  Say '[2/5] copying EFI folder...'
  Copy-Item "$src\EFI" "$b\" -Recurse -Force
  Say '[3/5] copying kernel + initrd (~300 MB)...'
  New-Item -ItemType Directory -Force "$b\images\pxeboot" | Out-Null
  Copy-Item "$src\images\pxeboot\*" "$b\images\pxeboot\" -Force
} finally {
  Dismount-DiskImage -ImagePath $Iso | Out-Null
}
foreach ($f in 'EFI\fedora\shimx64.efi', 'EFI\fedora\grubx64.efi', 'images\pxeboot\vmlinuz', 'images\pxeboot\initrd.img') {
  if (-not (Test-Path "$b\$f")) { throw "Missing $b\$f after copy." }
}

Say '[4/5] writing boot menu...'
# Files copied from an ISO keep the read-only attribute; clear it so we can edit grub.cfg.
attrib -r "$b\*" /s /d | Out-Null
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

Say '[5/5] firmware boot entry...'
$existing = $null
foreach ($block in (((bcdedit /enum firmware) -join "`n") -split "`n`n")) {
  if ($block -match [regex]::Escape($EntryName) -and $block -match '\{[0-9a-fA-F\-]{36}\}') { $existing = $Matches[0] }
}
if ($existing) {
  Say "      already present: $existing" 'Green'
} else {
  $copy = bcdedit /copy '{bootmgr}' /d $EntryName
  if (-not (($copy -join ' ') -match '\{[0-9a-fA-F\-]{36}\}')) { throw "bcdedit /copy failed: $copy" }
  $id = $Matches[0]
  bcdedit /set $id device "partition=$b" | Out-Null
  bcdedit /set $id path '\EFI\fedora\shimx64.efi' | Out-Null
  bcdedit /set '{fwbootmgr}' displayorder $id /addlast | Out-Null
  Say "      added $id -> $b\EFI\fedora\shimx64.efi" 'Green'
}
bcdedit /enum firmware | Select-String -Pattern 'description|path|device' | ForEach-Object { "      $_" }

Write-Host ''
Say 'ALL DONE. Reboot, press F7 repeatedly, choose "Bazzite Installer".' 'Green'
