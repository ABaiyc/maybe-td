extends RefCounted
class_name TowerDefs
## 防御塔目录 + 确定性融合表。权威设计见 docs/塔设计-30种.md。
## 主题：每个塔=一只猪持对应武器。M1 只有 3 个基础塔可建造并实现行为；
## 二/三级塔的数据与配方已就绪（供 M2 合成、M5 图鉴），行为暂用最接近的基础行为兜底。

# 行为标签（M1 实现 single/pierce/aoe，其余先归类到最接近的基础行为）
# single = 单体追踪 ; pierce = 直线穿透 ; aoe = 抛射范围爆炸(+debuff)

# 融合配方：[材料A, 材料B, 产物]（无序）
const RECIPES := [
	# 一级 -> 二级
	["L", "L", "LL"], ["E", "E", "EE"], ["B", "B", "BB"],
	["L", "E", "LE"], ["L", "B", "LB"], ["E", "B", "EB"],
	# 二级 -> 三级（6 种二级两两配对 = 21 种，逐一对应）
	["LL", "LL", "prism"],
	["EE", "EE", "reactor"],
	["BB", "BB", "railgun"],
	["LL", "LE", "beam_burst"],
	["LL", "LB", "rapid_ap"],
	["EE", "LE", "ele_matrix"],
	["EE", "EB", "barrage"],
	["BB", "LB", "anti_mat"],
	["BB", "EB", "burst_gl"],
	["LL", "EE", "plasma_field"],
	["LE", "LE", "twin_laser"],
	["LL", "BB", "precision_snipe"],
	["LB", "LB", "rapid_ap_chain"],
	["EE", "BB", "mine_layer"],
	["EB", "EB", "gl_array"],
	["LE", "LB", "emp"],
	["LL", "EB", "laser_detonate"],
	["LE", "EB", "catalyst"],
	["EE", "LB", "ele_ap"],
	["LB", "EB", "omni"],
	["BB", "LE", "tactical_mark"],
]

