extends Node2D
## 关卡编排（M2）：在 M1 基础上加入——
##  · 网格自由放置（除路径外任意处；不同塔占不同格数；格子悬停才显示）
##  · 点击位置 → 弹出三基础塔选项 → 选择放置
##  · 拖拽合成（同级配方融合，三级封顶）
##  · 战斗中可放置/拆除/合成

const CELL := 40.0
const COLS := 32
const ROWS := 18
const PATH_CLEAR := 42.0   # 离路径中心多近的格子不可建造
const KING_CLEAR := 72.0
const TOP_CLEAR := 80.0    # 顶部 HUD 区
const SELL_REFUND := 0.6

var _debug_autoplay := false

var level: Dictionary
var waypoints: PackedVector2Array
var bg_color := Color(0.13, 0.16, 0.12)
var road_color := Color(0.29, 0.35, 0.21)

var enemies_container: Node2D
var towers_container: Node2D
var projectiles_container: Node2D
var king: King
var spawn_timer: Timer
var wave_gap_timer: Timer

# 流程
var started := false
var prep_timer := 0.0
var wave_idx := -1
var spawn_queue: Array = []
var all_waves_spawned := false

# 网格 / 放置
var blocked := {}            # Vector2i -> true（路径/越界/禁区）
var occupied_cells := {}     # Vector2i -> Tower
var tower_cells := {}        # Tower -> Array[Vector2i]
var hover_cell := Vector2i(-999, -999)

# 拖拽移动/合成
var dragging := false
var drag_tower: Tower = null
var drag_orig_cells: Array = []

# 建造弹窗
var build_popup: Control
var build_cell := Vector2i.ZERO

# HUD
var gold_label: Label
var king_label: Label
var wave_label: Label
var phase_label: Label
var message_label: Label
var start_button: Button
var _msg_timeout := 0.0

func _ready() -> void:
	level = Levels.get_level(0)
	waypoints = PackedVector2Array(level["waypoints"])
	bg_color = Color(level.get("bg", "21281b"))
	road_color = Color(level.get("road", "4a5a36"))

	_build_containers()
	_build_king()
	_compute_blocked()
	_build_hud()
	GameState.reset((level["waves"] as Array).size())
	GameState.changed.connect(_refresh_hud)
	GameState.game_over.connect(_on_game_over)
	_refresh_hud()
	_set_message("点击「开始」进入 10 秒布防。\n点击空地选择防御塔，拖动塔到同级塔上可合成。")
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

func _compute_blocked() -> void:
	blocked.clear()
	var kpos: Vector2 = level["king_pos"]
	for cx in COLS:
		for cy in ROWS:
			var c := Vector2i(cx, cy)
			var center := _cell_center(c)
			var bad := false
			if center.y < TOP_CLEAR:
				bad = true
			elif center.distance_to(kpos) < KING_CLEAR:
				bad = true
			else:
				for i in range(waypoints.size() - 1):
					if _dist_point_seg(center, waypoints[i], waypoints[i + 1]) < PATH_CLEAR:
						bad = true
						break
			if bad:
				blocked[c] = true

