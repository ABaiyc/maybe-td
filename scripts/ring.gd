extends Node2D
class_name Ring
## 双子激光塔的元素圆环：先向外扩散再收缩，环边碰到的敌人受伤（扩散/收缩各一次=两段伤害）。

var max_radius: float = 160.0
var damage: float = 30.0
var color: Color = Color(0.5, 0.9, 0.9)
var chance: float = 0.45
const DUR := 0.9   # 总时长（扩散一半 + 收缩一半）

var _t: float = 0.0
var _phase: int = -1
var _hit := {}
var _kind := "slow"

func _ready() -> void:
	_kind = "slow" if randi() % 2 == 0 else "burn"
	color = Color(0.55, 0.8, 1.0) if _kind == "slow" else Color(1.0, 0.6, 0.3)

func _radius() -> float:
	var half := DUR * 0.5
	if _t < half:
		return max_radius * (_t / half)
	return max_radius * (1.0 - (_t - half) / half)

func _process(delta: float) -> void:
	if not GameState.active():
		return
	_t += delta
	var ph := 0 if _t < DUR * 0.5 else 1
	if ph != _phase:
		_phase = ph
		_hit.clear()
	_damage_ring(_radius())
	queue_redraw()
	if _t >= DUR:
		queue_free()

func _damage_ring(r: float) -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.is_queued_for_deletion() or _hit.has(e.get_instance_id()):
			continue
		var d: float = global_position.distance_to(e.global_position)
		if absf(d - r) <= 22.0 + e.radius:
			e.take_damage(damage)
			if randf() < chance:
				e.apply_debuff(_kind, 0.6 if _kind == "slow" else damage * 0.3, 1.2)
			_hit[e.get_instance_id()] = true

func _draw() -> void:
	var r: float = maxf(_radius(), 1.0)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(color.r, color.g, color.b, 0.75), 3.0)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(1, 1, 1, 0.3), 1.0)
