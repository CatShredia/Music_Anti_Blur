#Requires -Version 5.1
<#
.SYNOPSIS
  Поднимает Postgres/Redis/MailHog/MinIO, API и Flutter (hot reload).
  В режиме local после healthy API импортирует no_commit/music (если папка есть).

.PARAMETER Mode
  Пропустить меню: local | deploy | dual | 1 | 2 | 3 | 0
#>
param(
    [string]$Mode = ""
)

$ErrorActionPreference = "Stop"
try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
} catch {}

$DevopsRoot = $PSScriptRoot
$Root = Split-Path -Parent $DevopsRoot
$RunDir = Join-Path $DevopsRoot ".run"
$ApiProject = Join-Path $Root "src\api\MusicAntiBlur.Api\MusicAntiBlur.Api.csproj"
$MobileDir = Join-Path $Root "src\mobile"
$HealthUrl = "http://127.0.0.1:5080/health"

Set-Location $Root

function Write-Info([string]$Message) {
    Write-Host $Message -ForegroundColor Cyan
}

function Write-Warn([string]$Message) {
    Write-Host $Message -ForegroundColor Yellow
}

function Write-Err([string]$Message) {
    Write-Host $Message -ForegroundColor Red
}

function Assert-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Не найдена команда '$Name'. Установите её и повторите."
    }
}

function Confirm-Yes([string]$Prompt) {
    $choice = Read-Host "$Prompt [Y]"
    if ([string]::IsNullOrWhiteSpace($choice)) {
        return $true
    }
    $value = $choice.Trim().ToLowerInvariant()
    if ($value -in @("n", "no", "н", "нет", "0", "q", "quit")) {
        return $false
    }
    if ($value -match '^[yYдД]') {
        return $true
    }
    Write-Warn "Неизвестный ответ, копируем .env."
    return $true
}

function Ensure-DotEnv {
    $envFile = Join-Path $Root ".env"
    $localExample = Join-Path $Root ".env.local.example"
    if (Test-Path $envFile) {
        return
    }

    Write-Warn "Файл .env не найден."
    if (-not (Test-Path $localExample)) {
        throw "Нет .env.local.example. Создайте .env вручную и повторите."
    }

    $interactive = $true
    try {
        $interactive = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
    } catch {}
    if (-not $interactive) {
        throw "Нет .env и нет интерактивного ввода. Скопируйте .env.local.example в .env вручную."
    }

    if (-not (Confirm-Yes "Скопировать .env.local.example в .env и продолжить?")) {
        throw "Прервано: без .env скрипт не запускает инфраструктуру."
    }

    Copy-Item $localExample $envFile
    Write-Info "Создан .env из .env.local.example."
}

function Resolve-StartMode([string]$Raw) {
    $value = $Raw.Trim().ToLowerInvariant()
    if ($value -in @("1", "local", "dev", "--local")) { return "local" }
    if ($value -in @("2", "deploy", "--deploy")) { return "deploy" }
    if ($value -in @("3", "dual", "emulator", "chrome", "emulator-chrome", "--dual")) { return "dual" }
    if ($value -in @("0", "exit", "q", "quit", "--exit")) { return "exit" }
    return $null
}

function Choose-Mode {
    if ($Mode) {
        $parsed = Resolve-StartMode $Mode
        if (-not $parsed) {
            throw "Неизвестный режим '$Mode'. Используйте local, deploy, dual или exit."
        }
        return $parsed
    }

    Write-Host ""
    Write-Host "Music Anti Blur" -ForegroundColor Green
    Write-Host "Режим:"
    Write-Host "  [1] Локальная разработка   (по умолчанию, Enter)"
    Write-Host "  [2] Развертывание"
    Write-Host "  [3] Эмулятор Android + Chrome"
    Write-Host "  [0] Выход"
    $choice = Read-Host "Выбор [1]"
    if ([string]::IsNullOrWhiteSpace($choice)) {
        return "local"
    }
    $parsed = Resolve-StartMode $choice
    if ($parsed) {
        return $parsed
    }
    Write-Warn "Неизвестный пункт, берём локальную разработку."
    return "local"
}

