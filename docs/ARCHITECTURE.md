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

* **戰鬥是「邊算邊播」（V0.5）**：倒數歸零時建立 `CombatSim`（固定步長 0.05 秒、seeded RNG），`BattlePlayer` 依播放時間呼叫 `step_to()` 逐步推進並播放新事件；略過＝`run()` 一次算完剩下的部分。戰鬥中的操作（替場上棋子換裝備）以 `queue_items()` 排入下一步開頭套用並寫入 `op_log`；相同種子＋相同操作時間點一定得到同一場戰鬥。關鍵判定不寫在動畫 callback 中。
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

---

## 8. V0.2 架構變更

### 新增核心模組（scripts/core）
| 模組 | 用途 |
|---|---|
| `playback_clock.gd` | 實際播放秒數 ↔ 戰鬥模擬秒數（分段加速），只影響播放 |
| `prep_timer.gd` | 15 秒備戰倒數（可暫停、只觸發一次） |
| `stat_breakdown.gd` | 屬性最終值與來源明細（給資訊面板） |
| `leaderboard.gd` | 戰鬥貢獻排行的排序與百分比 |
| `Modifiers.sources_for_lineup()` | 修正值保留來源（文明效果、哪一個羈絆）；`for_lineup()` 由來源加總，兩者必定一致 |
| `Synergy.detail()` | 羈絆成員名單與狀態（上場／候補／未持有／本文明無法取得） |
| `Economy.xp_plan()`、`next_interest()` | XP 還差多少、要買幾次；下一個利息門檻 |
| `RunState.auto_fill_board()`、`three_star_ids()` | 開戰自動補位；三星排除 |

### 索敵演算法（`CombatSim.acquire_target`）
1. **嘲諷**：被嘲諷時強制攻擊嘲諷者，但不改寫原本的鎖定目標。
2. **鎖定**：已有目標且存活 → 持續追擊。只有「打不到也找不到路」連續超過 `targeting.stuck_retarget_time`（1.5 秒）才重新索敵。
3. **重新索敵**（開戰、目標死亡、卡死）：
   - 遠程：六角距離 → 血量 → 編號
   - 刺客：BFS 步數 → 血量 → 編號（不吃前排掩護）
   - 其他近戰：BFS 步數 + `front_weight`(2) × 目標部署深度 → 部署深度 → 欄位差 → 編號
   - 「部署深度」是開戰時的站位（0 前排～3 後排），戰鬥中不變，所以結果穩定、容易預測。
4. 技能可以明確指定新目標（突進類），其他技能（範圍法術等）不改變鎖定。

### 傷害管線（`CombatSim.deal_damage`）
來源 `source`（basic 普攻／skill 技能／item 裝備）與屬性 `dtype`（physical／magic）分開傳入 →
同類加成先加總（`damage_bonus_pct`）→ 暴擊（僅普攻）→ 防禦減傷 `0.75×D/(D+75)` → 額外百分比減傷 → 護盾吸收 → 扣 HP。
持續傷害在每次結算時套用一次加成。統計：有效 HP 傷害、承傷、護盾提供者的實際吸收量、有效治療、原始總傷害、溢出傷害。

### 場景樹變更（scenes/game.tscn）
```
Game
├─ TopBar：回合、生命、金幣（含下一利息門檻）、威脅、倒數／戰鬥時間、上場戰報、速度、略過、除錯、選單
├─ CivPanel（新）：文明 2 Buff（藍）／2 Debuff（紅），在 TraitPanel 左側，可收合
├─ TraitPanel：羈絆按鈕清單（點擊 → 右側完整名單），可收合
├─ InfoPanel：InfoBody（InfoView：可展開的屬性列）＋ 出售
├─ ShopBar：LevelBox（Lv、上場、XP 條、還差／購買次數）＋ 刷新／買經驗 ＋ 5 格商店 ＋ 鎖定／開始戰鬥（倒數秒數）
├─ BigCountdown（新）：最後 5 秒大字警示
└─ ResultOverlay：結算文字 ＋ 四個排行分頁 ＋ LeaderList
```
`BoardView` 新增戰鬥模式：點擊時以 `BattlePlayer.cid_at()` 找戰鬥單位，資訊面板用 `cid` 讀取即時狀態（由事件重建，不碰模擬）。

### 存檔
結構未變（version 1），V0.1 存檔可直接讀取。若日後需要改結構，在 `RunState.from_dict()` 依 `version` 做轉換。

