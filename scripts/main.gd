extends Node2D
## 类肉鸽无尽模式编排：
##  开始→三选一挑初始猪塔→10s布防→无尽狼潮(分数驱动难度/解锁Boss)
##  击杀得分+经验；升级弹三选一(元素)→点塔升级/点空位放新塔(上限5座)
##  满级(15次行动=5塔全三级)后升级改为属性三选一(攻击/攻速/暴击)

const CELL := 40.0
const COLS := 32
const ROWS := 18
const KING_CLEAR := 40.0

# 下方一排 1 格塔位
const ROW_TOP := 560.0
const ROW_BOTTOM := 600.0
# 右侧留给作弊器的 UI 栏
const BUILD_RIGHT := 1120.0

var _debug_autoplay := false

var cfg: Dictionary
var bg_color := Color(0.13, 0.16, 0.12)
var field_color := Color(0.17, 0.23, 0.15)
var _font: Font

var enemies_container: Node2D
var towers_container: Node2D
var projectiles_container: Node2D
var king: King

# 流程
var started := false
var prep_timer := 0.0
var _spawn_t := 0.0
var _next_alpha := Levels.ALPHA_UNLOCK
var _next_sheep := Levels.SHEEP_UNLOCK

# 网格 / 塔
var blocked := {}
var occupied_cells := {}
var tower_cells := {}
var hover_cell := Vector2i(-999, -999)
var actions_done := 0     # 已完成的放塔/升级次数（15 次=满级）

# 拖拽移动塔
var dragging := false
var drag_tower: Tower = null
var drag_orig_cells: Array = []

# 升级选择流程
var choice_active := false
var apply_elem := ""      # 选完元素后待应用（点塔/点空位）

# 作弊（按 C）
var cheat_on := false
var cheat_ids: Array = []
var deploy_dragging := false
var deploy_id := ""
const CHEAT_X := 1156.0
const CHEAT_Y := 400.0
const CHEAT_CELL := 26.0
const CHEAT_COLS := 4

# HUD
var score_label: Label
var king_label: Label
var level_label: Label
var phase_label: Label
var message_label: Label
var start_button: Button
var choice_buttons: Array = []
var choice_panel: Control
var _msg_timeout := 0.0

const ELEMS := ["L", "E", "B"]
const STAT_OPTS := [
	["攻击 +10%", "dmg"],
	["攻速 +8%", "spd"],
	["暴击 +5%", "crit"],
]

func _ready() -> void:
	_font = ThemeDB.fallback_font
	cfg = Levels.CONFIG
	bg_color = Color(cfg.get("bg", "21281b"))
	field_color = Color(cfg.get("field", "2c3a26"))
	cheat_ids = TowerDefs.ids_by_tier(1) + TowerDefs.ids_by_tier(2) + TowerDefs.ids_by_tier(3)

	_build_containers()
	_build_king()
	_compute_blocked()
	_build_hud()
	GameState.reset()
	GameState.changed.connect(_refresh_hud)
	GameState.game_over.connect(_on_game_over)
	GameState.leveled_up.connect(_on_leveled_up)
	_refresh_hud()
	_set_message("无尽狼潮：点击「开始」挑选你的初始猪塔。\n击杀得分和经验，分数越高狼越强！")
	queue_redraw()
	if _debug_autoplay:
		_run_autoplay()

func _build_containers() -> void:
	enemies_container = Node2D.new(); enemies_container.name = "Enemies"; add_child(enemies_container)
	towers_container = Node2D.new(); towers_container.name = "Towers"; add_child(towers_container)
	projectiles_container = Node2D.new(); projectiles_container.name = "Projectiles"; add_child(projectiles_container)

func _build_king() -> void:
	king = King.new()
	king.position = cfg["king_pos"]
	add_child(king)

func _compute_blocked() -> void:
	blocked.clear()
	var kpos: Vector2 = cfg["king_pos"]
	for cx in COLS:
		for cy in ROWS:
			var c := Vector2i(cx, cy)
			var center := _cell_center(c)
			var bad := false
			if center.y < ROW_TOP or center.y > ROW_BOTTOM:
				bad = true
			elif center.x > BUILD_RIGHT:
				bad = true
			elif center.distance_to(kpos) < KING_CLEAR:
				bad = true
			if bad:
				blocked[c] = true

