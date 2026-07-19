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
var comp: String = ""       # 元素成分（含E可锁定伪装敌人）

var projectiles_parent: Node = null

const MINE_CAP := 6
const BEAM_DPS_SCALE := 2.0

var _cooldown: float = 0.0
var _charge: float = 0.0
var _flash: float = 0.0
var _flash_to: Vector2 = Vector2.ZERO
var _beam_pts: Array = []
var _link_pts: Array = []
var _prism_segs: Array = []
var _target: Enemy = null
var _focus_target: Enemy = null   # 光束爆裂炮聚焦目标
var _focus_t: float = 0.0
var _ramp: int = 0                 # 机枪塔越打越快层数
var _since_fire: float = 0.0
var _ring_cd: float = 0.0          # 双子激光塔
var _ring_count: int = 0

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
	comp = String(def.get("c", id))
	color = TowerDefs.color_of(id)
	if id in ["LB", "rapid_ap", "ele_ap", "rapid_ap_chain"]:
		ignore_armor = 0.3
	queue_redraw()

func _process(delta: float) -> void:
	if not GameState.running:
		return
	_since_fire += delta
	if _since_fire > 3.0 and _ramp > 0:
		_ramp = 0  # 机枪塔停火3秒重置攻速
	match atk:
		"beam": _do_beam(delta)
		"split": _do_prism(delta)
		"ring": _do_ring(delta)
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
			_cooldown = _fire_cd()

func _fire_cd() -> float:
	if id == "BB":
		return maxf(0.1, fire_interval - _ramp * 0.025)  # 越打越快，下限0.1s
	return fire_interval

func _nearest_n(n: int) -> Array:
	var arr: Array = []
	for e in _enemies():
		if e.is_queued_for_deletion() or not e.hittable_by(comp):
			continue
		var d: float = global_position.distance_to(e.global_position)
		if d <= range_r:
			arr.append([d, e])
	arr.sort_custom(func(a, b): return a[0] < b[0])
	var out: Array = []
	for i in mini(n, arr.size()):
		out.append(arr[i][1])
	return out

func _enemies_along(dirv: Vector2) -> Array:
	var along: Array = []
	for e in _enemies():
		if e.is_queued_for_deletion() or not e.hittable_by(comp):
			continue
		var rel: Vector2 = e.global_position - global_position
		var proj: float = rel.dot(dirv)
		if proj < 0.0 or proj > range_r:
			continue
		if (rel - dirv * proj).length() <= e.radius + 7.0:
			along.append([proj, e])
	along.sort_custom(func(a, b): return a[0] < b[0])
	return along

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
		if e.is_queued_for_deletion() or not e.hittable_by(comp):
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
		if e.is_queued_for_deletion() or not e.hittable_by(comp):
			continue
		if global_position.distance_to(e.global_position) <= range_r and e.hp > best_hp:
			best_hp = e.hp
			best = e
	return best

func _find_farthest() -> Enemy:
	var best: Enemy = null
	var best_i := -1
	for e in _enemies():
		if e.is_queued_for_deletion() or not e.hittable_by(comp):
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
	_beam_pts = []
	var burst := id == "beam_burst"
	var targets: Array
	if burst:
		# 锁定单一目标，持续照射累计聚焦时间
		if _focus_target == null or not is_instance_valid(_focus_target) \
				or _focus_target.is_queued_for_deletion() \
				or global_position.distance_to(_focus_target.global_position) > range_r:
			_focus_target = _find_nearest()
			_focus_t = 0.0
		if _focus_target == null:
			queue_redraw()
			return
		targets = [_focus_target]
	else:
		targets = _nearest_n(2 if id == "LL" else 1)   # 聚焦激光：2束打2敌
		if targets.is_empty():
			queue_redraw()
			return
	var dps := damage * BEAM_DPS_SCALE * _catalyst_mult()
	_cooldown -= delta
	# 爆裂炮激光阶段不附元素，只有爆炸那一下才附
	var do_debuff := debuff and not burst and _cooldown <= 0.0
	if do_debuff:
		_cooldown = 0.4
	for tgt in targets:
		var dirv: Vector2 = tgt.global_position - global_position
		dirv = Vector2.RIGHT if dirv.length() < 1.0 else dirv.normalized()
		var far := global_position
		var hits := 0
		for pair in _enemies_along(dirv):
			if hits > pierce:
				break
			var e: Enemy = pair[1]
			e.take_damage(dps * delta, ignore_armor)
			if do_debuff:
				_beam_debuff(e)
			far = e.global_position
			hits += 1
		_beam_pts.append([global_position, far if hits > 0 else global_position + dirv * range_r])
	if burst:
		_focus_t += delta
		if _focus_t >= 1.0:   # 照射1秒触发爆炸
			_focus_t = 0.0
			_beam_burst_explode(_focus_target)
	queue_redraw()

