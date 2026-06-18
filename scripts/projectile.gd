extends Node2D
class_name Projectile
## 三种模式：
##  single  - 追踪目标，命中单体
##  pierce  - 直线飞行，穿透命中沿途敌人（pierce 次）
##  aoe     - 飞向落点，到达后范围爆炸 + 随机元素 debuff

var mode: String = "single"
var damage: float = 10.0
var speed: float = 460.0
var pierce: int = 0
var splash: float = 0.0
var debuff: bool = false
var ignore_armor: float = 0.0
var color: Color = Color(1, 0.85, 0.3)

var target: Enemy = null          # single 用
var dir: Vector2 = Vector2.RIGHT  # pierce 用
var dest: Vector2 = Vector2.ZERO  # aoe 用
var _hit := {}                    # pierce 已命中集合
var _life := 2.5

func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	match mode:
		"pierce":
			_move_pierce(delta)
		"aoe":
			_move_aoe(delta)
		_:
			_move_single(delta)

func _move_single(delta: float) -> void:
	if target == null or not is_instance_valid(target) or target.is_queued_for_deletion():
		queue_free()
		return
	var to_t: Vector2 = target.global_position - global_position
	var dist: float = to_t.length()
	var step: float = speed * delta
	if step >= dist - 6.0:
		target.take_damage(damage, ignore_armor)
		queue_free()
		return
	global_position += to_t / dist * step

func _move_pierce(delta: float) -> void:
	global_position += dir * speed * delta
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.is_queued_for_deletion() or _hit.has(e.get_instance_id()):
			continue
		if global_position.distance_to(e.global_position) <= e.radius + 6.0:
			e.take_damage(damage, ignore_armor)
			_hit[e.get_instance_id()] = true
			if _hit.size() > pierce:
				queue_free()
				return
	# 飞出屏幕回收
	if global_position.x < -80 or global_position.x > 1360 or global_position.y < -80 or global_position.y > 800:
		queue_free()

func _move_aoe(delta: float) -> void:
	var to_d: Vector2 = dest - global_position
	var dist: float = to_d.length()
	var step: float = speed * delta
	if step >= dist:
		_explode()
		return
	global_position += to_d / dist * step

func _explode() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.is_queued_for_deletion():
			continue
		if global_position.distance_to(e.global_position) <= splash + e.radius:
			e.take_damage(damage, ignore_armor)
			if debuff:
				_random_debuff(e)
	queue_free()

func _random_debuff(e: Enemy) -> void:
	match randi() % 3:
		0: e.apply_debuff("slow", 0.5, 1.8)      # 冰冻减速
		1: e.apply_debuff("burn", damage * 0.4, 2.0)  # 灼烧
		_: e.apply_debuff("slow", 0.25, 1.0)     # 麻痹(强减速)

func _draw() -> void:
	if mode == "aoe":
		draw_circle(Vector2.ZERO, 7.0, color)
	elif mode == "pierce":
		draw_line(Vector2.ZERO, -dir * 16.0, color, 4.0)
		draw_circle(Vector2.ZERO, 4.0, color.lightened(0.3))
	else:
		draw_circle(Vector2.ZERO, 5.0, color)
