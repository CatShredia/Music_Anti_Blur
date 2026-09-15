#Requires -Version 5.1
<#
.SYNOPSIS
  После старта API создаёт каталог из no_commit/music и заливает исходники (admin multipart).

  Каждая папка с аудио — минимум 4 трека (или все, если файлов меньше).
  Повторный запуск идемпотентен: готовые треки не заливаются снова.
#>
param(
    [string]$ApiBase = "http://127.0.0.1:5080",
    [string]$MusicRoot = "",
    [string]$Login = "admin",
    [string]$Password = "AdminPassword123",
    [int]$MinTracksPerFolder = 4
)

$ErrorActionPreference = "Stop"
try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
} catch {}

$DevopsRoot = $PSScriptRoot
$Root = Split-Path -Parent $DevopsRoot
if ([string]::IsNullOrWhiteSpace($MusicRoot)) {
    $MusicRoot = Join-Path $Root "no_commit\music"
}
$UploadScript = Join-Path $DevopsRoot "upload-catalog-source.ps1"
$AudioExt = @(".mp3", ".m4a", ".mp4", ".flac", ".wav", ".ogg", ".aac")
$NameMax = 200

function Write-Info([string]$Message) { Write-Host $Message -ForegroundColor Cyan }
function Write-Warn([string]$Message) { Write-Host $Message -ForegroundColor Yellow }

if (-not (Test-Path -LiteralPath $MusicRoot)) {
    Write-Warn "Нет $MusicRoot — локальные треки не импортируются."
    exit 0
}

if (-not (Test-Path -LiteralPath $UploadScript)) {
    throw "Не найден $UploadScript"
}

function Limit-Name([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return "Untitled" }
    $t = $Value.Trim()
    if ($t.Length -le $NameMax) { return $t }
    return $t.Substring(0, $NameMax)
}

function Get-AudioFiles([string]$Dir) {
    @(Get-ChildItem -LiteralPath $Dir -File -ErrorAction SilentlyContinue |
        Where-Object { $AudioExt -contains $_.Extension.ToLowerInvariant() } |
        Sort-Object Name)
}

function Select-FolderTracks([string]$Dir) {
    $files = @(Get-AudioFiles $Dir)
    if ($files.Count -eq 0) { return @() }
    if ($files.Count -lt $MinTracksPerFolder) {
        Write-Warn "В «$(Split-Path $Dir -Leaf)» только $($files.Count) аудио (ожидали минимум $MinTracksPerFolder). Берём все."
    }
    return @($files | Select-Object -First $MinTracksPerFolder)
}

function Split-ArtistFolder([string]$FolderName) {
    $idx = $FolderName.IndexOf(" - ")
    if ($idx -gt 0) {
        $artist = $FolderName.Substring(0, $idx).Trim()
        $album = $FolderName.Substring($idx + 3).Trim()
        foreach ($tag in @('iTunes', 'CD', 'WEB', 'FLAC', 'AAC', 'MP3', 'Vinyl')) {
            $open = ' (' + $tag
            $cut = $album.LastIndexOf($open)
            if ($cut -ge 0) {
                $album = $album.Substring(0, $cut).Trim()
                break
            }
        }
        return @{ Artist = $artist; Album = $album }
    }
    return @{ Artist = $FolderName; Album = $FolderName }
}

function Get-AlbumMeta([string]$FolderName, [string]$FallbackTitle) {
    if ($FolderName -match '^(\d{4})\s*-\s*(.+)$') {
        return @{ Title = $Matches[2].Trim(); Year = [int]$Matches[1] }
    }
    return @{ Title = $FallbackTitle; Year = $null }
}

