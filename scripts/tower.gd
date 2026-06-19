extends Node2D
class_name Tower
## 数据驱动防御塔。按 TowerDefs.attack_of(id) 的攻击原型分派，忠实还原设计稿：
## beam 持续激光 / proj 弹道 / snipe 狙击 / domain 领域 / mine 布雷 /
## charge 充能炮 / link 塔间连线 / aura 光环增益 / mark 集火标记。

var id: String = "B"
var def: Dictionary = {}
var atk: String = "proj"
var bhv: String = "single"
var range_r: float = 195.0
var damage: float = 8.0
var fire_interval: float = 0.35
var pierce: int = 0
var splash: float = 0.0
var debuff: bool = false
var ignore_armor: float = 0.0
var color: Color = Color.WHITE
var tier: int = 1
var waypoints: PackedVector2Array

var projectiles_parent: Node = null

const MINE_CAP := 6
const BEAM_DPS_SCALE := 2.0

var _cooldown: float = 0.0
var _charge: float = 0.0
var _flash: float = 0.0
var _flash_to: Vector2 = Vector2.ZERO
var _beam_pts: Array = []
var _link_pts: Array = []
var _target: Enemy = null

func _ready() -> void:
	add_to_group("towers")

func setup(tower_id: String) -> void:
	id = tower_id
	def = TowerDefs.get_def(id)
	atk = TowerDefs.attack_of(id)
	bhv = String(def.get("bhv", "single"))
	range_r = float(def.get("rng", 195.0))
	damage = float(def.get("dmg", 8.0))
	fire_interval = float(def.get("cd", 0.35))
	pierce = int(def.get("pierce", 0))
	splash = float(def.get("splash", 0.0))
	debuff = bool(def.get("debuff", false))
	tier = int(def.get("t", 1))
	color = TowerDefs.color_of(id)
	if id in ["LB", "rapid_ap", "ele_ap", "rapid_ap_chain"]:
		ignore_armor = 0.3
	queue_redraw()

func _process(delta: float) -> void:
	if not GameState.running:
		return
	match atk:
		"beam": _do_beam(delta)
		"domain": _do_domain(delta)
		"mine": _do_mine(delta)
		"charge": _do_charge(delta)
		"link": _do_link(delta)
		"snipe": _do_cd(delta, _fire_snipe)
		"mark": _do_cd(delta, _fire_mark)
		"aura": pass
		_: _do_cd(delta, _fire_projectile)
	if _flash > 0.0:
		_flash -= delta
		if _flash <= 0.0:
			queue_redraw()

# ── 通用 ──
func _enemies() -> Array:
	return get_tree().get_nodes_in_group("enemies")

func _do_cd(delta: float, fn: Callable) -> void:
	_cooldown -= delta
	if _cooldown <= 0.0:
		if fn.call():
			_cooldown = fire_interval

func _catalyst_mult() -> float:
	var m := 1.0
	for o in get_tree().get_nodes_in_group("towers"):
		if o == self or not is_instance_valid(o):
			continue
		if o.atk == "aura" and o.global_position.distance_to(global_position) <= o.range_r:
			m += 0.3
	return m

func _find_nearest() -> Enemy:
	var best: Enemy = null
	var best_d := range_r
	for e in _enemies():
		if e.is_queued_for_deletion():
			continue
		var d: float = global_position.distance_to(e.global_position)
		if d <= best_d:
			best_d = d
			best = e
	return best

func _find_highest_hp() -> Enemy:
	var best: Enemy = null
	var best_hp := -1.0
	for e in _enemies():
		if e.is_queued_for_deletion():
			continue
		if global_position.distance_to(e.global_position) <= range_r and e.hp > best_hp:
			best_hp = e.hp
			best = e
	return best

func _find_farthest() -> Enemy:
	var best: Enemy = null
	var best_i := -1
	for e in _enemies():
		if e.is_queued_for_deletion():
			continue
		if global_position.distance_to(e.global_position) <= range_r and e.index > best_i:
			best_i = e.index
			best = e
	return best

func _dist_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t: float = 0.0 if ab.length_squared() == 0.0 else clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)