func _build_hud() -> void:
	var layer := CanvasLayer.new(); add_child(layer)
	score_label = _mk_label(layer, Vector2(20, 12), 22)
	king_label = _mk_label(layer, Vector2(20, 42), 22)
	level_label = _mk_label(layer, Vector2(320, 12), 22)
	phase_label = _mk_label(layer, Vector2(320, 42), 22)
	message_label = _mk_label(layer, Vector2(300, 240), 24)
	message_label.size = Vector2(620, 180)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	start_button = Button.new()
	start_button.text = "开始"
	start_button.position = Vector2(585, 330)
	start_button.custom_minimum_size = Vector2(120, 54)
	start_button.add_theme_font_size_override("font_size", 24)
	start_button.pressed.connect(_on_start)
	layer.add_child(start_button)

	# 升级三选一面板
	choice_panel = Control.new()
	choice_panel.visible = false
	layer.add_child(choice_panel)
	for i in 3:
		var b := Button.new()
		b.custom_minimum_size = Vector2(220, 92)
		b.position = Vector2(280 + i * 240, 300)
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(_on_choice.bind(i))
		choice_panel.add_child(b)
		choice_buttons.append(b)

func _mk_label(parent: Node, pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	parent.add_child(l)
	return l

func _refresh_hud() -> void:
	score_label.text = "分数: %d   最佳: %d" % [GameState.score, GameState.best_score]
	king_label.text = "国王: %d/%d" % [int(GameState.king_hp), int(GameState.king_max_hp)]
	var lv_suffix := "(满级)" if actions_done >= GameState.MAX_ACTION_LEVEL else ""
	level_label.text = "等级: %d%s" % [GameState.xp_level, lv_suffix]
	match GameState.phase:
		GameState.Phase.PREP:
			phase_label.text = ("准备: %.0f s" % ceil(prep_timer)) if started else "待命"
		GameState.Phase.COMBAT:
			phase_label.text = "狼潮进行中"
		_:
			phase_label.text = "结束"
	queue_redraw()

# ── 流程 ──
func _on_start() -> void:
	if started:
		return
	started = true
	prep_timer = GameState.PREP_SECONDS
	start_button.hide()
	GameState.set_phase(GameState.Phase.PREP)
	# 首个选择：挑初始猪塔（免费）
	GameState.pending_choices += 1
	_show_choice()

func _process(delta: float) -> void:
	var hc := _world_to_cell(get_global_mouse_position())
	if hc != hover_cell or dragging or deploy_dragging or cheat_on:
		hover_cell = hc
		queue_redraw()
	if not GameState.running:
		return
	if dragging and drag_tower != null and is_instance_valid(drag_tower):
		drag_tower.position = _cell_center(hc)
	if GameState.active():
		if GameState.phase == GameState.Phase.PREP and started:
			prep_timer -= delta
			_refresh_hud()
			if prep_timer <= 0.0:
				GameState.set_phase(GameState.Phase.COMBAT)
				_set_message("")
		elif GameState.phase == GameState.Phase.COMBAT:
			_spawn_director(delta)
	# 轨道炮按钮刷新
	for t in towers_container.get_children():
		if t is Tower and t.atk == "charge":
			queue_redraw()
			break
	if _msg_timeout > 0.0:
		_msg_timeout -= delta
		if _msg_timeout <= 0.0:
			message_label.text = ""

## 出怪导演：间隔/血量/速度随分数变化；分数解锁 Boss
func _spawn_director(delta: float) -> void:
	_spawn_t -= delta
	if _spawn_t <= 0.0:
		_spawn_t = Levels.spawn_interval(GameState.score)
		var pool := Levels.enemy_pool(GameState.score)
		_spawn_enemy(pool[randi() % pool.size()])
	if GameState.score >= _next_alpha:
		_next_alpha += Levels.BOSS_EVERY
		_spawn_enemy("alpha")
	if GameState.score >= _next_sheep:
		_next_sheep += Levels.BOSS_EVERY
		_spawn_enemy("wolf_sheep")

func _spawn_enemy(enemy_id: String) -> void:
	var e := Enemy.new()
	var x := randf_range(Levels.SPAWN_X_MIN, Levels.SPAWN_X_MAX)
	var wp := PackedVector2Array([Vector2(x, Levels.SPAWN_Y), Vector2(x, Levels.LINE_Y - 12.0)])
	e.setup(EnemyDefs.get_def(enemy_id), wp, Levels.hp_mult(GameState.score), Levels.speed_mult(GameState.score))
	enemies_container.add_child(e)
	if e.is_boss:
		match e.mech:
			"stealth":
				_set_message("⚠ %s 现身！只有元素(E)系的塔能识破它！" % e.def.get("n", ""), 3.5)
			"rage":
				_set_message("⚠ %s 来袭！掉血会狂暴冲刺并甩掉负面！" % e.def.get("n", ""), 3.5)

func _on_game_over(_won: bool) -> void:
	choice_panel.hide()
	choice_active = false
	apply_elem = ""
	_set_message("💀 国王被狼群攻陷……\n最终分数 %d   历史最佳 %d\n按 R 再战！" % [GameState.score, GameState.best_score], 0.0)

# ── 升级三选一 ──
func _on_leveled_up() -> void:
	if not choice_active and apply_elem == "":
		_show_choice()

func _show_choice() -> void:
	if GameState.pending_choices <= 0:
		return
	if _debug_autoplay:
		_auto_resolve_choice()
		return
	choice_active = true
	GameState.ui_pause = true
	var stat_mode := actions_done >= GameState.MAX_ACTION_LEVEL
	for i in 3:
		var b: Button = choice_buttons[i]
		if stat_mode:
			b.text = "%s" % STAT_OPTS[i][0]
		else:
			var elem: String = ELEMS[i]
			var d := TowerDefs.get_def(elem)
			b.text = "%s (%s)\n%s" % [d["n"], elem, str(d["desc"]).substr(0, 22)]
	_set_message("升级！选择一个方向：" if actions_done > 0 else "挑选你的初始猪塔：", 0.0)
	choice_panel.show()

func _on_choice(i: int) -> void:
	var stat_mode := actions_done >= GameState.MAX_ACTION_LEVEL
	choice_panel.hide()
	choice_active = false
	if stat_mode:
		match STAT_OPTS[i][1]:
			"dmg": GameState.dmg_mult += 0.10
			"spd": GameState.atk_speed_mult += 0.08
			"crit": GameState.crit_chance = minf(GameState.crit_chance + 0.05, 0.8)
		GameState.consume_choice()
		_set_message("属性提升！攻击x%.2f 攻速x%.2f 暴击%d%%" % [GameState.dmg_mult, GameState.atk_speed_mult, int(GameState.crit_chance * 100)], 2.0)
		_after_choice_applied()
	else:
		apply_elem = ELEMS[i]
		_set_message("已选 %s —— 点击一座塔升级，或点击空塔位放置新塔（%d/%d座）" % [TowerDefs.name_of(apply_elem), _tower_count(), GameState.MAX_TOWERS], 0.0)

func _after_choice_applied() -> void:
	if GameState.pending_choices > 0:
		_show_choice()
	else:
		GameState.ui_pause = false

## 元素应用：点塔=升级；点空位=放新塔
func _try_apply_elem(pos: Vector2) -> void:
	var t := _tower_at(pos)
	if t != null:
		var res := TowerDefs.upgrade_result(t.id, apply_elem)
		if res == "":
			_set_message("%s 已是三级满阶，选别的塔。" % TowerDefs.name_of(t.id), 2.0)
			return
		var cells: Array = tower_cells[t]
		var anchor: Vector2i = cells[0]
		_free_tower(t)
		t.queue_free()
		_spawn_tower(res, anchor)
		_set_message("升级 → %s！" % TowerDefs.name_of(res), 2.0)
	else:
		var cell := _world_to_cell(pos)
		if not _is_buildable(cell):
			return
		if _tower_count() >= GameState.MAX_TOWERS:
			_set_message("塔位已满（%d座）——点一座塔升级它。" % GameState.MAX_TOWERS, 2.0)
			return
		_spawn_tower(apply_elem, cell)
		_set_message("放置 %s！" % TowerDefs.name_of(apply_elem), 2.0)
	apply_elem = ""
	actions_done += 1
	GameState.consume_choice()
	_after_choice_applied()

# ── 输入 ──
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			get_tree().reload_current_scene()
			return
		if event.keycode == KEY_C:
			cheat_on = not cheat_on
			_set_message("作弊模式：%s（右下网格拖塔免费放置）" % ("开" if cheat_on else "关"), 1.5)
			queue_redraw()
			return
	if not GameState.running:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var pos := get_global_mouse_position()
		if event.pressed:
			_on_left_down(pos)
		else:
			_on_left_up(pos)

func _on_left_down(pos: Vector2) -> void:
	# 0. 升级应用点击
	if apply_elem != "":
		_try_apply_elem(pos)
		return
	if choice_active:
		return
	# 1. 作弊网格拖出
	if cheat_on:
		for i in cheat_ids.size():
			if _cheat_rect(i).has_point(pos):
				deploy_dragging = true
				deploy_id = cheat_ids[i]
				queue_redraw()
				return
	# 2. 轨道炮发射按钮
	for t in towers_container.get_children():
		if t is Tower and t.atk == "charge" and _railgun_btn_rect(t).has_point(pos):
			if t.manual_fire():
				_set_message("轨道炮·手动发射！", 1.0)
			return
	# 3. 拖拽移动已放置塔
	var tw := _tower_at(pos)
	if tw != null:
		dragging = true
		drag_tower = tw
		drag_orig_cells = tower_cells[tw]
		_free_tower(tw)
		queue_redraw()

func _on_left_up(pos: Vector2) -> void:
	if deploy_dragging:
		_finish_cheat_deploy(pos)
		deploy_dragging = false
		deploy_id = ""
		queue_redraw()
		return
	if not dragging or drag_tower == null:
		dragging = false
		drag_tower = null
		return
	dragging = false
	var moving := drag_tower
	drag_tower = null
	var cell := _world_to_cell(pos)
	if _is_buildable(cell):
		_occupy(moving, cell)
	else:
		_occupy(moving, drag_orig_cells[0])
	queue_redraw()

func _finish_cheat_deploy(pos: Vector2) -> void:
	var cell := _world_to_cell(pos)
	if not _is_buildable(cell):
		_set_message("放不下，换个位置。", 2.0)
		return
	if _tower_count() >= GameState.MAX_TOWERS:
		_set_message("塔位已满（%d座）。" % GameState.MAX_TOWERS, 2.0)
		return
	_spawn_tower(deploy_id, cell)
	_set_message("作弊放置 → %s" % TowerDefs.name_of(deploy_id), 1.5)

# ── 塔管理 ──
func _tower_count() -> int:
	var n := 0
	for t in towers_container.get_children():
		if not t.is_queued_for_deletion():
			n += 1
	return n

func _spawn_tower(tid: String, cell: Vector2i) -> Tower:
	var t := Tower.new()
	t.setup(tid)
	t.position = _cell_center(cell)
	t.projectiles_parent = projectiles_container
	towers_container.add_child(t)
	occupied_cells[cell] = t
	tower_cells[t] = [cell]
	queue_redraw()
	return t

func _occupy(t: Tower, cell: Vector2i) -> void:
	t.position = _cell_center(cell)
	occupied_cells[cell] = t
	tower_cells[t] = [cell]

func _free_tower(t: Tower) -> void:
	if not tower_cells.has(t):
		return
	for c in tower_cells[t]:
		if occupied_cells.get(c) == t:
			occupied_cells.erase(c)
	tower_cells.erase(t)

# ── 网格 ──
func _world_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL)), int(floor(p.y / CELL)))

