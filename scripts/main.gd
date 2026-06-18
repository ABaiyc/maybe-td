extends Node2D
## 关卡编排（M1）：读关卡数据 → 大肥猪国王 + 阶段机(开始→10s准备→战斗→结算) +
## 基础塔建造 + 波次生成 + 狼围攻国王的胜负判定。

const SLOT_SIZE := 46.0
const SELL_REFUND := 0.6  # 拆除返还比例

var _debug_autoplay := false

var level: Dictionary
var waypoints: PackedVector2Array
var slot_positions: Array = []
var occupied := {}            # slot_idx -> Tower
var bg_color := Color(0.13, 0.16, 0.12)
var road_color := Color(0.29, 0.35, 0.21)

var enemies_container: Node2D
var towers_container: Node2D
var projectiles_container: Node2D
var king: King
var spawn_timer: Timer
var wave_gap_timer: Timer

# 流程状态
var started := false
var prep_timer := 0.0
var wave_idx := -1
var spawn_queue: Array = []
var all_waves_spawned := false

# 建造
var active_build_id := "L"

# HUD
var gold_label: Label
var king_label: Label
var wave_label: Label
var phase_label: Label
var message_label: Label
var start_button: Button
var build_buttons := {}

func _ready() -> void:
	level = Levels.get_level(0)
	waypoints = PackedVector2Array(level["waypoints"])
	slot_positions = level["slots"]
	bg_color = Color(level.get("bg", "21281b"))
	road_color = Color(level.get("road", "4a5a36"))

	_build_containers()
	_build_king()
	_build_hud()
	GameState.reset((level["waves"] as Array).size())
	GameState.changed.connect(_refresh_hud)
	GameState.game_over.connect(_on_game_over)
	_refresh_hud()
	_set_message("点击「开始」进入 10 秒布防，再迎击狼群！")
	queue_redraw()

	if _debug_autoplay:
		_run_autoplay()

func _build_containers() -> void:
	enemies_container = Node2D.new(); enemies_container.name = "Enemies"; add_child(enemies_container)
	towers_container = Node2D.new(); towers_container.name = "Towers"; add_child(towers_container)
	projectiles_container = Node2D.new(); projectiles_container.name = "Projectiles"; add_child(projectiles_container)
	spawn_timer = Timer.new(); spawn_timer.one_shot = false; spawn_timer.timeout.connect(_on_spawn_tick); add_child(spawn_timer)
	wave_gap_timer = Timer.new(); wave_gap_timer.one_shot = true; wave_gap_timer.timeout.connect(_on_wave_gap_done); add_child(wave_gap_timer)

func _build_king() -> void:
	king = King.new()
	king.position = level["king_pos"]
	add_child(king)

func _build_hud() -> void:
	var layer := CanvasLayer.new(); add_child(layer)
	gold_label = _mk_label(layer, Vector2(20, 12), 22)
	king_label = _mk_label(layer, Vector2(20, 42), 22)
	wave_label = _mk_label(layer, Vector2(250, 12), 22)
	phase_label = _mk_label(layer, Vector2(250, 42), 22)
	message_label = _mk_label(layer, Vector2(340, 280), 26)
	message_label.size = Vector2(600, 160)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# 建造面板（3 基础塔）
	var x := 500.0
	for tid in TowerDefs.BASE_IDS:
		var d := TowerDefs.get_def(tid)
		var b := Button.new()
		b.text = "%s\n%d金" % [d["n"], d["cost"]]
		b.position = Vector2(x, 10)
		b.custom_minimum_size = Vector2(86, 50)
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(_on_build_select.bind(tid))
		layer.add_child(b)
		build_buttons[tid] = b
		x += 94.0
	_highlight_build()

	start_button = Button.new()
	start_button.text = "开始"
	start_button.position = Vector2(1130, 12)
	start_button.custom_minimum_size = Vector2(110, 56)
	start_button.add_theme_font_size_override("font_size", 24)
	start_button.pressed.connect(_on_start)
	layer.add_child(start_button)

