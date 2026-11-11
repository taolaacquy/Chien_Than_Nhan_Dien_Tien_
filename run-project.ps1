$ErrorActionPreference = 'Stop'

function Get-BackendHealth {
    try {
        return Invoke-RestMethod -Uri 'http://127.0.0.1:8080/' -TimeoutSec 3
    } catch {
        return $null
    }
}

$backendDirectory = Join-Path $PSScriptRoot 'backend_ai'
$backendPython = Join-Path $backendDirectory '.venv\Scripts\python.exe'
$startedBackend = $null

try {
    $health = Get-BackendHealth
    if ($null -eq $health) {
        if (-not (Test-Path -LiteralPath $backendPython)) {
            throw 'Backend virtual environment missing. Follow README.md setup first.'
        }

        Write-Host 'Starting backend and loading the model...'
        $startedBackend = Start-Process `
            -FilePath $backendPython `
            -ArgumentList @('-m', 'uvicorn', 'main:app', '--host', '0.0.0.0', '--port', '8080') `
            -WorkingDirectory $backendDirectory `
            -WindowStyle Hidden `
            -PassThru

        $deadline = (Get-Date).AddMinutes(3)
        while ((Get-Date) -lt $deadline -and $health.model_loaded -ne $true) {
            if ($startedBackend.HasExited) {
                throw 'Backend stopped during startup. Run .\run-mobile-backend.ps1 to view its logs.'
            }
            Start-Sleep -Seconds 2
            $health = Get-BackendHealth
        }
    }

    if ($health.model_loaded -ne $true) {
        throw 'Backend did not report model_loaded=true. Check the backend and backend_ai\best.onnx.'
    }

    Write-Host 'Backend ready. Starting Flutter Web in Edge...'
    flutter run -d edge --dart-define=API_BASE_URL=http://127.0.0.1:8080
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter Web exited with code $LASTEXITCODE"
    }
} finally {
    if ($null -ne $startedBackend -and -not $startedBackend.HasExited) {
        Stop-Process -Id $startedBackend.Id -Force
    }
}
