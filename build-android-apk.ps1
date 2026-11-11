param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^http://')]
    [string]$BackendUrl
)

$ErrorActionPreference = 'Stop'
$BackendUrl = $BackendUrl.TrimEnd('/')

flutter build apk --release "--dart-define=API_BASE_URL=$BackendUrl"
if ($LASTEXITCODE -ne 0) {
    throw "APK build failed with exit code $LASTEXITCODE"
}

Write-Host "APK ready: $PSScriptRoot\build\app\outputs\flutter-apk\app-release.apk"
Write-Host "Backend URL embedded in APK: $BackendUrl"
