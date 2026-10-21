extends Control
## 規則／棋子圖鑑／文明／羈絆。內容全部由 data/*.json 產生，改數值後圖鑑自動更新。

@onready var tabs: TabContainer = $Margin/VBox/Tabs
@onready var rules: RichTextLabel = $Margin/VBox/Tabs/Rules
@onready var unit_grid: GridContainer = $Margin/VBox/Tabs/Units/UnitGrid
@onready var civs: RichTextLabel = $Margin/VBox/Tabs/Civs
@onready var traits_text: RichTextLabel = $Margin/VBox/Tabs/Traits
@onready var back_btn: Button = $Margin/VBox/Header/BackButton
@onready var star_btns: Array = [$Margin/VBox/Header/Star1, $Margin/VBox/Header/Star2, $Margin/VBox/Header/Star3]

var _star := 1


func _ready() -> void:
	tabs.set_tab_title(0, "規則")
	tabs.set_tab_title(1, "棋子圖鑑")
	tabs.set_tab_title(2, "文明")
	tabs.set_tab_title(3, "羈絆")
	UiStyle.style_button(back_btn, Color(0.18, 0.21, 0.28))
	back_btn.pressed.connect(func(): Session.goto(Session.codex_return))
	for i in 3:
		var s := i + 1
		star_btns[i].pressed.connect(func(): _set_star(s))
	for r in [rules, civs, traits_text]:
		r.add_theme_font_size_override("normal_font_size", 16)
		r.add_theme_font_size_override("bold_font_size", 18)
	rules.text = _rules_text()
	civs.text = _civ_text()
	traits_text.text = _traits_text()
	_set_star(1)


func _set_star(s: int) -> void:
	_star = s
	for i in 3:
		UiStyle.style_button(star_btns[i], Color(0.55, 0.36, 0.08) if i + 1 == s else Color(0.18, 0.21, 0.28), Color(1, 1, 1, 0.15), 15)
	for c in unit_grid.get_children():
		c.queue_free()
	for race in ["elf", "human", "orc", "centaur", "deer", "oni", "neutral"]:
		for u in GameData.units():
			if u["race"] == race:
				unit_grid.add_child(_unit_card(str(u["id"])))


func _unit_card(id: String) -> Control:
	var u := GameData.unit(id)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(280, 0)
	UiStyle.apply_panel(panel, Color(0.11, 0.13, 0.18), GameData.tier_color(int(u["cost"])))
	var rich := RichTextLabel.new()
	rich.bbcode_enabled = true
	rich.fit_content = true
	rich.scroll_active = false
	rich.add_theme_font_size_override("normal_font_size", 14)
	rich.add_theme_font_size_override("bold_font_size", 17)
	rich.text = "[b]%s[/b]　[color=#9aa3ad]%s[/color]\n%s" % [u["name"], id, UiStyle.unit_info_bbcode(id, _star)]
	panel.add_child(rich)
	return panel


