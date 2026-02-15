extends Node2D

## GameMain - Mirror War: 縦スクロールハクスラ。
## 手動で強くなる→装備更新→オート化を"勝ち取る"。
## 「プログラムが装備品」= 知識は力。

@onready var tower: Node2D = $Tower
@onready var ui_layer: CanvasLayer = $UI
@onready var hp_bar: ProgressBar = $UI/HPBar
@onready var hp_label: Label = $UI/HPBar/HPLabel
@onready var wave_label: Label = $UI/WaveLabel
@onready var timer_label: Label = $UI/TimerLabel
@onready var build_label: Label = $UI/BuildLabel
@onready var restart_label: Label = $UI/RestartLabel
@onready var distance_label: Label = $UI/DistanceLabel
@onready var crush_label: Label = $UI/CrushLabel

var build_system: Node  # BuildSystem autoload
var upgrade_ui: Node  # UpgradeUI

# ゲーム状態
var run_time := 0.0
var max_run_time := 600.0  # 10分
var game_over := false
var enemies_alive := 0
var game_started := false
var boss_spawned := false
var kill_count := 0
var next_milestone := 50.0  # 50mごとにマイルストーン
const BOSS_DISTANCE := 200.0  # メートル

# 判断イベント管理
var upgrade_events_given := 0
var next_upgrade_time := 0.0
# 縦スクロール: 距離ベースのアップグレード（メートル単位）
var upgrade_schedule: Array[float] = [10.0, 25.0, 45.0, 70.0, 100.0, 140.0, 190.0, 250.0, 320.0, 400.0]

# 敵スポーン
var enemy_scene: PackedScene
var spawn_timer := 0.0
var spawn_interval := 1.5  # 縦スクロール: 少しゆったり（手動操作のため）

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
	tower.crush_changed.connect(_on_crush_changed)

	# UI初期化（Design Lock準拠スタイル適用）
	_style_hud()
	hp_bar.max_value = tower.max_hp
	hp_bar.value = tower.max_hp
	_update_hp_label(tower.max_hp, tower.max_hp)
	restart_label.visible = false

	# XP表示接続
	tower.xp_gained.connect(_on_xp_gained)
	tower.level_up.connect(_on_level_up)

	# Mirror War: 即スタート。初期スキルはFireball
	var module: Variant = build_system.TowerModule.new("fireball")
	tower.set_module(0, module)
	_setup_tower_attacks()
	_update_build_display()
	var initial_xp_target: int = tower.get_xp_for_next_level()
	wave_label.text = "Lv.1  XP: 0/%d" % initial_xp_target
	game_started = true

	# 最初の判断イベントタイミング（距離ベース）
	if not upgrade_schedule.is_empty():
		next_upgrade_time = upgrade_schedule[0]

func _process(delta: float) -> void:
	if game_over or not game_started:
		return

	run_time += delta
	_update_timer_display()
	_update_distance_display()

	# Crush表示更新（敵数が変わるので毎フレーム更新）
	if tower.crush_active:
		crush_label.text = "SURROUNDED x%d" % tower.crush_count

	# 10分経過 → 勝利
	if run_time >= max_run_time:
		_win_game()
		return

	# 敵スポーン（縦スクロール: 上方スポーン中心）
	spawn_timer += delta
	var current_interval := maxf(spawn_interval - run_time * 0.002, 0.4)
	if spawn_timer >= current_interval:
		spawn_timer = 0.0
		_spawn_enemy()

	# 判断イベント（距離ベース: メートル単位）
	var distance_m: float = float(tower.distance_traveled) / 10.0  # 10px = 1m
	if distance_m >= next_upgrade_time and upgrade_events_given < upgrade_schedule.size():
		upgrade_events_given += 1
		if upgrade_events_given < upgrade_schedule.size():
			next_upgrade_time = upgrade_schedule[upgrade_events_given]
		else:
			next_upgrade_time = INF
		_show_upgrade_choice()

	# ボスの出現判定
	if not boss_spawned and distance_m >= BOSS_DISTANCE:
		_spawn_boss()

	# 距離マイルストーン（50mごと）
	if distance_m >= next_milestone:
		_show_milestone(int(next_milestone))
		next_milestone += 50.0

func _update_timer_display() -> void:
	var remaining := maxf(max_run_time - run_time, 0.0)
	var total_sec: int = floori(remaining)
	@warning_ignore("integer_division")
	var minutes: int = total_sec / 60
	var seconds: int = total_sec % 60
	timer_label.text = "%d:%02d" % [minutes, seconds]

