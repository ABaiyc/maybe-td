extends Node2D
## 关卡编排：阶段机(开始→10s准备→战斗→结算) + 大肥猪国王 +
## 右侧面板拖拽部署基础塔 + 已放置塔拖拽移动/合成 + 轨道炮发射按钮。

const CELL := 40.0
const COLS := 32
const ROWS := 18
const PATH_CLEAR := 42.0
const KING_CLEAR := 72.0
const TOP_CLEAR := 80.0
const SELL_REFUND := 0.6

# 建造区边界：格子中心 x 超过此值为右侧 UI 栏，永久禁建
const BUILD_RIGHT := 1120.0

# 右侧基础塔面板
const PAL_X := 1176.0
const PAL_W := 92.0
const PAL_H := 72.0
const PAL_Y0 := 120.0
const PAL_GAP := 82.0

var _debug_autoplay := false

var level: Dictionary
var waypoints: PackedVector2Array
var bg_color := Color(0.13, 0.16, 0.12)
var road_color := Color(0.29, 0.35, 0.21)
var _font: Font

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
var blocked := {}
var occupied_cells := {}
var tower_cells := {}
var hover_cell := Vector2i(-999, -999)

# 拖拽移动已放置的塔
var dragging := false
var drag_tower: Tower = null
var drag_orig_cells: Array = []

# 从右侧面板拖拽部署
var deploy_dragging := false
var deploy_id := ""
var deploy_free := false

# 开发者作弊（按 C 开关）：直接放置任意塔，无需合成、无需金币
# 面板位于右侧 UI 栏（基础塔面板下方），不占用建造区
var cheat_on := false
var cheat_ids: Array = []
const CHEAT_X := 1156.0
const CHEAT_Y := 400.0
const CHEAT_CELL := 26.0
const CHEAT_COLS := 4

# HUD
var gold_label: Label
var king_label: Label
var wave_label: Label
var phase_label: Label
var message_label: Label
var start_button: Button
var _msg_timeout := 0.0

func _ready() -> void:
	_font = ThemeDB.fallback_font
	level = Levels.get_level(GameState.current_level)
	waypoints = PackedVector2Array(level["waypoints"])
	bg_color = Color(level.get("bg", "21281b"))
	road_color = Color(level.get("road", "4a5a36"))

	_build_containers()
	_build_king()
	_compute_blocked()
	_build_hud()
	cheat_ids = TowerDefs.ids_by_tier(1) + TowerDefs.ids_by_tier(2) + TowerDefs.ids_by_tier(3)
	GameState.reset((level["waves"] as Array).size())
	GameState.changed.connect(_refresh_hud)
	GameState.game_over.connect(_on_game_over)
	_refresh_hud()
	_set_message("点击「开始」进入 10 秒布防。\n从右侧面板把猪塔拖到地图上部署；拖动已放置的塔到同级塔上可合成。")
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
			elif center.x > BUILD_RIGHT:
				bad = true  # 右侧 UI 栏（基础塔面板/作弊器）永久禁建
			elif center.distance_to(kpos) < KING_CLEAR:
				bad = true  # 国王周围禁建
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
	message_label = _mk_label(layer, Vector2(300, 250), 24)
	message_label.size = Vector2(620, 180)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	start_button = Button.new()
	start_button.text = "开始"
	start_button.position = Vector2(560, 12)
	start_button.custom_minimum_size = Vector2(110, 50)
	start_button.add_theme_font_size_override("font_size", 22)
	start_button.pressed.connect(_on_start)
	layer.add_child(start_button)

