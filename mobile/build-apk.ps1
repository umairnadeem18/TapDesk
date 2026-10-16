# Builds the Phase 2 debug APK.
#
# Detached and logged, because the first Gradle build downloads a large amount
# on this slow connection and a tool-session timeout would otherwise kill it
# partway through.
#
#   logs to : D:\Development\TAPDESK\mobile\build-apk.log
#   artifact: mobile\build\app\outputs\flutter-apk\app-debug.apk
$ErrorActionPreference = 'Continue'
$log = 'D:\Development\TAPDESK\mobile\build-apk.log'

function Say($m) {
  $line = "[{0}] {1}" -f (Get-Date).ToString('HH:mm:ss'), $m
  Write-Host $line
  Add-Content -Path $log -Value $line
}

$env:PATH = "D:\DevTools\git\cmd;D:\DevTools\flutter\bin;D:\DevTools\jdk-17\bin;D:\DevTools\android-sdk\platform-tools;$env:PATH"
$env:JAVA_HOME       = 'D:\DevTools\jdk-17'
$env:ANDROID_HOME    = 'D:\DevTools\android-sdk'
$env:ANDROID_SDK_ROOT= 'D:\DevTools\android-sdk'
$env:PUB_CACHE       = 'D:\DevTools\pub-cache'
$env:GRADLE_USER_HOME= 'D:\DevTools\gradle'

Set-Location 'D:\Development\TAPDESK\mobile'
Remove-Item $log -ErrorAction SilentlyContinue

Say '=== debug APK build started ==='

# Run through cmd so stderr lands in the log as plain text. Invoking the exe
# directly made PowerShell wrap every stderr line in a RemoteException record,
# which buried the real Gradle error.
$cmd = 'flutter build apk --debug 2>&1'
$raw = & cmd.exe /c $cmd 2>&1 | ForEach-Object { "$_" }
$raw | Where-Object { $_ -notmatch 'RemoteException' -and $_.Trim() -ne '' } |
  ForEach-Object { Add-Content -Path $log -Value $_ }
$code = $LASTEXITCODE
Say "flutter build apk --debug exited with $code"

$apk = 'D:\Development\TAPDESK\mobile\build\app\outputs\flutter-apk\app-debug.apk'
if (Test-Path $apk) {
  Say ("APK OK  {0} MB  {1}" -f [math]::Round((Get-Item $apk).Length/1MB,1), $apk)
} else {
  Say 'APK MISSING - see the log above for the first error'
  Say '--- last 40 log lines ---'
  Get-Content $log -Tail 40 | ForEach-Object { Add-Content -Path $log -Value $_ }
}
Say '=== debug APK build finished ==='