# 塔定义。字段：n=名 t=等级 c=元素成分 dmg 伤害 rng 射程 cd 攻击间隔
#   bhv 行为 pierce 穿透数 splash 溅射半径 debuff 是否附带元素效果
#   col 颜色(hex) cost 造价(仅基础塔可建造) desc 简述(图鉴用)
const TOWERS := {
	# ── 一级基础塔 ──
	"L": {"n": "激光猪", "t": 1, "c": "L", "dmg": 22.0, "rng": 230.0, "cd": 1.1, "bhv": "pierce", "pierce": 2, "splash": 0.0, "debuff": false, "col": "3a8ee6", "cost": 70, "cells": [2, 1], "desc": "蓝色激光持续照射，单体穿透2个敌人。攻速慢、不追踪。"},
	"E": {"n": "元素猪", "t": 1, "c": "E", "dmg": 14.0, "rng": 175.0, "cd": 1.4, "bhv": "aoe", "pierce": 0, "splash": 72.0, "debuff": true, "col": "a64ed6", "cost": 60, "cells": [2, 2], "desc": "抛射元素球范围爆炸，随机燃烧/冰冻效果。单发低、弹速慢。"},
	"B": {"n": "机枪猪", "t": 1, "c": "B", "dmg": 8.0, "rng": 195.0, "cd": 0.35, "bhv": "single", "pierce": 0, "splash": 0.0, "debuff": false, "col": "e6943a", "cost": 45, "cells": [1, 1], "desc": "突突突连射，高速稳定物理伤害。无穿透、打不动高甲。"},

	# ── 二级融合塔 ──
	"LL": {"n": "聚焦激光", "t": 2, "c": "LL", "dmg": 46.0, "rng": 300.0, "cd": 1.1, "bhv": "pierce", "pierce": 5, "splash": 0.0, "debuff": false, "col": "e6483a", "desc": "更粗的红色激光，伤害×2，穿透5个，射程+30%。"},
	"EE": {"n": "元素风暴", "t": 2, "c": "EE", "dmg": 18.0, "rng": 185.0, "cd": 1.3, "bhv": "aoe", "pierce": 0, "splash": 86.0, "debuff": true, "col": "c34ee6", "desc": "同时打出火/冰/雷三球，三种debuff可叠加。"},
	"BB": {"n": "机枪塔", "t": 2, "c": "BB", "dmg": 9.0, "rng": 200.0, "cd": 0.3, "bhv": "single", "pierce": 0, "splash": 0.0, "debuff": false, "col": "e6b03a", "desc": "双管并排射击，越打越快（有上限），停火3秒后重置。"},
	"LE": {"n": "元素激光", "t": 2, "c": "LE", "dmg": 30.0, "rng": 240.0, "cd": 1.0, "bhv": "pierce", "pierce": 2, "splash": 0.0, "debuff": true, "col": "7a6ee6", "desc": "激光附带随机元素效果，照射时持续刷新debuff。"},
	"LB": {"n": "穿甲弹", "t": 2, "c": "LB", "dmg": 34.0, "rng": 235.0, "cd": 0.6, "bhv": "pierce", "pierce": 3, "splash": 0.0, "debuff": false, "col": "6e9ee6", "desc": "激光制导穿甲弹追踪敌人，穿透3个、无视30%护甲。"},
	"EB": {"n": "榴弹炮", "t": 2, "c": "EB", "dmg": 26.0, "rng": 205.0, "cd": 1.2, "bhv": "aoe", "pierce": 0, "splash": 108.0, "debuff": true, "col": "d67a4e", "desc": "元素榴弹物理爆炸+灼烧，爆炸范围更大。"},

	# ── 三级质变塔（21）──
	"prism": {"n": "棱镜塔", "t": 3, "c": "LLLL", "dmg": 26.0, "rng": 320.0, "cd": 1.0, "bhv": "pierce", "pierce": 9, "splash": 0.0, "debuff": false, "col": "ff5a5a", "desc": "折射分裂：主激光命中后分裂3道小激光，再各分裂3道小小激光。"},
	"reactor": {"n": "元素反应炉", "t": 3, "c": "EEEE", "dmg": 24.0, "rng": 170.0, "cd": 0.5, "bhv": "aoe", "pierce": 0, "splash": 150.0, "debuff": true, "col": "d65adf", "desc": "领域展开：塔周围元素领域每秒三重元素伤害。"},
	"railgun": {"n": "轨道炮", "t": 3, "c": "BBBB", "dmg": 220.0, "rng": 700.0, "cd": 3.5, "bhv": "pierce", "pierce": 99, "splash": 0.0, "debuff": false, "col": "ffd23a", "desc": "充能巨炮：满弹一炮穿透全路径所有敌人。"},
	"beam_burst": {"n": "光束爆裂炮", "t": 3, "c": "LLLE", "dmg": 70.0, "rng": 300.0, "cd": 1.0, "bhv": "pierce", "pierce": 4, "splash": 60.0, "debuff": true, "col": "ff7a5a", "desc": "命中引爆：照射叠满3层引发元素爆炸，范围渐增。"},
	"rapid_ap": {"n": "高速穿甲枪", "t": 3, "c": "LLLB", "dmg": 30.0, "rng": 280.0, "cd": 0.125, "bhv": "pierce", "pierce": 99, "splash": 0.0, "debuff": false, "col": "5ab0ff", "desc": "穿透弹幕：每秒8发穿甲弹，穿透所有敌人。"},
	"ele_matrix": {"n": "元素矩阵", "t": 3, "c": "EEEL", "dmg": 40.0, "rng": 280.0, "cd": 0.9, "bhv": "pierce", "pierce": 5, "splash": 0.0, "debuff": true, "col": "c75adf", "desc": "多目标锁定：3道元素激光在怪群间弹射。"},
	"barrage": {"n": "弹幕炮塔", "t": 3, "c": "EEEB", "dmg": 11.0, "rng": 230.0, "cd": 1.5, "bhv": "aoe", "pierce": 0, "splash": 70.0, "debuff": true, "col": "df6acf", "desc": "弹幕覆盖：扇形倾泻12发元素弹，每发随机元素，攻速偏慢。"},
	"anti_mat": {"n": "反器材狙击炮", "t": 3, "c": "BBBL", "dmg": 260.0, "rng": 9000.0, "cd": 3.0, "bhv": "single", "pierce": 0, "splash": 0.0, "debuff": false, "col": "ffcf5a", "desc": "超远狙击：全图必中，优先打血最高者，伤害×5。"},
	"burst_gl": {"n": "爆裂榴弹炮", "t": 3, "c": "BBBE", "dmg": 40.0, "rng": 215.0, "cd": 1.1, "bhv": "aoe", "pierce": 0, "splash": 120.0, "debuff": true, "col": "e69a5a", "desc": "连锁爆炸：爆炸后分裂小炸弹二次爆炸。"},
	"plasma_field": {"n": "等离子场", "t": 3, "c": "LLEE", "dmg": 38.0, "rng": 260.0, "cd": 0.8, "bhv": "pierce", "pierce": 4, "splash": 0.0, "debuff": true, "col": "7adfe6", "desc": "塔间连线：与同类塔连出等离子电网，组网杀敌。"},
	"twin_laser": {"n": "双子激光塔", "t": 3, "c": "LLEE", "dmg": 42.0, "rng": 270.0, "cd": 0.5, "bhv": "pierce", "pierce": 3, "splash": 0.0, "debuff": true, "col": "5ae6c7", "desc": "双子同步：双激光交替射击，每2秒一次拍频爆发。"},
	"precision_snipe": {"n": "精准狙击塔", "t": 3, "c": "LLBB", "dmg": 120.0, "rng": 340.0, "cd": 1.4, "bhv": "single", "pierce": 0, "splash": 0.0, "debuff": false, "col": "9ad6ff", "desc": "锁头暴击：锁定血最高的敌人，必定暴击×3。"},
	"rapid_ap_chain": {"n": "连射穿甲炮", "t": 3, "c": "LLBB", "dmg": 28.0, "rng": 260.0, "cd": 0.18, "bhv": "pierce", "pierce": 99, "splash": 0.0, "debuff": false, "col": "6ec7e6", "desc": "穿透增伤：每穿透一个敌人伤害+15%（无上限）。"},
	"mine_layer": {"n": "自动布雷车", "t": 3, "c": "EEBB", "dmg": 30.0, "rng": 220.0, "cd": 1.0, "bhv": "aoe", "pierce": 0, "splash": 64.0, "debuff": true, "col": "c79a5a", "desc": "地雷战术：路径埋元素地雷，无限叠加越打越强。"},
	"gl_array": {"n": "元素榴弹阵列", "t": 3, "c": "EEBB", "dmg": 20.0, "rng": 240.0, "cd": 1.5, "bhv": "aoe", "pierce": 0, "splash": 100.0, "debuff": true, "col": "d6b05a", "desc": "齐射轰炸：一次6发榴弹，落地留元素残渣灼烧。"},
	"emp": {"n": "电磁脉冲塔", "t": 3, "c": "LLEB", "dmg": 30.0, "rng": 230.0, "cd": 1.6, "bhv": "aoe", "pierce": 0, "splash": 140.0, "debuff": true, "col": "5ad6df", "desc": "EMP干扰：范围内敌人攻速-70%、移动-50%。"},
	"laser_detonate": {"n": "激光引爆炮", "t": 3, "c": "LLEB", "dmg": 50.0, "rng": 290.0, "cd": 1.0, "bhv": "aoe", "pierce": 0, "splash": 110.0, "debuff": true, "col": "df8a5a", "desc": "标记→引爆：附着元素弹再用激光引爆，伤害×3。"},
	"catalyst": {"n": "催化反应塔", "t": 3, "c": "EELB", "dmg": 16.0, "rng": 200.0, "cd": 1.0, "bhv": "aoe", "pierce": 0, "splash": 80.0, "debuff": true, "col": "b0df5a", "desc": "元素共鸣：给周围塔加元素伤害buff，体系放大器。"},
	"ele_ap": {"n": "元素穿甲弹", "t": 3, "c": "EELB", "dmg": 38.0, "rng": 250.0, "cd": 0.5, "bhv": "pierce", "pierce": 99, "splash": 0.0, "debuff": true, "col": "9ad65a", "desc": "元素附魔穿透：每穿一个增强一层，5次后翻倍。"},
	"omni": {"n": "全能作战塔", "t": 3, "c": "BBLE", "dmg": 48.0, "rng": 260.0, "cd": 0.6, "bhv": "single", "pierce": 0, "splash": 40.0, "debuff": true, "col": "e6c75a", "desc": "形态自动切换：狙击/扫射/元素三形态智能选最优。"},
	"tactical_mark": {"n": "战术标记炮", "t": 3, "c": "BBLE", "dmg": 30.0, "rng": 300.0, "cd": 0.9, "bhv": "single", "pierce": 0, "splash": 0.0, "debuff": false, "col": "e6a85a", "desc": "标记集火：标记敌人，全塔对其伤害+40%（叠3层）。"},
}

