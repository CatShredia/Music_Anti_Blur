#Requires -Version 5.1
<#
.SYNOPSIS
  Admin multipart upload of a catalog source into MinIO, then Hangfire transcode.

.PARAMETER Path
  Local audio file (mp3/wav/flac/m4a/ogg).

.PARAMETER TrackId
  Catalog track id. Default: Neon Pulse seed.
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$Path,
    [string]$ApiBase = "http://127.0.0.1:5080",
    [string]$TrackId = "d1111111-1111-4111-8111-111111111111",
    [string]$Login = "admin",
    [string]$Password = "AdminPassword123"
)

$ErrorActionPreference = "Stop"
$file = Get-Item -LiteralPath $Path
$bytes = [System.IO.File]::ReadAllBytes($file.FullName)
$sha = [System.Security.Cryptography.SHA256]::Create()
$hash = [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace("-", "").ToLowerInvariant()
$ext = $file.Extension.ToLowerInvariant()
$contentType = switch ($ext) {
    ".mp3" { "audio/mpeg" }
    ".m4a" { "audio/mp4" }
    ".mp4" { "audio/mp4" }
    ".flac" { "audio/flac" }
    ".wav" { "audio/wav" }
    ".ogg" { "audio/ogg" }
    default { "application/octet-stream" }
}

$loginBody = @{ identifierType = "login"; identifier = $Login; password = $Password } | ConvertTo-Json
$session = Invoke-RestMethod -Method Post -Uri "$ApiBase/api/v1/auth/login" -ContentType "application/json" -Body $loginBody
$token = $session.accessToken
$headers = @{ Authorization = "Bearer $token"; "Idempotency-Key" = [guid]::NewGuid().ToString() }

$initBody = @{
    fileName = $file.Name
    sizeBytes = $file.Length
    contentType = $contentType
    checksumSha256 = $hash
} | ConvertTo-Json
$init = Invoke-RestMethod -Method Post -Uri "$ApiBase/api/v1/admin/tracks/$TrackId/uploads" -Headers $headers -ContentType "application/json" -Body $initBody
$generationId = $init.generationId
$partSize = [int64]$init.partSizeBytes
$partCount = [int]$init.partCount
Write-Host "generation $generationId parts $partCount x $partSize"

$etags = @()
for ($n = 1; $n -le $partCount; $n++) {
    $start = ($n - 1) * $partSize
    $len = [Math]::Min($partSize, $file.Length - $start)
    $partPath = Join-Path $env:TEMP ("mab-part-" + $generationId + "-$n.bin")
    $fs = [System.IO.File]::OpenRead($file.FullName)
    try {
        $null = $fs.Seek($start, "Begin")
        $buf = New-Object byte[] $len
        $read = $fs.Read($buf, 0, $len)
        $slice = New-Object byte[] $read
        [Array]::Copy($buf, $slice, $read)
        [System.IO.File]::WriteAllBytes($partPath, $slice)
    } finally {
        $fs.Close()
    }

    $partsHeaders = @{ Authorization = "Bearer $token" }
    $partsBody = "{`"partNumbers`":[$n]}"
    $parts = Invoke-RestMethod -Method Post -Uri "$ApiBase/api/v1/admin/tracks/$TrackId/uploads/$generationId/parts" -Headers $partsHeaders -ContentType "application/json" -Body $partsBody
    $url = $parts.parts[0].url
    $headerPath = Join-Path $env:TEMP ("mab-put-" + $generationId + "-$n.hdr")
    & curl.exe -sS -D $headerPath -o NUL -X PUT --data-binary "@$partPath" --url "$url"
    if ($LASTEXITCODE -ne 0) {
        throw "MinIO PUT part $n failed with exit $LASTEXITCODE"
    }
    $etagLine = Select-String -Path $headerPath -Pattern '(?i)^etag:' | Select-Object -First 1
    if (-not $etagLine) {
        throw "MinIO PUT part $n returned no ETag"
    }
    $etag = ($etagLine.Line -split ':', 2)[1].Trim()
    Remove-Item $headerPath -ErrorAction SilentlyContinue
    $etags += @{ partNumber = $n; etag = "$etag" }
    Remove-Item $partPath -ErrorAction SilentlyContinue
    Write-Host "uploaded part $n etag $etag"
}

$completeHeaders = @{ Authorization = "Bearer $token"; "Idempotency-Key" = [guid]::NewGuid().ToString() }
$completeBody = @{ parts = $etags } | ConvertTo-Json -Depth 5
$null = Invoke-RestMethod -Method Post -Uri "$ApiBase/api/v1/admin/tracks/$TrackId/uploads/$generationId/complete" -Headers $completeHeaders -ContentType "application/json" -Body $completeBody

$statusHeaders = @{ Authorization = "Bearer $token" }
for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Seconds 2
    $st = Invoke-RestMethod -Method Get -Uri "$ApiBase/api/v1/admin/tracks/$TrackId/uploads/$generationId" -Headers $statusHeaders
    Write-Host "status $($st.status)"
    if ($st.status -eq "ready") {
        $track = Invoke-RestMethod -Method Get -Uri "$ApiBase/api/v1/tracks/$TrackId" -Headers $statusHeaders
        Write-Host ($track.availableQualities | ConvertTo-Json -Compress)
        $play = Invoke-RestMethod -Method Post -Uri "$ApiBase/api/v1/tracks/$TrackId/playback-url" -Headers $statusHeaders -ContentType "application/json" -Body '{"sourcePreference":"catalog","qualityPreference":"auto","localAvailable":false}'
        Write-Host "playback $($play.resolvedQuality) $($play.url)"
        Write-Host "VLC: open the URL above. Range/expiry are signed query params."
        exit 0
    }
    if ($st.status -eq "failed" -or $st.status -eq "cancelled") {
        Write-Error "upload $($st.status): $($st.errorMessage)"
        exit 1
    }
}

Write-Error "timed out waiting for transcode"
exit 1
