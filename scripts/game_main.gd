extends Node2D

## GameMain - 放置専用アクションRPG。
## Behavior Chips（操作AI）を選んでスタート。プレイヤーは自動で動く。
## 「プログラムが装備品」= 知識は力。

@onready var tower: Node2D = $Tower
@onready var ui_layer: CanvasLayer = $UI
@onready var hp_bar: ProgressBar = $UI/HPBar
@onready var wave_label: Label = $UI/WaveLabel
@onready var timer_label: Label = $UI/TimerLabel
@onready var build_label: Label = $UI/BuildLabel
@onready var restart_label: Label = $UI/RestartLabel

var build_system: Node  # BuildSystem autoload
var upgrade_ui: Node  # UpgradeUI

# ゲーム状態
var run_time := 0.0
var max_run_time := 600.0  # 10分
var game_over := false
var enemies_alive := 0

# ロードアウト選択フェーズ
var loadout_phase := 0  # 0=preset選択, 1=playing

# 判断イベント管理
var upgrade_events_given := 0
var next_upgrade_time := 0.0
# 2分フック: 10秒で最初のゲームチェンジ体験
var upgrade_schedule: Array[float] = [10.0, 25.0, 45.0, 70.0, 100.0, 140.0, 190.0, 250.0, 320.0, 400.0]

# 敵スポーン（初期密度ブースト: 最初から弾幕感を出す）
var enemy_scene: PackedScene
var spawn_timer := 0.0
var spawn_interval := 1.2  # 2.0→1.2: 最初から敵が多い

func _ready() -> void:
	build_system = get_node("/root/BuildSystem")

	# 敵シーンロード
	enemy_scene = load("res://scenes/enemy.tscn")

	# UpgradeUI生成
	var upgrade_script := load("res://scripts/build_upgrade_ui.gd")
	upgrade_ui = CanvasLayer.new()
	upgrade_ui.set_script(upgrade_script)
	upgrade_ui.name = "UpgradeUI"
	add_child(upgrade_ui)
	upgrade_ui.upgrade_chosen.connect(_on_upgrade_chosen)

	# タワー接続
	tower.tower_damaged.connect(_on_tower_damaged)
	tower.tower_destroyed.connect(_on_tower_destroyed)

	# UI初期化
	hp_bar.max_value = tower.max_hp
	hp_bar.value = tower.max_hp
	restart_label.visible = false

	# ロードアウト選択開始（プリセット1画面）
	_show_loadout_choice()

	# 最初の判断イベントタイミング
	if not upgrade_schedule.is_empty():
		next_upgrade_time = upgrade_schedule[0]

func _process(delta: float) -> void:
	if game_over or loadout_phase < 1:
		return

	run_time += delta
	_update_timer_display()

	# 10分経過 → 勝利
	if run_time >= max_run_time:
		_win_game()
		return

	# 敵スポーン
	spawn_timer += delta
	var current_interval := maxf(spawn_interval - run_time * 0.003, 0.3)
	if spawn_timer >= current_interval:
		spawn_timer = 0.0
		_spawn_enemy()

	# 判断イベント
	if run_time >= next_upgrade_time and upgrade_events_given < upgrade_schedule.size():
		upgrade_events_given += 1
		if upgrade_events_given < upgrade_schedule.size():
			next_upgrade_time = upgrade_schedule[upgrade_events_given]
		else:
			next_upgrade_time = INF
		_show_upgrade_choice()

func _update_timer_display() -> void:
	var remaining := maxf(max_run_time - run_time, 0.0)
	var total_sec: int = floori(remaining)
	@warning_ignore("integer_division")
	var minutes: int = total_sec / 60
	var seconds: int = total_sec % 60
	timer_label.text = "%d:%02d" % [minutes, seconds]

