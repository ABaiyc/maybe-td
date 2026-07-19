extends RefCounted
class_name Levels
## 关卡数据：路径、备用分支(供 Boss 改路, M3 用)、塔位、波次、国王位置、主题色。
## 波次 waves：每波 {interval, entries:[[敌人id, 数量], ...], gap(波后间隔秒)}。

const LEVEL1 := {
	"name": "草原村道",
	"bg": "23301f",
	"road": "4a5a36",
	"waypoints": [
		Vector2(-40, 300), Vector2(240, 300), Vector2(240, 480),
		Vector2(560, 480), Vector2(560, 200), Vector2(860, 200),
		Vector2(860, 440), Vector2(1090, 440),
	],
	"alt_branches": [
		[Vector2(560, 200), Vector2(700, 200), Vector2(700, 440), Vector2(1090, 440)],
	],
	"king_pos": Vector2(1130, 440),
	"slots": [
		Vector2(140, 400), Vector2(360, 380), Vector2(360, 560),
		Vector2(460, 300), Vector2(660, 320), Vector2(720, 540),
		Vector2(760, 120), Vector2(980, 300), Vector2(1000, 540),
		Vector2(940, 440),
	],
	"waves": [
		{"interval": 0.7, "gap": 4.0, "entries": [["wolf", 6]]},
		{"interval": 0.65, "gap": 4.0, "entries": [["wolf", 8], ["fast", 3]]},
		{"interval": 0.6, "gap": 4.5, "entries": [["wolf", 10], ["fast", 5]]},
		{"interval": 0.55, "gap": 5.0, "entries": [["wolf", 8], ["fast", 6], ["armored", 3]]},
		{"interval": 0.7, "gap": 0.0, "entries": [["armored", 4], ["wolf", 6], ["alpha", 1]]},
	],
}

const LEVEL2 := {
	"name": "黑森林雪原",
	"bg": "1c2230",
	"road": "39425a",
	"waypoints": [
		Vector2(-40, 480), Vector2(300, 480), Vector2(300, 180),
		Vector2(620, 180), Vector2(620, 520), Vector2(940, 520),
		Vector2(940, 240), Vector2(1090, 240),
	],
	"alt_branches": [
		[Vector2(300, 180), Vector2(460, 180), Vector2(460, 520), Vector2(940, 520)],
	],
	"king_pos": Vector2(1130, 240),
	"slots": [
		Vector2(180, 360), Vector2(420, 300), Vector2(460, 420),
		Vector2(540, 360), Vector2(760, 360), Vector2(800, 420),
		Vector2(820, 120), Vector2(1040, 360), Vector2(1020, 120),
		Vector2(940, 400),
	],
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