function Start-Infra {
    Write-Info "Docker Compose: Postgres, Redis, MailHog, MinIO..."
    docker info 1>$null 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Docker не запущен. Откройте Docker Desktop и повторите."
    }

    docker compose --env-file .env up -d
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose up не удался."
    }

    Write-Info "Ждём healthy у Postgres, Redis и MinIO..."
    $deadline = (Get-Date).AddSeconds(90)
    do {
        $pgId = docker compose ps -q postgres
        $rdId = docker compose ps -q redis
        $mnId = docker compose ps -q minio
        if ($pgId -and $rdId -and $mnId) {
            $pg = docker inspect --format "{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}" $pgId
            $rd = docker inspect --format "{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}" $rdId
            $mn = docker inspect --format "{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}" $mnId
            if ($pg -eq "healthy" -and $rd -eq "healthy" -and $mn -eq "healthy") {
                return
            }
        }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)

    throw "Postgres/Redis/MinIO не стали healthy за 90 с. docker compose ps"
}

function Wait-Api {
    Write-Info "Ждём API $HealthUrl ..."
    $deadline = (Get-Date).AddSeconds(90)
    do {
        try {
            $r = Invoke-WebRequest -Uri $HealthUrl -UseBasicParsing -TimeoutSec 2
            if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 300) {
                Write-Info "API отвечает."
                return
            }
        } catch {
            Start-Sleep -Seconds 2
        }
    } while ((Get-Date) -lt $deadline)

    throw "API не ответил на $HealthUrl за 90 с. Смотрите окно/лог API."
}

function Start-ApiLocal {
    New-Item -ItemType Directory -Force -Path $RunDir | Out-Null
    Write-Info "Запуск API (Development) в отдельном окне..."
    $cmd = @"
`$Host.UI.RawUI.WindowTitle = 'Music Anti Blur — API'
Set-Location -LiteralPath '$Root'
`$env:ASPNETCORE_ENVIRONMENT='Development'
dotnet run --project '$ApiProject'
"@
    $proc = Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoExit", "-Command", $cmd) -PassThru
    Set-Content -Path (Join-Path $RunDir "api.pid") -Value $proc.Id -Encoding ASCII
}

function Start-ApiDeploy {
    New-Item -ItemType Directory -Force -Path $RunDir | Out-Null
    $out = Join-Path $RunDir "api"
    Write-Info "dotnet publish -c Release -> $out"
    dotnet publish $ApiProject -c Release -o $out --nologo
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet publish не удался."
    }

    Write-Info "Запуск API (Production) в отдельном окне..."
    $dll = Join-Path $out "MusicAntiBlur.Api.dll"
    $cmd = @"
`$Host.UI.RawUI.WindowTitle = 'Music Anti Blur — API'
Set-Location -LiteralPath '$Root'
`$env:ASPNETCORE_ENVIRONMENT='Production'
dotnet '$dll'
"@
    $proc = Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoExit", "-Command", $cmd) -PassThru
    Set-Content -Path (Join-Path $RunDir "api.pid") -Value $proc.Id -Encoding ASCII
}

function ConvertFrom-FlutterMachineJson([string]$Raw) {
    if ([string]::IsNullOrWhiteSpace($Raw)) {
        return @()
    }
    $arrayStart = $Raw.IndexOf('[')
    $arrayEnd = $Raw.LastIndexOf(']')
    if ($arrayStart -lt 0 -or $arrayEnd -le $arrayStart) {
        return @()
    }
    try {
        $parsed = $Raw.Substring($arrayStart, $arrayEnd - $arrayStart + 1) | ConvertFrom-Json
    } catch {
        return @()
    }
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($item in @($parsed)) {
        if ($null -ne $item) {
            [void]$list.Add($item)
        }
    }
    if ($list.Count -eq 0) {
        return @()
    }
    return , $list.ToArray()
}

function Get-FlutterMachineJson([string[]]$FlutterArgs) {
    $raw = & flutter @FlutterArgs 2>$null | Out-String
    ConvertFrom-FlutterMachineJson $raw
}

