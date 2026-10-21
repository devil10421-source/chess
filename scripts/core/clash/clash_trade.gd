class_name ClashTrade
extends RefCounted
## 《氏族爭霸》合作 PvE 前的雙向交易（由對局管理器集中處理，可直接搬到權威伺服器）。
## 規則：
##   - 每人最多提出一項：一隻已持有的棋子 {kind: "unit", uid} 或背包裡的一件裝備 {kind: "item", inv, id}；{}＝不提出。
##   - 雙方都提出且都按確認才成立（不允許單方面贈送）；任一方變更提案，雙方確認都清除。
##   - 成立時原子交換：先檢查全部條件，全部成立才一次移轉；任何一項不成立就整筆取消，不會半套成交。
##   - 交換的棋子只移轉所有權（共用棋池份數不變）；身上裝備退回原主背包，只交換棋子本體（避免夾帶）；
##     接收的棋子放進接收者候補區，候補沒有空位時拒絕交易（不刪除棋子）；原本在場上的也一樣離開場上。
##   - 時間到仍未成立 → 取消；已成立的保留。


static func new_trade(a: int, b: int) -> Dictionary:
	return {"a": a, "b": b, "offer": {a: {}, b: {}}, "confirm": {a: false, b: false}, "status": "open", "version": 0, "note": ""}


static func partner(t: Dictionary, seat: int) -> int:
	return int(t["b"]) if seat == int(t["a"]) else int(t["a"])


## 設定（或清除）提案。回傳 "" 或原因。
static func set_offer(m: ClashMatch, t: Dictionary, seat: int, offer: Dictionary) -> String:
	if str(t["status"]) != "open":
		return "交易已結束"
	if seat != int(t["a"]) and seat != int(t["b"]):
		return "不是這筆交易的成員"
	var p: ClashPlayer = m.players[seat]
	var clean := {}
	if not offer.is_empty():
		var reason := _validate_offer(p, offer)
		if reason != "":
			return reason
		if str(offer["kind"]) == "unit":
			clean = {"kind": "unit", "uid": int(offer["uid"])}
		else:
			var inv := int(offer["inv"])
			clean = {"kind": "item", "inv": inv, "id": str(p.run.inventory[inv])}
	t["offer"][seat] = clean
	# 任一方變更內容：雙方確認都清除
	t["confirm"][int(t["a"])] = false
	t["confirm"][int(t["b"])] = false
	t["version"] = int(t["version"]) + 1
	t["note"] = ""
	return ""


static func _validate_offer(p: ClashPlayer, offer: Dictionary) -> String:
	match str(offer.get("kind", "")):
		"unit":
			if p.run.find_unit(int(offer.get("uid", -1))).is_empty():
				return "找不到這隻棋子（可能已出售或已合成）"
			if p.run.is_fighting(int(offer["uid"])):
				return "戰鬥中的棋子不能交易"
			return ""
		"item":
			var inv := int(offer.get("inv", -1))
			if inv < 0 or inv >= p.run.inventory.size():
				return "背包沒有這件裝備"
			if offer.has("id") and str(p.run.inventory[inv]) != str(offer["id"]):
				return "背包內容已改變"
			return ""
	return "無效的提案"


## 確認／取消確認。雙方都確認時立即成交。回傳 "" 或原因。
static func set_confirm(m: ClashMatch, t: Dictionary, seat: int, value: bool) -> String:
	if str(t["status"]) != "open":
		return "交易已結束"
	if not value:
		t["confirm"][seat] = false
		return ""
	var reason := check(m, t)
	if reason != "":
		t["note"] = reason
		return reason
	t["confirm"][seat] = true
	if bool(t["confirm"][int(t["a"])]) and bool(t["confirm"][int(t["b"])]):
		return execute(m, t)
	return ""


