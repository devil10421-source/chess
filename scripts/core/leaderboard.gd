class_name Leaderboard
extends RefCounted
## 戰鬥貢獻度排行（資料來自 CombatSim.run() 的 stats，以單位實例 cid 為準）。

const METRICS := {
	"damage": "傷害輸出",
	"taken": "承受傷害",
	"shielded": "護盾吸收",
	"healing": "有效治療",
}
const ORDER := ["damage", "taken", "shielded", "healing"]


## 回傳依數值由高到低的列：[{cid, id, name, star, value, pct, ratio}]
## pct：占全隊總量的百分比；ratio：相對第一名的比例（畫橫條用）。同名多隻會加上 (1)(2) 區分。
static func rows(stats: Array, metric: String, side: int = 0) -> Array:
	var out: Array = []
	var total := 0.0
	var name_count := {}
	for s in stats:
		if int(s["side"]) != side:
			continue
		name_count[s["id"]] = int(name_count.get(s["id"], 0)) + 1
	var name_seen := {}
	for s in stats:
		if int(s["side"]) != side:
			continue
		var v := float(s.get(metric, 0))
		total += v
		var nm := str(GameData.unit(s["id"]).get("name", s["id"]))
		if int(name_count[s["id"]]) > 1:
			name_seen[s["id"]] = int(name_seen.get(s["id"], 0)) + 1
			nm += "（%d）" % int(name_seen[s["id"]])
		out.append({"cid": int(s["cid"]), "id": str(s["id"]), "name": nm, "star": int(s["star"]), "value": v})
	out.sort_custom(func(a, b) -> bool:
		if a["value"] != b["value"]:
			return a["value"] > b["value"]
		return a["cid"] < b["cid"])
	var top := float(out[0]["value"]) if not out.is_empty() else 0.0
	for r in out:
		r["pct"] = 0.0 if total <= 0.0 else 100.0 * float(r["value"]) / total
		r["ratio"] = 0.0 if top <= 0.0 else float(r["value"]) / top
	return out


static func total(stats: Array, metric: String, side: int = 0) -> float:
	var t := 0.0
	for s in stats:
		if int(s["side"]) == side:
			t += float(s.get(metric, 0))
	return t