func _style_hud() -> void:
	## Design Lock v1: semantic colors, min 16px text, 4.5:1 contrast
	var bg_color := Color(0.05, 0.02, 0.1, 1.0)  # match clear color
	var player_cyan := Color(0.35, 0.75, 1.0, 1.0)
	var text_color := Color(0.9, 0.88, 0.95, 1.0)  # high contrast vs dark BG
	var dim_text := Color(0.6, 0.55, 0.7, 1.0)

	# HP Bar: cyan fill on dark background
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.06, 0.04, 0.12, 0.9)
	bar_bg.border_color = Color(0.2, 0.18, 0.3, 0.8)
	bar_bg.set_border_width_all(1)
	bar_bg.set_corner_radius_all(3)
	hp_bar.add_theme_stylebox_override("background", bar_bg)

	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = player_cyan.darkened(0.2)
	bar_fill.set_corner_radius_all(2)
	hp_bar.add_theme_stylebox_override("fill", bar_fill)

	# HP label on top of bar
	hp_label.add_theme_font_size_override("font_size", 14)
	hp_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.95))
	hp_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	hp_label.add_theme_constant_override("shadow_offset_x", 1)
	hp_label.add_theme_constant_override("shadow_offset_y", 1)

	# Wave/title label
	wave_label.add_theme_font_size_override("font_size", 18)
	wave_label.add_theme_color_override("font_color", player_cyan.lightened(0.15))
	wave_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	wave_label.add_theme_constant_override("shadow_offset_x", 1)
	wave_label.add_theme_constant_override("shadow_offset_y", 1)

	# Timer label: prominent, right-aligned
	timer_label.add_theme_font_size_override("font_size", 22)
	timer_label.add_theme_color_override("font_color", text_color)
	timer_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	timer_label.add_theme_constant_override("shadow_offset_x", 1)
	timer_label.add_theme_constant_override("shadow_offset_y", 1)

	# Distance label (below title)
	distance_label.add_theme_font_size_override("font_size", 16)
	distance_label.add_theme_color_override("font_color", dim_text)
	distance_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	distance_label.add_theme_constant_override("shadow_offset_x", 1)
	distance_label.add_theme_constant_override("shadow_offset_y", 1)

	# Build info label
	build_label.add_theme_font_size_override("font_size", 13)
	build_label.add_theme_color_override("font_color", dim_text)
	build_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	build_label.add_theme_constant_override("shadow_offset_x", 1)
	build_label.add_theme_constant_override("shadow_offset_y", 1)

	# Crush warning label
	crush_label.add_theme_font_size_override("font_size", 22)
	crush_label.add_theme_color_override("font_color", Color(1.0, 0.25, 0.2, 1.0))
	crush_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	crush_label.add_theme_constant_override("shadow_offset_x", 2)
	crush_label.add_theme_constant_override("shadow_offset_y", 2)
	crush_label.visible = false

	# Restart label: large and clear
	restart_label.add_theme_font_size_override("font_size", 28)
	restart_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5, 1.0))
	restart_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	restart_label.add_theme_constant_override("shadow_offset_x", 2)
	restart_label.add_theme_constant_override("shadow_offset_y", 2)

func _update_hp_label(current: float, max_val: float) -> void:
	hp_label.text = "%d / %d" % [int(current), int(max_val)]

func _update_distance_display() -> void:
	var distance_m: float = float(tower.distance_traveled) / 10.0
	distance_label.text = "%dm" % int(distance_m)

