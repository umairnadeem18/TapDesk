# Installs the Android NDK that Flutter's Gradle plugin insists on.
#
# WHY THIS IS NEEDED - and why it is not obvious:
#
# Flutter's Gradle plugin (FlutterPluginUtils.maybeHandleToolNdkProvisioning)
# reads the AGP ndkVersion and, if that version is not installed, tries to
# install it by shelling out to:
#     sdkmanager --install "ndk;28.2.13676358"
# Note the SEMICOLON. The cmdline-tools shipped today replaced sdkmanager with
# the Android CLI, which uses SLASH notation. So Flutter's auto-install always
# fails on a current machine with:
#     Package ndk not found. / Package 28.2.13676358 not found.
#     -> "Android sdkmanager did not install NDK ... into ..."
# which looks like our build is broken when it is really a tool bug.
#
# The workaround is to install the NDK ourselves with correct syntax BEFORE
# building. Flutter then sees the version already present and never calls the
# broken path at all. This is the same semicolon-vs-slash trap that hit the
# Android SDK install in Phase 0 - recorded again here because it will bite
# anyone who rebuilds on a fresh machine.
$ErrorActionPreference = 'Continue'
$sdk = 'D:\DevTools\android-sdk'
$log = 'D:\DevTools\downloads\ndk-install.log'
$sm  = "$sdk\cmdline-tools\latest\bin\sdkmanager.bat"
$want = 'ndk/28.2.13676358'

function Say($m) {
  $line = "[{0}] {1}" -f (Get-Date).ToString('HH:mm:ss'), $m
  Write-Host $line
  Add-Content -Path $log -Value $line
}

$env:JAVA_HOME = 'D:\DevTools\jdk-17'
$env:ANDROID_HOME = $sdk
$env:ANDROID_SDK_ROOT = $sdk
$env:PATH = "D:\DevTools\jdk-17\bin;$sdk\cmdline-tools\latest\bin;$env:PATH"

$marker = "$sdk\$want\source.properties"
if (Test-Path $marker) { Say "$want already installed"; exit 0 }

Say "=== NDK install started ($want) ==="
Say 'expect roughly an hour on this connection'

& $sm --sdk_root=$sdk --install $want 2>&1 |
  Where-Object { $_ -notmatch 'deprecated|android binary|replacement|learn more|UseAllWindowsProcessorGroups' } |
  ForEach-Object { Add-Content -Path $log -Value $_ }

if (Test-Path $marker) {
  Say ("NDK OK - present at {0}" -f $marker)
} else {
  Say "NDK MISSING - marker not found at $marker"
  Say '--- last log lines ---'
  Get-Content $log -Tail 20 | ForEach-Object { Add-Content -Path $log -Value $_ }
}
Say '=== NDK install finished ==='
