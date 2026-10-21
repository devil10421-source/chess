# 《六族遠征》／《氏族爭霸》一鍵檢查（Windows PowerShell）
# 用法：powershell -ExecutionPolicy Bypass -File tools\check.ps1 "C:\Godot\Godot_v4.7.2-stable_win64_console.exe"
param([string]$Godot = $(if ($env:GODOT) { $env:GODOT } else { "godot" }))
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Continue"
Set-Location (Join-Path $PSScriptRoot "..")
New-Item -ItemType Directory -Force -Path build | Out-Null

function Fail($msg) { Write-Host "✗ $msg" -ForegroundColor Red; exit 1 }

Write-Host "[1/5] 匯入資源、建立類別快取並檢查所有腳本能否解析…"
& $Godot --headless --path . --import *> build\check_import.log
$bad = Select-String -Path build\check_import.log -Pattern "SCRIPT ERROR|Parse Error|Failed to load|Failed loading resource"
if ($bad) { $bad | ForEach-Object { Write-Host $_.Line }; Fail "匯入時有腳本解析或資源載入錯誤（build\check_import.log）" }

Write-Host "[2/5] 規則、經濟、戰鬥、24 技能、存檔、場景載入自動測試…"
& $Godot --headless --path . --script res://tests/run_tests.gd *>&1 | Tee-Object -FilePath build\check_tests.log
if ($LASTEXITCODE -ne 0) { Fail "自動測試未通過（build\check_tests.log）" }

Write-Host "[3/5] 實際開啟場景並模擬操作的冒煙測試…"
& $Godot --headless --path . res://tests/smoke_test.tscn *>&1 | Tee-Object -FilePath build\check_smoke.log
if ($LASTEXITCODE -ne 0) { Fail "冒煙測試未通過（build\check_smoke.log）" }
if (Select-String -Path build\check_smoke.log -Pattern "SCRIPT ERROR") { Fail "冒煙測試期間出現腳本錯誤" }

Write-Host "[4/5] 《氏族爭霸》10 人 PvPvE 規則測試…"
& $Godot --headless --path . --script res://tests/clash_tests.gd *>&1 | Tee-Object -FilePath build\check_clash_tests.log
if ($LASTEXITCODE -ne 0) { Fail "《氏族爭霸》測試未通過（build\check_clash_tests.log）" }

Write-Host "[5/5] 《氏族爭霸》畫面冒煙測試…"
& $Godot --headless --path . res://tests/clash_smoke_test.tscn *>&1 | Tee-Object -FilePath build\check_clash_smoke.log
if ($LASTEXITCODE -ne 0) { Fail "《氏族爭霸》冒煙測試未通過（build\check_clash_smoke.log）" }
if (Select-String -Path build\check_clash_smoke.log -Pattern "SCRIPT ERROR") { Fail "《氏族爭霸》冒煙測試期間出現腳本錯誤" }

Write-Host ""
Write-Host "✓ 全部檢查通過" -ForegroundColor Green
