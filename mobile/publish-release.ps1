# Publishes the signed release APKs to a GitHub Release.
#
# Why a Release and not the repository: the APKs are 20-26 MB each, which is
# fine as a Release asset (2 GB limit) but they are build artifacts that must
# never appear in git history. The website then links to
# /releases/latest/download/<asset>.
#
# The token is read from Git Credential Manager and written to a temporary
# header file, so it never appears in a command line or in this script.
param(
  # Defaults to the most recent published tag, so the common case needs no
  # arguments. Publishing a new build means passing -Tag explicitly, which is
  # deliberate: silently reusing the old tag would replace assets under a
  # version number that has already been downloaded by somebody.
  [string]$Tag = 'v1.0.0-beta.2',

  # Overrides the release notes. Kept as a parameter because the notes have to
  # change with every build, and a stale note ("the transport is not wired up"
  # on a build that connects) is worse than no note at all.
  [string]$Body,

  # Staged files to upload. Defaults to the split APKs in the build output.
  [string]$ApkDir = 'D:\Development\TAPDESK\mobile\build\app\outputs\flutter-apk'
)

$ErrorActionPreference = 'Stop'
$repo = 'umairnadeem18/TapDesk'
$tag  = $Tag
$apkDir = $ApkDir
$log = 'D:\Development\TAPDESK\mobile\publish-release.log'

if (-not $Body) {
  $Body = @"
TapDesk $tag - control this computer from your phone.

**This build can actually connect.** Pairing, transport and input are all wired
up: scan the QR code in the companion window and the phone drives the mouse,
keyboard and slides.

Install: allow your file manager to install unknown apps, then open the APK
matching your phone architecture. Most modern phones are arm64.

The PC side is a separate installer - download it from the website first.

SHA-256 checksums are published on the website download page.
"@
}

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
    # Deliberately not named "$body": PowerShell variable names are
    # case-insensitive, and the parameter below is "$Body" — reusing the name
    # here silently replaced the caller's release notes with this file path,
    # which is what every note built by this script published as.
    $notesFile = Join-Path $env:TEMP 'gh_release.json'
    # The body is escaped rather than interpolated raw: a newline in the notes
    # would otherwise produce a JSON document GitHub rejects, and the resulting
    # error message says nothing about the real cause.
    $escaped = $Body -replace '\\', '\\\\' -replace '"', '\"' -replace "`r`n", '\n' -replace "`n", '\n'
    # A tag is a pre-release when its name says so, and the stable v1.0.0 must
    # not: GitHub's "latest" link points at the newest non-prerelease, so a
    # final release accidentally marked pre-release would be invisible to
    # exactly the audience that searches for "the current version".
    $isPrerelease = if ($tag -match 'beta|rc|alpha') { 'true' } else { 'false' }
    $json = @"
{
  "tag_name": "$tag",
  "target_commitish": "main",
  "name": "TapDesk $tag",
  "body": "$escaped",
  "draft": false,
  "prerelease": $isPrerelease
}
"@
    # UTF-8 WITHOUT a BOM. PowerShell 5.1's Set-Content -Encoding UTF8 writes
    # one, and GitHub rejects the request as an invalid body - which is exactly
    # the silent failure this script had to work around.
    [IO.File]::WriteAllText($notesFile, $json, (New-Object Text.UTF8Encoding $false))

    $raw = Invoke-Gh "https://api.github.com/repos/$repo/releases" 'POST' `
            @('Content-Type: application/json') $notesFile
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

  # The desktop installer, if it has been built. Optional on purpose: the phone
  # build is the thing that has to ship first, and a missing installer should
  # be a skipped line rather than a failed publish.
  $installer = 'D:\Development\TAPDESK\companion\dist\TapDesk-1.0.0-setup.exe'
  if (Test-Path $installer) {
    $assets += @{ file = $installer; name = 'TapDesk-1.0.0-setup.exe' }
  }

  $existingNames = (Invoke-Gh "https://api.github.com/repos/$repo/releases/$releaseId/assets" |
                    ConvertFrom-Json | ForEach-Object { $_.name })

  foreach ($a in $assets) {
    # An asset may be named by absolute path - the desktop installer is not
    # built into the APK output folder - so only relative names get joined.
    $path = if ([IO.Path]::IsPathRooted($a.file)) { $a.file } else { Join-Path $apkDir $a.file }
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