# ── 激光束 ──
func _do_beam(delta: float) -> void:
	if _target == null or not is_instance_valid(_target) or _target.is_queued_for_deletion() \
			or global_position.distance_to(_target.global_position) > range_r:
		_target = _find_nearest()
	_beam_pts = []
	if _target == null:
		queue_redraw()
		return
	var dirv := (_target.global_position - global_position)
	dirv = Vector2.RIGHT if dirv.length() < 1.0 else dirv.normalized()
	var along: Array = []
	for e in _enemies():
		if e.is_queued_for_deletion():
			continue
		var rel: Vector2 = e.global_position - global_position
		var proj: float = rel.dot(dirv)
		if proj < 0.0 or proj > range_r:
			continue
		if (rel - dirv * proj).length() <= e.radius + 7.0:
			along.append([proj, e])
	along.sort_custom(func(a, b): return a[0] < b[0])
	var dps := damage * BEAM_DPS_SCALE * _catalyst_mult()
	_cooldown -= delta
	var do_debuff := debuff and _cooldown <= 0.0
	if do_debuff:
		_cooldown = 0.4
	var far := global_position
	var hits := 0
	for pair in along:
		if hits > pierce:
			break
		var e: Enemy = pair[1]
		e.take_damage(dps * delta, ignore_armor)
		if do_debuff:
			e.apply_debuff("slow", 0.6, 1.0) if randf() < 0.5 else e.apply_debuff("burn", dps * 0.3, 1.2)
		far = e.global_position
		hits += 1
	_beam_pts = [global_position, far if hits > 0 else global_position + dirv * range_r]
	queue_redraw()

# ── 领域 ──
func _do_domain(delta: float) -> void:
	var dps := damage * BEAM_DPS_SCALE * _catalyst_mult() * delta
	_cooldown -= delta
	var do_debuff := debuff and _cooldown <= 0.0
	if do_debuff:
		_cooldown = 0.5
	for e in _enemies():
		if e.is_queued_for_deletion():
			continue
		if global_position.distance_to(e.global_position) <= splash + e.radius:
			e.take_damage(dps, ignore_armor)
			if do_debuff:
				e.apply_debuff("slow", 0.7, 0.8)
	queue_redraw()

# ── 布雷 ──
func _do_mine(delta: float) -> void:
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	_cooldown = fire_interval
	if _active_mines() >= MINE_CAP:
		return
	var p := _random_path_point()
	if p.x < -9000.0:
		return
	var m := Mine.new()
	m.damage = damage * _catalyst_mult()
	m.splash = splash
	m.debuff = debuff
	m.owner_tower = self
	m.global_position = p
	if projectiles_parent != null:
		projectiles_parent.add_child(m)

func _active_mines() -> int:
	if projectiles_parent == null:
		return 0
	var n := 0
	for c in projectiles_parent.get_children():
		if c is Mine and c.owner_tower == self and not c.is_queued_for_deletion():
			n += 1
	return n

func _random_path_point() -> Vector2:
	if waypoints.size() < 2:
		return Vector2(-9999, -9999)
	var cands: Array = []
	var samples := 48
	for i in samples:
		var tt: float = float(i) / float(samples - 1) * float(waypoints.size() - 1)
		var seg: int = mini(int(tt), waypoints.size() - 2)
		var f: float = tt - seg
		var pt: Vector2 = waypoints[seg].lerp(waypoints[seg + 1], f)
		if global_position.distance_to(pt) <= range_r:
			cands.append(pt)
	if cands.is_empty():
		return Vector2(-9999, -9999)
	return cands[randi() % cands.size()]

# ── 充能炮 ──
func _do_charge(delta: float) -> void:
	_charge += delta
	if _charge < fire_interval:
		return
	var t := _find_farthest()
	if t == null:
		return
	_charge = 0.0
	var dirv := (t.global_position - global_position).normalized()
	var endp := global_position + dirv * 1600.0
	for e in _enemies():
		if e.is_queued_for_deletion():
			continue
		if _dist_seg(e.global_position, global_position, endp) <= 38.0 + e.radius:
			e.take_damage(damage * _catalyst_mult(), ignore_armor)
	_flash = 0.22
	_flash_to = endp
	queue_redraw()

# ── 塔间连线 ──
func _do_link(delta: float) -> void:
	_link_pts = []
	var dps := damage * 1.5 * _catalyst_mult() * delta
	for o in get_tree().get_nodes_in_group("towers"):
		if o == self or not is_instance_valid(o) or o.atk != "link":
			continue
		if global_position.distance_to(o.global_position) > range_r:
			continue
		_link_pts.append(o.global_position)
		for e in _enemies():
			if e.is_queued_for_deletion():
				continue
			if _dist_seg(e.global_position, global_position, o.global_position) <= 12.0 + e.radius:
				e.take_damage(dps, ignore_armor)
	queue_redraw()

# ── 狙击 / 标记 / 弹道（cd 触发）──
func _fire_snipe() -> bool:
	var t := _find_highest_hp()
	if t == null:
		return false
	var dmg := damage * _catalyst_mult()
	if id == "precision_snipe":
		dmg *= 3.0
	t.take_damage(dmg, ignore_armor)
	_flash = 0.15
	_flash_to = t.global_position
	queue_redraw()
	return true

func _fire_mark() -> bool:
	var t := _find_nearest()
	if t == null:
		return false
	t.apply_mark(0.2, 0.6, 3.0)
	t.take_damage(damage * _catalyst_mult(), ignore_armor)
	_flash = 0.12
	_flash_to = t.global_position
	queue_redraw()
	return true