func _mk_label(parent: Node, pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 不拦截鼠标，避免遮挡地图点击
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
	queue_redraw()  # 金币等状态变化时重绘，使面板可建选项实时亮起

func _on_start() -> void:
	if started:
		return
	started = true
	prep_timer = GameState.PREP_SECONDS
	start_button.hide()
	GameState.set_phase(GameState.Phase.PREP)
	_set_message("布防！%.0f 秒后狼群来袭。" % prep_timer, 0.0)

func _process(delta: float) -> void:
	if not GameState.running:
		return
	var hc := _world_to_cell(get_global_mouse_position())
	if hc != hover_cell or dragging or deploy_dragging or cheat_on:
		hover_cell = hc
		queue_redraw()
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
	# 轨道炮发射按钮需要随充能刷新
	for t in towers_container.get_children():
		if t.atk == "charge":
			queue_redraw()
			break
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
	if e.is_boss:
		match e.mech:
			"stealth":
				_set_message("⚠ Boss 出现：%s！\n它伪装成了羊——只有元素(E)系的塔能识破攻击它！" % e.def.get("n", ""), 4.0)
			"rage":
				_set_message("⚠ Boss 出现：%s！\n它掉血会瞬间狂暴加速并甩掉一切负面效果！" % e.def.get("n", ""), 4.0)
			_:
				_set_message("⚠ Boss 出现：%s！" % e.def.get("n", ""), 2.5)

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
		GameState.unlock_next_level()
		if GameState.current_level + 1 < Levels.count():
			_set_message("🏆 胜利！第二关已解锁。\n按 N 进入下一关，按 R 重玩本关。", 0.0)
		else:
			_set_message("🏆 全部关卡通关！猪猪王国安全了！\n按 R 重玩本关，按 1/2 选关。", 0.0)
	else:
		_set_message("💀 国王被狼群攻陷……\n按 R 重新开始。", 0.0)

# ── 输入 ──
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			get_tree().reload_current_scene()
			return
		if event.keycode == KEY_N and not GameState.running \
				and GameState.current_level + 1 < Levels.count() \
				and GameState.current_level + 1 < GameState.unlocked_levels:
			GameState.current_level += 1
			get_tree().reload_current_scene()
			return
		if event.keycode == KEY_1 or event.keycode == KEY_2:
			var idx := 0 if event.keycode == KEY_1 else 1
			if idx < Levels.count() and idx < GameState.unlocked_levels:
				GameState.current_level = idx
				get_tree().reload_current_scene()
			else:
				_set_message("关卡未解锁：先通过前一关。", 2.0)
			return
		if event.keycode == KEY_C:
			cheat_on = not cheat_on
			if cheat_on:
				GameState.add_gold(99999)
			_set_message("作弊模式：%s（左侧网格拖塔免费放置）" % ("开" if cheat_on else "关"), 1.5)
			queue_redraw()
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
	# 0. 作弊网格 → 免费拖拽部署任意塔
	if cheat_on:
		for i in cheat_ids.size():
			if _cheat_rect(i).has_point(pos):
				deploy_dragging = true
				deploy_id = cheat_ids[i]
				deploy_free = true
				queue_redraw()
				return
	# 1. 轨道炮发射按钮
	for t in towers_container.get_children():
		if t.atk == "charge" and _railgun_btn_rect(t).has_point(pos):
			if t.manual_fire():
				_set_message("轨道炮·手动发射！", 1.0)
			return
	# 2. 右侧面板 → 拖拽部署基础塔
	for i in TowerDefs.BASE_IDS.size():
		if _palette_rect(i).has_point(pos):
			deploy_dragging = true
			deploy_id = TowerDefs.BASE_IDS[i]
			deploy_free = false
			queue_redraw()
			return
	# 3. 已放置的塔 → 拖拽移动
	var t := _tower_at(pos)
	if t != null:
		dragging = true
		drag_tower = t
		drag_orig_cells = tower_cells[t]
		_free_tower(t)
		queue_redraw()

func _on_left_up(pos: Vector2) -> void:
	if deploy_dragging:
		_finish_deploy(pos)
		deploy_dragging = false
		deploy_id = ""
		deploy_free = false
		queue_redraw()
		return
	if not dragging or drag_tower == null:
		dragging = false
		drag_tower = null
		return
	dragging = false
	var moving := drag_tower
	drag_tower = null
	var size := TowerDefs.footprint(moving.id)
	# 落在另一座塔上 → 合成
	var target := _tower_at(pos)
	if target != null and target != moving:
		var res := TowerDefs.fuse(moving.id, target.id)
		if res != "":
			_do_merge(moving, target, res)
			queue_redraw()
			return
		else:
			_set_message("无法合成：需同级且配方存在（三级已封顶）。", 2.0)
	# 原地放回 / 移动到新位置
	if target == null and _world_to_cell(pos) in drag_orig_cells:
		_reoccupy(moving, drag_orig_cells)
		queue_redraw()
		return
	var anchor := _world_to_cell(pos) - Vector2i((size.x - 1) / 2, (size.y - 1) / 2)
	if _can_place(anchor, size):
		_reoccupy(moving, _footprint_cells(anchor, size))
	else:
		_reoccupy(moving, drag_orig_cells)
	queue_redraw()

func _finish_deploy(pos: Vector2) -> void:
	var tid := deploy_id
	var free := deploy_free
	var cost := int(TowerDefs.get_def(tid).get("cost", 0))  # 高级塔无 cost 字段，默认 0
	# 作弊：直接放置任意塔（不合成）
	if free:
		var size0 := TowerDefs.footprint(tid)
		var anchor0 := _world_to_cell(pos) - Vector2i((size0.x - 1) / 2, (size0.y - 1) / 2)
		if not _can_place(anchor0, size0):
			_set_message("放不下，换个位置。", 2.0)
			return
		_spawn_tower(tid, anchor0, size0, true)
		_set_message("作弊放置 → %s" % TowerDefs.name_of(tid), 1.5)
		return
	# 拖到已有塔上 → 直接合成
	var target := _tower_at(pos)
	if target != null:
		var res := TowerDefs.fuse(tid, target.id)
		if res == "":
			_set_message("无法与该塔合成（需同级配方）。", 2.0)
			return
		if not GameState.spend_gold(cost):
			_set_message("金币不足！%s 需 %d 金。" % [TowerDefs.name_of(tid), cost], 2.0)
			return
		var anchor: Vector2i = (tower_cells[target] as Array)[0]
		var rsize := TowerDefs.footprint(res)
		anchor.x = clampi(anchor.x, 0, COLS - rsize.x)
		anchor.y = clampi(anchor.y, 0, ROWS - rsize.y)
		_free_tower(target)
		target.queue_free()
		_spawn_tower(res, anchor, rsize, false)
		_set_message("合成 → %s！" % TowerDefs.name_of(res), 2.0)
		return
	# 空地放置
	var size := TowerDefs.footprint(tid)
	var anchor2 := _world_to_cell(pos) - Vector2i((size.x - 1) / 2, (size.y - 1) / 2)
	if not _can_place(anchor2, size):
		_set_message("放不下，换个位置。", 2.0)
		return
	if not GameState.spend_gold(cost):
		_set_message("金币不足！%s 需 %d 金。" % [TowerDefs.name_of(tid), cost], 2.0)
		return
	_spawn_tower(tid, anchor2, size, true)
	_set_message("")

func _reoccupy(t: Tower, cells: Array) -> void:
	t.position = _cells_center(cells)
	for c in cells:
		occupied_cells[c] = t
	tower_cells[t] = cells

func _spawn_tower(tid: String, anchor: Vector2i, size: Vector2i, _validate: bool) -> Tower:
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

func _palette_rect(i: int) -> Rect2:
	return Rect2(PAL_X, PAL_Y0 + i * PAL_GAP, PAL_W, PAL_H)

func _in_palette(point: Vector2) -> bool:
	for i in TowerDefs.BASE_IDS.size():
		if _palette_rect(i).has_point(point):
			return true
	return false

func _railgun_btn_rect(t: Tower) -> Rect2:
	return Rect2(t.global_position + Vector2(-34, -60), Vector2(68, 22))

func _set_message(t: String, timeout: float = 0.0) -> void:
	message_label.text = t
	_msg_timeout = timeout

# ── 绘制 ──
func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), bg_color)
	draw_polyline(waypoints, road_color.darkened(0.3), 50.0)
	draw_polyline(waypoints, road_color, 40.0)
	draw_circle(waypoints[0], 15.0, Color(0.7, 0.3, 0.3))
	draw_string(_font, Vector2(700, 34), "第%d关 · %s" % [GameState.current_level + 1, level.get("name", "")], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.85))
	draw_string(_font, Vector2(700, 56), "按1/2选关(需解锁)", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.45))

	var mp := get_global_mouse_position()
	# 部署预览（从面板拖出）
	if deploy_dragging:
		var dtgt := _tower_at(mp)
		if dtgt != null and not deploy_free:
			# 拖到塔上：绿圈=可合成 / 红圈=不可
			var canf := TowerDefs.fuse(deploy_id, dtgt.id) != "" and GameState.gold >= int(TowerDefs.get_def(deploy_id)["cost"])
			draw_arc(dtgt.global_position, 30.0, 0.0, TAU, 32, Color(0.3, 1, 0.4) if canf else Color(1, 0.3, 0.3), 3.0)
		else:
			var size := TowerDefs.footprint(deploy_id)
			var anchor := _world_to_cell(mp) - Vector2i((size.x - 1) / 2, (size.y - 1) / 2)
			var afford := deploy_free or GameState.gold >= int(TowerDefs.get_def(deploy_id)["cost"])
			var ok := _can_place(anchor, size) and afford
			_draw_cells(_footprint_cells(anchor, size), Color(0.4, 0.9, 0.5) if ok else Color(0.9, 0.3, 0.3))
	# 移动已放置塔
	elif dragging and drag_tower != null and is_instance_valid(drag_tower):
		var size := TowerDefs.footprint(drag_tower.id)
		var anchor := _world_to_cell(mp) - Vector2i((size.x - 1) / 2, (size.y - 1) / 2)
		var tgt := _tower_at(mp)
		if tgt != null and tgt != drag_tower:
			var canf := TowerDefs.fuse(drag_tower.id, tgt.id) != ""
			draw_arc(tgt.global_position, 30.0, 0.0, TAU, 32, Color(0.3, 1, 0.4) if canf else Color(1, 0.3, 0.3), 3.0)
		else:
			_draw_cells(_footprint_cells(anchor, size), Color(0.4, 0.9, 0.5) if _can_place(anchor, size) else Color(0.9, 0.3, 0.3))
	else:
		# 悬停：可建格高亮 + 塔名提示
		var ht := _tower_at(mp)
		if ht != null:
			_draw_tower_name(ht)
		elif hover_cell.x >= 0 and hover_cell.y >= 0 and hover_cell.x < COLS and hover_cell.y < ROWS and not _in_palette(mp):
			var col := Color(0.4, 0.9, 0.5, 0.6) if _is_buildable(hover_cell) else Color(0.9, 0.3, 0.3, 0.4)
			var rr := Rect2(Vector2(hover_cell.x * CELL, hover_cell.y * CELL) + Vector2(2, 2), Vector2(CELL - 4, CELL - 4))
			draw_rect(rr, Color(col.r, col.g, col.b, 0.15))
			draw_rect(rr, col, false, 2.0)

	# 轨道炮发射按钮
	for t in towers_container.get_children():
		if t.atk == "charge":
			_draw_railgun_button(t)

	_draw_palette()
	if cheat_on:
		_draw_cheat()
	draw_string(_font, Vector2(8, 712), "开发版 · 按 C 切换作弊（免费放置任意塔）", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.8, 0.5))