## 9. V0.3 架構變更

### 新增／改寫模組
| 層 | 檔案 | 責任 |
|---|---|---|
| 資料 | `data/equipment.json` | 16 件裝備（邪教／魔族／古神 × 普通／進階）、類型與稀有度顏色、獎勵回合表（`reward_rounds`）、每次 3 選 1、每隻 2 欄 |
| 資料 | `data/units.json → special_units` | 異界變體：`base` 指向原棋子、`phase` 指定階段倍率；可覆寫名稱、技能或固定數值（古神化身） |
| 資料 | `data/game_config.json → otherworld.phases` | 階段倍率 cult 1.0/1.0、demon 1.5/1.35、oldgod 2.1/1.7（生命／攻擊），只套用一次 |
| 核心 | `scripts/core/equipment.gd` | 依陣營與稀有度抽三選一、顯示文字 |
| 核心 | `scripts/core/combat/item_passives.gd` | 裝備被動（流血、燃燒、吸血、血契、詛咒、荊棘、狂暴、施法護盾、命中回魔、施法暈眩、虛空彈、緩速）的戰鬥掛勾 |
| 核心 | `scripts/core/stat_breakdown.gd` | `cells()` 回傳 12 格屬性：最終值、目前星級基礎值、顏色符號、只列存在的來源（基礎／文明／羈絆／裝備／暫時效果） |
| 核心 | `scripts/core/run_state.gd` | 背包、裝備、待領獎勵、存檔 version 2（讀 v1 自動補空資料） |
| 介面 | `scripts/ui/unit_card.gd` | 棋子面板：頭像、名稱、HP 數字＋血條＋護盾條、3×4 屬性格、格內彈出明細、2 個裝備欄 |
| 介面 | `scripts/ui/leader_panel.gd` | 右側可收合戰鬥貢獻面板（取代結算畫面的排行） |
| 介面 | `scripts/ui/reward_dots.gd` | 頂部 7 個獎勵點 |
| 介面 | `scripts/ui/ui_icon.gd` | 向量繪製的小圖示（不需圖片檔） |

`scripts/ui/leaderboard_view.gd` 與 ResultOverlay 已移除；每回合結果改為 `Toasts` 非阻擋提示，只保留遠征勝負的結束畫面。

### 屬性顏色規則
`UnitStats.base_stats(id, star)` 為「目前星級基礎值」，`UnitStats.final_stats()` 為實際戰鬥使用的值；兩者比較決定藍／紅／白。因為基礎值已含星級，正常升星不會變藍。戰鬥中額外乘上 `BattlePlayer.live_statuses()` 的暫時效果，並以 0.2 秒更新一次；只讀取播放端重建的狀態，不影響模擬。

### 場景樹（scenes/game.tscn，V0.3）
```
Game
├─ TopBar：RoundBox（X/24、RewardDots）、Countdown（30 秒倒數條）、速度／略過／除錯／選單
├─ LeftPanel：文明按鈕＋展開明細、羈絆清單（可收合）
├─ BoardView：棋盤＋候補區
├─ RightPanel/Stack：LeaderHost（LeaderPanel）、DetailBox（UnitCard／敵人／羈絆）
├─ BottomBar：RowA（金幣｜Lv｜HP｜人口、XP 條、背包）、RowB（刷新／文明升級｜5 格商店｜開戰／鎖定）
├─ BigCountdown、RewardOverlay（三選一）、ItemOverlay（背包／穿上／卸下）
├─ MenuOverlay、DebugPanel、AbandonConfirm
└─ Toasts
```

### 回合流程
V0.5：`PREP（計時器開始；若有上一場特殊戰鬥的獎勵就顯示三選一，計時不停）→（倒數歸零：未選的獎勵隨機發放 → 自動補位）BATTLE → AFTER（1 秒提示）→ PREP`。最後一回合或遠征生命歸零時，AFTER 之後進入結束畫面。

### 存檔
version 2：新增 `inventory`、每隻棋子的 `items`、`rewards_claimed`、`pending_reward`。讀到 version 1 會補空背包、空裝備欄與空領取紀錄。

## 10. V0.4 架構變更

