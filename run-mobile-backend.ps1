$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$backendDirectory = Join-Path $projectRoot 'backend_ai'
$python = Join-Path $backendDirectory '.venv\Scripts\python.exe'

if (-not (Test-Path -LiteralPath $python)) {
    throw 'Chưa có backend_ai\.venv. Hãy làm bước cài backend trong README.md trước.'
}
if (-not (Test-Path -LiteralPath (Join-Path $backendDirectory 'best.onnx'))) {
    throw 'Không tìm thấy backend_ai\best.onnx.'
}

Push-Location $backendDirectory
try {
    & $python -m uvicorn main:app --host 0.0.0.0 --port 8080
} finally {
    Pop-Location
}
