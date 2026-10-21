#!/usr/bin/env bash
# 《六族遠征》／《氏族爭霸》一鍵檢查（Linux / macOS）
# 用法：tools/check.sh [Godot 執行檔路徑]   （或設定環境變數 GODOT）
set -u
GODOT="${1:-${GODOT:-godot}}"
cd "$(dirname "$0")/.."
mkdir -p build
fail() { echo "✗ $1"; exit 1; }

echo "[1/5] 匯入資源、建立類別快取並檢查所有腳本能否解析…"
"$GODOT" --headless --path . --import > build/check_import.log 2>&1
if grep -E "SCRIPT ERROR|Parse Error|Failed to load|Failed loading resource" build/check_import.log; then
  fail "匯入時有腳本解析或資源載入錯誤（完整紀錄：build/check_import.log）"
fi

echo "[2/5] 規則、經濟、戰鬥、24 技能、存檔、場景載入自動測試…"
"$GODOT" --headless --path . --script res://tests/run_tests.gd 2>&1 | tee build/check_tests.log
[ "${PIPESTATUS[0]}" -eq 0 ] || fail "自動測試未通過（build/check_tests.log）"

echo "[3/5] 實際開啟場景並模擬操作的冒煙測試…"
"$GODOT" --headless --path . res://tests/smoke_test.tscn 2>&1 | tee build/check_smoke.log
[ "${PIPESTATUS[0]}" -eq 0 ] || fail "冒煙測試未通過（build/check_smoke.log）"
if grep -E "SCRIPT ERROR" build/check_smoke.log; then
  fail "冒煙測試期間出現腳本錯誤"
fi

echo "[4/5] 《氏族爭霸》10 人 PvPvE 規則測試（棋池、配對、交易、援軍、制度、淘汰、完整對局）…"
"$GODOT" --headless --path . --script res://tests/clash_tests.gd 2>&1 | tee build/check_clash_tests.log
[ "${PIPESTATUS[0]}" -eq 0 ] || fail "《氏族爭霸》測試未通過（build/check_clash_tests.log）"

echo "[5/5] 《氏族爭霸》畫面冒煙測試…"
"$GODOT" --headless --path . res://tests/clash_smoke_test.tscn 2>&1 | tee build/check_clash_smoke.log
[ "${PIPESTATUS[0]}" -eq 0 ] || fail "《氏族爭霸》冒煙測試未通過（build/check_clash_smoke.log）"
if grep -E "SCRIPT ERROR" build/check_clash_smoke.log; then
  fail "《氏族爭霸》冒煙測試期間出現腳本錯誤"
fi

echo ""
echo "✓ 全部檢查通過"