## 成交前的完整檢查（不改任何狀態）
static func check(m: ClashMatch, t: Dictionary) -> String:
	var a := int(t["a"])
	var b := int(t["b"])
	var oa: Dictionary = t["offer"][a]
	var ob: Dictionary = t["offer"][b]
	if oa.is_empty() or ob.is_empty():
		return "雙方都要提出一項資源（不允許單方面贈送）"
	for pair in [[a, oa], [b, ob]]:
		var reason := _validate_offer(m.players[pair[0]], pair[1])
		if reason != "":
			return reason
	# 接收者候補容量：收到棋子時需要 1 個候補空位（自己送出的若是候補棋子，會先讓出位置）
	for pair in [[a, ob, oa], [b, oa, ob]]:
		var recv: ClashPlayer = m.players[pair[0]]
		var incoming: Dictionary = pair[1]
		var outgoing: Dictionary = pair[2]
		if str(incoming["kind"]) != "unit":
			continue
		var free := 0
		for x in recv.run.bench:
			if x == null:
				free += 1
		if str(outgoing["kind"]) == "unit" and recv.run.find_unit(int(outgoing["uid"])).get("where", "") == "bench":
			free += 1
		if free < 1:
			return "%s的候補區已滿，無法接收棋子" % recv.country
	return ""


## 原子成交（呼叫前會再檢查一次）。回傳 "" 或原因。
static func execute(m: ClashMatch, t: Dictionary) -> String:
	var reason := check(m, t)
	if reason != "":
		t["confirm"][int(t["a"])] = false
		t["confirm"][int(t["b"])] = false
		t["note"] = reason
		return reason
	var a := int(t["a"])
	var b := int(t["b"])
	var pa: ClashPlayer = m.players[a]
	var pb: ClashPlayer = m.players[b]
	var oa: Dictionary = t["offer"][a]
	var ob: Dictionary = t["offer"][b]
	# 1) 從雙方取出（棋子身上的裝備退回原主背包）
	var from_a := _take(pa, oa)
	var from_b := _take(pb, ob)
	# 2) 交給對方
	var got_a := _give(pa, from_b)
	var got_b := _give(pb, from_a)
	t["status"] = "done"
	t["result"] = {a: got_a, b: got_b}
	t["note"] = "交易完成"
	m.log_event("交易：%s 的 %s ⇄ %s 的 %s" % [pa.country, describe(from_a), pb.country, describe(from_b)])
	return ""


static func _take(p: ClashPlayer, offer: Dictionary) -> Dictionary:
	if str(offer["kind"]) == "unit":
		var uid := int(offer["uid"])
		if p.core_uid == uid:
			p.core_uid = -1
		var u := p.run.take_unit_for_trade(uid)
		return {"kind": "unit", "id": u["id"], "star": u["star"]}
	var id := str(p.run.inventory[int(offer["inv"])])
	p.run.inventory.remove_at(int(offer["inv"]))
	p.run.changed.emit()
	return {"kind": "item", "id": id}


static func _give(p: ClashPlayer, thing: Dictionary) -> Dictionary:
	if str(thing["kind"]) == "unit":
		var uid := p.run.receive_traded_unit(str(thing["id"]), int(thing["star"]))
		return {"kind": "unit", "id": thing["id"], "star": thing["star"], "uid": uid}
	p.run.inventory.append(str(thing["id"]))
	p.run.changed.emit()
	return {"kind": "item", "id": thing["id"]}


## 時間到：未成立的取消
static func close(t: Dictionary) -> void:
	if str(t["status"]) == "open":
		t["status"] = "cancelled"
		t["note"] = "時間到，交易取消"


static func describe(thing: Dictionary) -> String:
	if thing.is_empty():
		return "（無）"
	if str(thing.get("kind", "")) == "unit":
		var stars := "★".repeat(int(thing.get("star", 1)))
		return "%s%s" % [GameData.unit(str(thing["id"])).get("name", thing["id"]), stars]
	return str(GameData.item(str(thing["id"])).get("name", thing["id"]))


## 提案的顯示資料（UI 用）
static func offer_info(m: ClashMatch, seat: int, offer: Dictionary) -> Dictionary:
	if offer.is_empty():
		return {}
	var p: ClashPlayer = m.players[seat]
	if str(offer["kind"]) == "unit":
		var f := p.run.find_unit(int(offer["uid"]))
		if f.is_empty():
			return {}
		var u: Dictionary = f["unit"]
		return {"kind": "unit", "id": str(u["id"]), "star": int(u["star"]), "where": f["where"]}
	return {"kind": "item", "id": str(offer.get("id", ""))}
