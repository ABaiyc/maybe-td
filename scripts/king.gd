extends Node2D
class_name King
## 大肥猪国王：路径终点，狼围攻它。血量由 GameState.king_hp 管理，本节点负责渲染与定位。

func _ready() -> void:
	add_to_group("king")
	GameState.changed.connect(queue_redraw)

func _draw() -> void:
	# 身体（胖粉猪）
	draw_circle(Vector2.ZERO, 34.0, Color(0.96, 0.66, 0.74))
	draw_arc(Vector2.ZERO, 34.0, 0.0, TAU, 28, Color(0.7, 0.4, 0.5), 3.0)
	# 耳朵
	draw_circle(Vector2(-22, -26), 9.0, Color(0.9, 0.55, 0.64))
	draw_circle(Vector2(22, -26), 9.0, Color(0.9, 0.55, 0.64))
	# 鼻子
	draw_circle(Vector2(0, 6), 12.0, Color(0.86, 0.5, 0.58))
	draw_circle(Vector2(-4, 6), 2.5, Color(0.4, 0.2, 0.25))
	draw_circle(Vector2(4, 6), 2.5, Color(0.4, 0.2, 0.25))
	# 眼睛
	draw_circle(Vector2(-12, -8), 3.0, Color.BLACK)
	draw_circle(Vector2(12, -8), 3.0, Color.BLACK)
	# 王冠
	var crown := PackedVector2Array([
		Vector2(-20, -34), Vector2(-20, -52), Vector2(-8, -42),
		Vector2(0, -56), Vector2(8, -42), Vector2(20, -52), Vector2(20, -34),
	])
	draw_colored_polygon(crown, Color(1.0, 0.84, 0.2))
	# 血条（画在国王右侧，避免与塔位带重叠）
	var w := 140.0
	var ratio: float = clampf(GameState.king_hp / GameState.king_max_hp, 0.0, 1.0)
	draw_rect(Rect2(52.0, -8.0, w, 12.0), Color(0, 0, 0, 0.6))
	var bar_col := Color(0.3, 0.9, 0.4) if ratio > 0.3 else Color(0.95, 0.4, 0.3)
	draw_rect(Rect2(52.0, -8.0, w * ratio, 12.0), bar_col)
	draw_rect(Rect2(52.0, -8.0, w, 12.0), Color(1, 1, 1, 0.35), false, 1.0)
