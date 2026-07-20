extends Node
## 全局状态（autoload GameState）——类肉鸽无尽模式。
## 分数=难度曲线；经验→升级三选一；全局属性加成；大肥猪国王血量；阶段机。

signal changed
signal phase_changed(phase: int)
signal game_over(won: bool)
signal leveled_up

enum Phase { PREP, COMBAT, RESULT }

const PREP_SECONDS := 10.0
const KING_HP := 1000.0
const MAX_TOWERS := 5
# 满级 = 5次放塔 + 每塔2次升级(1→2→3) = 15 次行动；之后升级改为属性三选一
const MAX_ACTION_LEVEL := 15
const SAVE_PATH := "user://save.json"

var score: int = 0
var best_score: int = 0
var xp: float = 0.0
var xp_level: int = 0          # 已完成的等级数
var pending_choices: int = 0   # 攒着未消费的升级选择
var king_max_hp: float = KING_HP
var king_hp: float = KING_HP
var phase: int = Phase.PREP
var running: bool = false
var ui_pause: bool = false     # 升级弹窗期间冻结战场

# 满级后的全局属性加成
var dmg_mult: float = 1.0
var atk_speed_mult: float = 1.0
var crit_chance: float = 0.0   # 暴击造成 2 倍伤害

func _ready() -> void:
	load_save()

## 战场实体是否应当运转
func active() -> bool:
	return running and not ui_pause

func reset() -> void:
	score = 0
	xp = 0.0
	xp_level = 0
	pending_choices = 0
	king_max_hp = KING_HP
	king_hp = KING_HP
	phase = Phase.PREP
	running = true
	ui_pause = false
	dmg_mult = 1.0
	atk_speed_mult = 1.0
	crit_chance = 0.0
	changed.emit()
	phase_changed.emit(phase)

func set_phase(p: int) -> void:
	phase = p
	phase_changed.emit(p)
	changed.emit()

## 升到下一级所需经验（等级越高越慢）
func xp_need() -> float:
	return 30.0 * pow(1.22, xp_level)

func add_score(n: int) -> void:
	score += n
	if score > best_score:
		best_score = score
	changed.emit()

func add_xp(n: float) -> void:
	xp += n
	var ding := false
	while xp >= xp_need():
		xp -= xp_need()
		xp_level += 1
		pending_choices += 1
		ding = true
	changed.emit()
	if ding:
		leveled_up.emit()

func consume_choice() -> void:
	pending_choices = maxi(0, pending_choices - 1)
	changed.emit()

func damage_king(d: float) -> void:
	if not running:
		return
	king_hp -= d
	if king_hp <= 0.0:
		king_hp = 0.0
		running = false
		ui_pause = false
		save_game()
		set_phase(Phase.RESULT)
		changed.emit()
		game_over.emit(false)
	else:
		changed.emit()

func save_game() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"best_score": best_score}))

func load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if data is Dictionary:
		best_score = maxi(0, int(data.get("best_score", 0)))