func _mk_label(parent: Node, pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	parent.add_child(l)
	return l

func _refresh_hud() -> void:
	gold_label.text = "金币: %d" % GameState.gold
	king_label.text = "国王: %d/%d" % [int(GameState.king_hp), int(GameState.king_max_hp)]
	wave_label.text = "波次: %d/%d" % [GameState.wave, GameState.total_waves]
	match GameState.phase:
		GameState.Phase.PREP:
			phase_label.text = ("准备: %.0f s" % ceil(prep_timer)) if started else "准备中"
		GameState.Phase.COMBAT:
			phase_label.text = "战斗中"
		_:
			phase_label.text = "结算"

func _on_build_select(tid: String) -> void:
	active_build_id = tid
	_highlight_build()

func _highlight_build() -> void:
	for tid in build_buttons:
		build_buttons[tid].modulate = Color(1, 1, 0.5) if tid == active_build_id else Color.WHITE

func _on_start() -> void:
	if started:
		return
	started = true
	prep_timer = GameState.PREP_SECONDS
	start_button.hide()
	GameState.set_phase(GameState.Phase.PREP)
	_set_message("布防！%.0f 秒后狼群来袭。" % prep_timer)

func _process(delta: float) -> void:
	if not GameState.running:
		return
	if GameState.phase == GameState.Phase.PREP and started:
		prep_timer -= delta
		_refresh_hud()
		if prep_timer <= 0.0:
			_start_combat()
	elif GameState.phase == GameState.Phase.COMBAT:
		if all_waves_spawned and _alive_enemies() == 0:
			GameState.win()

func _start_combat() -> void:
	GameState.set_phase(GameState.Phase.COMBAT)
	_set_message("")
	_begin_wave(0)

func _begin_wave(i: int) -> void:
	wave_idx = i
	var waves: Array = level["waves"]
	var w: Dictionary = waves[i]
	GameState.wave = i + 1
	GameState.changed.emit()
	spawn_queue.clear()
	for entry in w["entries"]:
		for n in int(entry[1]):
			spawn_queue.append(entry[0])
	spawn_timer.wait_time = float(w["interval"])
	spawn_timer.start()
	_on_spawn_tick()

func _on_spawn_tick() -> void:
	if spawn_queue.is_empty():
		spawn_timer.stop()
		_after_wave_spawned()
		return
	_spawn_enemy(spawn_queue.pop_front())
	if spawn_queue.is_empty():
		spawn_timer.stop()
		_after_wave_spawned()

func _after_wave_spawned() -> void:
	var waves: Array = level["waves"]
	if wave_idx + 1 < waves.size():
		wave_gap_timer.wait_time = maxf(0.1, float(waves[wave_idx].get("gap", 4.0)))
		wave_gap_timer.start()
	else:
		all_waves_spawned = true

func _on_wave_gap_done() -> void:
	_begin_wave(wave_idx + 1)

func _spawn_enemy(enemy_id: String) -> void:
	var e := Enemy.new()
	e.setup(EnemyDefs.get_def(enemy_id), waypoints)
	enemies_container.add_child(e)

func _alive_enemies() -> int:
	var n := 0
	for e in enemies_container.get_children():
		if not e.is_queued_for_deletion():
			n += 1
	return n

func _on_game_over(won: bool) -> void:
	spawn_timer.stop()
	wave_gap_timer.stop()
	if won:
		_set_message("🏆 胜利！国王守住了，狼群被全部击退。\n按 R 重新开始。")
	else:
		_set_message("💀 国王被狼群攻陷……\n按 R 重新开始。")

# ── 输入：建造 / 拆除 / 重开 ──
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		get_tree().reload_current_scene()
		return
	if not GameState.running:
		return
	if event.is_action_pressed("place_tower"):
		_try_place(get_global_mouse_position())
	elif event.is_action_pressed("cancel"):
		_try_sell(get_global_mouse_position())

func _try_place(pos: Vector2) -> void:
	var idx := _slot_at(pos)
	if idx == -1 or occupied.has(idx):
		return
	var d := TowerDefs.get_def(active_build_id)
	var cost := int(d.get("cost", 9999))
	if not GameState.spend_gold(cost):
		_set_message("金币不足！%s 需 %d 金。" % [d["n"], cost])
		return
	_place_tower(idx, active_build_id)

func _place_tower(idx: int, tid: String) -> Tower:
	var t := Tower.new()
	t.setup(tid)
	t.position = slot_positions[idx]
	t.projectiles_parent = projectiles_container
	towers_container.add_child(t)
	occupied[idx] = t
	queue_redraw()
	return t

func _try_sell(pos: Vector2) -> void:
	var idx := _slot_at(pos)
	if idx == -1 or not occupied.has(idx):
		return
	var t: Tower = occupied[idx]
	var refund := int(float(TowerDefs.get_def(t.id).get("cost", 0)) * SELL_REFUND)
	# 非基础塔按等级估个返还
	if refund == 0:
		refund = 30 * t.tier
	GameState.add_gold(refund)
	t.queue_free()
	occupied.erase(idx)
	queue_redraw()
	_set_message("拆除 %s，返还 %d 金。" % [t.id, refund])

func _slot_at(pos: Vector2) -> int:
	for i in slot_positions.size():
		if pos.distance_to(slot_positions[i]) <= SLOT_SIZE * 0.6:
			return i
	return -1

func _set_message(t: String) -> void:
	message_label.text = t

func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), bg_color)
	draw_polyline(waypoints, road_color.darkened(0.3), 50.0)
	draw_polyline(waypoints, road_color, 40.0)
	draw_circle(waypoints[0], 15.0, Color(0.7, 0.3, 0.3))  # 狼来的方向
	for i in slot_positions.size():
		if occupied.has(i):
			continue
		var p: Vector2 = slot_positions[i]
		var r := Rect2(p - Vector2(SLOT_SIZE, SLOT_SIZE) / 2.0, Vector2(SLOT_SIZE, SLOT_SIZE))
		draw_rect(r, Color(0.4, 0.85, 0.5, 0.16))
		draw_rect(r, Color(0.5, 0.95, 0.6, 0.5), false, 2.0)

# ── 仅供无头验证 ──
func _run_autoplay() -> void:
	GameState.add_gold(5000)
	var ids := ["L", "E", "B", "L", "E", "B", "L", "E", "B", "E"]
	for i in slot_positions.size():
		_place_tower(i, ids[i % ids.size()])
	started = true
	prep_timer = 1.0
	GameState.set_phase(GameState.Phase.PREP)
	GameState.game_over.connect(func(won): print("[AUTOPLAY] game_over won=", won, " king_hp=", int(GameState.king_hp), " wave=", GameState.wave))
