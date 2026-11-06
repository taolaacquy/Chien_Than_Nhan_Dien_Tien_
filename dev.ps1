$ErrorActionPreference = 'Stop'

function Get-BackendHealth {
    try {
        return Invoke-RestMethod -Uri 'http://127.0.0.1:8080/' -TimeoutSec 2
    } catch {
        return $null
    }
}

$projectRoot = $PSScriptRoot
$backendDirectory = Join-Path $projectRoot 'backend_ai'
$backendPython = Join-Path $backendDirectory '.venv\Scripts\python.exe'
$startedBackend = $null

if (-not (Test-Path -LiteralPath $backendPython)) {
    throw "Backend virtual environment not found at $backendPython. Follow the setup steps in README.md first."
}

try {
    $health = Get-BackendHealth
    if ($health.model_loaded -ne $true) {
        Write-Host 'Starting FastAPI and loading best.onnx...'
        $startedBackend = Start-Process `
            -FilePath $backendPython `
            -ArgumentList @('-m', 'uvicorn', 'main:app', '--host', '0.0.0.0', '--port', '8080') `
            -WorkingDirectory $backendDirectory `
            -WindowStyle Hidden `
            -PassThru

        $deadline = (Get-Date).AddSeconds(120)
        do {
            if ($startedBackend.HasExited) {
                throw 'Backend stopped during startup. Check dependencies and backend_ai/best.onnx.'
            }
            $health = Get-BackendHealth
            if ($health.model_loaded -eq $true) { break }
            Start-Sleep -Seconds 2
        } while ((Get-Date) -lt $deadline)

        if ($health.model_loaded -ne $true) {
            throw 'Timed out waiting for the ONNX model. Start the backend manually to inspect its logs.'
        }
    }

    Write-Host 'Backend is ready. Launching Flutter Web on Edge...'
    flutter run -d edge
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter exited with code $LASTEXITCODE."
    }
} finally {
    if ($null -ne $startedBackend -and -not $startedBackend.HasExited) {
        Stop-Process -Id $startedBackend.Id -Force
    }
}