function Get-FlutterDeviceId([object]$Device) {
    if ($null -eq $Device) {
        return $null
    }
    $rawId = $Device.id
    if ($rawId -is [System.Array]) {
        return $null
    }
    $id = [string]$rawId
    if ([string]::IsNullOrWhiteSpace($id) -or $id -match '\s') {
        return $null
    }
    return $id
}

function Get-FlutterDeviceList {
    $items = Get-FlutterMachineJson @("devices", "--machine")
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($item in @($items)) {
        if ($null -ne $item) {
            [void]$list.Add($item)
        }
    }
    if ($list.Count -eq 0) {
        return @()
    }
    return , $list.ToArray()
}

function Test-ChromeDevicePresent {
    foreach ($device in (Get-FlutterDeviceList)) {
        if ((Get-FlutterDeviceId $device) -eq "chrome") {
            return $true
        }
    }
    return $false
}

function Get-AndroidEmulatorDeviceId {
    foreach ($device in (Get-FlutterDeviceList)) {
        $id = Get-FlutterDeviceId $device
        if ($id -match '^emulator-\d+$') {
            return $id
        }
        $platform = [string]$device.targetPlatform
        if ($id -and $platform -like "android*" -and $device.emulator -eq $true) {
            return $id
        }
    }
    return $null
}

function Assert-ChromeDevice {
    if (Test-ChromeDevicePresent) {
        return
    }
    throw "В flutter devices нет chrome. Нужен Google Chrome и включённый web: flutter config --enable-web."
}

function Start-AndroidEmulatorIfNeeded {
    if (Get-AndroidEmulatorDeviceId) {
        Write-Info "Android-эмулятор уже запущен."
        return
    }

    $avds = @()
    foreach ($avd in (Get-FlutterMachineJson @("emulators", "--machine"))) {
        $blob = "$($avd.id) $($avd.name) $($avd.platform) $($avd.platformType) $($avd.category)"
        if ($blob -match "android|pixel") {
            $avds += $avd
        }
    }
    if ($avds.Count -eq 0) {
        throw "Нет Android-эмулятора (AVD). Создайте его в Android Studio, затем flutter emulators."
    }

    $avdId = Get-FlutterDeviceId $avds[0]
    if (-not $avdId) {
        throw "Не удалось прочитать id Android-эмулятора из flutter emulators --machine."
    }
    Write-Info "Запускаем эмулятор $avdId..."
    flutter emulators --launch $avdId
    if ($LASTEXITCODE -ne 0) {
        throw "Не удалось запустить эмулятор $avdId."
    }
}

function Wait-AndroidEmulatorDevice {
    Write-Info "Ждём Android-эмулятор в flutter devices..."
    $deadline = (Get-Date).AddSeconds(120)
    do {
        $id = Get-AndroidEmulatorDeviceId
        if ($id) {
            Write-Info "Эмулятор: $id"
            return $id
        }
        Start-Sleep -Seconds 3
    } while ((Get-Date) -lt $deadline)

    throw "Эмулятор не появился в flutter devices за 120 с."
}

function Start-PowerShellWindow([string]$Title, [string]$PidName, [string]$ScriptBody) {
    New-Item -ItemType Directory -Force -Path $RunDir | Out-Null
    $safeName = ($PidName -replace '\.pid$', '' -replace '[^\w.-]', '-')
    $runner = Join-Path $RunDir "$safeName.ps1"
    Set-Content -Path $runner -Value $ScriptBody -Encoding UTF8
    $proc = Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoExit", "-NoProfile", "-File", $runner) -PassThru
    Set-Content -Path (Join-Path $RunDir $PidName) -Value $proc.Id -Encoding ASCII
}

