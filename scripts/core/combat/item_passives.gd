class_name ItemPassives
extends RefCounted
## 裝備被動（V0.3）。由 CombatSim 在固定時機呼叫；數值全部來自 data/equipment.json。
## 裝備造成的獨立傷害來源為 "item"：不吃技能傷害加成（例如鬼人 +12%）。

const KINDS := ["on_hit_bleed", "on_hit_burn", "lifesteal", "blood_pact", "curse_on_hit", "thorns",
	"berserk", "on_cast_shield", "mana_on_hit", "cast_stun", "void_bolt", "on_hit_slow"]


## 開戰時
static func on_battle_start(sim: CombatSim, u: CombatUnit) -> void:
	for p in u.passives:
		if p["kind"] == "blood_pact":
			var cost := roundf(u.max_hp * float(p.get("hp_cost_pct", 10)) / 100.0)
			u.hp = maxf(1.0, u.hp - cost)
			sim.emit({"k": "item", "cid": u.cid, "kind": "blood_pact", "hp": u.hp})


## 普攻命中後（目標仍可能已死亡）
static func on_basic_hit(sim: CombatSim, u: CombatUnit, tgt: CombatUnit) -> void:
	for p in u.passives:
		match str(p["kind"]):
			"on_hit_bleed":
				if tgt.alive:
					sim.add_periodic(u, tgt, "dot", float(p.get("total", 10)), float(p.get("dur", 3)), "physical", "item")
			"on_hit_burn":
				if tgt.alive:
					sim.add_periodic(u, tgt, "dot", float(p.get("total", 10)), float(p.get("dur", 3)), "magic", "item")
			"curse_on_hit":
				if tgt.alive and tgt.status_from("atk_down", u.cid).is_empty():
					sim.add_status(tgt, "atk_down", float(p.get("pct", 10)), float(p.get("dur", 3)), u.cid)
			"mana_on_hit":
				sim.gain_mana(u, float(p.get("amount", 5)))
			"void_bolt":
				u.item_counter += 1
				if u.item_counter % int(p.get("every", 3)) == 0 and tgt.alive:
					sim.deal_damage(u, tgt, float(p.get("damage", 40)), "magic", "item", false)


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
				if attacker.status_from("slow", u.cid).is_empty():
					sim.add_status(attacker, "slow", float(p.get("pct", 20)), float(p.get("dur", 1.5)), u.cid)


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