func _fire_projectile() -> bool:
	var t := _find_nearest()
	if t == null or projectiles_parent == null:
		return false
	# 多发/分裂的特殊弹道塔（忠实还原设计稿）
	match id:
		"barrage": _spawn_fan(t, 12, 82.0)        # 弹幕炮塔：扇形12发随机元素
		"EE": _spawn_fan(t, 3, 26.0)              # 元素风暴：火/冰/雷三球
		"gl_array": _spawn_fan(t, 6, 55.0)        # 元素榴弹阵列：齐射6发
		"burst_gl": _spawn_aoe(t.global_position, splash, damage, 3)  # 爆裂榴弹炮：分裂3小炸弹
		_: _spawn_one(t)
	return true

func _spawn_one(t: Enemy) -> void:
	var p := Projectile.new()
	p.damage = damage * _catalyst_mult()
	p.pierce = pierce
	p.splash = splash
	p.debuff = debuff
	p.ignore_armor = ignore_armor
	p.color = color
	p.global_position = global_position
	match bhv:
		"pierce":
			p.mode = "pierce"
			p.dir = (t.global_position - global_position).normalized()
			p.speed = 720.0
		"aoe":
			p.mode = "aoe"
			p.dest = t.global_position
			p.speed = 360.0
		_:
			p.mode = "single"
			p.target = t
			p.speed = 520.0
	projectiles_parent.add_child(p)

## 扇形齐射：朝目标方向铺开 count 发元素弹，每发随机元素
func _spawn_fan(t: Enemy, count: int, spread_deg: float) -> void:
	var base := t.global_position - global_position
	var dist := clampf(base.length(), 90.0, range_r)
	var dir := base.normalized() if base.length() > 1.0 else Vector2.RIGHT
	var mult := _catalyst_mult()
	for i in count:
		var frac := 0.0 if count <= 1 else (float(i) / float(count - 1) - 0.5)
		var d := dir.rotated(deg_to_rad(spread_deg) * frac)
		var p := Projectile.new()
		p.mode = "aoe"
		p.damage = damage * mult
		p.splash = maxf(splash * 0.7, 36.0)
		p.debuff = true
		p.ignore_armor = ignore_armor
		p.color = color
		p.global_position = global_position
		p.dest = global_position + d * dist
		p.speed = 330.0
		projectiles_parent.add_child(p)

func _spawn_aoe(dest: Vector2, sp: float, dmg: float, split: int) -> void:
	var p := Projectile.new()
	p.mode = "aoe"
	p.damage = dmg * _catalyst_mult()
	p.splash = sp
	p.debuff = debuff
	p.ignore_armor = ignore_armor
	p.color = color
	p.split = split
	p.global_position = global_position
	p.dest = dest
	p.speed = 340.0
	projectiles_parent.add_child(p)

# ── 绘制 ──
func _draw() -> void:
	draw_arc(Vector2.ZERO, range_r, 0.0, TAU, 48, Color(color.r, color.g, color.b, 0.08), 1.5)
	# 领域范围
	if atk == "domain":
		draw_circle(Vector2.ZERO, splash, Color(color.r, color.g, color.b, 0.10))
		draw_arc(Vector2.ZERO, splash, 0.0, TAU, 48, Color(color.r, color.g, color.b, 0.4), 2.0)
	# 激光束
	if atk == "beam" and _beam_pts.size() == 2:
		var w := 3.0 + tier * 1.5
		draw_line(to_local(_beam_pts[0]), to_local(_beam_pts[1]), Color(color.r, color.g, color.b, 0.85), w)
		draw_line(to_local(_beam_pts[0]), to_local(_beam_pts[1]), Color(1, 1, 1, 0.6), w * 0.4)
	# 塔间连线
	if atk == "link":
		for q in _link_pts:
			draw_line(Vector2.ZERO, to_local(q), Color(color.r, color.g, color.b, 0.7), 3.0)
	# 充能/狙击/标记 闪光线
	if _flash > 0.0:
		var lw := 10.0 if atk == "charge" else 2.5
		draw_line(Vector2.ZERO, to_local(_flash_to), Color(color.r, color.g, color.b, _flash * 4.0), lw)
	# 猪底座
	var r := 16.0 + tier * 2.0
	draw_circle(Vector2.ZERO, r, Color(0.96, 0.66, 0.74))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 24, Color(0.7, 0.4, 0.5), 2.0)
	draw_circle(Vector2(0, 3), 6.0, Color(0.86, 0.5, 0.58))
	draw_circle(Vector2(0, -r * 0.4), 6.0, color)
	for i in tier:
		draw_circle(Vector2(-6.0 + i * 6.0, r + 6.0), 2.5, color)
