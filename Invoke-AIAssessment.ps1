param([ValidateSet("ES","EN")] [string]$Language="ES",[string]$OutDir=".\out")
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function GB([double]$b){ [math]::Round($b/1GB,2) }

$os=Get-CimInstance Win32_OperatingSystem
$cpu=Get-CimInstance Win32_Processor | Select-Object -First 1
$gpus=Get-CimInstance Win32_VideoController
$disks=Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"

$ramGB=GB(([double]$os.TotalVisibleMemorySize)*1KB)
$gpuList=@()
foreach($g in $gpus){
  $gpuList += [pscustomobject]@{
    name=$g.Name; driver=$g.DriverVersion; vramGB=if($g.AdapterRAM){GB([double]$g.AdapterRAM)}else{0}
  }
}
$maxVram=if($gpuList.Count -gt 0){($gpuList|Measure-Object vramGB -Maximum).Maximum}else{0}
$mainDisk=$disks|Where-Object{$_.DeviceID -eq $env:SystemDrive}|Select-Object -First 1
if(-not $mainDisk){$mainDisk=$disks|Select-Object -First 1}
$diskFree=if($mainDisk){GB([double]$mainDisk.FreeSpace)}else{0}

$score=0
if($ramGB -ge 16){$score+=35}elseif($ramGB -ge 8){$score+=20}
if($maxVram -ge 8){$score+=40}elseif($maxVram -ge 4){$score+=20}
if([int]$cpu.NumberOfCores -ge 8){$score+=15}elseif([int]$cpu.NumberOfCores -ge 4){$score+=10}
if($diskFree -ge 40){$score+=10}elseif($diskFree -ge 20){$score+=5}
if($score -gt 100){$score=100}

$tier=if($score -ge 80){"Local Pro"}elseif($score -ge 60){"Local Basic"}else{"Enterprise Online"}
$flag=if($score -ge 80){"GREEN"}elseif($score -ge 60){"YELLOW"}else{"RED"}
$flagColor=if($flag -eq "GREEN"){"#16a34a"}elseif($flag -eq "YELLOW"){"#ca8a04"}else{"#dc2626"}

$local=@("gemma:2b","gemma:7b","llama3:8b","mistral:7b","phi-3-mini")
$ent=@("deepseek-r1","deepseek-v3","gpt-4.1","claude-sonnet","gemini-1.5-pro")

$report=[pscustomobject]@{
  generated_at=(Get-Date).ToString("s")
  language=$Language
  score=$score
  tier=$tier
  semaforo=$flag
  system=[pscustomobject]@{
    os=$os.Caption
    arch=$os.OSArchitecture
    cpu=$cpu.Name.Trim()
    cores=[int]$cpu.NumberOfCores
    threads=[int]$cpu.NumberOfLogicalProcessors
    ram_gb=$ramGB
    max_vram_gb=$maxVram
    disk_free_gb=$diskFree
    gpus=$gpuList
  }
  local_candidates=$local
  enterprise_candidates=$ent
}

$json=Join-Path $OutDir "report.json"
$html=Join-Path $OutDir "report.html"
$report | ConvertTo-Json -Depth 10 | Out-File -Encoding utf8 $json

$gpuRows=($gpuList|ForEach-Object{"<tr><td>$($_.name)</td><td>$($_.driver)</td><td>$($_.vramGB)</td></tr>"}) -join ""
if(-not $gpuRows){$gpuRows="<tr><td colspan='3'>No GPU data</td></tr>"}
$localList=($local|ForEach-Object{"<li>$_</li>"}) -join ""
$entList=($ent|ForEach-Object{"<li>$_</li>"}) -join ""

$h=@"
<!doctype html><html><head><meta charset='utf-8'><title>AI Readiness Report</title>
<style>
body{font-family:Segoe UI,Arial;background:#0f172a;color:#e5e7eb;margin:0}
.wrap{max-width:1100px;margin:24px auto;padding:0 16px}
.card{background:#111827;border:1px solid #374151;border-radius:12px;padding:14px;margin-bottom:12px}
.grid{display:grid;grid-template-columns:repeat(4,1fr);gap:10px}
.kpi{font-size:26px;font-weight:700}
.muted{color:#9ca3af;font-size:12px}
table{width:100%;border-collapse:collapse}th,td{border:1px solid #374151;padding:8px}th{background:#1f2937}
.badge{display:inline-block;padding:7px 12px;border-radius:999px;color:#fff;font-weight:700;background:$flagColor}
</style></head><body><div class='wrap'>
<h1>AI Readiness Audit - Professional</h1>
<p><span class='badge'>$flag - $tier</span> Score: <b>$score/100</b></p>

<div class='grid'>
  <div class='card'><div class='kpi'>$ramGB GB</div><div class='muted'>RAM</div></div>
  <div class='card'><div class='kpi'>$maxVram GB</div><div class='muted'>Max VRAM</div></div>
  <div class='card'><div class='kpi'>$diskFree GB</div><div class='muted'>Disk Free</div></div>
  <div class='card'><div class='kpi'>$([int]$cpu.NumberOfCores)</div><div class='muted'>CPU Cores</div></div>
</div>

<div class='card'>
<h2>Executive Summary</h2>
<p><b>Recommendation:</b> $tier</p>
<p><b>OS:</b> $($os.Caption) ($($os.OSArchitecture))</p>
<p><b>CPU:</b> $($cpu.Name.Trim()) | Cores: $([int]$cpu.NumberOfCores) | Threads: $([int]$cpu.NumberOfLogicalProcessors)</p>
</div>

<div class='card'>
<h2>GPU Inventory</h2>
<table><thead><tr><th>GPU</th><th>Driver</th><th>VRAM (GB)</th></tr></thead><tbody>$gpuRows</tbody></table>
</div>

<div class='card'><h2>Local candidates</h2><ul>$localList</ul></div>
<div class='card'><h2>Enterprise online candidates</h2><ul>$entList</ul></div>

<p class='muted'>Generated: $(Get-Date)</p>
</div></body></html>
"@
$h | Out-File -Encoding utf8 $html

Write-Host "OK -> $json"
Write-Host "OK -> $html"
