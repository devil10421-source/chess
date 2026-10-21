class_name ItemPassives
extends RefCounted
## 裝備唯一特性（V0.4）。由 CombatSim 在固定時機呼叫；數值全部來自 data/equipment.json。
## 裝備造成的獨立傷害來源為 "item"：不吃技能傷害加成（例如鬼人 +12%）。
## 同一棋子身上相同唯一特性 id 只生效一次（取效果最強的一件，見 unique_passives）。
## 不會互相無限觸發：反彈、持續傷害、虛空彈都是「裝備」來源，不是普攻，所以不會再觸發受到普攻／普攻命中類的效果。

const KINDS := ["on_hit_bleed", "on_hit_burn", "on_hit_dot", "lifesteal", "blood_pact", "curse_on_hit", "thorns",
	"berserk", "on_cast_shield", "mana_on_hit", "cast_stun", "void_bolt", "on_hit_slow", "on_battle_shield", "on_crit_wound"]


## 依唯一特性去重：同 id 只保留效果最強的一件（數值相同時保留較前面的欄位）
static func unique_passives(items: Array) -> Array:
	var best := {}
	var order: Array = []
	for item_id in items:
		var it := GameData.item(str(item_id))
		var p: Dictionary = it.get("passive", {})
		if p.is_empty():
			continue
		var uid := str(it.get("unique", {}).get("id", str(item_id)))
		if not best.has(uid):
			best[uid] = p
			order.append(uid)
		elif _power(p) > _power(best[uid]):
			best[uid] = p
	var out: Array = []
	for k in order:
		out.append(best[k])
	return out


static func _power(p: Dictionary) -> float:
	for k in ["total", "pct", "amount", "damage", "dur", "hp_cost_pct"]:
		if p.has(k):
			return float(p[k])
	return 0.0


## 開戰時
static func on_battle_start(sim: CombatSim, u: CombatUnit) -> void:
	for p in u.passives:
		if p["kind"] == "on_battle_shield":
			sim.add_shield(u, u, float(p.get("amount", 60)), float(p.get("dur", 4)))
		if p["kind"] == "blood_pact":
			var cost := roundf(u.max_hp * float(p.get("hp_cost_pct", 10)) / 100.0)
			u.hp = maxf(1.0, u.hp - cost)
			sim.emit({"k": "item", "cid": u.cid, "kind": "blood_pact", "hp": u.hp})


## 普攻命中後（目標仍可能已死亡）
static func on_basic_hit(sim: CombatSim, u: CombatUnit, tgt: CombatUnit) -> void:
	for p in u.passives:
		match str(p["kind"]):
			"on_hit_bleed", "on_hit_burn", "on_hit_dot":
				# 持續傷害（V0.4 統一名稱）；同一攻擊者重複命中只刷新，不堆疊
				if tgt.alive:
					var dt := str(p.get("dtype", "magic" if p["kind"] == "on_hit_burn" else "physical"))
					sim.add_periodic(u, tgt, "dot", float(p.get("total", 10)), float(p.get("dur", 3)), dt, "item", "item:" + str(p["kind"]))
			"curse_on_hit":
				if tgt.alive and tgt.status_from("atk_down", u.cid).is_empty():
					sim.add_status(tgt, "atk_down", float(p.get("pct", 10)), float(p.get("dur", 3)), u.cid)
			"mana_on_hit":
				sim.gain_mana(u, float(p.get("amount", 5)))
			"void_bolt":
				u.item_counter += 1
				if u.item_counter % int(p.get("every", 3)) == 0 and tgt.alive:
					sim.deal_damage(u, tgt, float(p.get("damage", 40)), "magic", "item", false)


## 移動一格後（游擊等）
static func on_move(sim: CombatSim, u: CombatUnit) -> void:
	for p in u.passives:
		if p["kind"] == "after_move_armor":
			sim.add_status(u, "armor_up", float(p.get("armor", 20)), float(p.get("dur", 1.5)), u.cid, {"tag": "after_move"})


## 暴擊時（灼心：重傷）
static func on_crit(sim: CombatSim, u: CombatUnit, tgt: CombatUnit) -> void:
	if tgt == null or not tgt.alive:
		return
	for p in u.passives:
		if p["kind"] == "on_crit_wound":
			sim.add_status(tgt, "wound", 0.0, float(p.get("dur", 3)), u.cid)


## 造成有效 HP 傷害後（吸血）
static func on_damage_dealt(sim: CombatSim, u: CombatUnit, hp_damage: float) -> void:
	if hp_damage <= 0.0 or not u.alive:
		return
	for p in u.passives:
		if p["kind"] == "lifesteal":
			sim.heal(u, u, hp_damage * float(p.get("pct", 10)) / 100.0)


## 受到普攻後（反甲、緩速）
static func on_basic_taken(sim: CombatSim, u: CombatUnit, attacker: CombatUnit, dmg: float) -> void:
	if attacker == null or not attacker.alive:
		return
	for p in u.passives:
		match str(p["kind"]):
			"thorns":
				if attacker.is_melee():
					sim.deal_damage(u, attacker, dmg * float(p.get("pct", 20)) / 100.0, "magic", "item", false)
			"on_hit_slow":
				sim.add_status(attacker, "slow", 0.0, float(p.get("dur", 1.5)), u.cid)


## 施放技能後
static func on_cast(sim: CombatSim, u: CombatUnit) -> void:
	for p in u.passives:
		match str(p["kind"]):
			"on_cast_shield":
				sim.add_shield(u, u, float(p.get("amount", 100)), float(p.get("dur", 4)))
			"cast_stun":
				var tgt := sim.unit_by_cid(u.target_cid)
				if tgt != null and tgt.alive and tgt.side != u.side:
					sim.apply_cc(u, tgt, "stun", float(p.get("dur", 0.5)))


## 直接傷害加成（狂暴）
static func bonus_pct(u: CombatUnit) -> float:
	var pct := 0.0
	for p in u.passives:
		if p["kind"] == "berserk" and u.hp_ratio() < float(p.get("threshold", 0.5)):
			pct += float(p.get("pct", 20))
	return pct