func _rules_text() -> String:
	var eco := GameData.cfg("economy")
	var th := Economy.xp_thresholds()
	var lines: Array = []
	lines.append("[b][color=#ffd24d]遠征流程[/color][/b]")
	lines.append("選擇一個文明後挑戰 %d 回合（4 章 × 6 關；第 6、12、18、24 回合為首領戰）。每回合：備戰購物／佈陣 → 按「開始戰鬥」→ 自動戰鬥（最長 %d 秒）→ 結算。" % [GameData.total_rounds(), int(GameData.cfg("combat").get("max_time", 45))])
	lines.append("第 24 回合全清且遠征生命大於 0 即通關；遠征生命歸零、或第 24 回合未全清則遠征失敗／未完成。棋子不會永久死亡，每回合恢復滿血。")
	lines.append("")
	lines.append("每回合有 %d 秒備戰（最後 10 秒變黃、5 秒變紅），可提前開戰；倒數結束自動開戰，人口未滿時從候補區最左側自動補位。" % int(GameData.cfg("rounds").get("prep_seconds", 30)))
	lines.append("")
	lines.append("[b][color=#ffd24d]異界入侵與裝備[/color][/b]")
	lines.append("第 3、6、9 回合為邪教，第 12、15、18 回合為惡魔，第 21 回合為古神眷族，第 24 回合為最終首領「古神化身」；其餘回合是六族敵軍。")
	lines.append("完成第 3、6、9、12、15、18、21 回合後可從 3 件裝備中選 1 件（第 12、18、21 回合為進階裝備）。每隻棋子最多 2 件，穿脫免費；出售棋子時裝備回到背包，合成時最多保留 2 件、其餘回到背包。")
	lines.append("")
	lines.append("[b][color=#ffd24d]經濟[/color][/b]")
	lines.append("開局 %d 金。每回合戰後：固定 +%d、全清 +%d、利息 = 開戰瞬間金幣每 %d 金 +1（最多 +%d）。" % [
		Economy.start_gold(), Economy.base_income(), Economy.clear_bonus(), int(eco.get("interest_step", 10)), int(eco.get("interest_max", 2))])
	lines.append("刷新商店 %d 金；買經驗 %d 金 +%d XP；每回合戰後自然 +%d XP。出售回收：1 星＝費用、2 星＝3×費用、3 星＝9×費用。" % [
		Economy.reroll_cost(), Economy.xp_cost(), Economy.xp_per_buy(), Economy.natural_xp()])
	lines.append("鎖定商店後，下一回合不會自動刷新（直到解鎖）。候補區 %d 格；候補滿且無法立即合成時不能購買。" % Shop.bench_size())
	lines.append("")
	lines.append("[b][color=#ffd24d]文明等級與上場人數[/color][/b]")
	var parts: Array = []
	for i in range(1, th.size()):
		parts.append("Lv.%d：%d" % [i + 1, int(th[i])])
	lines.append("上場上限＝文明等級（最高 10）。升級所需累積 XP：" + "、".join(parts))
	lines.append("")
	lines.append("[b][color=#ffd24d]商店機率（1／2／3／4 費）[/color][/b]")
	for lv in range(1, 11):
		var o := Shop.odds_for_level(lv)
		lines.append("Lv.%d：%d%%／%d%%／%d%%／%d%%" % [lv, o[0], o[1], o[2], o[3]])
	lines.append("1～3 費可抽六族全部棋子與中立棋子；4 費只會出現你所選文明的專屬 4 費與 5 名中立 4 費（其他文明的 4 費不可招募）。")
	lines.append("有限卡池：每種棋子 1 費 %d 張、2 費 %d 張、3 費 %d 張、4 費 %d 張。商店先依等級機率決定費用，再依剩餘張數加權抽棋子；商店上顯示的棋子已預留，二星＝3 張、三星＝9 張，出售時歸還。" % [Shop.supply(1), Shop.supply(2), Shop.supply(3), Shop.supply(4)])
	lines.append("")
	lines.append("[b][color=#ffd24d]升星[/color][/b]")
	lines.append("三隻同名同星自動合成高一星（最高 3 星），合成後只佔一個位置。生命 1×／1.9×／3.3×、攻擊 1×／1.85×／3.33×、護甲魔抗 +0／+3／+7、技能固定量 1×／1.85×／3.33×；攻速、暴擊、射程不隨星級成長。")
	lines.append("")
	lines.append("[b][color=#ffd24d]遠征生命[/color][/b]")
	lines.append("起始 %d。未全清時扣血 = min(10, 無條件進位(剩餘威脅 × 回合倍率))；威脅：1 星 1、2 星 2、3 星 4。" % Economy.start_hp())
	var mults: Array = []
	for m in GameData.cfg("expedition").get("round_multipliers", []):
		mults.append("%d–%d 回合 ×%.1f" % [m["from"], m["to"], m["mult"]])
	lines.append("回合倍率：" + "、".join(mults))
	lines.append("")
	lines.append("[b][color=#ffd24d]戰鬥[/color][/b]")
	lines.append("棋子自動索敵（距離→血量→編號），近戰射程 1、遠程射程 3（六角格距離）。普攻 +10 魔力、受到普攻 +5 魔力，魔力滿自動施放技能。物理傷害依護甲減免、法術傷害依魔抗減免；基礎暴擊率 5%%、暴擊傷害 150%%；沒有閃避。羈絆在開戰時計算，戰鬥中不因陣亡而改變。")
	var st: Dictionary = GameData.cfg("combat").get("status", {})
	lines.append("")
	lines.append("[b][color=#ffd24d]戰鬥術語[/color][/b]")
	lines.append("物理穿透／魔法穿透：造成該類傷害時，忽略目標一定比例的減傷率（例：減傷 40%%、穿透 25%% → 30%%）；同類加總最多 %d%%。" % int(st.get("penetration_max_pct", 60)))
	lines.append("重傷：受到的治療 −%d%%，不疊加、不影響護盾。緩速：移動速度 −%d%%、攻擊速度 −%d%%，不同來源不相加。" % [int(st.get("wound_heal_reduction_pct", 40)), int(st.get("slow_move_pct", 25)), int(st.get("slow_as_pct", 10))])
	lines.append("持續傷害：每 0.5 秒結算一次（物理或魔法）；不同施加者各自計算，同一來源重複施加只刷新時間。")
	lines.append("")
	lines.append("[b][color=#ffd24d]操作[/color][/b]")
	lines.append("點棋子＝選取；再點空格＝移動；拖曳＝移動或互換；拖到商店列或按「出售」＝賣出。電腦快捷鍵：D 刷新、F 買經驗、E 出售、空白鍵 開始戰鬥／繼續、Esc 選單。")
	return "\n".join(lines)


