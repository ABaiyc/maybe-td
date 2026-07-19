extends Node2D
class_name Enemy
## 数据驱动的狼。沿路径行进；到终点转「围攻国王」状态，停下定时攻击国王（仍可被塔击杀）。
## 支持元素 debuff：slow(减速) / burn(灼烧DoT)。armor 提供伤害减免。

var def: Dictionary
var waypoints: PackedVector2Array
var index: int = 1
var base_speed: float = 95.0
var max_hp: float = 40.0
var hp: float = 40.0
var armor: float = 0.0
var reward: int = 8
var atk: float = 4.0
var radius: float = 13.0
var is_boss: bool = false
var color: Color = Color.GRAY
var mech: String = ""            # Boss 机制: reroute(改路) / stealth(伪装)
var stealth: bool = false        # 伪装态：自动索敌无法锁定，仅 E 系范围伤害可命中
var alt_branches: Array = []     # 改路用备用分支（由 main 注入）
var _reroute_thresholds: Array = [0.75, 0.5, 0.25]

# debuff
var slow_factor: float = 1.0
var slow_time: float = 0.0
var burn_dps: float = 0.0
var burn_time: float = 0.0
var mark: float = 0.0       # 集火标记：受到伤害放大 (1+mark)
var mark_time: float = 0.0

# 围攻
var besieging: bool = false
var _besiege_cd: float = 0.0
const BESIEGE_INTERVAL := 0.8
var _king: Node2D = null

func setup(enemy_def: Dictionary, wp: PackedVector2Array, hp_mult: float = 1.0) -> void:
	def = enemy_def
	waypoints = wp
	max_hp = float(def.get("hp", 40.0)) * hp_mult
	hp = max_hp
	base_speed = float(def.get("speed", 95.0))
	armor = float(def.get("armor", 0.0))
	reward = int(def.get("reward", 8))
	atk = float(def.get("atk", 4.0))
	radius = float(def.get("radius", 13.0))
	is_boss = bool(def.get("boss", false))
	mech = String(def.get("mech", ""))
	stealth = mech == "stealth"
	color = Color(def.get("col", "888888"))
	position = wp[0]

func _ready() -> void:
	add_to_group("enemies")

func _process(delta: float) -> void:
	if not GameState.running:
		return
	_tick_debuffs(delta)
	if besieging:
		_besiege(delta)
		return
	_advance(delta)

func _advance(delta: float) -> void:
	if index >= waypoints.size():
		_start_besiege()
		return
	var target: Vector2 = waypoints[index]
	var to_target: Vector2 = target - global_position
	var dist: float = to_target.length()
	var step: float = base_speed * slow_factor * delta
	if step >= dist:
		global_position = target
		index += 1
		if index >= waypoints.size():
			_start_besiege()
	else:
		global_position += to_target / dist * step

func _start_besiege() -> void:
	besieging = true
	_king = get_tree().get_first_node_in_group("king")

func _besiege(delta: float) -> void:
	# 靠到国王身边一圈
	if _king != null and is_instance_valid(_king):
		var to_king: Vector2 = _king.global_position - global_position
		var d: float = to_king.length()
		if d > 56.0:
			global_position += to_king / d * base_speed * slow_factor * delta
	_besiege_cd -= delta
	if _besiege_cd <= 0.0:
		_besiege_cd = BESIEGE_INTERVAL
		GameState.damage_king(atk)

func _tick_debuffs(delta: float) -> void:
	if slow_time > 0.0:
		slow_time -= delta
		if slow_time <= 0.0:
			slow_factor = 1.0
	if burn_time > 0.0:
		burn_time -= delta
		_apply_damage(burn_dps * delta, true)
	if mark_time > 0.0:
		mark_time -= delta
		if mark_time <= 0.0:
			mark = 0.0