func _cheat_rect(i: int) -> Rect2:
	var col := i % CHEAT_COLS
	@warning_ignore("integer_division")
	var row := i / CHEAT_COLS
	return Rect2(CHEAT_X + col * (CHEAT_CELL + 3.0), CHEAT_Y + row * (CHEAT_CELL + 3.0), CHEAT_CELL, CHEAT_CELL)

func _draw_cheat() -> void:
	draw_string(_font, Vector2(CHEAT_X, CHEAT_Y - 6.0), "作弊·拖塔免费放置", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.6, 0.6))
	var mp := get_global_mouse_position()
	var hover_id := ""
	for i in cheat_ids.size():
		var tid: String = cheat_ids[i]
		var rect := _cheat_rect(i)
		draw_rect(rect, Color(0.1, 0.1, 0.14, 0.92))
		var border := Color(0.4, 1.0, 0.5) if rect.has_point(mp) else Color(0.7, 0.7, 0.85)
		draw_rect(rect, border, false, 1.0)
		var cc := rect.position + rect.size / 2.0
		draw_circle(cc, 9.0, Color(0.95, 0.66, 0.74))
		draw_circle(cc + Vector2(0, -4), 3.5, TowerDefs.color_of(tid))
		draw_string(_font, rect.position + Vector2(2, rect.size.y - 2), str(int(TowerDefs.get_def(tid)["t"])), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)
		if rect.has_point(mp):
			hover_id = tid
	# 悬停作弊塔显示名称
	if hover_id != "":
		var nm := TowerDefs.name_of(hover_id)
		var bw := float(nm.length() * 15 + 16)
		var box := Rect2(CHEAT_X - bw - 8.0, mp.y - 12.0, bw, 24.0)
		draw_rect(box, Color(0, 0, 0, 0.8))
		draw_string(_font, box.position + Vector2(8, 17), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 0.85))