func _update_build_display() -> void:
	var lines: PackedStringArray = []

	# Behavior Chips表示（"manual"はデータにないので直接表示）
	var move_chip: Dictionary = build_system.get_equipped_chip("move")
	var attack_chip: Dictionary = build_system.get_equipped_chip("attack")
	var skill_chip: Dictionary = build_system.get_equipped_chip("skill")
	var move_name: String = move_chip.get("name", "Manual") if not move_chip.is_empty() else "Manual"
	var attack_name: String = attack_chip.get("name", "Manual Aim") if not attack_chip.is_empty() else "Manual Aim"
	lines.append("Move: %s / Aim: %s / Cast: %s" % [
		move_name,
		attack_name,
		skill_chip.get("name", "Auto"),
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

func _on_upgrade_chosen(upgrade_data: Dictionary) -> void:
	var upgrade_type: String = upgrade_data.get("type", "")

	match upgrade_type:
		"levelup":
			var stat_id: String = upgrade_data.get("stat_id", "")
			_apply_levelup_stat(stat_id)

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

# --- アップグレード選択（ラン中）---

func _show_upgrade_choice() -> void:
	# 最初のアップグレード（10m）は強力サポートを保証
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

func _spawn_boss() -> void:
	if enemy_scene == null:
		return
	boss_spawned = true

	var boss := enemy_scene.instantiate() as CharacterBody2D
	# ボスは上方から出現
	var cam_pos := tower.global_position
	boss.position = Vector2(cam_pos.x, cam_pos.y - 500)

	var distance_m: float = float(tower.distance_traveled) / 10.0
	var progress_scale := 1.0 + distance_m / 50.0 + run_time / 120.0
	var hp_val := 25.0 * progress_scale
	var speed_val := 65.0 + distance_m * 0.1 + run_time * 0.08
	var dmg_val := 6.0 + distance_m * 0.02

	boss.init(tower, speed_val, hp_val, dmg_val, "boss")
	boss.died.connect(_on_boss_died)
	enemies_alive += 1
	add_child(boss)

	# "BOSS INCOMING!" 警告テキスト
	var label := Label.new()
	label.text = "BOSS INCOMING!"
	label.add_theme_font_size_override("font_size", 36)
	label.add_theme_color_override("font_color", Color(0.7, 0.3, 1.0, 1.0))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	label.position = Vector2(640 - 200, 120)
	label.custom_minimum_size = Vector2(400, 0)
	label.z_index = 200
	ui_layer.add_child(label)

	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "scale", Vector2(1.3, 1.3), 0.3).set_trans(Tween.TRANS_BOUNCE)
	tween.chain().tween_property(label, "scale", Vector2(1.0, 1.0), 0.2)
	tween.chain().tween_property(label, "modulate:a", 0.0, 1.5).set_delay(1.0)
	tween.chain().tween_callback(label.queue_free)

func _on_boss_died(_enemy: Node2D) -> void:
	enemies_alive -= 1
	kill_count += 1
	tower.enemy_killed.emit()

	# ボス撃破のお祝い表示
	var label := Label.new()
	label.text = "BOSS DEFEATED!"
	label.add_theme_font_size_override("font_size", 36)
	label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4, 1.0))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(640 - 200, 120)
	label.custom_minimum_size = Vector2(400, 0)
	label.z_index = 200
	ui_layer.add_child(label)

	var tween := label.create_tween()
	tween.tween_property(label, "modulate:a", 0.0, 2.0).set_delay(1.5)
	tween.chain().tween_callback(label.queue_free)

func _spawn_enemy() -> void:
	if enemy_scene == null:
		return

	var enemy := enemy_scene.instantiate() as CharacterBody2D

	# 縦スクロール: 70%上から、15%左右、15%下からスポーン
	var cam_pos := tower.global_position
	var spawn_pos := Vector2.ZERO
	var roll := randf()

	if roll < 0.7:
		# 上方（進行方向）からスポーン
		spawn_pos = Vector2(
			cam_pos.x + randf_range(-640, 640),
			cam_pos.y - randf_range(400, 550)
		)
	elif roll < 0.85:
		# 左右からスポーン
		var side_x := -660.0 if randf() < 0.5 else 660.0
		spawn_pos = Vector2(
			cam_pos.x + side_x,
			cam_pos.y + randf_range(-300, 300)
		)
	else:
		# 下方（後方）からスポーン
		spawn_pos = Vector2(
			cam_pos.x + randf_range(-640, 640),
			cam_pos.y + randf_range(400, 550)
		)

	# X座標をワールド範囲にクランプ
	spawn_pos.x = clampf(spawn_pos.x, -40, 1320)

	enemy.position = spawn_pos

	# 距離＋時間でスケーリング
	var distance_m: float = float(tower.distance_traveled) / 10.0
	var progress_scale := 1.0 + distance_m / 50.0 + run_time / 120.0
	var hp_val := 25.0 * progress_scale
	var speed_val := 65.0 + distance_m * 0.1 + run_time * 0.08
	var dmg_val := 6.0 + distance_m * 0.02

	# 敵タイプ選択: 60% normal, 25% swarmer, 15% tank（tankは50m以降）
	var type_roll := randf()
	var etype := "normal"
	if type_roll < 0.25:
		etype = "swarmer"
	elif type_roll < 0.40 and distance_m >= 50.0:
		etype = "tank"

	enemy.init(tower, speed_val, hp_val, dmg_val, etype)
	enemy.died.connect(_on_enemy_died)
	enemies_alive += 1
	add_child(enemy)

