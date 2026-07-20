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
		{"interval": 0.7, "gap": 4.0, "entries": [["wolf", 6]]},
		{"interval": 0.65, "gap": 4.0, "entries": [["wolf", 8], ["fast", 3]]},
		{"interval": 0.6, "gap": 4.5, "entries": [["wolf", 10], ["fast", 5]]},
		{"interval": 0.55, "gap": 5.0, "entries": [["wolf", 8], ["fast", 6], ["armored", 3]]},
		{"interval": 0.7, "gap": 0.0, "entries": [["armored", 4], ["wolf", 6], ["alpha", 1]]},
	],
}

const LEVEL2 := {
	"name": "雪原防线",
	"bg": "1c2230",
	"field": "252c40",
	"king_pos": Vector2(560, 682),
	"waves": [
		{"interval": 0.6, "gap": 4.0, "entries": [["wolf", 8], ["armored", 2]]},
		{"interval": 0.55, "gap": 4.0, "entries": [["fast", 8], ["armored", 4]]},
		{"interval": 0.5, "gap": 4.5, "entries": [["wolf", 12], ["fast", 8]]},
		{"interval": 0.55, "gap": 5.0, "entries": [["armored", 8], ["wolf", 8]]},
		{"interval": 0.7, "gap": 0.0, "entries": [["armored", 6], ["fast", 8], ["wolf_sheep", 1]]},
	],
}

const ALL := [LEVEL1, LEVEL2]

static func get_level(idx: int) -> Dictionary:
	if idx < 0 or idx >= ALL.size():
		return LEVEL1
	return ALL[idx]

static func count() -> int:
	return ALL.size()
