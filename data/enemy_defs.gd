extends RefCounted
class_name EnemyDefs
## 狼群与 Boss 定义。armor = 伤害减免(0..1)。
## boss 的特殊机制(改路/伪装)在 M3 实现，M1 仅作为高血量精英出现。

const WOLVES := {
	"wolf": {"n": "野狼", "hp": 42.0, "speed": 92.0, "armor": 0.0, "reward": 8, "atk": 4.0, "radius": 13.0, "col": "8a8f99", "boss": false},
	"fast": {"n": "疾风狼", "hp": 24.0, "speed": 165.0, "armor": 0.0, "reward": 7, "atk": 3.0, "radius": 11.0, "col": "9fb6c9", "boss": false},
	"armored": {"n": "铁背狼", "hp": 130.0, "speed": 68.0, "armor": 0.4, "reward": 14, "atk": 7.0, "radius": 16.0, "col": "5a606b", "boss": false},
	# Boss（M1 无特殊机制，纯肉）
	"alpha": {"n": "头狼", "hp": 1400.0, "speed": 78.0, "armor": 0.2, "reward": 120, "atk": 16.0, "radius": 26.0, "col": "3a3f4a", "boss": true, "mech": "rage"},
	"wolf_sheep": {"n": "披着羊皮的狼", "hp": 1700.0, "speed": 86.0, "armor": 0.1, "reward": 140, "atk": 14.0, "radius": 24.0, "col": "e8e4d8", "boss": true, "mech": "stealth"},
}

static func get_def(id: String) -> Dictionary:
	return WOLVES.get(id, {})

static func color_of(id: String) -> Color:
	return Color(WOLVES.get(id, {}).get("col", "888888"))