func apply_debuff(kind: String, power: float, duration: float) -> void:
	match kind:
		"slow", "freeze", "paralyze":
			slow_factor = minf(slow_factor, power)
			slow_time = maxf(slow_time, duration)
		"burn":
			burn_dps = maxf(burn_dps, power)
			burn_time = maxf(burn_time, duration)
	queue_redraw()

func take_damage(d: float, ignore_armor: float = 0.0) -> void:
	var eff_armor: float = maxf(0.0, armor - ignore_armor)
	_apply_damage(d * (1.0 - eff_armor) * (1.0 + mark), false)

## 伪装判定：非伪装敌人谁都能打；伪装敌人只有成分含 E(元素) 的塔能锁定/命中
func hittable_by(comp: String) -> bool:
	return not stealth or comp.contains("E")

func apply_mark(stack: float, max_mark: float, dur: float) -> void:
	mark = minf(max_mark, mark + stack)
	mark_time = maxf(mark_time, dur)
	queue_redraw()

func _apply_damage(amount: float, _is_dot: bool) -> void:
	if hp <= 0.0:
		return
	hp -= amount
	if hp <= 0.0:
		GameState.add_gold(reward)
		queue_free()
	else:
		_check_reroute()
		queue_redraw()

## 头狼：血量掉过阈值时跳到备用分支路径（变异改路）
func _check_reroute() -> void:
	if mech != "reroute" or besieging or alt_branches.is_empty():
		return
	var ratio := hp / max_hp
	while not _reroute_thresholds.is_empty() and ratio <= _reroute_thresholds[0]:
		_reroute_thresholds.pop_front()
		_do_reroute()

func _do_reroute() -> void:
	var branch: Array = alt_branches[randi() % alt_branches.size()]
	var new_wp := PackedVector2Array(branch)
	# 找分支上最近的路点，从那里继续走
	var best_i := 0
	var best_d := INF
	for i in new_wp.size():
		var d := global_position.distance_to(new_wp[i])
		if d < best_d:
			best_d = d
			best_i = i
	waypoints = new_wp
	index = best_i
	_howl_flash = 0.5
	queue_redraw()

var _howl_flash := 0.0

func _draw() -> void:
	var body := color
	if slow_time > 0.0:
		body = body.lerp(Color(0.5, 0.7, 1.0), 0.4)  # 冰冻泛蓝
	if stealth:
		# 伪装态：羊皮白 + 半透明
		body = Color(0.93, 0.9, 0.82, 0.55)
	if _howl_flash > 0.0:
		_howl_flash -= 0.016
		draw_arc(Vector2.ZERO, radius + 8.0, 0.0, TAU, 24, Color(1, 0.3, 0.2, _howl_flash), 3.0)
	draw_circle(Vector2.ZERO, radius, body)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 24, body.darkened(0.5), 2.0)
	# 尖耳朵（狼）
	draw_colored_polygon(PackedVector2Array([
		Vector2(-radius * 0.6, -radius * 0.5), Vector2(-radius * 0.9, -radius * 1.4), Vector2(-radius * 0.2, -radius * 0.9)
	]), body.darkened(0.2))
	draw_colored_polygon(PackedVector2Array([
		Vector2(radius * 0.6, -radius * 0.5), Vector2(radius * 0.9, -radius * 1.4), Vector2(radius * 0.2, -radius * 0.9)
	]), body.darkened(0.2))
	if burn_time > 0.0:
		draw_arc(Vector2.ZERO, radius + 3.0, 0.0, TAU, 16, Color(1.0, 0.5, 0.1, 0.8), 2.0)
	# 血条
	var w: float = radius * 2.2
	var ratio: float = clampf(hp / max_hp, 0.0, 1.0)
	var y: float = -radius - (12.0 if is_boss else 9.0)
	draw_rect(Rect2(-w / 2.0, y, w, 5.0), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(-w / 2.0, y, w * ratio, 5.0), Color(0.9, 0.3, 0.3) if is_boss else Color(0.3, 0.9, 0.4))
