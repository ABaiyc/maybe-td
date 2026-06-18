extends Node2D
class_name Enemy
## 沿路径点移动的敌人。到达终点扣生命，被击杀给金币。

var waypoints: PackedVector2Array
var index: int = 1
var speed: float = 95.0
var max_hp: float = 30.0
var hp: float = 30.0
var reward: int = 8
var radius: float = 13.0

func setup(wp: PackedVector2Array, _hp: float, _speed: float, _reward: int) -> void:
	waypoints = wp
	max_hp = _hp
	hp = _hp
	speed = _speed
	reward = _reward
	position = wp[0]

func _ready() -> void:
	add_to_group("enemies")

func _process(delta: float) -> void:
	if index >= waypoints.size():
		return
	var target: Vector2 = waypoints[index]
	var to_target: Vector2 = target - global_position
	var dist: float = to_target.length()
	var step: float = speed * delta
	if step >= dist:
		global_position = target
		index += 1
		if index >= waypoints.size():
			GameState.lose_life(1)
			queue_free()
	else:
		global_position += to_target / dist * step

func take_damage(d: float) -> void:
	hp -= d
	if hp <= 0.0:
		GameState.add_gold(reward)
		queue_free()
	else:
		queue_redraw()

func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, Color(0.85, 0.25, 0.30))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 24, Color(0.2, 0.05, 0.08), 2.0)
	var w := 30.0
	var ratio := clampf(hp / max_hp, 0.0, 1.0)
	draw_rect(Rect2(-w / 2.0, -radius - 11.0, w, 5.0), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(-w / 2.0, -radius - 11.0, w * ratio, 5.0), Color(0.3, 0.9, 0.4))
