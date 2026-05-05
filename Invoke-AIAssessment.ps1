param(
  [ValidateSet("ES","EN")] [string]$Language = "ES",
  [string]$OutDir = ".\out"
)

function GB([double]$b) { [math]::Round($b / 1GB, 2) }

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$os   = Get-CimInstance Win32_OperatingSystem
$cpu  = Get-CimInstance Win32_Processor | Select-Object -First 1
$gpu  = Get-CimInstance Win32_VideoController | Select-Object -First 1
$disk = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | Where-Object { $_.DeviceID -eq $env:SystemDrive } | Select-Object -First 1

$ramGB      = GB(([double]$os.TotalVisibleMemorySize) * 1KB)
$vramGB     = if ($gpu -and $gpu.AdapterRAM) { GB([double]$gpu.AdapterRAM) } else { 0 }
$diskFreeGB = if ($disk) { GB([double]$disk.FreeSpace) } else { 0 }

$localScore = 0
if ($ramGB -ge 16) { $localScore += 35 } elseif ($ramGB -ge 8) { $localScore += 20 }
if ($vramGB -ge 8) { $localScore += 40 } elseif ($vramGB -ge 4) { $localScore += 20 }
if ([int]$cpu.NumberOfCores -ge 8) { $localScore += 15 } elseif ([int]$cpu.NumberOfCores -ge 4) { $localScore += 10 }
if ($diskFreeGB -ge 40) { $localScore += 10 } elseif ($diskFreeGB -ge 20) { $localScore += 5 }
if ($localScore -gt 100) { $localScore = 100 }

$localTier = if ($localScore -ge 80) { "Local Pro" } elseif ($localScore -ge 60) { "Local Basic" } else { "Enterprise Online" }
$semaforo  = if ($localScore -ge 80) { "GREEN" } elseif ($localScore -ge 60) { "YELLOW" } else { "RED" }

$enterpriseModels = @("deepseek-r1","deepseek-v3","gpt-4.1","claude-sonnet","gemini-1.5-pro")
$localModels      = @("gemma:2b","gemma:7b","llama3:8b","mistral:7b","phi-3-mini")

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
    score = $localScore
    semaforo = $semaforo
    recommendation = $localTier
    local_candidates = $localModels
    enterprise_candidates = $enterpriseModels
  }
}

$jsonPath = Join-Path $OutDir "report.json"
$htmlPath = Join-Path $OutDir "report.html"

$report | ConvertTo-Json -Depth 8 | Out-File -Encoding utf8 $jsonPath

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
<p><b>Score:</b> $localScore / 100 ($semaforo)</p>
<p><b>Recommendation:</b> $localTier</p>
<p><b>CPU:</b> $($cpu.Name.Trim())</p>
<p><b>RAM:</b> $ramGB GB</p>
<p><b>GPU:</b> $(if($gpu){$gpu.Name}else{"Unknown"}) ($vramGB GB)</p>
<p><b>Disk free:</b> $diskFreeGB GB</p>
</div>
<h2>Local candidates</h2>
<ul><li>$($localModels -join "</li><li>")</li></ul>
<h2>Enterprise online candidates</h2>
<ul><li>$($enterpriseModels -join "</li><li>")</li></ul>
</body>
</html>
"@

$html | Out-File -Encoding utf8 $htmlPath

Write-Host "OK -> $jsonPath"
Write-Host "OK -> $htmlPath"