### 版面（scenes/game.tscn，由 `tools/gen_game_scene.py` 產生）
- 棋盤可用區＝上下兩條之間；左右以「左側羈絆清單寬度」對稱保留，棋盤固定置中（`GameScreen.board_rect()`）。右側面板（排行／棋子資訊／背包）與羈絆說明 `TraitPopover` 都浮在戰場上，不參與棋盤尺寸計算，開關時棋盤的位置與縮放不變。
- 手機安全區：`_safe_insets()` 讀 `DisplayServer.get_display_safe_area()`，只在 mobile 平台內縮上下左右的面板。
- `BoardView.top_pad()`：第一排棋子頭上狀態條需要的空間；候補格 1.32 格寬、間距 0.32 格。
- `UnitToken.head_layout()`：頭上元件位置（星級標記在 HP／MP 條左側；裝備圖示在條下方，0 件時為空陣列）。`UiIcon.paint()` 為靜態繪圖，棋子與介面共用同一套圖示。

### 戰鬥（scripts/core/combat）
| 項目 | 實作 |
|---|---|
| 穿透 | `CombatUnit.penetration(dtype)`＝mods（裝備／文明／羈絆）＋自身狀態（技能），上限 `combat.status.penetration_max_pct`；`CombatSim.reduction_after_pen()`＝減傷率 ×（1 − 穿透）。舊的 `armor_down` 已移除，技能改用 `params.pen／pen_dur`（`SkillRunner._self_pen`） |
| 狀態規則 | `CombatSim.UNIQUE_STATUSES`（緩速、重傷：只有一份，取較長時間）；`REFRESH_STATUSES`（持續傷害、持續治療、穿透、標記、守護連結、返刃、祝福：同來源同 tag 刷新） |
| 傷害管線 | `deal_damage`：加成 → 暴擊 → 防禦（含穿透）→ 額外減傷 → 返刃格擋 → `_apply_hit`（護盾 → 守護連結轉移 → 扣血 → 事件／統計 → 陣亡或祝福觸發）→ 回魔與裝備被動 → 反擊 |
| 延遲效果 | `CombatSim.add_delayed()／_run_delayed()`（虛空裂隙），每步在狀態結算後執行，結果可重現 |
| 後撤 | `CombatSim.retreat_step()`：相鄰合法空格，排序鍵＝最近敵人距離↓、可攻擊此格的敵人數↑、仍在原目標射程內、與敵人距離總和↓、座標；產生 `retreat` 事件 |
| 新事件 | `retreat`、`rift`、`burst`；`damage` 另有 `redirect_from`、`parried`；反擊的 `attack` 帶 `counter` |

### 經濟與卡池（scripts/core/shop.gd、run_state.gd）
- 卡池剩餘張數不另外存狀態：`RunState.pool_remaining()`＝供應量 − 商店預留 − 玩家持有（`Shop.copies_for_star`：1／3／9）。存讀檔、鎖定、合成、出售都自然守恆；存檔另存一份快照供核對。
- `Shop.roll_slot(rng, level, civ, excluded, pool)`：先抽費用（沒有合格棋子的費用權重為 0），再依剩餘張數加權抽棋子並扣 1。

### 中立陣營
- `race = "neutral"`：`Synergy.count` 跳過沒有定義的種族；`Shop.pool_for` 的 4 費＝本族＋中立。
- 4 費規格數值放在 `units.json → spec`，`UnitStats.base_stats` 以 `neutral.spec_scale` 換算生命與攻擊；`skill.spec_scaled` 的技能固定量＝參數 × 倍率 × 星級技能倍率；攻擊力百分比型技能直接用已含星級的攻擊力。
- 被動技能（`skill.passive`，追跡獵手）：`mana_max = 0`，不累積魔力、不施放。

### 裝備
- `equipment.json`：`stats`＋`unique {id, name, desc}`＋`passive`；`drop` 只決定掉落池。`ItemPassives.unique_passives()` 依唯一特性 id 去重（取效果較強者）。
- `RunState.equip()` 不再能覆蓋或互換；`use_remover()` 消耗卸除器取下；`_merge_candidates()` 的主體順序：已上場 → 玩家選中（`buy(slot, preferred_uid)`）→ uid 小。
- 介面：右側 `BagBox` 背包；拖曳在 `GameScreen._drag_input()`（`_input` 階段處理），落點用 `BoardView.unit_at_screen()`；點裝備再點棋子用 `BoardView.tap_interceptor`。

### 存檔
version 3：新增 `pool`（快照）、`removers`、`removers_granted`；`pending_reward.tier` 改名 `drop`（讀檔相容舊名）。version 1、2 存檔可直接讀取。

