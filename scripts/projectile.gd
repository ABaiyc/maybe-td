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
var split: int = 0          # 爆炸后分裂出的小炸弹数
var bomblet: bool = false   # 是否为分裂出的小炸弹（更小）
var bounces: int = 0        # 弹射剩余次数（元素矩阵）
var can_hit_stealth := false  # 元素系弹药可命中伪装敌人
var _bhit := {}             # 弹射已命中集合

var target: Enemy = null          # single 用
var dir: Vector2 = Vector2.RIGHT  # pierce 用
var dest: Vector2 = Vector2.ZERO  # aoe 用
var _hit := {}                    # pierce 已命中集合
var _life := 2.5
var _last_dir := Vector2.UP       # 目标死亡后沿此方向继续飞

func _process(delta: float) -> void:
	if not GameState.active():
		return
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	match mode:
		"pierce":
			_move_pierce(delta)
		"aoe":
			_move_aoe(delta)
		"bounce":
			_move_bounce(delta)
		_:
			_move_single(delta)

func _move_single(delta: float) -> void:
	if target == null or not is_instance_valid(target) or target.is_queued_for_deletion():
		# 目标死亡 → 就近换新目标，而不是消失；没敌人就沿原方向飞完
		target = _nearest_any()
		if target == null:
			global_position += _last_dir * speed * delta
			return
	var to_t: Vector2 = target.global_position - global_position
	var dist: float = to_t.length()
	var step: float = speed * delta
	_last_dir = to_t / maxf(dist, 0.001)
	if step >= dist - 6.0:
		target.take_damage(damage, ignore_armor)
		queue_free()
		return
	global_position += _last_dir * step

func _nearest_any() -> Enemy:
	var best: Enemy = null
	var best_d := INF
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.is_queued_for_deletion():
			continue
		if e.stealth and not can_hit_stealth:
			continue
		var d: float = global_position.distance_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best

func _move_bounce(delta: float) -> void:
	if target == null or not is_instance_valid(target) or target.is_queued_for_deletion():
		target = _next_bounce_target()
		if target == null:
			# 没有可弹射的目标 → 沿原方向飞完，不凭空消失
			global_position += _last_dir * speed * delta
			return
	var to_t: Vector2 = target.global_position - global_position
	var dist: float = to_t.length()
	var step: float = speed * delta
	_last_dir = to_t / maxf(dist, 0.001)
	if step >= dist - 6.0:
		target.take_damage(damage, ignore_armor)
		if debuff:
			_random_debuff(target)
		_bhit[target.get_instance_id()] = true
		if bounces > 0:
			bounces -= 1
			target = _next_bounce_target()
			if target == null:
				queue_free()
		else:
			queue_free()
		return
	global_position += to_t / dist * step

func _next_bounce_target() -> Enemy:
	var best: Enemy = null
	var best_d := 200.0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.is_queued_for_deletion() or _bhit.has(e.get_instance_id()):
			continue
		if e.stealth and not can_hit_stealth:
			continue
		var d: float = global_position.distance_to(e.global_position)
		if d <= best_d:
			best_d = d
			best = e
	return best

func _move_pierce(delta: float) -> void:
	global_position += dir * speed * delta
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.is_queued_for_deletion() or _hit.has(e.get_instance_id()):
			continue
		if e.stealth and not can_hit_stealth:
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
		if e.stealth and not can_hit_stealth:
			continue
		if global_position.distance_to(e.global_position) <= splash + e.radius:
			e.take_damage(damage, ignore_armor)
			if debuff:
				_random_debuff(e)
	_spawn_boom()
	# 爆裂榴弹炮：分裂出可见的小炸弹，二次爆炸
	if split > 0 and get_parent() != null:
		for i in split:
			var b := Projectile.new()
			b.mode = "aoe"
			b.damage = damage * 0.6
			b.splash = splash * 0.7
			b.debuff = debuff
			b.ignore_armor = ignore_armor
			b.color = color
			b.bomblet = true
			b.can_hit_stealth = can_hit_stealth
			b.global_position = global_position
			b.dest = global_position + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(45.0, 95.0)
			b.speed = 300.0
			get_parent().add_child(b)
	queue_free()

func _spawn_boom() -> void:
	if get_parent() == null:
		return
	var boom := Boom.new()
	boom.radius = maxf(splash, 30.0)
	boom.color = color
	boom.global_position = global_position
	get_parent().add_child(boom)

func _random_debuff(e: Enemy) -> void:
	match randi() % 3:
		0: e.apply_debuff("slow", 0.5, 1.8)      # 冰冻减速
		1: e.apply_debuff("burn", damage * 0.4, 2.0)  # 灼烧
		_: e.apply_debuff("slow", 0.25, 1.0)     # 麻痹(强减速)

func _draw() -> void:
	if mode == "aoe":
		draw_circle(Vector2.ZERO, 4.0 if bomblet else 7.0, color)
	elif mode == "pierce":
		draw_line(Vector2.ZERO, -dir * 16.0, color, 4.0)
		draw_circle(Vector2.ZERO, 4.0, color.lightened(0.3))
	elif mode == "bounce":
		draw_circle(Vector2.ZERO, 6.0, color)
		draw_arc(Vector2.ZERO, 8.0, 0.0, TAU, 12, Color(1, 1, 1, 0.5), 1.5)
	else:
		draw_circle(Vector2.ZERO, 5.0, color)
