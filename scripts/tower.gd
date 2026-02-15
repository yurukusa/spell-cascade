extends Node2D

## Tower - プレイヤーの塔。モジュールスロットを持ち、各スロットが独立して攻撃する。
## 操作は最小（配置/差し替え/リンク）、判断が最大。

signal module_changed(slot_index: int)
signal tower_damaged(current_hp: float, max_hp: float)
signal tower_destroyed

@export var max_hp := 500.0
@export var max_slots := 3  # Week1は3スロット

var hp: float
var modules: Array = []  # Array of BuildSystem.TowerModule

func _ready() -> void:
	hp = max_hp
	# 空スロットで初期化
	for i in range(max_slots):
		modules.append(null)

func get_module(slot: int):
	if slot >= 0 and slot < modules.size():
		return modules[slot]
	return null

func set_module(slot: int, module) -> void:
	if slot >= 0 and slot < modules.size():
		modules[slot] = module
		module_changed.emit(slot)

func get_filled_modules() -> Array:
	var filled := []
	for m in modules:
		if m != null:
			filled.append(m)
	return filled

func take_damage(amount: float) -> void:
	hp -= amount
	tower_damaged.emit(hp, max_hp)
	if hp <= 0:
		hp = 0
		tower_destroyed.emit()

func heal(amount: float) -> void:
	hp = minf(hp + amount, max_hp)
	tower_damaged.emit(hp, max_hp)
