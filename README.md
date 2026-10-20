# 六族遠征 V0.1（Godot 4 版）

單機 PVE 自走棋原型：六大文明、24 回合、TFT 式 7×8 錯位六角棋盤、24 種棋子、三星合成、商店／利息／文明等級、三層羈絆、文明 Buff／Debuff、遠征生命。
引擎：**Godot 4.7.2 stable（GDScript）**，渲染器 Compatibility。架構與場景樹說明見 [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)。

---

## 1. 在 Godot 編輯器開啟與執行

1. 到 <https://godotengine.org/download/archive/4.7.2-stable/> 下載 **Godot 4.7.2 stable（標準版，非 .NET 版）**，解壓即可使用。
2. 開啟 Godot → 「匯入」→ 選這個資料夾裡的 `project.godot`。
3. 第一次開啟會自動匯入字型與圖示（幾秒鐘）。
4. 按右上角 ▶（或 F5）執行。從主選單開始。

> 在編輯器中執行屬於「除錯版」，頂端會出現「除錯」按鈕：選關、+20 金幣、文明 +1 級、直接過關。匯出的正式版不會出現。

## 2. 遊戲操作

| 動作 | 滑鼠／觸控 | 電腦快捷鍵 |
|---|---|---|
| 招募 | 點商店卡片 | — |
| 選取／查看 | 點棋子（敵方棋子也可點） | — |
| 移動 | 選取後點空格；或直接拖曳（拖到有棋子的格子＝互換） | — |
| 出售 | 拖到下方商店列；或選取後按「出售」 | E |
| 刷新商店 | 「刷新」 | D |
| 買經驗 | 「買經驗」 | F |
| 開始戰鬥／繼續 | 「開始戰鬥」 | 空白鍵 |
| 選單 | 「選單」 | Esc |

戰鬥中可切換 1×／2×／4× 速度或「略過動畫」（略過只跳過動畫，結果相同）。

## 3. 自動化檢查（確認沒有載入或解析錯誤）

一鍵執行三個步驟：① 匯入並解析所有腳本 ② 規則／戰鬥自動測試 ③ 實際開啟每個畫面並模擬點擊、拖曳、開戰、存讀檔的冒煙測試。

**Windows**（請用檔名有 `_console` 的 Godot 執行檔，才看得到輸出）：
```bat
tools\check.bat "C:\Godot\Godot_v4.7.2-stable_win64_console.exe"
```
**Linux / macOS**：
```bash
tools/check.sh /path/to/godot
```
最後出現 `✓ 全部檢查通過` 即代表成功；紀錄在 `build/check_*.log`。

也可以單獨執行：
```bash
godot --headless --path . --script res://tests/run_tests.gd        # 規則與戰鬥測試
godot --headless --path . res://tests/smoke_test.tscn              # 畫面冒煙測試
godot --headless --path . --script res://tests/balance_sim.gd -- --runs=20   # 難度模擬報表
```

測試涵蓋：所有腳本與場景可載入、資料完整性（24 棋子／6 文明／24 關）、六角距離與找路、商店機率總和 100% 與牌池（外族 4 費永不出現）、經濟／利息／出售、XP 與等級表、購買與金幣不為負、三合一與三星上限、上場人數上限、羈絆同名只計一次、文明修正實際影響數值、星級倍率、遠征扣血公式（含浮點誤差）、結算順序（死亡不觸發鹿角人恢復）、通關／未完成判定、人類免費刷新券、商店鎖定、戰鬥可重現、單位不重疊、**24 種技能都會在實戰中施放並產生效果**、存讀檔一致、六個文明各打一整局。

## 4. 匯出

在編輯器：「專案 → 匯出」，已預先建立以下設定（`export_presets.cfg`）：

| 預設 | 狀態 |
|---|---|
| **Windows Desktop** | 可直接匯出成單一 `SixTribes.exe`（資料已內嵌）。第一次需在匯出視窗按「管理匯出範本 → 下載並安裝」。 |
| Android | 已設定套件名稱 `com.sixtribes.expedition`、橫向、arm64；需在「編輯器設定 → 匯出 → Android」設定 Android SDK 與 debug keystore 後才能匯出。 |
| iOS | 已設定 Bundle ID；需在 macOS + Xcode 並填入 Apple Team ID 才能匯出。 |
| Linux（自動驗證用） | 用於在 Linux 上自動驗證匯出流程。 |

命令列匯出 Windows 版：
```bash
godot --headless --path . --export-release "Windows Desktop" build/windows/SixTribes.exe
```

專案沒有使用任何外掛、原生擴充或平台專屬 API；觸控透過「觸控模擬滑鼠」與滑鼠共用同一套操作，介面以 1280×720 為基準並自動延展到各種橫向比例（已測 16:9 與 20:9）。

## 5. 調整數值與美術

所有平衡數值都在 `data/`，改完重新執行即可，不必改程式：

| 檔案 | 內容 |
|---|---|
| `game_config.json` | 經濟、利息、XP 表、商店機率、星級倍率、稀有度基礎屬性、職業修正、戰鬥常數、敵方羈絆開關 |
| `units.json` | 24 棋子的種族／費用／類型／職業／射程／魔力與技能參數 |
| `civs.json` | 6 文明的 Buff／Debuff（以效果碼描述，文字可直接改） |
| `traits.json` | 種族／職業／類型羈絆門檻與效果 |
| `stages.json` | 24 關敵軍清單、星級、站位、亂數種子 |

改完建議跑一次 `tools/check` 與 `balance_sim.gd` 看難度曲線。

**美術替換**：把圖片放到 `assets/units/<棋子ID>/star1.png`、`star2.png`、`star3.png`（例如 `assets/units/ELF1/star1.png`），遊戲會自動改用圖片；沒有圖片的棋子維持幾何占位圖，不會出錯。建議透明底、正方形、512×512。

## 6. 存檔位置

- Windows：`%APPDATA%\Godot\app_userdata\六族遠征\save_v1.json`
- Android／iOS：App 私有資料夾

每次進入備戰與每次操作後自動存檔；主選單「繼續遠征」可接續。遠征結束（通關／失敗）後存檔自動清除。

## 7. 目前範圍

已完成企劃書第 1～4 階段。**第 5 階段（遠征徽記、2 費替代型態）尚未實作**，主選單只保留停用的入口。未加入多人連線、困難模式、無盡模式或其他未確認的玩法。

字型：Noto Sans CJK TC（SIL Open Font License 1.1，見 `assets/fonts/LICENSE-NotoSansCJK.txt`），已裁成 Big5 常用字＋專案用字的子集；重新產生：`python3 tools/make_font_subset.py <NotoSansCJK 字型檔>`。
