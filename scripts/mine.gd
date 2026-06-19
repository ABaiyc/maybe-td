extends Node2D
class_name Mine
## 自动布雷车埋下的地雷：静置在路径上，敌人靠近即引爆造成范围伤害。

var damage: float = 50.0
var splash: float = 90.0
var debuff: bool = true
var trigger: float = 26.0
var owner_tower: Node = null
var _arm: float = 0.25  # 布置后短暂引信延迟

func _process(delta: float) -> void:
	if _arm > 0.0:
		_arm -= delta
		queue_redraw()
		return
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.is_queued_for_deletion():
			continue
		if global_position.distance_to(e.global_position) <= trigger + e.radius:
			_explode()
			return

func _explode() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.is_queued_for_deletion():
			continue
		if global_position.distance_to(e.global_position) <= splash + e.radius:
			e.take_damage(damage)
			if debuff:
				e.apply_debuff("burn", damage * 0.25, 1.6)
	queue_free()

func _draw() -> void:
	var c := Color(0.95, 0.45, 0.2) if _arm <= 0.0 else Color(0.6, 0.6, 0.3)
	draw_circle(Vector2.ZERO, 7.0, c)
	draw_arc(Vector2.ZERO, 7.0, 0.0, TAU, 12, Color(0.35, 0.1, 0.05), 2.0)
	draw_circle(Vector2(0, -2), 2.0, Color(1, 1, 0.6))
