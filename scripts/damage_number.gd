extends Node2D
class_name DamageNumber
## 飘出的伤害数字：上浮、淡出、自毁。数值越大字越大越黄。

var amount: float = 0.0
var _t: float = 0.0
const DUR := 0.7
var _vel := Vector2.ZERO

func _ready() -> void:
	_vel = Vector2(randf_range(-14.0, 14.0), -46.0)

func _process(delta: float) -> void:
	if not GameState.running:
		return
	_t += delta
	if _t >= DUR:
		queue_free()
		return
	position += _vel * delta
	queue_redraw()

func _draw() -> void:
	var a := 1.0 - _t / DUR
	var big := amount >= 60.0
	var size := 14 + mini(10, int(amount / 25.0))
	var col := Color(1.0, 0.9, 0.35, a) if big else Color(1.0, 1.0, 1.0, a)
	var txt := str(int(roundf(amount)))
	var w := float(txt.length()) * size * 0.55
	draw_string(ThemeDB.fallback_font, Vector2(-w / 2.0, 0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
