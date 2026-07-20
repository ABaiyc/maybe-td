extends RefCounted
class_name Levels
## 无尽模式配置（类肉鸽）：不再有关卡/波次，出怪由分数难度曲线驱动（见 main.gd 出怪导演）。

const SPAWN_Y := -30.0        # 出怪 y（屏幕上方外）
const LINE_Y := 560.0         # 防线：敌人走到这里开始围攻国王
const SPAWN_X_MIN := 60.0
const SPAWN_X_MAX := 1060.0

const CONFIG := {
	"name": "无尽狼潮",
	"bg": "23301f",
	"field": "2c3a26",
	"king_pos": Vector2(560, 682),
}

# ── 分数难度曲线 ──
## 出怪间隔：随分数缩短
static func spawn_interval(score: int) -> float:
	return clampf(0.85 - float(score) / 2500.0, 0.16, 0.85)

## 敌人血量倍率：随分数增厚
static func hp_mult(score: int) -> float:
	return 1.0 + float(score) / 600.0

## 敌人移速倍率：缓慢上升，封顶 1.6
static func speed_mult(score: int) -> float:
	return minf(1.0 + float(score) / 5000.0, 1.6)

## 分数解锁的敌人池（新机制怪按分数逐步登场）
static func enemy_pool(score: int) -> Array:
	var pool := ["wolf", "wolf", "wolf"]
	if score >= 250:
		pool.append_array(["fast", "fast"])
	if score >= 700:
		pool.append("armored")
	if score >= 1400:
		pool.append("armored")
	return pool

# Boss 登场：分数过阈值后周期性出现（头狼先、羊皮狼后）
const ALPHA_UNLOCK := 1500
const SHEEP_UNLOCK := 3500
const BOSS_EVERY := 1200      # 解锁后每涨这么多分再来一只