func _on_enemy_died(_enemy: Node2D) -> void:
	enemies_alive -= 1
	kill_count += 1
	tower.enemy_killed.emit()

# --- タワーイベント ---

func _on_tower_damaged(current: float, max_val: float) -> void:
	hp_bar.value = current
	_update_hp_label(current, max_val)

	# HP低下でバーの色を変化（cyan → yellow → red）
	var pct := current / max_val
	var fill_style := hp_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill_style:
		if pct > 0.5:
			fill_style.bg_color = Color(0.28, 0.6, 0.8, 1.0)  # cyan
		elif pct > 0.25:
			fill_style.bg_color = Color(0.85, 0.75, 0.2, 1.0)  # yellow warning
		else:
			fill_style.bg_color = Color(0.9, 0.2, 0.15, 1.0)  # red danger

func _on_xp_gained(total_xp: int, current_level: int) -> void:
	var next_xp: int = tower.get_xp_for_next_level()
	wave_label.text = "Lv.%d  XP: %d/%d" % [current_level, total_xp, next_xp]

func _on_crush_changed(active: bool, count: int) -> void:
	if active:
		crush_label.text = "SURROUNDED x%d" % count
		crush_label.visible = true
	else:
		crush_label.visible = false

# --- レベルアップ選択肢プール ---
var levelup_pool: Array[Dictionary] = [
	{"id": "damage", "name": "+25% Damage", "description": "All attacks deal 25% more damage"},
	{"id": "fire_rate", "name": "+20% Fire Rate", "description": "Attack cooldown reduced by 20%"},
	{"id": "projectile", "name": "+1 Projectile", "description": "Fire an extra projectile per attack"},
	{"id": "move_speed", "name": "+15% Move Speed", "description": "Move 15% faster"},
	{"id": "max_hp", "name": "+50 Max HP", "description": "Increase max HP by 50 and heal 50"},
	{"id": "attract", "name": "+100 Attract Range", "description": "Pick up XP orbs from further away"},
]

func _on_level_up(new_level: int) -> void:
	# 3つランダムに選んで表示
	var pool := levelup_pool.duplicate()
	pool.shuffle()
	var choices: Array[Dictionary] = []
	for i in range(mini(3, pool.size())):
		choices.append(pool[i])
	upgrade_ui.show_levelup_choice(new_level, choices)

	# レベルアップフラッシュVFX
	_spawn_levelup_vfx()

func _apply_levelup_stat(stat_id: String) -> void:
	match stat_id:
		"damage":
			tower.damage_mult *= 1.25
		"fire_rate":
			tower.cooldown_mult *= 0.8
		"projectile":
			tower.projectile_bonus += 1
		"move_speed":
			tower.move_speed_mult *= 1.15
		"max_hp":
			tower.max_hp += 50.0
			tower.heal(50.0)
			hp_bar.max_value = tower.max_hp
		"attract":
			tower.attract_range_bonus += 100.0

func _spawn_levelup_vfx() -> void:
	# 金色の拡散リングで「レベルアップ感」
	var ring := Polygon2D.new()
	var pts: PackedVector2Array = []
	for i in range(16):
		var a := i * TAU / 16
		pts.append(Vector2(cos(a), sin(a)) * 20.0)
	ring.polygon = pts
	ring.color = Color(1.0, 0.9, 0.4, 0.6)
	ring.global_position = tower.global_position
	ring.z_index = 150
	add_child(ring)

	var tween := ring.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector2(4.0, 4.0), 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring, "modulate:a", 0.0, 0.4)
	tween.chain().tween_callback(ring.queue_free)

