param([ValidateSet("ES","EN")] [string]$Language="ES",[string]$OutDir=".\out")
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$report = [pscustomobject]@{
  generated_at=(Get-Date).ToString("s")
  language=$Language
  status="ok"
  note="stable saved version"
}
$report | ConvertTo-Json -Depth 5 | Out-File -Encoding utf8 (Join-Path $OutDir "report.json")
"<html><body><h1>AI Readiness Audit</h1><p>Stable saved version</p></body></html>" | Out-File -Encoding utf8 (Join-Path $OutDir "report.html")
Write-Host "OK -> $OutDir\report.json"
Write-Host "OK -> $OutDir\report.html"