func _build_hud() -> void:
	var layer := CanvasLayer.new(); add_child(layer)
	gold_label = _mk_label(layer, Vector2(20, 12), 22)
	king_label = _mk_label(layer, Vector2(20, 42), 22)
	wave_label = _mk_label(layer, Vector2(250, 12), 22)
	phase_label = _mk_label(layer, Vector2(250, 42), 22)
	message_label = _mk_label(layer, Vector2(330, 270), 24)
	message_label.size = Vector2(620, 180)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	start_button = Button.new()
	start_button.text = "开始"
	start_button.position = Vector2(1130, 12)
	start_button.custom_minimum_size = Vector2(110, 56)
	start_button.add_theme_font_size_override("font_size", 24)
	start_button.pressed.connect(_on_start)
	layer.add_child(start_button)

	# 建造弹窗（点击空地后出现的三选一）
	build_popup = Control.new()
	build_popup.visible = false
	build_popup.size = Vector2(300, 64)
	layer.add_child(build_popup)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	build_popup.add_child(hb)
	for tid in TowerDefs.BASE_IDS:
		var d := TowerDefs.get_def(tid)
		var b := Button.new()
		b.text = "%s\n%d金 / %d格" % [d["n"], d["cost"], _cells_count(tid)]
		b.custom_minimum_size = Vector2(94, 58)
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(_on_choose_build.bind(tid))
		hb.add_child(b)

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
	# 悬停格刷新
	var hc := _world_to_cell(get_global_mouse_position())
	if hc != hover_cell or dragging:
		hover_cell = hc
		queue_redraw()
	# 拖拽中：防御塔跟随鼠标
	if dragging and drag_tower != null and is_instance_valid(drag_tower):
		var size := TowerDefs.footprint(drag_tower.id)
		var anchor := hc - Vector2i((size.x - 1) / 2, (size.y - 1) / 2)
		drag_tower.position = _cells_center(_footprint_cells(anchor, size))
	if GameState.phase == GameState.Phase.PREP and started:
		prep_timer -= delta
		_refresh_hud()
		if prep_timer <= 0.0:
			_start_combat()
	elif GameState.phase == GameState.Phase.COMBAT:
		if all_waves_spawned and _alive_enemies() == 0:
			GameState.win()
	# 建造弹窗按钮随金币实时刷新可用状态
	if build_popup.visible:
		_refresh_popup_buttons()
	# 临时提示自动消失
	if _msg_timeout > 0.0:
		_msg_timeout -= delta
		if _msg_timeout <= 0.0:
			message_label.text = ""

# ── 波次 ──
func _start_combat() -> void:
	GameState.set_phase(GameState.Phase.COMBAT)
	_set_message("")
	_begin_wave(0)

func _begin_wave(i: int) -> void:
	wave_idx = i
	var w: Dictionary = (level["waves"] as Array)[i]
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
	build_popup.hide()
	if won:
		_set_message("🏆 胜利！国王守住了，狼群被全部击退。\n按 R 重新开始。")
	else:
		_set_message("💀 国王被狼群攻陷……\n按 R 重新开始。")

# ── 输入：建造弹窗 / 拖拽合成 / 拆除 / 重开 ──
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		get_tree().reload_current_scene()
		return
	if not GameState.running:
		return
	if event is InputEventMouseButton:
		var pos := get_global_mouse_position()
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_on_left_down(pos)
			else:
				_on_left_up(pos)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_try_sell(pos)

func _on_left_down(pos: Vector2) -> void:
	if build_popup.visible:
		build_popup.hide()
		return
	var t := _tower_at(pos)
	if t != null:
		# 长按拿起：临时释放其格子，让它跟随鼠标移动
		dragging = true
		drag_tower = t
		drag_orig_cells = tower_cells[t]
		_free_tower(t)
		queue_redraw()
		return
	var cell := _world_to_cell(pos)
	if _is_buildable(cell):
		_open_popup(pos, cell)

func _on_left_up(pos: Vector2) -> void:
	if not dragging or drag_tower == null:
		dragging = false
		drag_tower = null
		return
	dragging = false
	var moving := drag_tower
	drag_tower = null
	var size := TowerDefs.footprint(moving.id)
	# 落在另一座塔上 → 尝试合成
	var target := _tower_at(pos)
	if target != null and target != moving:
		var res := TowerDefs.fuse(moving.id, target.id)
		if res != "":
			_do_merge(moving, target, res)
			queue_redraw()
			return
		else:
			_set_message("无法合成：需同级且配方存在（三级已封顶）。", 2.0)
	# 原地轻点（没拖走）→ 轨道炮手动发射
	if target == null and _world_to_cell(pos) in drag_orig_cells:
		if moving.manual_fire():
			_set_message("轨道炮·手动发射！", 1.2)
		_reoccupy(moving, drag_orig_cells)
		queue_redraw()
		return
	# 落在空地 → 移动到新位置；放不下则退回原位
	var anchor := _world_to_cell(pos) - Vector2i((size.x - 1) / 2, (size.y - 1) / 2)
	if _can_place(anchor, size):
		_reoccupy(moving, _footprint_cells(anchor, size))
	else:
		_reoccupy(moving, drag_orig_cells)
	queue_redraw()

func _reoccupy(t: Tower, cells: Array) -> void:
	t.position = _cells_center(cells)
	for c in cells:
		occupied_cells[c] = t
	tower_cells[t] = cells