func _update_build_display() -> void:
	var lines: PackedStringArray = []

	# Behavior Chips表示
	var move_chip: Dictionary = build_system.get_equipped_chip("move")
	var attack_chip: Dictionary = build_system.get_equipped_chip("attack")
	var skill_chip: Dictionary = build_system.get_equipped_chip("skill")
	lines.append("AI: %s / %s / %s" % [
		move_chip.get("name", "?"),
		attack_chip.get("name", "?"),
		skill_chip.get("name", "?"),
	])
	lines.append("")

	# スキルスロット
	for i in range(tower.max_slots):
		var module: Variant = tower.get_module(i)
		if module == null:
			lines.append("Slot %d: [Empty]" % (i + 1))
		else:
			var stats: Dictionary = build_system.calculate_module_stats(module)
			var skill_name: String = stats.get("name", "?")
			var sup_names: PackedStringArray = []
			for sup_id in module.support_ids:
				var sup_data: Dictionary = build_system.supports.get(sup_id, {})
				sup_names.append(sup_data.get("name", sup_id))
			var mod_info := ""
			if not module.prefix.is_empty():
				mod_info += module.prefix.get("name", "")
			if not module.suffix.is_empty():
				if mod_info != "":
					mod_info += " "
				mod_info += module.suffix.get("name", "")
			var link_str := ""
			if not sup_names.is_empty():
				link_str = " + " + " + ".join(sup_names)
			if mod_info != "":
				link_str += " [%s]" % mod_info
			lines.append("Slot %d: %s%s" % [(i + 1), skill_name, link_str])

	# シナジー表示
	var filled: Array = tower.get_filled_modules()
	if not filled.is_empty():
		var active_synergies: Array = build_system.check_active_synergies(filled)
		if not active_synergies.is_empty():
			lines.append("")
			for syn in active_synergies:
				lines.append("SYNERGY: %s" % syn.get("name", "?"))

	build_label.text = "\n".join(lines)

# --- ロードアウト選択（1画面プリセット）---

func _show_loadout_choice() -> void:
	var presets_list: Array[Dictionary] = build_system.get_all_presets()
	upgrade_ui.show_preset_choice(presets_list)

func _on_upgrade_chosen(upgrade_data: Dictionary) -> void:
	var upgrade_type: String = upgrade_data.get("type", "")

	match upgrade_type:
		"preset":
			var preset_id: String = upgrade_data.get("preset_id", "")
			var starting_skill: String = build_system.apply_preset(preset_id)
			# プリセットの初期スキルでSlot 0を即セット
			if starting_skill != "":
				var module: Variant = build_system.TowerModule.new(starting_skill)
				tower.set_module(0, module)
				_setup_tower_attacks()
			loadout_phase = 1
			_start_game()

		"chip":
			var chip_id: String = upgrade_data.get("chip_id", "")
			var chip_data: Dictionary = build_system.get_chip(chip_id)
			var category: String = chip_data.get("category", "")
			build_system.equip_chip(category, chip_id)

		"skill":
			var slot: int = upgrade_data.get("slot", 0)
			var skill_id: String = upgrade_data.get("skill_id", "")
			var module: Variant = build_system.TowerModule.new(skill_id)
			tower.set_module(slot, module)
			_setup_tower_attacks()

		"support":
			var support_id: String = upgrade_data.get("support_id", "")
			var target_slot: int = upgrade_data.get("target_slot", 0)
			var module: Variant = tower.get_module(target_slot)
			if module and module.support_ids.size() < 2:
				module.support_ids.append(support_id)
				tower.module_changed.emit(target_slot)
				_setup_tower_attacks()

		"mod":
			var mod_data: Dictionary = upgrade_data.get("mod_data", {})
			var mod_type: String = upgrade_data.get("mod_type", "prefix")
			var target_slot: int = upgrade_data.get("target_slot", 0)
			var module: Variant = tower.get_module(target_slot)
			if module:
				if mod_type == "prefix":
					module.prefix = mod_data
				else:
					module.suffix = mod_data
				tower.module_changed.emit(target_slot)
				_setup_tower_attacks()

	_update_build_display()

func _start_game() -> void:
	_update_build_display()
	get_tree().paused = false
	# 即座に3体スポーンして「始まった！」感を出す
	for i in range(3):
		_spawn_enemy()

# --- アップグレード選択（ラン中）---