func _show_milestone(meters: int) -> void:
	## 距離マイルストーン: 達成感を出す中央テキスト + 画面フラッシュ
	var label := Label.new()
	label.text = "%dm REACHED!" % meters
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0, 1.0))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(640 - 150, 200)
	label.custom_minimum_size = Vector2(300, 0)
	label.z_index = 200
	label.modulate.a = 0.0
	ui_layer.add_child(label)

	var tween := label.create_tween()
	tween.tween_property(label, "modulate:a", 1.0, 0.15)
	tween.tween_property(label, "scale", Vector2(1.15, 1.15), 0.1).set_trans(Tween.TRANS_BACK)
	tween.tween_property(label, "scale", Vector2(1.0, 1.0), 0.1)
	tween.tween_interval(1.0)
	tween.tween_property(label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(label.queue_free)

	# 画面フラッシュ（白く一瞬光る）
	var flash := ColorRect.new()
	flash.color = Color(0.4, 0.8, 1.0, 0.15)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(flash)

	var flash_tween := flash.create_tween()
	flash_tween.tween_property(flash, "color:a", 0.0, 0.4)
	flash_tween.tween_callback(flash.queue_free)

func _on_tower_destroyed() -> void:
	game_over = true
	_show_result_screen(false)

func _win_game() -> void:
	game_over = true
	_show_result_screen(true)

func _show_result_screen(is_victory: bool) -> void:
	## リザルト画面: 暗転 → タイトル → スタッツ → リトライ
	var result_layer := CanvasLayer.new()
	result_layer.layer = 100
	add_child(result_layer)

	# 暗転オーバーレイ
	var overlay := ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.0)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result_layer.add_child(overlay)

	# フェードイン
	var fade_tween := overlay.create_tween()
	fade_tween.tween_property(overlay, "color:a", 0.75, 0.8).set_trans(Tween.TRANS_QUAD)

	# コンテンツ（VBox中央配置）
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result_layer.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(vbox)

	# タイトル
	var title := Label.new()
	if is_victory:
		title.text = "VICTORY"
		title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3, 1.0))
	else:
		title.text = "GAME OVER"
		title.add_theme_color_override("font_color", Color(1.0, 0.2, 0.15, 1.0))
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 3)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.modulate.a = 0.0
	vbox.add_child(title)

	# 区切り線
	var sep := HSeparator.new()
	sep.custom_minimum_size = Vector2(300, 2)
	sep.modulate.a = 0.0
	vbox.add_child(sep)

	# スタッツ
	var distance_m: float = float(tower.distance_traveled) / 10.0
	var time_sec := int(run_time)
	@warning_ignore("integer_division")
	var t_min := time_sec / 60
	var t_sec := time_sec % 60

	var stats_data: Array[Array] = [
		["Distance", "%dm" % int(distance_m)],
		["Level", "%d" % tower.level],
		["Kills", "%d" % kill_count],
		["Time", "%d:%02d" % [t_min, t_sec]],
	]

	var stat_labels: Array[Label] = []
	var stat_color := Color(0.85, 0.82, 0.92, 1.0)

	for stat in stats_data:
		var lbl := Label.new()
		lbl.text = "%s:  %s" % [stat[0], stat[1]]
		lbl.add_theme_font_size_override("font_size", 24)
		lbl.add_theme_color_override("font_color", stat_color)
		lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
		lbl.add_theme_constant_override("shadow_offset_x", 1)
		lbl.add_theme_constant_override("shadow_offset_y", 1)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.modulate.a = 0.0
		vbox.add_child(lbl)
		stat_labels.append(lbl)

	# スペーサー
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer)

	# リトライ
	var retry := Label.new()
	retry.text = "Press R to Retry"
	retry.add_theme_font_size_override("font_size", 22)
	retry.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5, 1.0))
	retry.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	retry.add_theme_constant_override("shadow_offset_x", 2)
	retry.add_theme_constant_override("shadow_offset_y", 2)
	retry.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	retry.modulate.a = 0.0
	vbox.add_child(retry)

	# 順番にフェードインするアニメーション
	var anim := create_tween()
	anim.tween_property(title, "modulate:a", 1.0, 0.3).set_delay(0.5)
	anim.tween_property(sep, "modulate:a", 0.4, 0.2)
	for lbl in stat_labels:
		anim.tween_property(lbl, "modulate:a", 1.0, 0.15)
	anim.tween_property(retry, "modulate:a", 1.0, 0.3).set_delay(0.3)

	# リトライラベルの点滅
	anim.tween_callback(func():
		var blink := retry.create_tween()
		blink.set_loops()
		blink.tween_property(retry, "modulate:a", 0.4, 0.6).set_trans(Tween.TRANS_SINE)
		blink.tween_property(retry, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_SINE)
	)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_R and game_over:
			get_tree().paused = false
			get_tree().reload_current_scene()
		elif event.keycode == KEY_ESCAPE and not game_over:
			get_tree().paused = not get_tree().paused
			if get_tree().paused:
				wave_label.text = "PAUSED"
