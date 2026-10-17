# Publishes the signed release APKs to a GitHub Release.
#
# Why a Release and not the repository: the APKs are 20-26 MB each, which is
# fine as a Release asset (2 GB limit) but they are build artifacts that must
# never appear in git history. The website then links to
# /releases/latest/download/<asset>.
#
# The token is read from Git Credential Manager and written to a temporary
# header file, so it never appears in a command line or in this script.
$ErrorActionPreference = 'Stop'
$repo = 'umairnadeem18/TapDesk'
$tag  = 'v1.0.0-beta.1'
$apkDir = 'D:\Development\TAPDESK\mobile\build\app\outputs\flutter-apk'
$log = 'D:\Development\TAPDESK\mobile\publish-release.log'

function Say($m) {
  $line = "[{0}] {1}" -f (Get-Date).ToString('HH:mm:ss'), $m
  Write-Host $line
  Add-Content -Path $log -Value $line
}

Remove-Item $log -ErrorAction SilentlyContinue

# ---- get a token from Git Credential Manager -------------------------------
$git = 'D:\DevTools\git\cmd\git.exe'
$filled = "protocol=https`nhost=github.com`n`n" | & $git -c credential.helper=manager credential fill
$token = ($filled | Where-Object { $_ -like 'password=*' }) -replace '^password=', ''
if (-not $token) { Say 'no credential available from Git Credential Manager'; exit 1 }
Say 'obtained a token from Git Credential Manager'

$hdr = Join-Path $env:TEMP 'gh_headers.txt'
@("Authorization: Bearer $token", 'Accept: application/vnd.github+json',
  'X-GitHub-Api-Version: 2022-11-28', "User-Agent: tapdesk-publish") | Set-Content $hdr -Encoding ASCII

function Invoke-Gh($url, $method = 'GET', $extraHeaders = @(), $bodyFile = $null) {
  $args = @('-s', '-X', $method, '-H', "@$hdr", $url)
  foreach ($h in $extraHeaders) { $args += @('-H', $h) }
  if ($bodyFile) { $args += @('--data-binary', "@$bodyFile") }
  & curl.exe @args
}

try {
  # ---- create the release (or reuse it if the tag already exists) ---------
  $existing = Invoke-Gh "https://api.github.com/repos/$repo/releases/tags/$tag" | ConvertFrom-Json
  if ($existing.id) {
    Say "release $tag already exists (id $($existing.id)) - reusing"
    $releaseId = $existing.id
  } else {
    $body = Join-Path $env:TEMP 'gh_release.json'
    $json = @"
{
  "tag_name": "$tag",
  "target_commitish": "main",
  "name": "TapDesk $tag",
  "body": "Beta build of the TapDesk Android controller.\n\nSlides, Mouse and pairing are implemented. The transport is not yet wired up, so this build cannot connect to a PC - it is published so the interface can be reviewed on a real phone.\n\nInstall: allow your file manager to install unknown apps, then open the APK matching your phone architecture.\n\nSHA-256 checksums are published on the website download page.",
  "draft": false,
  "prerelease": true
}
"@
    # UTF-8 WITHOUT a BOM. PowerShell 5.1's Set-Content -Encoding UTF8 writes
    # one, and GitHub rejects the request as an invalid body - which is exactly
    # the silent failure this script had to work around.
    [IO.File]::WriteAllText($body, $json, (New-Object Text.UTF8Encoding $false))

    $raw = Invoke-Gh "https://api.github.com/repos/$repo/releases" 'POST' `
            @('Content-Type: application/json') $body
    if ($raw -match '"message"') { Say "release creation error: $raw" }
    $created = $raw | ConvertFrom-Json
    if (-not $created.id) { Say 'release creation failed'; exit 1 }
    $releaseId = $created.id
    Say "created release $tag (id $releaseId)"
  }

  # ---- upload assets -------------------------------------------------------
  # x86_64 is skipped on purpose: it only ever runs on an emulator, and every
  # MB matters on this connection.
  #
  # Names are built with double quotes. Single quotes would leave a literal
  # "$tag" in the filename, which is exactly what happened the first time.
  $assets = @(
    @{ file = 'app-arm64-v8a-release.apk';   name = "TapDesk-$tag-arm64-v8a.apk" },
    @{ file = 'app-armeabi-v7a-release.apk'; name = "TapDesk-$tag-armeabi-v7a.apk" }
  )

  $existingNames = (Invoke-Gh "https://api.github.com/repos/$repo/releases/$releaseId/assets" |
                    ConvertFrom-Json | ForEach-Object { $_.name })

  foreach ($a in $assets) {
    $path = Join-Path $apkDir $a.file
    if (-not (Test-Path $path)) { Say "missing $($a.file) - skipping"; continue }
    if ($existingNames -contains $a.name) { Say "already uploaded: $($a.name)"; continue }

    $mb = [math]::Round((Get-Item $path).Length / 1MB, 1)
    Say "uploading $($a.name) ($mb MB) - slow on this connection"
    $resp = Invoke-Gh "https://uploads.github.com/repos/$repo/releases/$releaseId/assets?name=$([uri]::EscapeDataString($a.name))" `
            'POST' @('Content-Type: application/octet-stream') $path | ConvertFrom-Json
    if ($resp.id) { Say "  uploaded (id $($resp.id))" } else { Say "  upload failed for $($a.name)" }
  }

  Say '---- release contents ----'
  Invoke-Gh "https://api.github.com/repos/$repo/releases/$releaseId" |
    ConvertFrom-Json | ForEach-Object { "  $($_.html_url)"; $_.assets | ForEach-Object { "    $($_.name)  $([math]::Round($_.size/1MB,1)) MB  $($_.browser_download_url)" } }
  Say '=== publish finished ==='
}
finally {
  Remove-Item $hdr -ErrorAction SilentlyContinue
  $token = $null
}