func _show_upgrade_choice() -> void:
	# 最初の判断イベント（10秒）は「ゲームが変わる」体験を保証
	# → 強力サポート（Chain/Fork/Pierce）を確定提示
	if upgrade_events_given == 1:
		var guaranteed_supports: Array = ["chain", "fork", "pierce"]
		upgrade_ui.show_support_choice(guaranteed_supports)
		return

	# 空スロットがあればスキル追加
	var empty_slot := -1
	for i in range(tower.max_slots):
		if tower.get_module(i) == null:
			empty_slot = i
			break

	if empty_slot >= 0:
		# 既存スキルと重複しないように除外
		var equipped: Array[String] = []
		for i in range(tower.max_slots):
			var m: Variant = tower.get_module(i)
			if m != null:
				equipped.append(m.skill_id)
		var skill_ids: Array = build_system.get_random_skill_ids(3, equipped)
		upgrade_ui.show_skill_choice(empty_slot, skill_ids)
	else:
		var roll := randf()
		if roll < 0.3:
			# サポートリンク
			var support_ids: Array = build_system.get_random_support_ids(3)
			upgrade_ui.show_support_choice(support_ids)
		elif roll < 0.55:
			# Mod付与
			var prefix: Dictionary = build_system.roll_prefix()
			var suffix: Dictionary = build_system.roll_suffix()
			upgrade_ui.show_mod_choice(prefix, suffix)
		elif roll < 0.8:
			# スキル入れ替え
			var swap_slot: int = randi() % tower.max_slots
			var current_module: Variant = tower.get_module(swap_slot)
			var exclude: Array[String] = []
			if current_module:
				exclude.append(current_module.skill_id)
			var skill_ids: Array = build_system.get_random_skill_ids(3, exclude)
			upgrade_ui.show_skill_swap(swap_slot, skill_ids)
		else:
			# Behavior Chip入替（ラン中ドロップ相当）
			var categories: Array[String] = ["move", "attack", "skill"]
			var cat: String = categories[randi() % categories.size()]
			var cat_label: String = {"move": "Move AI", "attack": "Attack AI", "skill": "Skill AI"}.get(cat, cat)
			var chip_options: Array[Dictionary] = build_system.get_chips_by_category(cat)
			upgrade_ui.show_chip_choice(cat_label + " Swap", chip_options)

func _setup_tower_attacks() -> void:
	# 既存の攻撃ノードを削除
	for child in tower.get_children():
		if child.is_in_group("tower_attacks"):
			child.queue_free()

	# 各スロットの攻撃ノードを生成
	for i in range(tower.max_slots):
		var module: Variant = tower.get_module(i)
		if module == null:
			continue

		var stats: Dictionary = build_system.calculate_module_stats(module)
		var attack_node := Node2D.new()
		var attack_script := load("res://scripts/tower_attack.gd")
		attack_node.set_script(attack_script)
		attack_node.name = "Attack_%d" % i
		attack_node.add_to_group("tower_attacks")
		tower.add_child(attack_node)
		attack_node.setup(i, stats)

# --- 敵スポーン ---

func _spawn_enemy() -> void:
	if enemy_scene == null:
		return

	var enemy := enemy_scene.instantiate() as CharacterBody2D

	# 画面外からスポーン
	var vp := get_tree().root.get_visible_rect().size
	var side := randi() % 4
	var spawn_pos := Vector2.ZERO

	match side:
		0: spawn_pos = Vector2(randf_range(0, vp.x), -40)
		1: spawn_pos = Vector2(randf_range(0, vp.x), vp.y + 40)
		2: spawn_pos = Vector2(-40, randf_range(0, vp.y))
		3: spawn_pos = Vector2(vp.x + 40, randf_range(0, vp.y))

	enemy.position = spawn_pos

	# 時間経過でスケーリング（2分で緊張感が出る難易度）
	var time_scale := 1.0 + run_time / 80.0
	var hp_val := 30.0 * time_scale
	var speed_val := 70.0 + run_time * 0.15
	var dmg_val := 8.0 + run_time * 0.03

	enemy.init(tower, speed_val, hp_val, dmg_val)
	enemy.died.connect(_on_enemy_died)
	enemies_alive += 1
	add_child(enemy)

func _on_enemy_died(_enemy: Node2D) -> void:
	enemies_alive -= 1
	# enemy_killed シグナルをtowerから発火（on_killチップ用）
	tower.enemy_killed.emit()

# --- タワーイベント ---

func _on_tower_damaged(current: float, _max: float) -> void:
	hp_bar.value = current

func _on_tower_destroyed() -> void:
	game_over = true
	wave_label.text = "DESTROYED"
	restart_label.visible = true
	restart_label.text = "Press R to Restart"

func _win_game() -> void:
	game_over = true
	wave_label.text = "SURVIVED 10 MINUTES!"
	restart_label.visible = true
	restart_label.text = "Press R to Restart"

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_R and game_over:
			get_tree().paused = false
			get_tree().reload_current_scene()
		elif event.keycode == KEY_ESCAPE and not game_over:
			get_tree().paused = not get_tree().paused
			if get_tree().paused:
				wave_label.text = "PAUSED"
