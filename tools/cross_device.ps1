# Runs integration_test/cross_device_test.dart on two devices at once:
#   Windows (inviter)  <->  Android emulator / phone (joiner)
# and carries the connection codes between them (what a user does by copy-paste).
param(
  [string]$AndroidDevice = "emulator-5554",
  [int]$TimeoutMinutes = 30
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$ex = Join-Path $env:TEMP ("jp_exchange_" + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Force $ex | Out-Null
$winLog = Join-Path $ex "windows.log"
$andLog = Join-Path $ex "android.log"
Write-Host "Takas klasoru: $ex"
$photo = [System.IO.Path]::Combine($root, "integration_test", "fixtures", "foto_exif.jpg")
$photoSha = (Get-FileHash -Algorithm SHA256 $photo).Hash.ToLower()

$win = Start-Process -FilePath "flutter.bat" -WorkingDirectory $root -NoNewWindow -PassThru `
  -RedirectStandardOutput $winLog -RedirectStandardError "$winLog.err" `
  -ArgumentList @("test", "integration_test/cross_device_test.dart", "-d", "windows",
                  "--dart-define=ROLE=inviter", "--dart-define=EXCHANGE=$ex", "--dart-define=PHOTO=$photo")

$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
$inviteFile = Join-Path $ex "invite.txt"
while (-not (Test-Path $inviteFile)) {
  if ($win.HasExited) { Get-Content $winLog -Tail 40; throw "Windows tarafi davet uretmeden kapandi" }
  if ((Get-Date) -gt $deadline) { throw "Davet kodu zaman asimi" }
  Start-Sleep -Milliseconds 500
}
$invite = (Get-Content $inviteFile -Raw).Trim()
Write-Host "Davet kodu alindi ($($invite.Length) karakter) -> Android'e veriliyor"

$and = Start-Process -FilePath "flutter.bat" -WorkingDirectory $root -NoNewWindow -PassThru `
  -RedirectStandardOutput $andLog -RedirectStandardError "$andLog.err" `
  -ArgumentList @("test", "integration_test/cross_device_test.dart", "-d", $AndroidDevice,
                  "--dart-define=ROLE=joiner", "--dart-define=INVITE=$invite", "--dart-define=PHOTO_SHA=$photoSha")

$answerFile = Join-Path $ex "answer.txt"
while (-not (Test-Path $answerFile)) {
  if ($and.HasExited) { Get-Content $andLog -Tail 60; throw "Android tarafi yanit uretmeden kapandi" }
  if ((Get-Date) -gt $deadline) { throw "Yanit kodu zaman asimi" }
  # Only take the code once its whole line (incl. line break) has been written.
  $text = Get-Content $andLog -Raw -ErrorAction SilentlyContinue
  if ($null -eq $text) { $text = "" }
  $m = [regex]::Match($text,"ANSWER_CODE:(JP1A-[A-Za-z0-9_-]+)\r?\n")
  if ($m.Success) {
    $m.Groups[1].Value | Set-Content -NoNewline -Encoding ascii $answerFile
    Write-Host "Yanit kodu alindi -> Windows'a veriliyor"
  }
  Start-Sleep -Milliseconds 500
}

while (-not ($win.HasExited -and $and.HasExited)) {
  if ((Get-Date) -gt $deadline) { Stop-Process -Id $win.Id, $and.Id -ErrorAction SilentlyContinue; throw "Test zaman asimi" }
  Start-Sleep -Seconds 1
}

Write-Host "`n===== WINDOWS ====="
Select-String -Path $winLog -Pattern "\[inviter\]|All tests passed|Some tests failed|\[E\]|Expected|Actual|Bad state" | ForEach-Object { $_.Line }
Write-Host "`n===== ANDROID ====="
Select-String -Path $andLog -Pattern "\[joiner\]|All tests passed|Some tests failed|\[E\]|Expected|Actual|Bad state" | ForEach-Object { $_.Line }
Write-Host "`nLoglar: $ex"
