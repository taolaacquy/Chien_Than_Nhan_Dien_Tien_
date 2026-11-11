$ErrorActionPreference = 'Stop'

Write-Host 'Starting Flutter Web in Edge. Start the backend first with .\run-mobile-backend.ps1.'
flutter run -d edge --dart-define=API_BASE_URL=http://127.0.0.1:8080
if ($LASTEXITCODE -ne 0) {
    throw "Flutter Web exited with code $LASTEXITCODE"
}
