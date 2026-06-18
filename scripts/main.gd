extends Node2D
## 关卡编排：路径、塔位、波次生成、HUD、输入。第一个可玩切片。

const TOWER_COST := 50
const SLOT_SIZE := 44.0
const WAVE_BONUS := 40

var waypoints := PackedVector2Array([
	Vector2(-40, 360), Vector2(220, 360), Vector2(220, 150),
	Vector2(540, 150), Vector2(540, 540), Vector2(860, 540),
	Vector2(860, 250), Vector2(1240, 250),
])

var slot_positions := [
	Vector2(120, 250), Vector2(330, 260), Vector2(360, 430),
	Vector2(650, 250), Vector2(660, 450), Vector2(760, 360),
	Vector2(980, 360), Vector2(1010, 150), Vector2(440, 540),
]
var occupied := {}

var waves := [
	{"count": 8, "hp": 36.0, "speed": 90.0},
	{"count": 12, "hp": 52.0, "speed": 95.0},
	{"count": 16, "hp": 70.0, "speed": 100.0},
	{"count": 20, "hp": 95.0, "speed": 105.0},
	{"count": 24, "hp": 130.0, "speed": 112.0},
]

var enemies_container: Node2D
var towers_container: Node2D
var projectiles_container: Node2D
var spawn_timer: Timer

var wave_active := false
var spawn_finished := false
var to_spawn := 0
var cur_wave_cfg := {}

var gold_label: Label
var lives_label: Label
var wave_label: Label
var message_label: Label
var wave_button: Button

func _ready() -> void:
	_build_containers()
	_build_hud()
	GameState.reset()
	GameState.changed.connect(_refresh_hud)
	GameState.game_over.connect(_on_game_over)
	_refresh_hud()
	_set_message("点击空地建塔（%d 金），然后按「开始下一波」迎敌。\n塔会自动攻击射程内最近的敌人。" % TOWER_COST)
	queue_redraw()

func _build_containers() -> void:
	enemies_container = Node2D.new()
	enemies_container.name = "Enemies"
	add_child(enemies_container)
	towers_container = Node2D.new()
	towers_container.name = "Towers"
	add_child(towers_container)
	projectiles_container = Node2D.new()
	projectiles_container.name = "Projectiles"
	add_child(projectiles_container)
	spawn_timer = Timer.new()
	spawn_timer.one_shot = false
	spawn_timer.wait_time = 0.65
	spawn_timer.timeout.connect(_on_spawn_tick)
	add_child(spawn_timer)

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	gold_label = _mk_label(layer, Vector2(20, 14), 24)
	lives_label = _mk_label(layer, Vector2(230, 14), 24)
	wave_label = _mk_label(layer, Vector2(430, 14), 24)
	message_label = _mk_label(layer, Vector2(340, 285), 26)
	message_label.size = Vector2(600, 150)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wave_button = Button.new()
	wave_button.text = "开始下一波"
	wave_button.position = Vector2(1070, 12)
	wave_button.add_theme_font_size_override("font_size", 20)
	wave_button.pressed.connect(_on_wave_button)
	layer.add_child(wave_button)

func _mk_label(parent: Node, pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	parent.add_child(l)
	return l

func _refresh_hud() -> void:
	gold_label.text = "金币: %d" % GameState.gold
	lives_label.text = "生命: %d" % GameState.lives
	wave_label.text = "波次: %d/%d" % [GameState.wave, waves.size()]

func _on_wave_button() -> void:
	if wave_active or not GameState.running or GameState.wave >= waves.size():
		return
	_start_wave()

func _start_wave() -> void:
	GameState.wave += 1
	cur_wave_cfg = waves[GameState.wave - 1]
	to_spawn = int(cur_wave_cfg["count"])
	wave_active = true
	spawn_finished = false
	wave_button.disabled = true
	_set_message("")
	GameState.changed.emit()
	spawn_timer.start()
	_on_spawn_tick()

func _on_spawn_tick() -> void:
	if to_spawn <= 0:
		spawn_timer.stop()
		spawn_finished = true
		return
	_spawn_enemy()
	to_spawn -= 1
	if to_spawn <= 0:
		spawn_timer.stop()
		spawn_finished = true

func _spawn_enemy() -> void:
	var e := Enemy.new()
	e.setup(waypoints, float(cur_wave_cfg["hp"]), float(cur_wave_cfg["speed"]), 8)
	enemies_container.add_child(e)

func _process(_delta: float) -> void:
	if wave_active and spawn_finished and _alive_enemies() == 0:
		_on_wave_cleared()

func _alive_enemies() -> int:
	var n := 0
	for e in enemies_container.get_children():
		if not e.is_queued_for_deletion():
			n += 1
	return n

func _on_wave_cleared() -> void:
	wave_active = false
	if GameState.wave >= waves.size():
		GameState.running = false
		GameState.game_over.emit(true)
	else:
		wave_button.disabled = false
		GameState.add_gold(WAVE_BONUS)
		_set_message("第 %d 波清空！+%d 金，准备下一波。" % [GameState.wave, WAVE_BONUS])

func _on_game_over(won: bool) -> void:
	wave_button.disabled = true
	spawn_timer.stop()
	if won:
		_set_message("🏆 胜利！%d 波全部击退。\n按 R 重新开始。" % waves.size())
	else:
		_set_message("💀 基地失守……\n按 R 重新开始。")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		get_tree().reload_current_scene()
		return
	if event.is_action_pressed("place_tower"):
		_try_place_tower(get_global_mouse_position())

func _try_place_tower(pos: Vector2) -> void:
	if not GameState.running:
		return
	var idx := _slot_at(pos)
	if idx == -1:
		return
	if occupied.has(idx):
		_set_message("这个位置已经有塔了。")
		return
	if not GameState.spend_gold(TOWER_COST):
		_set_message("金币不足！建塔需要 %d 金。" % TOWER_COST)
		return
	var t := Tower.new()
	t.position = slot_positions[idx]
	t.projectiles_parent = projectiles_container
	towers_container.add_child(t)
	occupied[idx] = t
	_set_message("")
	queue_redraw()

func _slot_at(pos: Vector2) -> int:
	for i in slot_positions.size():
		if pos.distance_to(slot_positions[i]) <= SLOT_SIZE * 0.6:
			return i
	return -1

func _set_message(t: String) -> void:
	message_label.text = t

func _draw() -> void:
	draw_polyline(waypoints, Color(0.16, 0.16, 0.2), 48.0)
	draw_polyline(waypoints, Color(0.28, 0.28, 0.34), 38.0)
	draw_circle(waypoints[0], 16.0, Color(0.8, 0.3, 0.3))
	draw_circle(waypoints[waypoints.size() - 1], 18.0, Color(0.2, 0.5, 0.9))
	for i in slot_positions.size():
		if occupied.has(i):
			continue
		var p: Vector2 = slot_positions[i]
		var r := Rect2(p - Vector2(SLOT_SIZE, SLOT_SIZE) / 2.0, Vector2(SLOT_SIZE, SLOT_SIZE))
		draw_rect(r, Color(0.3, 0.8, 0.4, 0.18))
		draw_rect(r, Color(0.4, 0.9, 0.5, 0.5), false, 2.0)