func _draw_cells(cells: Array, col: Color) -> void:
	for c in cells:
		var rr := Rect2(Vector2(c.x * CELL, c.y * CELL) + Vector2(2, 2), Vector2(CELL - 4, CELL - 4))
		draw_rect(rr, Color(col.r, col.g, col.b, 0.22))
		draw_rect(rr, col, false, 2.0)

func _draw_tower_name(t: Tower) -> void:
	var nm := TowerDefs.name_of(t.id)
	var w := float(nm.length() * 15 + 16)
	var box := Rect2(t.global_position + Vector2(-w / 2.0, -42.0), Vector2(w, 22.0))
	draw_rect(box, Color(0, 0, 0, 0.7))
	draw_string(_font, box.position + Vector2(8, 16), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 0.85))

func _draw_railgun_button(t: Tower) -> void:
	var rect := _railgun_btn_rect(t)
	var ratio: float = t.charge_ratio()
	draw_rect(rect, Color(0.15, 0.12, 0.05, 0.9))
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * ratio, rect.size.y)), Color(0.5, 0.35, 0.1, 0.8))
	draw_rect(rect, Color(1, 0.9, 0.4) if ratio >= 1.0 else Color(0.8, 0.7, 0.4), false, 2.0)
	draw_string(_font, rect.position + Vector2(6, 16), "发射 %d%%" % int(ratio * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 0.7))

