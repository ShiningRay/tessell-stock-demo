# One-shot quality gate: specs -> build -> 2-frame screenshot smoke.
# Requires Windows + msys2 ucrt64 + Crystal 1.22.
$ErrorActionPreference = "Stop"

$env:PATH = "C:\msys64\ucrt64\bin;$env:PATH"
Set-Location (Split-Path $PSScriptRoot -Parent)
New-Item -ItemType Directory -Force -Path bin, docs | Out-Null

Write-Host "== shards install =="
shards install
if ($LASTEXITCODE -ne 0) { throw "shards install failed" }

Write-Host "== crystal spec =="
crystal spec
if ($LASTEXITCODE -ne 0) { throw "crystal spec failed" }

Write-Host "== crystal build =="
crystal build src/stock_demo.cr -o bin/stock_demo.exe
if ($LASTEXITCODE -ne 0) { throw "crystal build failed" }

Write-Host "== screenshot smoke =="
$shot = "docs\.gate.tsraw"
Remove-Item -Force $shot -ErrorAction SilentlyContinue
$output = & .\bin\stock_demo.exe --frames=2 --warmup=20 --screenshot=$shot 2>&1
$output | Write-Host
if ($LASTEXITCODE -ne 0) { throw "stock demo smoke run failed" }
if (-not (Test-Path $shot)) { throw "smoke screenshot missing" }
if ((Get-Item $shot).Length -lt 100000) { throw "smoke screenshot too small" }
Remove-Item -Force $shot

Write-Host "GATE PASS"
