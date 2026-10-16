# Installs Android NDK 28.2.13676358 (r28c) without the SDK manager.
#
# WHY NOT sdkmanager: `sdkmanager --install ndk/28.2.13676358` HANGS on this
# machine - no output, no network activity, no files created, indefinitely.
# The new Android CLI appears not to handle the NDK package. Rather than fight
# it, download the official archive and lay it out exactly as the SDK manager
# would, including source.properties. Flutter only checks for that marker file,
# so this is equivalent as far as the build is concerned.
#
# Layout produced (the path Flutter looks for):
#   D:\DevTools\android-sdk\ndk\28.2.13676358\source.properties
#
# Runs detached and logs to D:\DevTools\downloads\ndk-install.log.
$ErrorActionPreference = 'Continue'
$sdk   = 'D:\DevTools\android-sdk'
$dl    = 'D:\DevTools\downloads'
$log   = "$dl\ndk-install.log"
$url   = 'https://dl.google.com/android/repository/android-ndk-r28c-windows.zip'
$zip   = "$dl\android-ndk-r28c-windows.zip"
$rev   = '28.2.13676358'
$final = "$sdk\ndk\$rev"

function Say($m) {
  $line = "[{0}] {1}" -f (Get-Date).ToString('HH:mm:ss'), $m
  Write-Host $line
  Add-Content -Path $log -Value $line
}

if (Test-Path "$final\source.properties") { Say "NDK $rev already present"; exit 0 }

Say '=== NDK direct install started ==='

# ---- download, resumable, with the zip-integrity check that caught the
# ---- truncated archives in Phase 0.
$attempt = 0
while ($attempt -lt 10) {
  $attempt++
  $before = if (Test-Path $zip) { (Get-Item $zip).Length } else { 0 }
  Say ("download attempt {0}, resuming at {1} MB" -f $attempt, [math]::Round($before/1MB,1))

  curl.exe -L -C - --retry 5 --retry-delay 5 --retry-all-errors `
           --speed-limit 20480 --speed-time 90 -o $zip $url *> "$dl\ndk_curl.tmp"

  $now = if (Test-Path $zip) { (Get-Item $zip).Length } else { 0 }
  if ($now -le $before) { Say '  no progress, retrying'; Start-Sleep 5; continue }

  try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $z = [System.IO.Compression.ZipFile]::OpenRead($zip)
    $n = $z.Entries.Count; $z.Dispose()
    Say ("  download OK - {0} MB, {1} entries" -f [math]::Round($now/1MB,1), $n)
    break
  } catch {
    Say ("  incomplete at {0} MB, resuming" -f [math]::Round($now/1MB,1))
  }
}

if (-not (Test-Path $zip)) { Say 'NDK FAILED - no archive'; exit 1 }

# ---- extract straight into the versioned folder.
Say 'extracting (this takes a few minutes)'
New-Item -ItemType Directory -Force -Path "$sdk\ndk" | Out-Null
if (Test-Path $final) { Remove-Item $final -Recurse -Force }
tar -xf $zip -C "$sdk\ndk"
$extracted = "$sdk\ndk\android-ndk-r28c"
if (-not (Test-Path $extracted)) {
  Say 'NDK FAILED - expected folder android-ndk-r28c not found after extract'
  Get-ChildItem "$sdk\ndk" | ForEach-Object { Add-Content -Path $log -Value ("  found: " + $_.Name) }
  exit 1
}
Rename-Item $extracted $rev

# ---- the marker Flutter checks for.
$props = Join-Path $final 'source.properties'
if (-not (Test-Path $props)) {
  @"
Pkg.Desc = Android NDK
Pkg.Revision = $rev
"@ | Set-Content -Path $props -Encoding ASCII
  Say 'wrote source.properties'
} else {
  Say ("source.properties already shipped by the archive: " + ((Get-Content $props) -join ' | '))
}

if (Test-Path $props) { Say "NDK OK - $final" } else { Say 'NDK FAILED - no marker' }
Say '=== NDK direct install finished ==='