func _draw_palette() -> void:
	for i in TowerDefs.BASE_IDS.size():
		var tid: String = TowerDefs.BASE_IDS[i]
		var d := TowerDefs.get_def(tid)
		var rect := _palette_rect(i)
		var afford := GameState.gold >= int(d["cost"])
		draw_rect(rect, Color(0.12, 0.14, 0.18, 0.92))
		draw_rect(rect, Color(0.9, 0.85, 0.4) if afford else Color(0.4, 0.4, 0.45), false, 2.0)
		# 迷你猪 + 武器色
		var cc := rect.position + Vector2(rect.size.x / 2.0, 26.0)
		draw_circle(cc, 13.0, Color(0.96, 0.66, 0.74) if afford else Color(0.5, 0.45, 0.48))
		draw_circle(cc + Vector2(0, -6), 4.0, TowerDefs.color_of(tid))
		var nm: String = d["n"]
		draw_string(_font, rect.position + Vector2(6, 54), nm, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 8, 13, Color.WHITE if afford else Color(0.6, 0.6, 0.6))
		draw_string(_font, rect.position + Vector2(6, 70), "%d金 拖动部署" % int(d["cost"]), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 8, 11, Color(1, 0.9, 0.5) if afford else Color(0.6, 0.5, 0.4))

# ── 仅供无头验证 ──
func _run_autoplay() -> void:
	GameState.add_gold(20000)
	var adv := ["L", "E", "B", "mine_layer", "reactor", "railgun", "anti_mat",
		"catalyst", "tactical_mark", "plasma_field", "plasma_field", "twin_laser", "prism", "emp", "LB",
		"barrage", "burst_gl", "gl_array", "EE", "LL", "BB", "beam_burst", "ele_matrix"]
	var col := 2
	for tid in adv:
		var size := TowerDefs.footprint(tid)
		_spawn_tower(tid, Vector2i(col, 11), size, false)
		col += maxi(2, size.x + 1)
		if col > COLS - 4:
			col = 2
	var a := _spawn_tower("L", Vector2i(2, 15), TowerDefs.footprint("L"), false)
	var b := _spawn_tower("L", Vector2i(4, 15), TowerDefs.footprint("L"), false)
	_do_merge(a, b, TowerDefs.fuse("L", "L"))
	print("[AUTOPLAY] towers=", towers_container.get_child_count(), " merge L+L=", TowerDefs.fuse("L", "L"))
	# 伪装机制断言：B 塔(无E)锁不住伪装狼，E 塔能锁
	var sheep := Enemy.new()
	sheep.setup(EnemyDefs.get_def("wolf_sheep"), waypoints)
	enemies_container.add_child(sheep)
	print("[AUTOPLAY] stealth: hittable_by(B)=", sheep.hittable_by("B"), " hittable_by(E)=", sheep.hittable_by("E"), " hittable_by(LLLE)=", sheep.hittable_by("LLLE"))
	# 狂暴机制断言：上减速后打掉 30% 血 → 应清除减速并进入狂暴加速
	var alpha := Enemy.new()
	alpha.setup(EnemyDefs.get_def("alpha"), waypoints)
	enemies_container.add_child(alpha)
	alpha.apply_debuff("slow", 0.5, 5.0)
	var slowed_speed := alpha._speed()
	alpha.take_damage(alpha.max_hp * 0.3 / (1.0 - alpha.armor))
	print("[AUTOPLAY] rage: speed_before=", slowed_speed, " after=", alpha._speed(),
		" debuff_cleared=", alpha.slow_time == 0.0, " raging=", alpha._rage_t > 0.0)
	sheep.queue_free()
	alpha.queue_free()
	started = true
	prep_timer = 1.0
	GameState.set_phase(GameState.Phase.PREP)
	GameState.game_over.connect(func(won): print("[AUTOPLAY] game_over won=", won, " king_hp=", int(GameState.king_hp), " wave=", GameState.wave, " level=", GameState.current_level, " unlocked=", GameState.unlocked_levels))
