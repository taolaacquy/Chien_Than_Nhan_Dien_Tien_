$ErrorActionPreference = 'Stop'

$projectRoot = $PSScriptRoot
$backendDirectory = Join-Path $projectRoot 'backend_ai'
$backendPython = Join-Path $backendDirectory '.venv\Scripts\python.exe'
$modelPath = Join-Path $backendDirectory 'best.onnx'

if (-not (Test-Path -LiteralPath $backendPython)) {
    throw "Chua co Python environment: $backendPython. Cai dat theo README.md truoc."
}
if (-not (Test-Path -LiteralPath $modelPath)) {
    throw "Khong tim thay model: $modelPath"
}
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Khong tim thay Flutter trong PATH.'
}

$lanAddress = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object {
        $_.IPAddress -notlike '127.*' -and
        $_.IPAddress -notlike '169.254.*' -and
        $_.AddressState -eq 'Preferred'
    } |
    Select-Object -First 1 -ExpandProperty IPAddress
if (-not $lanAddress) {
    throw 'Khong tim thay IPv4 mang LAN. Hay ket noi laptop vao Wi-Fi truoc.'
}

$health = $null
try { $health = Invoke-RestMethod -Uri 'http://127.0.0.1:8080/' -TimeoutSec 2 } catch {}
$startedBackend = $null

if ($health.model_loaded -ne $true) {
    $startedBackend = Start-Process `
        -FilePath $backendPython `
        -ArgumentList @('-m', 'uvicorn', 'main:app', '--host', '0.0.0.0', '--port', '8080') `
        -WorkingDirectory $backendDirectory `
        -WindowStyle Hidden `
        -PassThru

    $deadline = (Get-Date).AddSeconds(180)
    do {
        if ($startedBackend.HasExited) {
            throw 'Backend dung khi khoi dong. Hay chay backend rieng de xem loi.'
        }
        try { $health = Invoke-RestMethod -Uri 'http://127.0.0.1:8080/' -TimeoutSec 2 } catch { $health = $null }
        if ($health.model_loaded -eq $true) { break }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)

    if ($health.model_loaded -ne $true) {
        throw 'Het thoi gian cho model. Hay chay backend rieng de xem loi.'
    }
}

$appUrl = "http://${lanAddress}:5000"
$apiUrl = "http://${lanAddress}:8080"
Write-Host ''
Write-Host 'Backend san sang. Dien thoai va laptop can cung mang Wi-Fi.' -ForegroundColor Green
Write-Host "Mo Chrome tren dien thoai: $appUrl" -ForegroundColor Cyan
Write-Host "Kiem tra backend tren dien thoai: $apiUrl/" -ForegroundColor Cyan
Write-Host 'De dung demo, nhan Ctrl+C tai cua so nay. Laptop phai tiep tuc bat.'
Write-Host ''

try {
    flutter run -d web-server --web-hostname 0.0.0.0 --web-port 5000 `
        --dart-define="API_BASE_URL=$apiUrl"
    if ($LASTEXITCODE -ne 0) { throw "Flutter thoat voi ma $LASTEXITCODE." }
} finally {
    if ($null -ne $startedBackend -and -not $startedBackend.HasExited) {
        Stop-Process -Id $startedBackend.Id -Force
    }
}
