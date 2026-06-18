extends Node2D
class_name Tower
## 防御塔：周期性索敌（范围内最近的敌人）并发射子弹。

var range_r: float = 135.0
var damage: float = 18.0
var fire_interval: float = 0.65
var _cooldown: float = 0.0
var projectiles_parent: Node = null

func _process(delta: float) -> void:
	_cooldown -= delta
	if _cooldown <= 0.0:
		var target := _find_target()
		if target != null:
			_shoot(target)
			_cooldown = fire_interval

func _find_target() -> Enemy:
	var best: Enemy = null
	var best_d := range_r
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.is_queued_for_deletion():
			continue
		var d: float = global_position.distance_to(e.global_position)
		if d <= best_d:
			best_d = d
			best = e
	return best

func _shoot(target: Enemy) -> void:
	var p := Projectile.new()
	p.setup(target, damage, global_position)
	if projectiles_parent != null:
		projectiles_parent.add_child(p)

func _draw() -> void:
	draw_arc(Vector2.ZERO, range_r, 0.0, TAU, 48, Color(0.4, 0.6, 1.0, 0.12), 1.5)
	draw_circle(Vector2.ZERO, 18.0, Color(0.25, 0.5, 0.85))
	draw_arc(Vector2.ZERO, 18.0, 0.0, TAU, 24, Color(0.1, 0.2, 0.4), 3.0)
	draw_circle(Vector2.ZERO, 7.0, Color(0.85, 0.9, 1.0))
