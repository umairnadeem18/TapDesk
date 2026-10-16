# Fetches the bundled fonts required by docs/design-system.md.
#
# Fonts must be bundled as assets, not fetched at runtime: pairing happens on a
# local network that may have no internet, and the app must look identical
# offline. This script downloads them once; it is not part of any build.
$ErrorActionPreference = 'Continue'
$dest = 'D:\Development\TAPDESK\mobile\assets\fonts'
$log  = 'D:\Development\TAPDESK\mobile\assets\fonts\fetch.log'
New-Item -ItemType Directory -Force -Path $dest | Out-Null

function Say($m) {
  $line = "[{0}] {1}" -f (Get-Date).ToString('HH:mm:ss'), $m
  Write-Host $line
  Add-Content -Path $log -Value $line
}

function Get-File($url, $out) {
  if ((Test-Path $out) -and (Get-Item $out).Length -gt 2000) { Say "skip  $(Split-Path $out -Leaf)"; return $true }
  curl.exe -sL --retry 5 --retry-delay 3 -o $out $url
  if ((Test-Path $out) -and (Get-Item $out).Length -gt 2000) {
    Say ("ok    {0,-34} {1} KB" -f (Split-Path $out -Leaf), [math]::Round((Get-Item $out).Length/1KB))
    return $true
  }
  Say ("FAIL  {0}" -f $url)
  if (Test-Path $out) { Remove-Item $out -Force }
  return $false
}

Say '=== font fetch started ==='

# Poppins — headings. Static weights exist on google/fonts.
$gf = 'https://raw.githubusercontent.com/google/fonts/main/ofl/poppins'
foreach ($w in @('Regular','Medium','SemiBold','Bold')) {
  Get-File "$gf/Poppins-$w.ttf" "$dest\Poppins-$w.ttf" | Out-Null
}

# JetBrains Mono — IP, PIN, fingerprint. Statics live in the JetBrains repo.
$jb = 'https://raw.githubusercontent.com/JetBrains/JetBrainsMono/master/fonts/ttf'
foreach ($w in @('JetBrainsMono-Regular.ttf','JetBrainsMono-Medium.ttf','JetBrainsMono-Bold.ttf')) {
  Get-File "$jb/$w" "$dest\$w" | Out-Null
}

# Inter — body. Statics are published in the rsms/inter release zip rather than
# individually, so grab the zip and extract just the static TTFs.
$zip = "$env:TEMP\inter.zip"
if (-not ((Test-Path $zip) -and (Get-Item $zip).Length -gt 100000)) {
  Say 'fetching Inter release zip'
  curl.exe -sL --retry 5 --retry-delay 3 -o $zip 'https://github.com/rsms/inter/releases/download/v4.1/Inter-4.1.zip'
}
if ((Test-Path $zip) -and (Get-Item $zip).Length -gt 100000) {
  Say ("Inter zip {0} KB - extracting statics" -f [math]::Round((Get-Item $zip).Length/1KB))
  $tmp = "$env:TEMP\inter_x"
  if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
  Expand-Archive -Path $zip -DestinationPath $tmp -Force
  # Statics live under extras/ttf/ in the release zip, not a "static" folder.
  $found = Get-ChildItem $tmp -Recurse -Filter '*.ttf' |
           Where-Object { $_.FullName -match '\\extras\\ttf\\' -and $_.Name -notmatch 'Italic' }
  foreach ($f in $found) {
    # Only the four weights the design system actually uses; Display variants
    # are for large text and would only bloat the APK.
    if ($f.Name -match '^Inter-(Regular|Medium|SemiBold|Bold)\.ttf$') {
      Copy-Item $f.FullName "$dest\$($f.Name)" -Force
      Say ("ok    {0,-34} {1} KB" -f $f.Name, [math]::Round($f.Length/1KB))
    }
  }
  Remove-Item $tmp -Recurse -Force
} else {
  Say 'Inter zip unavailable - Inter will fall back to the bundled default'
}

Say '--- fonts present ---'
Get-ChildItem $dest -Filter '*.ttf' | ForEach-Object { Say ("      {0,-34} {1} KB" -f $_.Name, [math]::Round($_.Length/1KB)) }
Say '=== font fetch finished ==='
