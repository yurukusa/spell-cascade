extends Node2D

## GameMain - Idol Tower ゲームループ。
## タワー中央配置、周回敵、10分ラン、判断イベント>=6回保証。

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
var current_wave := 0
var max_waves := 20
var enemies_alive := 0

# 判断イベント管理（最初は頻繁に、徐々に間隔が開く）
var upgrade_events_given := 0
var next_upgrade_time := 0.0
# 各イベントのタイミング: 15s, 35s, 60s, 90s, 130s, 180s, 240s, 310s, 390s, 480s, 570s
var upgrade_schedule: Array[float] = [15.0, 35.0, 60.0, 90.0, 130.0, 180.0, 240.0, 310.0, 390.0, 480.0, 570.0]

# 敵スポーン
var enemy_scene: PackedScene
var spawn_timer := 0.0
var spawn_interval := 2.0  # 初期スポーン間隔

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

	# 初回アップグレード（ゲーム開始時にスキル選択）
	_show_initial_skill_choice()

	# 最初の判断イベントタイミング（スケジュール式）
	if not upgrade_schedule.is_empty():
		next_upgrade_time = upgrade_schedule[0]

func _process(delta: float) -> void:
	if game_over:
		return

	run_time += delta
	_update_timer_display()

	# 10分経過 → 勝利
	if run_time >= max_run_time:
		_win_game()
		return

	# 敵スポーン
	spawn_timer += delta
	var current_interval := maxf(spawn_interval - run_time * 0.003, 0.3)  # 時間経過で加速
	if spawn_timer >= current_interval:
		spawn_timer = 0.0
		_spawn_enemy()

	# 判断イベント（スケジュール式: 最初は頻繁に）
	if run_time >= next_upgrade_time and upgrade_events_given < upgrade_schedule.size():
		upgrade_events_given += 1
		if upgrade_events_given < upgrade_schedule.size():
			next_upgrade_time = upgrade_schedule[upgrade_events_given]
		else:
			next_upgrade_time = INF  # スケジュール終了
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

# --- 初回スキル選択 ---

func _show_initial_skill_choice() -> void:
	var skill_ids: Array = build_system.get_random_skill_ids(3)
	upgrade_ui.show_skill_choice(0, skill_ids)

# --- アップグレード選択 ---

func _show_upgrade_choice() -> void:
	# 空スロットがあればスキル追加、なければサポート/Mod追加
	var empty_slot := -1
	for i in range(tower.max_slots):
		if tower.get_module(i) == null:
			empty_slot = i
			break

	if empty_slot >= 0:
		# 新スキル選択
		var skill_ids: Array = build_system.get_random_skill_ids(3)
		upgrade_ui.show_skill_choice(empty_slot, skill_ids)
	else:
		# 全スロット埋まっている → サポート/Mod/入れ替え
		var roll := randf()
		if roll < 0.4:
			# サポートリンク
			var support_ids: Array = build_system.get_random_support_ids(3)
			upgrade_ui.show_support_choice(support_ids)
		elif roll < 0.7:
			# Mod付与
			var prefix: Dictionary = build_system.roll_prefix()
			var suffix: Dictionary = build_system.roll_suffix()
			upgrade_ui.show_mod_choice(prefix, suffix)
		else:
			# スキル入れ替え（主体感を出す。受動成長だけにしない）
			var swap_slot: int = randi() % tower.max_slots
			var current_module: Variant = tower.get_module(swap_slot)
			var exclude: Array[String] = []
			if current_module:
				exclude.append(current_module.skill_id)
			var skill_ids: Array = build_system.get_random_skill_ids(3, exclude)
			upgrade_ui.show_skill_swap(swap_slot, skill_ids)

func _on_upgrade_chosen(upgrade_data: Dictionary) -> void:
	var upgrade_type: String = upgrade_data.get("type", "")

	match upgrade_type:
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

	# 時間経過でスケーリング
	var time_scale := 1.0 + run_time / 120.0  # 2分ごとに+1倍
	var hp_val := 20.0 * time_scale
	var speed_val := 60.0 + run_time * 0.05
	var dmg_val := 5.0 + run_time * 0.01

	enemy.init(tower, speed_val, hp_val, dmg_val)
	enemy.died.connect(_on_enemy_died)
	enemies_alive += 1
	add_child(enemy)

func _on_enemy_died(_enemy: Node2D) -> void:
	enemies_alive -= 1

# --- タワーイベント ---

func _on_tower_damaged(current: float, _max: float) -> void:
	hp_bar.value = current

func _on_tower_destroyed() -> void:
	game_over = true
	wave_label.text = "TOWER DESTROYED"
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
