extends Node2D
class_name Boom
## 一次性爆炸视觉：扩张光环 + 淡出。

var radius: float = 60.0
var color: Color = Color(1.0, 0.6, 0.2)
var _t: float = 0.0
const DUR := 0.26

func _process(delta: float) -> void:
	if not GameState.running:
		return
	_t += delta
	if _t >= DUR:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var f := _t / DUR
	var a := (1.0 - f) * 0.7
	draw_circle(Vector2.ZERO, radius * (0.25 + 0.75 * f), Color(color.r, color.g, color.b, a * 0.35))
	draw_arc(Vector2.ZERO, radius * (0.3 + 0.7 * f), 0.0, TAU, 32, Color(color.r, color.g, color.b, a), 3.0)
