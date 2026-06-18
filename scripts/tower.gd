extends Node2D
class_name Tower
## 数据驱动防御塔。按 tower_def 的 bhv 决定开火方式：
##  pierce -> 直线穿透弹 ; aoe -> 抛射范围弹 ; single -> 追踪单体弹。

var id: String = "B"
var def: Dictionary = {}
var range_r: float = 195.0
var damage: float = 8.0
var fire_interval: float = 0.35
var bhv: String = "single"
var pierce: int = 0
var splash: float = 0.0
var debuff: bool = false
var ignore_armor: float = 0.0
var color: Color = Color.WHITE
var tier: int = 1

var _cooldown: float = 0.0
var projectiles_parent: Node = null

func setup(tower_id: String) -> void:
	id = tower_id
	def = TowerDefs.get_def(id)
	range_r = float(def.get("rng", 195.0))
	damage = float(def.get("dmg", 8.0))
	fire_interval = float(def.get("cd", 0.35))
	bhv = String(def.get("bhv", "single"))
	pierce = int(def.get("pierce", 0))
	splash = float(def.get("splash", 0.0))
	debuff = bool(def.get("debuff", false))
	tier = int(def.get("t", 1))
	color = TowerDefs.color_of(id)
	# 穿甲系无视部分护甲
	if id in ["LB", "rapid_ap", "ele_ap", "rapid_ap_chain"]:
		ignore_armor = 0.3
	queue_redraw()

func _process(delta: float) -> void:
	_cooldown -= delta
	if _cooldown <= 0.0:
		var t := _find_target()
		if t != null:
			_shoot(t)
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

func _shoot(t: Enemy) -> void:
	if projectiles_parent == null:
		return
	var p := Projectile.new()
	p.damage = damage
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

func _draw() -> void:
	# 射程圈
	draw_arc(Vector2.ZERO, range_r, 0.0, TAU, 48, Color(color.r, color.g, color.b, 0.10), 1.5)
	# 底座（猪），等级越高越大
	var r := 16.0 + tier * 2.0
	draw_circle(Vector2.ZERO, r, Color(0.96, 0.66, 0.74))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 24, Color(0.7, 0.4, 0.5), 2.0)
	# 鼻子
	draw_circle(Vector2(0, 3), 6.0, Color(0.86, 0.5, 0.58))
	# 武器配色块（表示元素/武器）
	draw_circle(Vector2(0, -r * 0.4), 6.0, color)
	# 等级点
	for i in tier:
		draw_circle(Vector2(-6.0 + i * 6.0, r + 6.0), 2.5, color)