func _open_popup(pos: Vector2, cell: Vector2i) -> void:
	build_cell = cell
	build_popup.position = Vector2(clampf(pos.x - 150, 4, 976), clampf(pos.y + 16, 84, 640))
	# 刷新按钮可用性
	var hb := build_popup.get_child(0)
	var i := 0
	for tid in TowerDefs.BASE_IDS:
		var btn: Button = hb.get_child(i)
		btn.disabled = GameState.gold < int(TowerDefs.get_def(tid)["cost"])
		i += 1
	build_popup.show()

func _on_choose_build(tid: String) -> void:
	build_popup.hide()
	_place_new(tid, build_cell)

func _place_new(tid: String, center_cell: Vector2i) -> void:
	var size := TowerDefs.footprint(tid)
	var anchor := center_cell - Vector2i((size.x - 1) / 2, (size.y - 1) / 2)
	if not _can_place(anchor, size):
		_set_message("这里放不下 %s（%d格），换个位置。" % [TowerDefs.name_of(tid), _cells_count(tid)], 2.0)
		return
	var cost := int(TowerDefs.get_def(tid)["cost"])
	if not GameState.spend_gold(cost):
		_set_message("金币不足！%s 需 %d 金。" % [TowerDefs.name_of(tid), cost], 2.0)
		return
	_spawn_tower(tid, anchor, size, true)
	_set_message("")

func _spawn_tower(tid: String, anchor: Vector2i, size: Vector2i, validate: bool) -> Tower:
	var cells := _footprint_cells(anchor, size)
	var t := Tower.new()
	t.setup(tid)
	t.position = _cells_center(cells)
	t.projectiles_parent = projectiles_container
	t.waypoints = waypoints
	towers_container.add_child(t)
	for c in cells:
		occupied_cells[c] = t
	tower_cells[t] = cells
	queue_redraw()
	return t

func _do_merge(a: Tower, b: Tower, res: String) -> void:
	var anchor: Vector2i = (tower_cells[b] as Array)[0]
	var size := TowerDefs.footprint(res)
	# 锚点夹到边界内
	anchor.x = clampi(anchor.x, 0, COLS - size.x)
	anchor.y = clampi(anchor.y, 0, ROWS - size.y)
	_free_tower(a)
	_free_tower(b)
	a.queue_free()
	b.queue_free()
	_spawn_tower(res, anchor, size, false)
	_set_message("合成 → %s！" % TowerDefs.name_of(res), 2.0)

func _free_tower(t: Tower) -> void:
	if not tower_cells.has(t):
		return
	for c in tower_cells[t]:
		if occupied_cells.get(c) == t:
			occupied_cells.erase(c)
	tower_cells.erase(t)

func _try_sell(pos: Vector2) -> void:
	if build_popup.visible:
		build_popup.hide()
	var t := _tower_at(pos)
	if t == null:
		return
	var refund := int(float(TowerDefs.get_def(t.id).get("cost", 0)) * SELL_REFUND)
	if refund == 0:
		refund = 30 * t.tier
	GameState.add_gold(refund)
	_free_tower(t)
	t.queue_free()
	queue_redraw()
	_set_message("拆除 %s，返还 %d 金。" % [TowerDefs.name_of(t.id), refund], 2.0)

# ── 网格工具 ──
func _world_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL)), int(floor(p.y / CELL)))

func _cell_center(c: Vector2i) -> Vector2:
	return Vector2((c.x + 0.5) * CELL, (c.y + 0.5) * CELL)

func _footprint_cells(anchor: Vector2i, size: Vector2i) -> Array:
	var out := []
	for dy in size.y:
		for dx in size.x:
			out.append(anchor + Vector2i(dx, dy))
	return out

func _cells_center(cells: Array) -> Vector2:
	var sum := Vector2.ZERO
	for c in cells:
		sum += _cell_center(c)
	return sum / float(cells.size())

func _cells_count(tid: String) -> int:
	var s := TowerDefs.footprint(tid)
	return s.x * s.y

func _is_buildable(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= COLS or cell.y >= ROWS:
		return false
	return not blocked.has(cell) and not occupied_cells.has(cell)

func _can_place(anchor: Vector2i, size: Vector2i) -> bool:
	for c in _footprint_cells(anchor, size):
		if not _is_buildable(c):
			return false
	return true

func _tower_at(pos: Vector2) -> Tower:
	return occupied_cells.get(_world_to_cell(pos), null)

func _dist_point_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t: float = 0.0 if ab.length_squared() == 0.0 else clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)