func _cell_center(c: Vector2i) -> Vector2:
	return Vector2((c.x + 0.5) * CELL, (c.y + 0.5) * CELL)

func _is_buildable(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= COLS or cell.y >= ROWS:
		return false
	return not blocked.has(cell) and not occupied_cells.has(cell)

func _tower_at(pos: Vector2) -> Tower:
	return occupied_cells.get(_world_to_cell(pos), null)

func _railgun_btn_rect(t: Tower) -> Rect2:
	return Rect2(t.global_position + Vector2(-34, -56), Vector2(68, 20))

func _cheat_rect(i: int) -> Rect2:
	var col := i % CHEAT_COLS
	@warning_ignore("integer_division")
	var row := i / CHEAT_COLS
	return Rect2(CHEAT_X + col * (CHEAT_CELL + 3.0), CHEAT_Y + row * (CHEAT_CELL + 3.0), CHEAT_CELL, CHEAT_CELL)

func _set_message(t: String, timeout: float = 0.0) -> void:
	message_label.text = t
	_msg_timeout = timeout

# ── 绘制 ──
func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), bg_color)
	draw_rect(Rect2(0, 80, BUILD_RIGHT + 20.0, ROW_TOP - 80.0), field_color)
	for gx in range(120, int(BUILD_RIGHT), 200):
		draw_colored_polygon(PackedVector2Array([
			Vector2(gx, 92), Vector2(gx - 8, 80), Vector2(gx + 8, 80)
		]), Color(0.8, 0.3, 0.3, 0.55))
	draw_line(Vector2(0, ROW_TOP), Vector2(BUILD_RIGHT + 20.0, ROW_TOP), Color(0.85, 0.25, 0.25, 0.9), 3.0)
	draw_string(_font, Vector2(12, ROW_TOP - 8), "⚔ 防线 —— 狼越过这里就会围攻国王", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.9, 0.5, 0.5, 0.8))
	draw_rect(Rect2(0, ROW_TOP, BUILD_RIGHT + 20.0, ROW_BOTTOM - ROW_TOP), bg_color.lightened(0.06))
	draw_rect(Rect2(0, ROW_BOTTOM, BUILD_RIGHT + 20.0, 720.0 - ROW_BOTTOM), bg_color.darkened(0.25))
	draw_string(_font, Vector2(12, 706), "🏰 王座后方 —— 守住国王！", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.85, 0.4, 0.6))
	draw_string(_font, Vector2(700, 34), Levels.CONFIG.get("name", ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.85))

	# 经验条
	var xw := 220.0
	var xr: float = clampf(GameState.xp / GameState.xp_need(), 0.0, 1.0)
	draw_rect(Rect2(460, 18, xw, 14), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(460, 18, xw * xr, 14), Color(0.5, 0.85, 1.0))
	draw_rect(Rect2(460, 18, xw, 14), Color(1, 1, 1, 0.35), false, 1.0)
	draw_string(_font, Vector2(460, 50), "经验 %d/%d" % [int(GameState.xp), int(GameState.xp_need())], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.8, 0.9, 1.0, 0.8))

	var mp := get_global_mouse_position()
	# 作弊拖拽预览
	if deploy_dragging:
		var cell := _world_to_cell(mp)
		var col := Color(0.4, 0.9, 0.5) if _is_buildable(cell) else Color(0.9, 0.3, 0.3)
		_draw_cell(cell, col)
	elif dragging and drag_tower != null and is_instance_valid(drag_tower):
		var cell := _world_to_cell(mp)
		_draw_cell(cell, Color(0.4, 0.9, 0.5) if _is_buildable(cell) else Color(0.9, 0.3, 0.3))
	elif apply_elem != "":
		# 升级应用模式：高亮可点塔位与塔
		var ht := _tower_at(mp)
		if ht != null:
			var ok := TowerDefs.upgrade_result(ht.id, apply_elem) != ""
			draw_arc(ht.global_position, 26.0, 0.0, TAU, 32, Color(0.3, 1, 0.4) if ok else Color(1, 0.3, 0.3), 3.0)
		elif hover_cell.y >= 0:
			if _is_buildable(hover_cell) and _tower_count() < GameState.MAX_TOWERS:
				_draw_cell(hover_cell, Color(0.4, 0.9, 0.5))
	else:
		var ht2 := _tower_at(mp)
		if ht2 != null:
			_draw_tower_name(ht2)
		elif hover_cell.y >= 0 and hover_cell.x >= 0 and hover_cell.x < COLS and hover_cell.y < ROWS:
			if not blocked.has(hover_cell) and not occupied_cells.has(hover_cell):
				_draw_cell(hover_cell, Color(0.4, 0.9, 0.5, 0.5))

	# 塔位余量提示
	draw_string(_font, Vector2(20, ROW_BOTTOM + 24), "塔位 %d/%d" % [_tower_count(), GameState.MAX_TOWERS], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.7))

	for t in towers_container.get_children():
		if t is Tower and t.atk == "charge":
			_draw_railgun_button(t)

	if cheat_on:
		_draw_cheat()
	draw_string(_font, Vector2(880, 712), "开发版 · 按 C 切换作弊（免费放置任意塔）", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.8, 0.5))