### 模擬
`tests/strategy_bot.gd`＋`tests/strategy_sim.gd`：A 純抽卡（不含戰鬥）與 B 三種策略完整對局（含戰鬥）分開輸出，報告在 `docs/V0.5_模擬報告.md`（V0.4 的保留在 `docs/V0.4_模擬報告.md`）。

## 11. V0.5 架構變更

### 即時戰鬥模擬（scripts/core/combat/combat_sim.gd）
| 項目 | 實作 |
|---|---|
| 逐步推進 | `start()`（開戰效果只觸發一次）→ `step()`／`step_to(t)`／`run()`；`finished`、`result()`、`snapshots()`。`run()` 等同一路 `step()` 到結束，結果相同 |
| 戰鬥中換裝備 | `RunState._sync_live_items(uid)` → `CombatSim.queue_items(uid, items)`；下一步開頭 `_apply_ops()` 依序套用：mods＝mods − item_mods(舊) + item_mods(新)，重新登錄唯一特性（不重觸發開戰效果）；生命上限增加時目前生命同量增加、減少時不超過新上限；產生 `items` 事件。已發生的事件不改寫 |
| 重播 | `op_log` 記錄 `{tick, uid, items}`；以 `scheduled_ops` 餵回相同操作可得到完全相同的事件 |
| 施法前搖 | `combat.cast_windup` 0.25 秒；`SkillRunner.can_cast()` 確認有合法目標才開始前搖，產生 `cast_start` 事件，前搖結束才真正施放 |
| 投射物 | 遠程普攻以 `add_delayed({kind: "projectile"})` 在飛行時間（`projectile_base` + 距離 × `projectile_per_hex`）後命中；目標已陣亡則落空 |

### 戰鬥中的商店與候補（scripts/core/run_state.gd）
- `battle_active`／`live_battle`／`is_fighting(uid)`：戰鬥中場上棋子不能出售、移動、卸裝；`move_to_board` 一律拒絕。
- `_merge_candidates()` 在戰鬥中跳過場上棋子；被延後的升星在 `begin_round()` 的 `resolve_pending_merges()` 完成。
- 介面：`GameScreen._shop_open()` 在 PREP／BATTLE／AFTER 都成立；`BoardView` 在戰鬥模式下用 `BattlePlayer.cid_at()` 找到戰鬥中的己方棋子，支援拖放與點選裝備。

### 組件與合成
- `equipment.json`：`source`＝`component`／`craft`／`special`；`recipes`（順序不拘）；`component_drops`（chance、guarantee、cap、guarantee_round_in_chapter）。三選一只從 `special` 抽。
- `RunState.combine_inventory(i, j)`、`combine_on_unit(uid, slot, inv)`、`combinable_slot(uid, inv)`；戰鬥中合成同樣透過 `_sync_live_items` 立即生效。
- `RunState._component_drops(round)`：種子＝`mix(run_seed, 7000 + round)`，與操作時機無關；`component_log` 記錄每次掉落（存檔）。
- 新唯一特性種類：`combo_strike`、`on_hit_magic`、`after_move_armor`（`ItemPassives.on_move`）、`on_skill_hit_shield`（`on_skill_taken`，有冷卻）、`on_cast_ally_shield`；每個唯一特性有自己的普攻計數（`ItemPassives._count`）。
- 介面：`GameScreen._preview_combine()` 顯示結果卡＋「確認合成」；`_give_item()` 決定合成或直接穿上。

### 特殊獎勵
- `RunState.auto_claim_reward()`：在 `create_battle()` 開頭呼叫；種子＝`mix(run_seed, 9000 + 獎勵回合)`；`claim_reward()` 在 `battle_active` 時拒絕。`last_auto_reward` 供畫面提示。
- 介面：`RewardOverlay` 的 `mouse_filter` 為 IGNORE（面板外可操作）；`RewardReopen` 按鈕顯示剩餘秒數；`_update_reward_countdown()` 處理最後 5 秒提示。

### 備戰時間與節奏
- `rounds.prep_by_round`（`PrepTimer.seconds_for_round()`）；沒有開始戰鬥按鈕。
- `battle_playback.segments` 0.85×／1.3×／1.7×；`BattlePlayer`：普攻前衝 0.264 秒、傷害數字 1.04 秒、施法範圍 0.7 秒＋光環、陣亡淡出 0.5 秒。
- 候補區 `UnitToken.on_bench`：不畫 HP／MP，只在頭上畫星級（`_draw_bench_star`）。

### 存檔
version 3 不變；新增 `component_log`（舊存檔讀為空）。
