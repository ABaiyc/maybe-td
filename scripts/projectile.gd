extends Node2D
class_name Projectile
## 追踪目标敌人的子弹，命中即造成伤害。

var target: Enemy
var damage: float = 18.0
var speed: float = 430.0
var radius: float = 5.0

func setup(_target: Enemy, _damage: float, _pos: Vector2) -> void:
	target = _target
	damage = _damage
	global_position = _pos

func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target) or target.is_queued_for_deletion():
		queue_free()
		return
	var to_target: Vector2 = target.global_position - global_position
	var dist: float = to_target.length()
	var step: float = speed * delta
	if step >= dist - 6.0:
		target.take_damage(damage)
		queue_free()
		return
	global_position += to_target / dist * step

func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, Color(1.0, 0.85, 0.3))