function Get-TrackMeta([System.IO.FileInfo]$File, [int]$Index) {
    $base = [IO.Path]::GetFileNameWithoutExtension($File.Name)
    $number = $Index
    if ($base -match '^(\d{1,2})-(\d{2})\b') {
        $number = [int]$Matches[2]
        $base = $base.Substring($Matches[0].Length)
    }
    elseif ($base -match '^(\d{1,3})\.\s+') {
        $number = [int]$Matches[1]
        $base = $base.Substring($Matches[0].Length)
    }
    elseif ($base -match '^(\d{1,3})\s+-\s+') {
        $number = [int]$Matches[1]
        $base = $base.Substring($Matches[0].Length)
    }
    $base = $base.Trim(" .-_")
    if ([string]::IsNullOrWhiteSpace($base)) { $base = [IO.Path]::GetFileNameWithoutExtension($File.Name) }
    if ($number -lt 1) { $number = $Index }
    return @{ Title = (Limit-Name $base); TrackNumber = $number }
}

$script:Token = $null

function Connect-Admin {
    $loginBody = @{ identifierType = "login"; identifier = $Login; password = $Password } | ConvertTo-Json -Compress
    $session = Invoke-RestMethod -Method Post -Uri "$ApiBase/api/v1/auth/login" -ContentType "application/json" -Body $loginBody
    $script:Token = $session.accessToken
}

function Invoke-Api {
    param(
        [string]$Method,
        [string]$Url,
        $Body = $null,
        [string]$IdempotencyKey = ""
    )
    $attempt = 0
    while ($true) {
        $attempt++
        $headers = @{ Authorization = "Bearer $($script:Token)" }
        if (-not [string]::IsNullOrWhiteSpace($IdempotencyKey)) {
            $headers["Idempotency-Key"] = $IdempotencyKey
        }
        $params = @{ Method = $Method; Uri = $Url; Headers = $headers }
        if ($null -ne $Body) {
            $params.ContentType = "application/json"
            $params.Body = ($Body | ConvertTo-Json -Depth 6 -Compress)
        }
        try {
            return Invoke-RestMethod @params
        }
        catch {
            if ($attempt -ge 2) { throw }
            Connect-Admin
        }
    }
}

function Get-AllArtists {
    $all = @()
    $cursor = $null
    do {
        $url = "$ApiBase/api/v1/artists?limit=50"
        if ($cursor) { $url += "&cursor=$([uri]::EscapeDataString($cursor))" }
        $page = Invoke-Api -Method Get -Url $url
        $all += @($page.items)
        $cursor = $page.nextCursor
    } while ($cursor)
    return @($all)
}

function Get-OrCreateArtist([string]$Name) {
    $name = Limit-Name $Name
    $existing = Get-AllArtists | Where-Object { $_.name -eq $name } | Select-Object -First 1
    if ($existing) { return $existing.id }
    $created = Invoke-Api -Method Post -Url "$ApiBase/api/v1/admin/artists" -Body @{ name = $name }
    Write-Info "артист $name"
    return $created.id
}

function Get-OrCreateAlbum([string]$ArtistId, [string]$Title, $Year) {
    $title = Limit-Name $Title
    $artist = Invoke-Api -Method Get -Url "$ApiBase/api/v1/artists/$ArtistId"
    $existing = @($artist.albums) | Where-Object { $_.title -eq $title } | Select-Object -First 1
    if ($existing) { return $existing.id }
    $body = @{ artistId = $ArtistId; title = $title }
    if ($null -ne $Year) { $body.year = [int]$Year }
    $created = Invoke-Api -Method Post -Url "$ApiBase/api/v1/admin/albums" -Body $body
    Write-Info "альбом $title"
    return $created.id
}

function Get-OrCreateTrack([string]$AlbumId, [string]$ArtistId, [string]$Title, [int]$TrackNumber) {
    $title = Limit-Name $Title
    $album = Invoke-Api -Method Get -Url "$ApiBase/api/v1/albums/$AlbumId"
    $existing = @($album.tracks) | Where-Object { $_.title -eq $title } | Select-Object -First 1
    if ($existing) { return $existing.id }
    $created = Invoke-Api -Method Post -Url "$ApiBase/api/v1/admin/tracks" -Body @{
        albumId     = $AlbumId
        artistId    = $ArtistId
        title       = $title
        trackNumber = $TrackNumber
    }
    Write-Info "трек $title"
    return $created.id
}

