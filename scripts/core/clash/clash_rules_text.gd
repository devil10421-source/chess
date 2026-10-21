class_name ClashRulesText
extends RefCounted
## 《氏族爭霸》規則說明（全部由 clash_config.json 產生，改數值後說明自動更新；圖鑑使用）。


static func rules() -> String:
	var mc := GameData.clash_cfg("match")
	var rc := GameData.clash_cfg("rounds")
	var pc := GameData.clash_cfg("pve")
	var sup: Dictionary = GameData.clash_cfg("pool").get("supply", {})
	var lines: Array = []
	lines.append("[b][color=#ffd24d]十人淘汰競技[/color][/b]")
	lines.append("%d 名玩家（本原型：1 名真人＋%d 名 AI），每人生命 %d，各自擁有經濟、等級、商店、棋盤與棋子。最後存活的玩家獲勝。" % [int(mc.get("players", 10)), int(mc.get("players", 10)) - 1, int(mc.get("start_hp", 100))])
	lines.append("同一回合多人淘汰：回合開始時生命較高者名次較前；再比本回合結算後的生命（可為負）；完全相同則並列。第 %d 回合仍未分出勝負時依生命排名。" % int(mc.get("max_rounds", 45)))
	lines.append("")
	lines.append("[b][color=#ffd24d]棋子與共用棋池[/color][/b]")
	lines.append("沒有開局文明，所有玩家都能購買六大氏族（精靈、人類、半獸人、半人馬、鹿角人、鬼人）的全部棋子；原本的中立棋子先以【測試分配】歸入各氏族。種族、職業、類型羈絆與升星規則不變。")
	lines.append("十人共用有限棋池：每種棋子 1／2／3／4 費各 %s／%s／%s／%s 份（1★=1、2★=3、3★=9 份）。商店顯示即預留；出售、淘汰時歸還；交易只轉移所有權；幽靈陣容與援軍只是戰鬥快照，不佔份數。" % [sup.get("1", 0), sup.get("2", 0), sup.get("3", 0), sup.get("4", 0)])
	lines.append("")
	lines.append("[b][color=#ffd24d]回合[/color][/b]")
	lines.append("多數回合為 PvP；從第 %d 回合起每 %d 回合一次合作 PvE（只剩 2 人時一律 PvP）。備戰 %d 秒左右，時間到自動開戰。" % [int(rc.get("pve_first", 2)), int(rc.get("pve_every", 6)), int(ClashMatch.prep_seconds(2))])
	lines.append("PvP：存活玩家兩兩對戰，盡量不連續遇到同一對手；奇數人時一人與另一名玩家的陣容鏡像進行幽靈戰（被複製的玩家不受影響）。輸方扣血＝回合基礎值＋對方存活棋子（1／2／3 星各 1／2／3）；時間到雙方都有存活＝平手，雙方都扣血。勝方 +%d 金。" % int(GameData.clash_cfg("pvp").get("win_gold", 1)))
	lines.append("")
	lines.append("[b][color=#ffd24d]合作 PvE[/color][/b]")
	lines.append("存活玩家隨機兩兩合作，奇數人時一人單人挑戰（敵軍 ×%.2f、沒有交易與救援）。" % float(pc.get("solo_scale", 0.85)))
	lines.append("開打前 %d 秒交易：每人最多提出一隻棋子或一件背包裝備，雙方都確認才永久交換；任一方變更內容，確認全部清除。交換的棋子回到接收者候補區（候補已滿不能交易），身上裝備退回原主。" % int(ClashMatch.trade_seconds()))
	lines.append("兩人各守一張棋盤、打同一組敵軍。先清場的一方，存活棋子在 %.1f 秒行軍後帶著當時的生命前往隊友的棋盤協助。全滅的一方戰場凍結（敵軍生命與狀態保留）等待救援，等待期間不計入戰鬥時間。兩張棋盤都清場才算成功：成功雙方都不扣血並獲得 %d 金與 1 個基礎組件；失敗雙方各扣 PvE 失敗生命。" % [float(pc.get("reinforce_delay", 1.5)), int(pc.get("reward_gold", 2))])
	lines.append("")
	lines.append("[b][color=#ffd24d]國家制度[/color][/b]")
	lines.append("第 %d 回合選擇國家制度，第 %d 回合選擇該制度的深化政策；選擇時倒數不暫停，時間到隨機決定。詳見「國家制度」分頁。" % [ClashGovernment.system_round(), ClashGovernment.policy_round()])
	return "\n".join(lines)


static func governments() -> String:
	var lines: Array = []
	for sys in ClashGovernment.systems():
		var sc := ClashGovernment.system_cfg(sys)
		lines.append("[b][color=#ffd24d]%s[/color][/b]　[color=#9aa3ad]%s[/color]" % [sc.get("name", sys), sc.get("role", "")])
		lines.append("[color=#5aa9ff]制度效果：%s[/color]" % sc.get("base_text", ""))
		for pol in ClashGovernment.policies_for(sys):
			var pc := ClashGovernment.policy_cfg(pol)
			lines.append("　[b]%s[/b]　[i]「%s」[/i]" % [pc.get("name", pol), pc.get("slogan", "")])
			lines.append("　%s" % pc.get("text", ""))
		lines.append("")
	return "\n".join(lines)