func _civ_text() -> String:
	var lines: Array = []
	for c in GameData.civs():
		var col := UiStyle.hex_color(GameData.race_color(str(c["race"])).lightened(0.3))
		var four: Array = Shop.pool_for(str(c["id"]), 4).filter(func(x): return not GameData.is_neutral(x))
		lines.append("[b][color=%s]%s[/color][/b]　[color=#9aa3ad]商店頂尖棋子：%s[/color]" % [col, c["name"], GameData.unit(four[0])["name"] if not four.is_empty() else "?"])
		for b in c["buffs"]:
			lines.append("　[color=#6bdc85]▲ %s[/color]" % b["text"])
		for d in c["debuffs"]:
			lines.append("　[color=#f07a70]▼ %s[/color]" % d["text"])
		lines.append("")
	lines.append("[color=#9aa3ad]文明效果作用於玩家所有上場棋子（不論棋子種族）；敵軍沒有文明加成。[/color]")
	return "\n".join(lines)


func _traits_text() -> String:
	var lines: Array = []
	lines.append("[color=#9aa3ad]只計棋盤上「不同名稱」的棋子（同名重複上場只算 1 種），候補區不計。達到較高門檻時取代較低門檻；效果只加成符合該標籤的棋子。[/color]")
	var titles := {"race": "種族羈絆（2／3 種）", "class": "職業羈絆（2／3 種）", "type": "類型羈絆（2／4 種）"}
	for group in ["race", "class", "type"]:
		lines.append("")
		lines.append("[b][color=#ffd24d]%s[/color][/b]" % titles[group])
		var defs: Dictionary = GameData.traits()[group]
		for key in defs.keys():
			var d: Dictionary = defs[key]
			var members: Array = []
			for u in GameData.units():
				if str(u[group]) == key:
					members.append(u["name"])
			var tiers: Array = []
			for t in d["tiers"]:
				tiers.append("%d 種：%s" % [t["count"], t["text"]])
			lines.append("[b]%s[/b]　%s" % [d["name"], "；".join(tiers)])
			lines.append("　[color=#9aa3ad]%s[/color]" % "、".join(members))
	return "\n".join(lines)
