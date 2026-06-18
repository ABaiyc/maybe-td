extends Node
## 全局游戏状态（autoload 单例 GameState）：金币 / 生命 / 波次，及变更信号。

signal changed
signal game_over(won: bool)

var gold: int = 0
var lives: int = 0
var wave: int = 0
var running: bool = false

func reset() -> void:
	gold = 120
	lives = 20
	wave = 0
	running = true
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

func lose_life(n: int = 1) -> void:
	if not running:
		return
	lives -= n
	if lives <= 0:
		lives = 0
		running = false
		changed.emit()
		game_over.emit(false)
	else:
		changed.emit()