function Test-TrackReady([string]$TrackId) {
    $track = Invoke-Api -Method Get -Url "$ApiBase/api/v1/tracks/$TrackId"
    return (@($track.availableQualities).Count -gt 0)
}

function Import-AlbumFiles {
    param(
        [string]$ArtistId,
        [string]$AlbumTitle,
        $Year,
        [System.IO.FileInfo[]]$Files
    )
    if (-not $Files -or $Files.Count -eq 0) { return @() }
    $albumId = Get-OrCreateAlbum $ArtistId $AlbumTitle $Year
    $ids = @()
    $n = 0
    foreach ($file in $Files) {
        $n++
        $meta = Get-TrackMeta $file $n
        $trackId = Get-OrCreateTrack $albumId $ArtistId $meta.Title $meta.TrackNumber
        if (Test-TrackReady $trackId) {
            Write-Host "skip ready $($meta.Title)"
            continue
        }
        Write-Info "upload $($file.Name) -> $($meta.Title)"
        try {
            & $UploadScript -Path $file.FullName -ApiBase $ApiBase -TrackId $trackId -AccessToken $script:Token -SkipReadyWait
        }
        catch {
            Connect-Admin
            & $UploadScript -Path $file.FullName -ApiBase $ApiBase -TrackId $trackId -AccessToken $script:Token -SkipReadyWait
        }
        $ids += $trackId
    }
    return @($ids)
}

Write-Info "Импорт из $MusicRoot"
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Write-Warn "ffmpeg не в PATH — Hangfire не соберёт качества. Установите FFmpeg и повторите."
}
Connect-Admin

$pending = @()
$artistDirs = @(Get-ChildItem -LiteralPath $MusicRoot -Directory | Sort-Object Name)
foreach ($artistDir in $artistDirs) {
    $split = Split-ArtistFolder $artistDir.Name
    $artistId = Get-OrCreateArtist $split.Artist
    $albumDirs = @(Get-ChildItem -LiteralPath $artistDir.FullName -Directory | Sort-Object Name |
        Where-Object { (Get-AudioFiles $_.FullName).Count -gt 0 })
    $direct = @(Select-FolderTracks $artistDir.FullName)

    if ($albumDirs.Count -gt 0) {
        foreach ($albumDir in $albumDirs) {
            $files = @(Select-FolderTracks $albumDir.FullName)
            $meta = Get-AlbumMeta $albumDir.Name $albumDir.Name
            $pending += @(Import-AlbumFiles -ArtistId $artistId -AlbumTitle $meta.Title -Year $meta.Year -Files $files)
        }
        if ($direct.Count -gt 0) {
            $pending += @(Import-AlbumFiles -ArtistId $artistId -AlbumTitle $split.Album -Year $null -Files $direct)
        }
    }
    else {
        if ($direct.Count -gt 0) {
            $pending += @(Import-AlbumFiles -ArtistId $artistId -AlbumTitle $split.Album -Year $null -Files $direct)
        }
    }
}

$pending = @($pending | Where-Object { $_ } | Select-Object -Unique)
if ($pending.Count -eq 0) {
    Write-Info "Новых загрузок нет (всё уже Ready или папки без аудио)."
    exit 0
}

if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Write-Warn "Загрузки приняты, но без ffmpeg транскод не завершится. Hangfire: $ApiBase/hangfire"
    exit 1
}

Write-Info "Ждём транскод Hangfire для $($pending.Count) трек(ов)..."
$deadline = (Get-Date).AddMinutes(15)
$left = @($pending)
while ($left.Count -gt 0 -and (Get-Date) -lt $deadline) {
    $still = @()
    foreach ($id in $left) {
        if (Test-TrackReady $id) {
            Write-Host "ready $id"
        }
        else {
            $still += $id
        }
    }
    $left = @($still)
    if ($left.Count -gt 0) {
        Start-Sleep -Seconds 3
    }
}

if ($left.Count -gt 0) {
    Write-Warn "Не дождались Ready: $($left -join ', '). Hangfire: $ApiBase/hangfire"
    exit 1
}

Write-Info "Локальные треки из no_commit/music готовы."
exit 0
