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
var mech: String = ""            # Boss 机制: rage(狂暴加速) / stealth(伪装)
var stealth: bool = false        # 伪装态：自动索敌无法锁定，仅 E 系范围伤害可命中
var _rage_thresholds: Array = [0.75, 0.5, 0.25]
var _rage_t: float = 0.0         # 狂暴剩余时间（期间加速）
const RAGE_SPEED := 2.4
const RAGE_DUR := 1.6

# debuff
var slow_factor: float = 1.0
var slow_time: float = 0.0
var burn_dps: float = 0.0
var burn_time: float = 0.0
var mark: float = 0.0       # 集火标记：受到伤害放大 (1+mark)
var mark_time: float = 0.0

# 伤害数字（0.4s 合并一次，避免激光每帧刷屏）
var _dmg_accum: float = 0.0
var _dmg_t: float = 0.0

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
	_dmg_t -= delta
	if _dmg_accum >= 0.5 and _dmg_t <= 0.0:
		_flush_damage_number()
	if besieging:
		_besiege(delta)
		return
	_advance(delta)

func _flush_damage_number() -> void:
	if _dmg_accum < 0.5 or get_parent() == null:
		return
	var n := DamageNumber.new()
	n.amount = _dmg_accum
	n.global_position = global_position + Vector2(randf_range(-8, 8), -radius - 8.0)
	get_parent().add_child(n)
	_dmg_accum = 0.0
	_dmg_t = 0.4

func _advance(delta: float) -> void:
	if index >= waypoints.size():
		_start_besiege()
		return
	var target: Vector2 = waypoints[index]
	var to_target: Vector2 = target - global_position
	var dist: float = to_target.length()
	var step: float = _speed() * delta
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
			global_position += to_king / d * _speed() * delta
	_besiege_cd -= delta
	if _besiege_cd <= 0.0:
		_besiege_cd = BESIEGE_INTERVAL
		GameState.damage_king(atk)

func _speed() -> float:
	var s := base_speed * slow_factor
	if _rage_t > 0.0:
		s = base_speed * RAGE_SPEED  # 狂暴期间无视减速全速冲刺
	return s

func _tick_debuffs(delta: float) -> void:
	if _rage_t > 0.0:
		_rage_t -= delta
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
	_dmg_accum += amount
	if hp <= 0.0:
		_flush_damage_number()
		GameState.add_gold(reward)
		queue_free()
	else:
		_check_rage()
		queue_redraw()

## 头狼：血量每掉过 75%/50%/25% 阈值 → 瞬间狂暴加速 + 清除自身负面效果
func _check_rage() -> void:
	if mech != "rage":
		return
	var ratio := hp / max_hp
	while not _rage_thresholds.is_empty() and ratio <= _rage_thresholds[0]:
		_rage_thresholds.pop_front()
		_do_rage()

func _do_rage() -> void:
	# 清除负面效果
	slow_factor = 1.0
	slow_time = 0.0
	burn_dps = 0.0
	burn_time = 0.0
	mark = 0.0
	mark_time = 0.0
	# 狂暴加速
	_rage_t = RAGE_DUR
	_howl_flash = 0.6
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
	if _rage_t > 0.0:
		body = body.lerp(Color(1.0, 0.3, 0.2), 0.35)  # 狂暴泛红
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
