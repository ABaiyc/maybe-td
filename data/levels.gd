extends RefCounted
class_name Levels
## 关卡数据（竖版车道模式）：上方出怪往下走，下方一排塔位，塔位带后是大肥猪国王防线。
## 波次 waves：每波 {interval, entries:[[敌人id, 数量], ...], gap(波后间隔秒)}。

# 战场公共布局（两关共用）
const SPAWN_Y := -30.0        # 出怪 y（屏幕上方外）
const LINE_Y := 560.0         # 防线：敌人走到这里开始围攻国王
const SPAWN_X_MIN := 60.0
const SPAWN_X_MAX := 1060.0

const LEVEL1 := {
	"name": "草原防线",
	"bg": "23301f",
	"field": "2c3a26",
	"king_pos": Vector2(560, 682),
	"waves": [
		{"interval": 0.45, "gap": 4.0, "entries": [["wolf", 15]]},
		{"interval": 0.4, "gap": 4.0, "entries": [["wolf", 20], ["fast", 8]]},
		{"interval": 0.35, "gap": 4.5, "entries": [["wolf", 26], ["fast", 12]]},
		{"interval": 0.3, "gap": 5.0, "entries": [["wolf", 22], ["fast", 14], ["armored", 8]]},
		{"interval": 0.35, "gap": 0.0, "entries": [["armored", 10], ["wolf", 18], ["fast", 10], ["alpha", 1]]},
	],
}

const LEVEL2 := {
	"name": "雪原防线",
	"bg": "1c2230",
	"field": "252c40",
	"king_pos": Vector2(560, 682),
	"waves": [
		{"interval": 0.4, "gap": 4.0, "entries": [["wolf", 20], ["armored", 5]]},
		{"interval": 0.35, "gap": 4.0, "entries": [["fast", 20], ["armored", 10]]},
		{"interval": 0.28, "gap": 4.5, "entries": [["wolf", 30], ["fast", 20]]},
		{"interval": 0.3, "gap": 5.0, "entries": [["armored", 18], ["wolf", 20]]},
		{"interval": 0.35, "gap": 0.0, "entries": [["armored", 14], ["fast", 20], ["wolf_sheep", 1]]},
	],
}

const ALL := [LEVEL1, LEVEL2]

static func get_level(idx: int) -> Dictionary:
	if idx < 0 or idx >= ALL.size():
		return LEVEL1
	return ALL[idx]

static func count() -> int:
	return ALL.size()
