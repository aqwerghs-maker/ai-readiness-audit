param(
  [ValidateSet("ES","EN")] [string]$Language = "ES",
  [string]$OutDir = ".\out",
  [int]$HfCacheTtlHours = 24
)

function GB([double]$b) { [math]::Round($b / 1GB, 2) }

function Get-DynamicLocalModels {
  param([int]$TtlHours = 24)

  $cacheDir = ".\.cache"
  New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
  $cacheFile = Join-Path $cacheDir "hf-local-models.json"
  $fallbackFile = ".\config\curated-local-fallback.json"

  $useCache = $false
  if (Test-Path $cacheFile) {
    $age = (Get-Date) - (Get-Item $cacheFile).LastWriteTime
    if ($age.TotalHours -lt $TtlHours) { $useCache = $true }
  }

  if ($useCache) {
    return (Get-Content $cacheFile -Raw | ConvertFrom-Json)
  }

  try {
    $url = "https://huggingface.co/api/models?pipeline_tag=text-generation&sort=downloads&direction=-1&limit=120"
    $resp = Invoke-RestMethod -Uri $url -Method GET -TimeoutSec 25

    $models = $resp | Where-Object {
      $_.id -match "gguf|gemma|llama|mistral|phi|qwen"
    } | Select-Object -First 40 | ForEach-Object {
      [pscustomobject]@{
        name = $_.id
        minRAMGB = 16
        minVRAMGB = 8
        minDiskGB = 40
      }
    }

    $obj = [pscustomobject]@{
      source = "dynamic_hf"
      refreshed_at = (Get-Date).ToString("s")
      models = $models
    }

    $obj | ConvertTo-Json -Depth 8 | Out-File -Encoding UTF8 $cacheFile
    return $obj
  }
  catch {
    if (Test-Path $fallbackFile) {
      return (Get-Content $fallbackFile -Raw | ConvertFrom-Json)
    }
    return [pscustomobject]@{ source = "empty"; models = @() }
  }
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$os   = Get-CimInstance Win32_OperatingSystem
$cpu  = Get-CimInstance Win32_Processor | Select-Object -First 1
$gpu  = Get-CimInstance Win32_VideoController | Select-Object -First 1
$disk = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | Where-Object { $_.DeviceID -eq $env:SystemDrive } | Select-Object -First 1

$ramGB      = GB(([double]$os.TotalVisibleMemorySize) * 1KB)
$vramGB     = if ($gpu -and $gpu.AdapterRAM) { GB([double]$gpu.AdapterRAM) } else { 0 }
$diskFreeGB = if ($disk) { GB([double]$disk.FreeSpace) } else { 0 }

$score = 0
if ($ramGB -ge 16) { $score += 35 } elseif ($ramGB -ge 8) { $score += 20 }
if ($vramGB -ge 8) { $score += 40 } elseif ($vramGB -ge 4) { $score += 20 }
if ([int]$cpu.NumberOfCores -ge 8) { $score += 15 } elseif ([int]$cpu.NumberOfCores -ge 4) { $score += 10 }
if ($diskFreeGB -ge 40) { $score += 10 } elseif ($diskFreeGB -ge 20) { $score += 5 }
if ($score -gt 100) { $score = 100 }

$recommendation = if ($score -ge 80) { "Local Pro" } elseif ($score -ge 60) { "Local Basic" } else { "Enterprise Online" }
$semaforo = if ($score -ge 80) { "GREEN" } elseif ($score -ge 60) { "YELLOW" } else { "RED" }

$enterpriseModels = @("deepseek-r1","deepseek-v3","gpt-4.1","claude-sonnet","gemini-1.5-pro")
$dynamicCatalog = Get-DynamicLocalModels -TtlHours $HfCacheTtlHours

$report = [pscustomobject]@{
  generated_at = (Get-Date).ToString("s")
  language = $Language
  system = [pscustomobject]@{
    os = $os.Caption
    cpu = $cpu.Name.Trim()
    cores = [int]$cpu.NumberOfCores
    ram_gb = $ramGB
    gpu = if ($gpu) { $gpu.Name } else { "Unknown" }
    vram_gb = $vramGB
    disk_free_gb = $diskFreeGB
  }
  assessment = [pscustomobject]@{
    score = $score
    semaforo = $semaforo
    recommendation = $recommendation
    local_dynamic_source = $dynamicCatalog.source
    local_candidates = $dynamicCatalog.models
    enterprise_candidates = $enterpriseModels
  }
}

$jsonPath = Join-Path $OutDir "report.json"
$htmlPath = Join-Path $OutDir "report.html"

$report | ConvertTo-Json -Depth 10 | Out-File -Encoding UTF8 $jsonPath

$localListHtml = ""
if ($dynamicCatalog.models.Count -gt 0) {
  $names = $dynamicCatalog.models | Select-Object -First 20 | ForEach-Object { $_.name }
  $localListHtml = "<ul><li>" + ($names -join "</li><li>") + "</li></ul>"
} else {
  $localListHtml = "<p>No local models available.</p>"
}

$entListHtml = "<ul><li>" + ($enterpriseModels -join "</li><li>") + "</li></ul>"

$html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset='utf-8'>
<style>
body { font-family: Segoe UI, Arial; margin: 20px; }
.card { border: 1px solid #ddd; padding: 12px; border-radius: 8px; }
</style>
</head>
<body>
<h1>AI Readiness Audit</h1>
<div class='card'>
<p><b>Score:</b> $score / 100 ($semaforo)</p>
<p><b>Recommendation:</b> $recommendation</p>
<p><b>CPU:</b> $($cpu.Name.Trim())</p>
<p><b>RAM:</b> $ramGB GB</p>
<p><b>GPU:</b> $(if($gpu){$gpu.Name}else{"Unknown"}) ($vramGB GB)</p>
<p><b>Disk free:</b> $diskFreeGB GB</p>
<p><b>Local source:</b> $($dynamicCatalog.source)</p>
</div>

<h2>Local dynamic candidates</h2>
$localListHtml

<h2>Enterprise online candidates</h2>
$entListHtml
</body>
</html>
"@

$html | Out-File -Encoding UTF8 $htmlPath

Write-Host "OK -> $jsonPath"
Write-Host "OK -> $htmlPath"