func _draw_cell(c: Vector2i, col: Color) -> void:
	var rr := Rect2(Vector2(c.x * CELL, c.y * CELL) + Vector2(2, 2), Vector2(CELL - 4, CELL - 4))
	draw_rect(rr, Color(col.r, col.g, col.b, 0.2))
	draw_rect(rr, col, false, 2.0)

func _draw_tower_name(t: Tower) -> void:
	var nm := TowerDefs.name_of(t.id)
	var w := float(nm.length() * 15 + 16)
	var box := Rect2(t.global_position + Vector2(-w / 2.0, -44.0), Vector2(w, 22.0))
	draw_rect(box, Color(0, 0, 0, 0.7))
	draw_string(_font, box.position + Vector2(8, 16), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 0.85))

func _draw_railgun_button(t: Tower) -> void:
	var rect := _railgun_btn_rect(t)
	var ratio: float = t.charge_ratio()
	draw_rect(rect, Color(0.15, 0.12, 0.05, 0.9))
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * ratio, rect.size.y)), Color(0.5, 0.35, 0.1, 0.8))
	draw_rect(rect, Color(1, 0.9, 0.4) if ratio >= 1.0 else Color(0.8, 0.7, 0.4), false, 2.0)
	draw_string(_font, rect.position + Vector2(4, 15), "发射 %d%%" % int(ratio * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 0.7))

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
	if hover_id != "":
		var nm := TowerDefs.name_of(hover_id)
		var bw := float(nm.length() * 15 + 16)
		var box := Rect2(CHEAT_X - bw - 8.0, mp.y - 12.0, bw, 24.0)
		draw_rect(box, Color(0, 0, 0, 0.8))
		draw_string(_font, box.position + Vector2(8, 17), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 0.85))