const BASE_IDS := ["L", "E", "B"]

## 攻击原型（严格对应 docs/塔设计-30种.md 的攻击方式，而非一律弹道）：
##  beam   持续直线激光，瞄准跟随，沿线 DPS（dmg 视为 DPS）
##  proj   弹道（具体 single/pierce/aoe 看 bhv）
##  snipe  瞬发狙击：锁血量最高、超大射程、单发巨伤（可暴击）
##  domain 领域：塔周围范围持续 DPS
##  mine   布雷：无论有无敌人按频率往路径埋雷，敌人踩中爆炸
##  charge 充能巨炮：蓄满后一道贯穿长线轰所有敌人
##  link   塔间连线：与同类塔之间拉伤害线，敌人穿过受伤
##  aura   被动光环：给周围塔加伤害（自身不攻击）
##  mark   标记：给敌人挂集火标记，全体对其伤害放大
const ATTACK := {
	"L": "beam", "E": "proj", "B": "proj",
	"LL": "beam", "EE": "proj", "BB": "proj", "LE": "beam", "LB": "proj", "EB": "proj",
	"prism": "split", "reactor": "domain", "railgun": "charge",
	"beam_burst": "beam", "rapid_ap": "proj", "ele_matrix": "proj", "barrage": "proj",
	"anti_mat": "snipe", "burst_gl": "proj", "plasma_field": "link", "twin_laser": "ring",
	"precision_snipe": "snipe", "rapid_ap_chain": "proj", "mine_layer": "mine",
	"gl_array": "proj", "emp": "proj", "laser_detonate": "proj", "catalyst": "aura",
	"ele_ap": "proj", "omni": "proj", "tactical_mark": "mark",
}

