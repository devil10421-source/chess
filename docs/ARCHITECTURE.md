# 《六族遠征》V0.1 — Godot 4 重新規劃

引擎：**Godot 4.7.2 stable（GDScript）**，渲染器 **Compatibility（OpenGL 3 / GLES3）**——對舊 PC、Android、iOS 相容性最好，且不需任何平台專屬外掛。
專案以 Godot 4.7.2 實際匯入、執行與測試過；4.3 以上版本理應也能開啟（只用到穩定 API），但以 4.7.x 為準。

企劃書 v0.1 的所有規則**原樣保留**；只有「技術方案」一節從 Phaser/Vite/TypeScript 改為 Godot。
存檔由瀏覽器 localStorage 改為 Godot 的 `user://`（Windows：`%APPDATA%\Godot\app_userdata\六族遠征\`）。

---

## 1. 分層原則

```
┌────────────── 畫面層 scripts/ui + scenes/*.tscn ──────────────┐
│ 只負責顯示、輸入、播放動畫；不做任何規則判定                    │
└───────────────▲──────────────────────────────┬────────────────┘
                │ 讀取狀態 / 戰鬥事件            │ 呼叫操作（買、賣、移動…）
┌───────────────┴──────────────────────────────▼────────────────┐
│ 規則層 scripts/core（純 RefCounted，不依賴任何 Node／畫面）      │
│  RunState ─ Shop ─ Economy ─ Synergy ─ Modifiers ─ UnitStats   │
│  combat/CombatSim ─ CombatUnit ─ SkillRunner ─ BattleSetup     │
│  HexGrid ─ SeededRng ─ SaveSystem ─ AutoPlayer（測試用 bot）    │
└───────────────▲───────────────────────────────────────────────┘
                │ 讀取
┌───────────────┴───────────────────────────────────────────────┐
│ 資料層 data/*.json（所有平衡數值；改數值不必動程式）            │
│  game_config / units / civs / traits / stages                  │
└───────────────────────────────────────────────────────────────┘
```

* **戰鬥是「先算後播」**：按下「開始戰鬥」時 `CombatSim` 以固定步長（0.05 秒）與 seeded RNG 一次算完整場，輸出事件清單；`BattlePlayer` 只負責依時間播放事件。關鍵判定不寫在動畫 callback 中，同一個種子一定得到同一場戰鬥。
* **JSON 而非 .tres**：選用 JSON 是因為可以直接用任何文字編輯器或試算表轉換工具修改、容易比對差異；匯出設定已把 `data/*.json` 納入封包。

## 2. 資料夾結構

```
six-tribes-godot/
├─ project.godot              專案設定（橫向、1280×720 基準、canvas_items 縮放、觸控模擬滑鼠）
├─ export_presets.cfg         Windows / Android / iOS 匯出預設
├─ icon.svg
├─ data/                      ← 平衡數值全部在這裡
│  ├─ game_config.json        經濟、XP 表、商店機率、星級倍率、稀有度基礎值、職業修正、戰鬥常數
│  ├─ units.json              24 棋子（種族／費用／類型／職業／射程／技能參數）
│  ├─ civs.json               6 文明的 2 Buff + 2 Debuff（以效果碼描述）
│  ├─ traits.json             種族／類型／職業羈絆門檻與效果
│  └─ stages.json             24 關敵軍清單、星級、站位
├─ assets/
│  ├─ fonts/                  Noto Sans CJK TC（OFL）常用字子集
│  ├─ theme/main_theme.tres   全域字型與字級
│  └─ units/<ID>/star1.png…   之後放 AI 美術；檔案不存在時自動用幾何占位圖
├─ scenes/
│  ├─ main_menu.tscn          主選單
│  ├─ civ_select.tscn         文明六選一
│  ├─ game.tscn               備戰＋戰鬥（同一場景切換狀態）
│  ├─ unit_token.tscn         棋子外觀
│  ├─ codex.tscn              規則／棋子圖鑑／文明／羈絆
│  └─ end_screen.tscn         通關／戰敗／未完成
├─ scripts/
│  ├─ autoload/session.gd     目前這局 RunState、場景切換、除錯開關
│  ├─ core/                   規則層（見 §1）
│  └─ ui/                     畫面層
├─ tests/
│  ├─ run_tests.gd            無頭自動測試（規則、戰鬥、24 技能、存檔、全部場景與腳本載入）
│  ├─ smoke_test.tscn/.gd     實際跑「主選單→選文明→備戰→戰鬥→結算」的自動操作
│  └─ balance_sim.gd          bot 打 24 關的難度模擬報表
└─ tools/
   ├─ check.bat / check.ps1   Windows 一鍵檢查
   ├─ check.sh                Linux/macOS 一鍵檢查
   └─ make_font_subset.py     重新產生內嵌字型子集
```

## 3. 場景樹

```
MainMenu (Control) ─ main_menu.gd
├─ Background (ColorRect)
├─ Center (CenterContainer) / Box (VBoxContainer)
│  ├─ Title, Subtitle (Label)
│  └─ NewGameButton, ContinueButton, CodexButton, UnlockButton(停用：第 5 階段), QuitButton
└─ ConfirmNewGame (ConfirmationDialog)          有存檔時「新開局會清除存檔」確認

CivSelect (Control) ─ civ_select.gd
├─ Background
└─ Margin / VBox
   ├─ Title
   ├─ CivGrid (GridContainer 3×2) ← 執行時放入 6 張文明卡（Button）
   ├─ Detail (RichTextLabel)        已選文明完整 Buff／Debuff
   └─ Buttons: BackButton, StartButton

Game (Control) ─ game_screen.gd                   狀態：PREP → BATTLE → RESULT → PREP…
├─ Background (ColorRect)
├─ BoardView (Node2D) ─ board_view.gd            7×8 錯位六角格＋12 格候補區；點選／拖曳
│  ├─ Tokens (Node2D)                             UnitToken 實例
│  ├─ Effects (Node2D)                            彈道、傷害數字、技能範圍
│  └─ BattlePlayer (Node) ─ battle_player.gd      播放 CombatSim 事件
├─ TopBar (PanelContainer)  回合 n/24・章、遠征生命、金幣（預計利息）、文明 Lv/XP、威脅值、速度、略過、選單、除錯
├─ TraitPanel (PanelContainer, 可收合)  文明名稱與羈絆達成
├─ InfoPanel (PanelContainer)  選取棋子的屬性、技能、出售
├─ ShopBar (PanelContainer)  刷新、買經驗、5 格商店、鎖定、開始戰鬥（也是拖曳出售區）
├─ ResultOverlay (PanelContainer)  本回合結算明細
├─ MenuOverlay (PanelContainer)    繼續／圖鑑／存檔並回主選單
├─ DebugPanel (PanelContainer)     只在除錯版（編輯器執行）出現：選關、設金幣、設等級、直接過關
└─ Toast (Label)

UnitToken (Node2D) ─ unit_token.gd
├─ Art (Sprite2D)       有 assets/units/<ID>/star<N>.png 才顯示
└─ (其餘以 _draw 繪製：底座、稀有度環、星級特效、名稱、血條／護盾／魔力、狀態字)

Codex (Control) ─ codex.gd ─ TabContainer：規則｜棋子圖鑑｜文明｜羈絆
EndScreen (Control) ─ end_screen.gd
```

## 4. 核心資料模型

| 類別 | 內容 |
|---|---|
| `GameData` | 靜態快取讀取 `data/*.json`；`unit(id)`、`civ(id)`、`stage(round)`… |
| `RunState` | 文明、回合、遠征生命、金幣、累積 XP、商店 5 格、鎖定、人類免費刷新券、候補 12 格、棋盤 `{Vector2i: 棋子}`、uid 計數、RNG seed/state、歷史紀錄；所有玩家操作（買、賣、刷新、買 XP、移動、開戰、結算）都是它的方法，回傳是否成功 |
| 棋子實例 | `{uid, id, star}`，位置由所在容器決定（候補索引或棋盤格） |
| `Shop` | 依等級機率抽稀有度 → 同稀有度等機率；4 費只放所選文明的頂尖棋子（共 19 種可抽） |
| `Economy` | 利息、等級／XP、威脅值、回合倍率、扣血、出售價 |
| `Synergy` | 只計棋盤上「不同名稱」的棋子；種族 2/3、職業 2/3、類型 2/4 |
| `Modifiers` | 把文明效果與羈絆效果加總成每隻棋子的百分比／固定值（先加總再套用） |
| `UnitStats` | 稀有度基礎值 × 職業修正 × 星級倍率；技能數值＝稀有度預算 × 參數 × 星級倍率 |
| `CombatSim` | 固定步長模擬：索敵（距離→血量→ID）、BFS 找路、單格單位、普攻、魔力、24 種技能、護盾、控制、DoT/HoT、45 秒上限 |
| `SaveSystem` | `user://save_v1.json`；每次進入備戰、每次操作後自動存檔 |

## 5. 開發階段（每階段都可在編輯器按 F5 執行並以 `tools/check` 驗證）

| 階段 | 內容 | 本次狀態 |
|---|---|---|
| 1 | 六角棋盤、可移動／自動攻擊的棋子、單關敵軍、事件播放 | ✅ 完成 |
| 2 | 商店、金幣、利息、文明等級、候補區、合成升星、出售 | ✅ 完成 |
| 3 | 六文明 Buff/Debuff、24 棋子與技能、三層羈絆 | ✅ 完成 |
| 4 | 24 回合、通關／戰敗／未完成、存檔續玩、除錯工具 | ✅ 完成 |
| 5 | 局外徽記與 2 費替代型態（企劃第 11 節） | ⏸ 只保留主選單停用入口，待確認後再做 |

第 1～4 階段的規則彼此高度相依（例如合成要算人口、羈絆要算商店買到的棋子），所以這次一次做到第 4 階段；第 5 階段依企劃書明文「先把主要 24 回合單機對局跑順」暫不實作。

## 6. 規格中需要明確化的地方（已採最小解讀，未改動規則）

1. **「直接傷害」**：解讀為非持續傷害（普攻＋技能的直接命中）；燃燒／流血等 DoT 不吃「直接傷害」加成。
2. **「法術傷害 -8%」（半獸人）**：作用於所有法術傷害（含 DoT）；「法術直接傷害」（鬼人種族羈絆）不含 DoT。
3. **鎖定商店**：鎖定會一直保持到玩家手動解鎖。
4. **拖曳 vs 點選**：點選棋子＝選取並顯示資訊；再點空格＝移動；拖曳可移動或互換位置；拖到商店列＝出售。
5. **敵方羈絆**：依企劃 V0.1 預設關閉，`game_config.json → enemy.use_synergies` 可開。
6. **控制時間的文明修正上限 0.2 秒**：施放方（精靈）與承受方（半人馬）分別計算各自上限。

## 7. 難度模擬結果（V0.1 數值，bot 各文明 8 局）

bot 只會照固定規則買高費棋子、近戰站前排，不會刻意湊羈絆，所以是「下限」參考。
調整後的全清率：第 1 關 94%、第 1 章 88–100%、第 2 章 50–87%、第 3 章 60–100%、第 4 章 31–65%、終局首領 13%；
bot 平均打到第 19–22 回合。真人依羈絆與站位調整，表現應明顯高於 bot。
原本的第 1 關（單一行旅醫士）會自我治療導致多數 1 費棋子 1 對 1 打不贏，已改為草原弓手；第 12、14、18 關各調降 1～2 隻敵人的星級以消除難度斷崖。