function Start-FlutterWindow([string]$Title, [string]$DeviceId, [string]$PidName, [bool]$RunPubGet) {
    $titleEsc = $Title.Replace("'", "''")
    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add("`$Host.UI.RawUI.WindowTitle = '$titleEsc'")
    [void]$lines.Add("Set-Location -LiteralPath '$MobileDir'")
    if ($RunPubGet) {
        [void]$lines.Add("flutter pub get")
        [void]$lines.Add("if (`$LASTEXITCODE -ne 0) { Write-Host 'flutter pub get не удался.' -ForegroundColor Red; pause; exit `$LASTEXITCODE }")
    }
    if ($DeviceId) {
        [void]$lines.Add("flutter run --device-id=$DeviceId")
    } else {
        [void]$lines.Add("flutter run")
    }
    Start-PowerShellWindow -Title $Title -PidName $PidName -ScriptBody ($lines -join "`r`n")
}

function Start-FlutterDev {
    param([string[]]$DeviceIds = @())

    New-Item -ItemType Directory -Force -Path $RunDir | Out-Null
    if ($DeviceIds.Count -eq 0) {
        Write-Info "Запуск Flutter в отдельном окне..."
        $deviceId = $env:FLUTTER_DEVICE
        Start-FlutterWindow -Title "Music Anti Blur — Flutter" -DeviceId $deviceId -PidName "flutter.pid" -RunPubGet $true
        return
    }

    Write-Info "flutter pub get..."
    Push-Location $MobileDir
    try {
        flutter pub get
        if ($LASTEXITCODE -ne 0) {
            throw "flutter pub get не удался."
        }
    } finally {
        Pop-Location
    }

    foreach ($id in $DeviceIds) {
        if ($id -match '\s') {
            throw "Некорректный id устройства Flutter: '$id'."
        }
        Write-Info "Запуск Flutter ($id) в отдельном окне..."
        $safe = $id -replace '[^\w.-]', '-'
        Start-FlutterWindow -Title "Music Anti Blur — Flutter ($id)" -DeviceId $id -PidName "flutter-$safe.pid" -RunPubGet $false
    }
}

Assert-Command docker
Assert-Command dotnet
Assert-Command flutter

$selected = Choose-Mode
if ($selected -eq "exit") {
    Write-Info "Выход."
    exit 0
}

Ensure-DotEnv

Write-Host ""
if ($selected -eq "local") {
    Write-Info "Режим: локальная разработка"
} elseif ($selected -eq "dual") {
    Write-Info "Режим: эмулятор Android + Chrome"
    Assert-ChromeDevice
    Start-AndroidEmulatorIfNeeded
} else {
    Write-Info "Режим: развертывание (Release API + Flutter hot reload)"
    Write-Warn "Production без смены Jwt/паролей из .env.example небезопасен."
}

Start-Infra

if ($selected -eq "deploy") {
    Start-ApiDeploy
} else {
    Start-ApiLocal
}

Wait-Api

if ($selected -ne "deploy") {
    $seedScript = Join-Path $DevopsRoot "seed-local-music.ps1"
    Write-Info "После API: импорт no_commit/music (минимум 4 трека из каждой папки)..."
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File $seedScript -ApiBase "http://127.0.0.1:5080"
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Импорт no_commit/music завершился с кодом $LASTEXITCODE. Flutter всё равно запускаем."
    }
}

if ($selected -eq "dual") {
    $emulatorId = Wait-AndroidEmulatorDevice
    Start-FlutterDev -DeviceIds @("chrome", $emulatorId)
} else {
    Start-FlutterDev
}

Write-Host ""
Write-Host "HTTP API     http://127.0.0.1:5080" -ForegroundColor DarkGray
Write-Host "Swagger      http://127.0.0.1:5080/swagger  (только Development)" -ForegroundColor DarkGray
Write-Host "MailHog      http://127.0.0.1:8025" -ForegroundColor DarkGray
Write-Host "MinIO S3     http://127.0.0.1:9000" -ForegroundColor DarkGray
Write-Host "MinIO UI     http://127.0.0.1:9001  (minio / minio-local-only)" -ForegroundColor DarkGray
Write-Host "Hangfire     http://127.0.0.1:5080/hangfire" -ForegroundColor DarkGray
Write-Info "API и Flutter запущены в отдельных окнах. Остановка: devops\stop.cmd"