# ── 仅供无头验证 ──
func _auto_resolve_choice() -> void:
	# 自动消费选择：优先升级已有塔，其次放新塔，满级后随机属性
	while GameState.pending_choices > 0:
		if actions_done >= GameState.MAX_ACTION_LEVEL:
			GameState.dmg_mult += 0.10
			GameState.consume_choice()
			continue
		var done := false
		for t in towers_container.get_children():
			if t.is_queued_for_deletion():
				continue
			for elem in ELEMS:
				var res: String = TowerDefs.upgrade_result(t.id, elem)
				if res != "":
					var anchor: Vector2i = (tower_cells[t] as Array)[0]
					_free_tower(t)
					t.queue_free()
					_spawn_tower(res, anchor)
					done = true
					break
			if done:
				break
		if not done and _tower_count() < GameState.MAX_TOWERS:
			for cx in COLS:
				var cell := Vector2i(cx, 14)
				if _is_buildable(cell):
					_spawn_tower(ELEMS[randi() % 3], cell)
					done = true
					break
		actions_done += 1
		GameState.consume_choice()
	GameState.ui_pause = false

func _run_autoplay() -> void:
	# 升级表完备性断言
	var fails := 0
	for t1 in ["L", "E", "B"]:
		for e1 in ELEMS:
			var t2: String = TowerDefs.upgrade_result(t1, e1)
			if t2 == "" or TowerDefs.get_def(t2).is_empty() or int(TowerDefs.get_def(t2)["t"]) != 2:
				print("FAIL t1 ", t1, "+", e1, "->", t2); fails += 1
			for e2 in ELEMS:
				var t3: String = TowerDefs.upgrade_result(t2, e2)
				if t3 == "" or TowerDefs.get_def(t3).is_empty() or int(TowerDefs.get_def(t3)["t"]) != 3:
					print("FAIL t2 ", t2, "+", e2, "->", t3); fails += 1
				if TowerDefs.upgrade_result(t3, "L") != "":
					print("FAIL t3 not capped ", t3); fails += 1
	print("[AUTOPLAY] upgrade-table fails=", fails)
	# 起始塔 + 直接开战
	_spawn_tower("B", Vector2i(10, 14))
	actions_done = 1
	started = true
	prep_timer = 1.0
	GameState.set_phase(GameState.Phase.PREP)
	GameState.game_over.connect(func(_w): print("[AUTOPLAY] game_over score=", GameState.score, " level=", GameState.xp_level, " towers=", _tower_count(), " actions=", actions_done))
