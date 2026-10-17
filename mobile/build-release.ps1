# Builds the signed release APKs, one per ABI.
#
# Split per ABI because a universal APK carries three architectures and is
# ~170 MB, while any single phone only ever loads one of them. A split APK is
# around a fifth of that, which matters a lot on a 250 KB/s connection.
#
# Signed with D:\Development\TapDesk-Secrets\tapdesk-release.jks, referenced by
# mobile\android\key.properties (gitignored). Never with the debug key.
#
# Output: mobile\build\app\outputs\flutter-apk\app-<abi>-release.apk
$ErrorActionPreference = 'Continue'
$log = 'D:\Development\TAPDESK\mobile\build-release.log'

function Say($m) {
  $line = "[{0}] {1}" -f (Get-Date).ToString('HH:mm:ss'), $m
  Write-Host $line
  Add-Content -Path $log -Value $line
}

$env:PATH = "D:\DevTools\git\cmd;D:\DevTools\flutter\bin;D:\DevTools\jdk-17\bin;$env:PATH"
$env:JAVA_HOME        = 'D:\DevTools\jdk-17'
$env:ANDROID_HOME     = 'D:\DevTools\android-sdk'
$env:ANDROID_SDK_ROOT = 'D:\DevTools\android-sdk'
$env:PUB_CACHE        = 'D:\DevTools\pub-cache'
$env:GRADLE_USER_HOME = 'D:\DevTools\gradle'

Set-Location 'D:\Development\TAPDESK\mobile'
Remove-Item $log -ErrorAction SilentlyContinue

Say '=== release APK build started ==='
& cmd.exe /c 'flutter build apk --release --split-per-abi 2>&1' | ForEach-Object {
  $line = "$_"
  if ($line -notmatch 'RemoteException' -and $line.Trim() -ne '') {
    Add-Content -Path $log -Value $line
  }
}
$code = $LASTEXITCODE
Say "flutter build apk --release exited with $code"

$dir = 'D:\Development\TAPDESK\mobile\build\app\outputs\flutter-apk'
$apks = Get-ChildItem $dir -Filter '*release.apk' -ErrorAction SilentlyContinue
if ($apks) {
  foreach ($a in $apks) {
    $hash = (Get-FileHash $a.FullName -Algorithm SHA256).Hash.ToLower()
    Say ("{0,-34} {1,7:N1} MB  sha256={2}" -f $a.Name, ($a.Length/1MB), $hash)
  }
} else {
  Say 'NO APKS PRODUCED - see the log above'
}
Say '=== release APK build finished ==='