func _beam_debuff(e: Enemy) -> void:
	if randf() < 0.5:
		e.apply_debuff("slow", 0.6, 1.0)
	else:
		e.apply_debuff("burn", damage * BEAM_DPS_SCALE * 0.3, 1.2)

# 光束爆裂炮：聚焦3秒后的范围爆炸（可视化 + 几率附元素）
func _beam_burst_explode(tgt: Enemy) -> void:
	if tgt == null or not is_instance_valid(tgt):
		return
	var pos := tgt.global_position
	var rad := maxf(splash, 110.0)
	if projectiles_parent != null:
		var boom := Boom.new()
		boom.radius = rad
		boom.color = Color(1.0, 0.7, 0.3)
		boom.global_position = pos
		projectiles_parent.add_child(boom)
	var burst_dmg := damage * BEAM_DPS_SCALE * 3.0 * _catalyst_mult()
	for e in _enemies():
		if e.is_queued_for_deletion():
			continue
		if pos.distance_to(e.global_position) <= rad + e.radius:
			e.take_damage(burst_dmg, ignore_armor)
			if randf() < 0.6:
				_beam_debuff(e)

# ── 棱镜折射分裂 ──
func _do_prism(delta: float) -> void:
	_prism_segs = []
	var primary := _find_nearest()
	if primary == null:
		queue_redraw()
		return
	var dps := damage * BEAM_DPS_SCALE * _catalyst_mult()
	var visited := {primary.get_instance_id(): true}
	primary.take_damage(dps * delta, ignore_armor)
	_prism_segs.append([global_position, primary.global_position, 4.0])
	# 一级分裂：最多3道小激光
	for a in _nearest_others(primary.global_position, 3, visited, 130.0):
		a.take_damage(dps * 0.6 * delta, ignore_armor)
		_prism_segs.append([primary.global_position, a.global_position, 2.6])
		# 二级分裂：最多3道小小激光
		for c in _nearest_others(a.global_position, 3, visited, 110.0):
			c.take_damage(dps * 0.36 * delta, ignore_armor)
			_prism_segs.append([a.global_position, c.global_position, 1.6])
	queue_redraw()

func _nearest_others(pos: Vector2, n: int, visited: Dictionary, radius: float) -> Array:
	var arr: Array = []
	for e in _enemies():
		if e.is_queued_for_deletion() or visited.has(e.get_instance_id()) or not e.hittable_by(comp):
			continue
		var d: float = pos.distance_to(e.global_position)
		if d <= radius:
			arr.append([d, e])
	arr.sort_custom(func(a, b): return a[0] < b[0])
	var out: Array = []
	for i in mini(n, arr.size()):
		out.append(arr[i][1])
		visited[arr[i][1].get_instance_id()] = true
	return out

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
	queue_redraw()  # 刷新充能进度条
	if _charge < fire_interval:
		return
	# 蓄满：有目标则自动满威力发射
	if _find_farthest() != null:
		_railgun_fire(1.0)

func _railgun_fire(scale: float) -> void:
	var t := _find_farthest()
	var dirv := (t.global_position - global_position).normalized() if t != null else Vector2.RIGHT
	var endp := global_position + dirv * 1600.0
	var dmg := damage * scale * _catalyst_mult()
	for e in _enemies():
		if e.is_queued_for_deletion() or not e.hittable_by(comp):
			continue
		if _dist_seg(e.global_position, global_position, endp) <= 38.0 + e.radius:
			e.take_damage(dmg, ignore_armor)
	_charge = 0.0
	_flash = 0.22
	_flash_to = endp
	queue_redraw()

## 手动发射（发射按钮触发）：未蓄满也能放，伤害随当前充能比例打折
func manual_fire() -> bool:
	if atk != "charge" or charge_ratio() < 0.1:
		return false
	_railgun_fire(charge_ratio())
	return true

func charge_ratio() -> float:
	return clampf(_charge / fire_interval, 0.0, 1.0) if atk == "charge" else 0.0

