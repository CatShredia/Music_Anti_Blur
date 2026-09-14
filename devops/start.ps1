#Requires -Version 5.1
<#
.SYNOPSIS
  Поднимает Postgres/Redis/MailHog/MinIO, API и Flutter (hot reload).

.PARAMETER Mode
  Пропустить меню: local | deploy | 1 | 2
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

function Ensure-DotEnv {
    $envFile = Join-Path $Root ".env"
    $example = Join-Path $Root ".env.example"
    if (-not (Test-Path $envFile)) {
        if (-not (Test-Path $example)) {
            throw "Нет .env и .env.example в корне репозитория."
        }
        Copy-Item $example $envFile
        Write-Warn "Создан .env из .env.example. Проверьте секреты перед продом."
    }
}

function Choose-Mode {
    if ($Mode) {
        $raw = $Mode.Trim().ToLowerInvariant()
        if ($raw -in @("1", "local", "dev", "--local")) { return "local" }
        if ($raw -in @("2", "deploy", "--deploy")) { return "deploy" }
        throw "Неизвестный режим '$Mode'. Используйте local или deploy."
    }

    Write-Host ""
    Write-Host "Music Anti Blur" -ForegroundColor Green
    Write-Host "Режим:"
    Write-Host "  [1] Локальная разработка   (по умолчанию, Enter)"
    Write-Host "  [2] Развертывание"
    $choice = Read-Host "Выбор [1]"
    if ([string]::IsNullOrWhiteSpace($choice) -or $choice -eq "1") { return "local" }
    if ($choice -eq "2") { return "deploy" }
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

function Start-FlutterDev {
    New-Item -ItemType Directory -Force -Path $RunDir | Out-Null
    Write-Info "Запуск Flutter в отдельном окне..."
    $deviceArg = ""
    if ($env:FLUTTER_DEVICE) {
        $deviceArg = " -d $($env:FLUTTER_DEVICE)"
    }
    $cmd = @"
`$Host.UI.RawUI.WindowTitle = 'Music Anti Blur — Flutter'
Set-Location -LiteralPath '$MobileDir'
flutter pub get
if (`$LASTEXITCODE -ne 0) { Write-Host 'flutter pub get не удался.' -ForegroundColor Red; pause; exit `$LASTEXITCODE }
flutter run$deviceArg
"@
    $proc = Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoExit", "-Command", $cmd) -PassThru
    Set-Content -Path (Join-Path $RunDir "flutter.pid") -Value $proc.Id -Encoding ASCII
}

Assert-Command docker
Assert-Command dotnet
Assert-Command flutter
Ensure-DotEnv

$selected = Choose-Mode
Write-Host ""
if ($selected -eq "local") {
    Write-Info "Режим: локальная разработка"
} else {
    Write-Info "Режим: развертывание (Release API + Flutter hot reload)"
    Write-Warn "Production без смены Jwt/паролей из .env.example небезопасен."
}

Start-Infra

if ($selected -eq "local") {
    Start-ApiLocal
} else {
    Start-ApiDeploy
}

Wait-Api
Start-FlutterDev

Write-Host ""
Write-Host "HTTP API     http://127.0.0.1:5080" -ForegroundColor DarkGray
Write-Host "Swagger      http://127.0.0.1:5080/swagger  (только Development)" -ForegroundColor DarkGray
Write-Host "MailHog      http://127.0.0.1:8025" -ForegroundColor DarkGray
Write-Host "MinIO S3     http://127.0.0.1:9000" -ForegroundColor DarkGray
Write-Host "MinIO UI     http://127.0.0.1:9001  (minio / minio-local-only)" -ForegroundColor DarkGray
Write-Host "Hangfire     http://127.0.0.1:5080/hangfire" -ForegroundColor DarkGray
Write-Info "API и Flutter запущены в отдельных окнах. Остановка: devops\stop.cmd"