func _set_message(t: String, timeout: float = 0.0) -> void:
	message_label.text = t
	_msg_timeout = timeout

func _refresh_popup_buttons() -> void:
	var hb := build_popup.get_child(0)
	var i := 0
	for tid in TowerDefs.BASE_IDS:
		(hb.get_child(i) as Button).disabled = GameState.gold < int(TowerDefs.get_def(tid)["cost"])
		i += 1

# ── 绘制 ──
func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), bg_color)
	draw_polyline(waypoints, road_color.darkened(0.3), 50.0)
	draw_polyline(waypoints, road_color, 40.0)
	draw_circle(waypoints[0], 15.0, Color(0.7, 0.3, 0.3))

	if dragging and drag_tower != null and is_instance_valid(drag_tower):
		var mp := get_global_mouse_position()
		var size := TowerDefs.footprint(drag_tower.id)
		var anchor := _world_to_cell(mp) - Vector2i((size.x - 1) / 2, (size.y - 1) / 2)
		var tgt := _tower_at(mp)
		if tgt != null and tgt != drag_tower:
			# 悬停在另一座塔上：绿圈可合成 / 红圈不可
			var ok := TowerDefs.fuse(drag_tower.id, tgt.id) != ""
			draw_arc(tgt.global_position, 28.0, 0.0, TAU, 32, Color(0.3, 1, 0.4) if ok else Color(1, 0.3, 0.3), 3.0)
		else:
			# 塔触碰到的可放置格子亮起（绿=可放/红=不可）
			var placeable := _can_place(anchor, size)
			var col := Color(0.4, 0.9, 0.5) if placeable else Color(0.9, 0.3, 0.3)
			for c in _footprint_cells(anchor, size):
				var rr := Rect2(Vector2(c.x * CELL, c.y * CELL) + Vector2(2, 2), Vector2(CELL - 4, CELL - 4))
				draw_rect(rr, Color(col.r, col.g, col.b, 0.2))
				draw_rect(rr, col, false, 2.0)
	elif not build_popup.visible:
		# 悬停时才显示当前格（绿=可建，红=不可）
		if hover_cell.x >= 0 and hover_cell.y >= 0 and hover_cell.x < COLS and hover_cell.y < ROWS:
			var center := _cell_center(hover_cell)
			if _tower_at(center) == null:
				var col := Color(0.4, 0.9, 0.5, 0.5) if _is_buildable(hover_cell) else Color(0.9, 0.3, 0.3, 0.4)
				var r := Rect2(Vector2(hover_cell.x * CELL, hover_cell.y * CELL) + Vector2(2, 2), Vector2(CELL - 4, CELL - 4))
				draw_rect(r, Color(col.r, col.g, col.b, 0.15))
				draw_rect(r, col, false, 2.0)

# ── 仅供无头验证 ──
func _run_autoplay() -> void:
	GameState.add_gold(20000)
	# 强制铺设各类攻击原型的塔，验证 beam/domain/mine/charge/snipe/aura/mark/link/proj 均无报错
	var adv := ["L", "E", "B", "mine_layer", "reactor", "railgun", "anti_mat",
		"catalyst", "tactical_mark", "plasma_field", "plasma_field", "twin_laser", "prism", "emp", "LB",
		"barrage", "burst_gl", "gl_array", "EE"]
	var col := 2
	for tid in adv:
		var size := TowerDefs.footprint(tid)
		_spawn_tower(tid, Vector2i(col, 11), size, false)
		col += maxi(2, size.x + 1)
		if col > COLS - 3:
			col = 2
	# 测试拖拽合成产物（L+L→聚焦激光，beam 二级）
	var a := _spawn_tower("L", Vector2i(2, 14), TowerDefs.footprint("L"), false)
	var b := _spawn_tower("L", Vector2i(6, 14), TowerDefs.footprint("L"), false)
	_do_merge(a, b, TowerDefs.fuse("L", "L"))
	print("[AUTOPLAY] towers=", towers_container.get_child_count(), " merge L+L=", TowerDefs.fuse("L", "L"))
	started = true
	prep_timer = 1.0
	GameState.set_phase(GameState.Phase.PREP)
	GameState.game_over.connect(func(won): print("[AUTOPLAY] game_over won=", won, " king_hp=", int(GameState.king_hp), " wave=", GameState.wave))
