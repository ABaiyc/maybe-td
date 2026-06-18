extends Node
## 全局状态（autoload GameState）：金币 / 波次 / 大肥猪国王血量 / 阶段机。
## 阶段：PREP(准备,10s倒计时) → COMBAT(战斗) → RESULT(结算)。

signal changed
signal phase_changed(phase: int)
signal game_over(won: bool)

enum Phase { PREP, COMBAT, RESULT }

const PREP_SECONDS := 10.0
const START_GOLD := 200
const KING_HP := 1000.0

var gold: int = 0
var wave: int = 0
var total_waves: int = 0
var king_max_hp: float = KING_HP
var king_hp: float = KING_HP
var phase: int = Phase.PREP
var running: bool = false

func reset(_total_waves: int) -> void:
	gold = START_GOLD
	wave = 0
	total_waves = _total_waves
	king_max_hp = KING_HP
	king_hp = KING_HP
	phase = Phase.PREP
	running = true
	changed.emit()
	phase_changed.emit(phase)

func set_phase(p: int) -> void:
	phase = p
	phase_changed.emit(p)
	changed.emit()

func add_gold(n: int) -> void:
	gold += n
	changed.emit()

func spend_gold(n: int) -> bool:
	if gold < n:
		return false
	gold -= n
	changed.emit()
	return true

func damage_king(d: float) -> void:
	if not running:
		return
	king_hp -= d
	if king_hp <= 0.0:
		king_hp = 0.0
		running = false
		changed.emit()
		game_over.emit(false)
	else:
		changed.emit()

func win() -> void:
	if not running:
		return
	running = false
	set_phase(Phase.RESULT)
	game_over.emit(true)