static func attack_of(id: String) -> String:
	return ATTACK.get(id, "proj")

static func get_def(id: String) -> Dictionary:
	return TOWERS.get(id, {})

static func name_of(id: String) -> String:
	return TOWERS.get(id, {}).get("n", id)

## 两塔融合，返回产物 id；不可融合返回空串。
static func fuse(a: String, b: String) -> String:
	for r in RECIPES:
		if (r[0] == a and r[1] == b) or (r[0] == b and r[1] == a):
			return r[2]
	return ""

## 反查某塔由哪些配方合成（图鉴用），返回 [[A,B], ...]
static func recipes_for(id: String) -> Array:
	var out := []
	for r in RECIPES:
		if r[2] == id:
			out.append([r[0], r[1]])
	return out

static func ids_by_tier(t: int) -> Array:
	var out := []
	for id in TOWERS:
		if TOWERS[id]["t"] == t:
			out.append(id)
	return out

static func color_of(id: String) -> Color:
	return Color(TOWERS.get(id, {}).get("col", "ffffff"))

## 占地格数 (列, 行)，统一按等级：一级 1 格、二级 4 格、三级 6 格。
static func footprint(id: String) -> Vector2i:
	match int(get_def(id).get("t", 1)):
		1: return Vector2i(1, 1)  # 1 格
		2: return Vector2i(2, 2)  # 4 格
		_: return Vector2i(3, 2)  # 6 格