# ── 等离子场：连接范围内所有类型的塔，敌人穿过受伤+减速 ──
func _do_link(delta: float) -> void:
	_link_pts = []
	var dps := damage * 1.5 * _catalyst_mult() * delta
	for o in get_tree().get_nodes_in_group("towers"):
		if o == self or not is_instance_valid(o):
			continue
		if global_position.distance_to(o.global_position) > range_r:
			continue
		_link_pts.append(o.global_position)
		for e in _enemies():
			if e.is_queued_for_deletion():
				continue
			if _dist_seg(e.global_position, global_position, o.global_position) <= 12.0 + e.radius:
				e.take_damage(dps, ignore_armor)
				e.apply_debuff("slow", 0.6, 0.5)
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
		"ele_matrix": _fire_ele_matrix()          # 元素矩阵：3道弹射激光
		"BB":                                     # 机枪塔：双管并排 + 越打越快
			_spawn_double(t)
			_ramp = mini(_ramp + 1, 8)
			_since_fire = 0.0
		_: _spawn_one(t)
	return true

func _spawn_double(t: Enemy) -> void:
	var dir := (t.global_position - global_position).normalized()
	var perp := Vector2(-dir.y, dir.x) * 7.0
	for s in [-1.0, 1.0]:
		var p := Projectile.new()
		p.can_hit_stealth = comp.contains("E")
		p.mode = "single"
		p.target = t
		p.damage = damage * _catalyst_mult()
		p.ignore_armor = ignore_armor
		p.color = color
		p.speed = 560.0
		p.global_position = global_position + perp * s
		projectiles_parent.add_child(p)

func _fire_ele_matrix() -> void:
	for tgt in _nearest_n(3):
		var p := Projectile.new()
		p.can_hit_stealth = comp.contains("E")
		p.mode = "bounce"
		p.target = tgt
		p.bounces = 2
		p.damage = damage * _catalyst_mult()
		p.debuff = true
		p.color = color
		p.speed = 600.0
		p.global_position = global_position
		projectiles_parent.add_child(p)

# ── 双子激光塔：扩散收缩伤害圆环，连续2发后2s小cd ──
func _do_ring(delta: float) -> void:
	_ring_cd -= delta
	if _ring_cd > 0.0:
		return
	if _find_nearest() == null:
		_ring_cd = 0.3
		return
	if projectiles_parent != null:
		var r := Ring.new()
		r.max_radius = range_r   # 圆环范围 = 攻击距离
		r.damage = damage * _catalyst_mult()
		r.global_position = global_position
		projectiles_parent.add_child(r)
	_ring_count += 1
	if _ring_count >= 2:
		_ring_count = 0
		_ring_cd = 2.0
	else:
		_ring_cd = 0.5

func _spawn_one(t: Enemy) -> void:
	var p := Projectile.new()
	p.can_hit_stealth = comp.contains("E")
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
		p.can_hit_stealth = comp.contains("E")
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
	p.can_hit_stealth = comp.contains("E")
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
	if atk == "beam":
		var w := 3.0 + tier * 1.5
		for seg in _beam_pts:
			draw_line(to_local(seg[0]), to_local(seg[1]), Color(color.r, color.g, color.b, 0.85), w)
			draw_line(to_local(seg[0]), to_local(seg[1]), Color(1, 1, 1, 0.6), w * 0.4)
	# 棱镜折射光束（主光束 + 分裂小激光）
	if atk == "split":
		for seg in _prism_segs:
			draw_line(to_local(seg[0]), to_local(seg[1]), Color(color.r, color.g, color.b, 0.85), seg[2])
			draw_line(to_local(seg[0]), to_local(seg[1]), Color(1, 1, 1, 0.5), seg[2] * 0.4)
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
	# 轨道炮：充能进度条 + 蓄满提示
	if atk == "charge":
		var ratio := charge_ratio()
		var bw := 46.0
		var by := -r - 16.0
		draw_rect(Rect2(-bw / 2.0, by, bw, 6.0), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-bw / 2.0, by, bw * ratio, 6.0), Color(1.0, 0.85, 0.3) if ratio < 1.0 else Color(0.4, 1.0, 0.5))
		draw_rect(Rect2(-bw / 2.0, by, bw, 6.0), Color(1, 1, 1, 0.3), false, 1.0)
		if ratio >= 1.0:
			draw_string(ThemeDB.fallback_font, Vector2(-40, by - 6.0), "蓄满! 点击发射", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 0.6))
