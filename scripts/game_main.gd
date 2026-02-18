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
var xp_bar: ProgressBar = null  # XP進捗バー

# ゲーム状態
var run_time := 0.0
var max_run_time := 600.0  # 10分
var game_over := false
var enemies_alive := 0
var game_started := false
var boss_spawned := false
var kill_count := 0
var next_milestone := 50.0  # 50mごとにマイルストーン

# Kill combo（連続キル）
var combo_count := 0
var combo_timer := 0.0
const COMBO_WINDOW := 2.0  # 秒以内に次のキルで継続
var combo_label_node: Label = null  # HUD上のコンボ表示
var best_combo := 0  # リザルト画面用

# Crush ring visual（タワー周囲の危険ゾーン表示）
var crush_ring: Line2D = null
var crush_warning_label: Label = null  # pre-crush "DANGER" 表示

# Boss HP bar
var boss_hp_bar: ProgressBar = null

# Hitstop リエントラント管理（複数同時呼び出しで早期復帰を防止）
var _hitstop_depth := 0
var boss_hp_label: Label = null
var boss_phase_label: Label = null

# 画面外敵インジケーター
var indicator_pool: Array[Polygon2D] = []
const MAX_INDICATORS := 8
const SCREEN_MARGIN := 40.0  # 画面端からの余白
const BOSS_DISTANCE := 100.0  # メートル（200mでは到達不可能だったため短縮）
const BOSS_TIME_TRIGGER := 360.0  # 6分で距離未達でもボス出現（時間救済）
const BOSS_WARNING_TIME := 350.0  # ボス10秒前予告
var boss_warning_shown := false

# Shrine（中盤イベント: 120-225sのquiet zone対策）
const SHRINE_TIME := 150.0  # 2:30で出現
const SHRINE_AUTO_SELECT_TIME := 10.0  # 10秒で自動選択
var shrine_shown := false
var shrine_ui: Control = null
var shrine_timer := 0.0

# Onboarding overlay（初回ガイド: 5秒 or 初回アップグレードで消える）
var onboarding_panel: PanelContainer = null
var onboarding_timer := 0.0
const ONBOARDING_DURATION := 5.0

# 判断イベント管理（v0.2.6: 距離ベース完全削除、XP levelupのみ）
# なぜ: 距離だけで敵倒してないのにupgrade乱発→違和感（ぐらす最終判断）
var upgrade_events_given := 0

# 敵スポーン
var enemy_scene: PackedScene
var spawn_timer := 0.0
var spawn_interval := 1.0  # v0.3.3: Dead Time<10s目標（旧1.2）

# ステージランプ（v0.3.2: 3-Act構造）
var current_stage := 1  # 1=vulnerability, 2=growth, 3=crisis
const STAGE_2_TIME := 20.0  # Stage 2 開始時間
const STAGE_3_TIME := 40.0  # Stage 3 開始時間
const STAGE_SPAWN_MULT = [1.0, 1.2, 1.6]  # v0.3: Stage1を0.8→1.0（序盤の空白削減）
const STAGE_HP_MULT = [1.0, 1.3, 1.8]  # ステージ別敵HP倍率
const DESPERATE_PUSH_TIME = 45.0  # 最後15秒のスポーン加速開始

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
	tower.crush_warning.connect(_on_crush_warning)
	tower.crush_breakout.connect(_on_crush_breakout)

	# Crush ring visual（ワールド空間でタワーに追従）
	_setup_crush_ring()

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
	SFX.play_bgm()

	# Onboarding overlay（操作説明 + 目的）
	_show_onboarding()

	# v0.3.3: 初期波（近距離スポーンで序盤Dead Time削減）
	_spawn_initial_wave()

	# v0.2.6: 距離ベースupgrade完全削除。XP levelupのみ

func _process(delta: float) -> void:
	if game_over or not game_started:
		return

	run_time += delta
	_update_timer_display()
	_update_distance_display()

	# Crush表示更新（敵数が変わるので毎フレーム更新）
	if tower.crush_active:
		var sec_left := maxf(tower.CRUSH_BREAKOUT_TIME - tower.crush_duration, 0.0)
		if tower.crush_breakout_ready:
			crush_label.text = "SURROUNDED x%d - BURST!" % tower.crush_count
		else:
			crush_label.text = "SURROUNDED x%d  %.1fs" % [tower.crush_count, sec_left]
	# Crush ring visual更新
	_update_crush_ring()

	# 10分経過 → 勝利
	if run_time >= max_run_time:
		_win_game()
		return

	# ステージ遷移（v0.3.2: 3-Act構造）
	var prev_stage := current_stage
	if run_time >= STAGE_3_TIME and current_stage < 3:
		current_stage = 3
		spawn_timer = -2.0  # 2秒の呼吸タイム（ステージ間ブリージングルーム）
	elif run_time >= STAGE_2_TIME and current_stage < 2:
		current_stage = 2
		spawn_timer = -2.0

	# 敵スポーン（縦スクロール: 上方スポーン中心）
	spawn_timer += delta
	var stage_spawn: float = STAGE_SPAWN_MULT[current_stage - 1]
	# 最後15秒: desperate push（スポーン加速 ×1.6）
	if run_time >= DESPERATE_PUSH_TIME:
		stage_spawn *= 1.6
	var current_interval := maxf(spawn_interval - run_time * 0.002, 0.4) / stage_spawn
	# ボス出現後は雑魚スポーンを25%に抑制（ボス戦に集中）
	if boss_spawned:
		current_interval *= 4.0
	if spawn_timer >= current_interval:
		spawn_timer = 0.0
		_spawn_enemy()

	# スポーンフロア: t=3s以降、最低6体を維持（v0.3.3: 序盤イベント密度UP）
	if run_time >= 3.0 and enemies_alive < 6 and not boss_spawned and spawn_timer >= current_interval * 0.5:
		spawn_timer = 0.0
		_spawn_enemy()

	# v0.2.6: 距離ベースupgrade完全削除（XP levelupのみ）
	var distance_m: float = float(tower.distance_traveled) / 10.0  # 10px = 1m

	# Shrine（150sで中盤イベント: quiet zone対策）
	if not shrine_shown and run_time >= SHRINE_TIME:
		shrine_shown = true
		_show_shrine()
	# Shrine自動選択タイマー
	if shrine_ui and shrine_timer > 0:
		shrine_timer -= delta
		if shrine_timer <= 0:
			_shrine_auto_select()

	# ボス予告（350sで "BOSS IN 10s"）
	if not boss_spawned and not boss_warning_shown and run_time >= BOSS_WARNING_TIME:
		boss_warning_shown = true
		_show_boss_warning()

	# ボスの出現判定（距離100m OR 時間6:00）
	if not boss_spawned and (distance_m >= BOSS_DISTANCE or run_time >= BOSS_TIME_TRIGGER):
		_spawn_boss()

	# 画面外敵インジケーター更新
	_update_offscreen_indicators()

	# 距離マイルストーン（50mごと）
	if distance_m >= next_milestone:
		_show_milestone(int(next_milestone))
		next_milestone += 50.0

	# Onboarding overlay タイマー
	if onboarding_panel and onboarding_timer > 0:
		onboarding_timer -= delta
		if onboarding_timer <= 0:
			_dismiss_onboarding()

	# Kill combo タイマー減衰
	if combo_count > 0:
		combo_timer -= delta
		if combo_timer <= 0:
			combo_count = 0
			_update_combo_display()

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

	# XP progress bar (WaveLabelの下、薄いバー)
	xp_bar = ProgressBar.new()
	xp_bar.name = "XPBar"
	xp_bar.position = Vector2(530, 44)
	xp_bar.custom_minimum_size = Vector2(220, 6)
	xp_bar.size = Vector2(220, 6)
	xp_bar.max_value = tower.get_xp_for_next_level()
	xp_bar.value = 0
	xp_bar.show_percentage = false

	var xp_bar_bg := StyleBoxFlat.new()
	xp_bar_bg.bg_color = Color(0.08, 0.06, 0.15, 0.6)
	xp_bar_bg.set_corner_radius_all(2)
	xp_bar.add_theme_stylebox_override("background", xp_bar_bg)

	var xp_bar_fill := StyleBoxFlat.new()
	xp_bar_fill.bg_color = Color(0.35, 0.85, 0.45, 0.8)  # 緑: XPカラー
	xp_bar_fill.set_corner_radius_all(2)
	xp_bar.add_theme_stylebox_override("fill", xp_bar_fill)
	ui_layer.add_child(xp_bar)

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

	# Kill combo label (画面右上、タイマーの下)
	combo_label_node = Label.new()
	combo_label_node.name = "ComboLabel"
	combo_label_node.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	combo_label_node.position = Vector2(1080, 40)
	combo_label_node.custom_minimum_size = Vector2(180, 0)
	combo_label_node.add_theme_font_size_override("font_size", 20)
	combo_label_node.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2, 1.0))
	combo_label_node.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	combo_label_node.add_theme_constant_override("shadow_offset_x", 2)
	combo_label_node.add_theme_constant_override("shadow_offset_y", 2)
	combo_label_node.z_index = 100
	combo_label_node.visible = false
	ui_layer.add_child(combo_label_node)

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
	var skill_chip_name: String = skill_chip.get("name", "Auto Cast") if not skill_chip.is_empty() else "Auto Cast"
	lines.append("Move: %s | Aim: %s | Trigger: %s" % [
		move_name,
		attack_name,
		skill_chip_name,
	])

	# v0.2.6: Projectile count + trigger条件を明示的に表示
	# 弾数表示（常時、0でも表示して「増える」ことを意識させる）
	var total_proj: int = 1 + tower.projectile_bonus
	lines.append("Bullets: x%d" % total_proj)

	# Skill trigger条件の表示（skill_chipは上で取得済み）
	var skill_trigger_id: String = skill_chip.get("id", "auto_cast")
	var trigger_desc := ""
	match skill_trigger_id:
		"auto_cast":
			trigger_desc = "AUTO: fires on cooldown"
		"on_kill":
			trigger_desc = "ON KILL: burst after kill"
		"panic":
			var threshold: float = skill_chip.get("params", {}).get("hp_threshold", 0.3)
			trigger_desc = "PANIC: 2x speed below %d%% HP" % int(threshold * 100)
		_:
			trigger_desc = "AUTO: fires on cooldown"
	lines.append("Trigger: %s" % trigger_desc)
	lines.append("")

	# スキルスロット（CD + 弾数 + 効果の1行サマリー）
	for i in range(tower.max_slots):
		var module: Variant = tower.get_module(i)
		if module == null:
			lines.append("[%d] empty" % (i + 1))
		else:
			var stats: Dictionary = build_system.calculate_module_stats(module)
			var skill_name: String = stats.get("name", "?")
			var cd: float = stats.get("cooldown", 1.0)
			if "cooldown_mult" in tower:
				cd *= tower.cooldown_mult
			var proj_count: int = stats.get("projectile_count", 1) + tower.projectile_bonus
			# トリガー＋CD＋弾数の1行サマリー
			var trigger_info := "%.1fs" % cd
			if proj_count > 1:
				trigger_info += " x%d" % proj_count
			# 特殊効果タグ
			var effects: PackedStringArray = []
			var on_hit: Dictionary = stats.get("on_hit", {})
			if on_hit.has("slow"):
				effects.append("Slow")
			if on_hit.has("dot_damage"):
				effects.append("DoT")
			if stats.get("pierce", false):
				effects.append("Pierce")
			if stats.get("area_radius", 0) > 0:
				effects.append("AoE")
			var effect_str := ""
			if not effects.is_empty():
				effect_str = " [%s]" % ", ".join(effects)
			# サポート＋Mod
			var extras: PackedStringArray = []
			for sup_id in module.support_ids:
				var sup_data: Dictionary = build_system.supports.get(sup_id, {})
				extras.append(sup_data.get("name", sup_id))
			if not module.prefix.is_empty():
				extras.append(module.prefix.get("name", ""))
			if not module.suffix.is_empty():
				extras.append(module.suffix.get("name", ""))
			var extras_str := ""
			if not extras.is_empty():
				extras_str = " + " + ", ".join(extras)
			lines.append("[%d] %s (%s)%s%s" % [(i + 1), skill_name, trigger_info, effect_str, extras_str])

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
	# 初回アップグレード選択でオンボーディングを消す
	if onboarding_panel:
		_dismiss_onboarding()

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

# --- Onboarding overlay ---

func _show_onboarding() -> void:
	## ゲーム開始直後に表示: 目的・操作・ヒント。10秒 or 初回アップグレードで消える
	onboarding_panel = PanelContainer.new()
	onboarding_panel.name = "OnboardingOverlay"

	# 半透明ダーク背景
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.01, 0.06, 0.85)
	style.border_color = Color(0.35, 0.75, 1.0, 0.4)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(24)
	onboarding_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	onboarding_panel.add_child(vbox)

	# 目的
	var goal_lbl := Label.new()
	goal_lbl.text = "SURVIVE UNTIL THE BOSS"
	goal_lbl.add_theme_font_size_override("font_size", 28)
	goal_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 1.0))
	goal_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(goal_lbl)

	# 操作
	var controls_lbl := Label.new()
	controls_lbl.text = "WASD — Move     Mouse — Aim\nKill enemies for XP     Choose upgrades to grow"
	controls_lbl.add_theme_font_size_override("font_size", 18)
	controls_lbl.add_theme_color_override("font_color", Color(0.9, 0.88, 0.95, 1.0))
	controls_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(controls_lbl)

	# ヒント: CRUSH → BREAKOUT
	var hint_lbl := Label.new()
	hint_lbl.text = "When surrounded: CRUSH triggers — survive it for BREAKOUT!"
	hint_lbl.add_theme_font_size_override("font_size", 14)
	hint_lbl.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0, 0.8))
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint_lbl)

	# UI Layer上にセンタリング配置
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_CENTER_TOP)
	center.anchor_left = 0.0
	center.anchor_right = 1.0
	center.anchor_top = 0.15
	center.anchor_bottom = 0.15
	center.offset_left = 0
	center.offset_right = 0
	center.offset_top = 0
	center.offset_bottom = 200
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	onboarding_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(onboarding_panel)
	ui_layer.add_child(center)

	# フェードイン
	onboarding_panel.modulate.a = 0.0
	var tween := onboarding_panel.create_tween()
	tween.tween_property(onboarding_panel, "modulate:a", 1.0, 0.5)

	onboarding_timer = ONBOARDING_DURATION

func _dismiss_onboarding() -> void:
	if onboarding_panel == null:
		return
	var panel := onboarding_panel
	onboarding_panel = null
	onboarding_timer = 0.0
	var tween := panel.create_tween()
	tween.tween_property(panel, "modulate:a", 0.0, 0.5)
	# CenterContainerごと消す
	tween.tween_callback(panel.get_parent().queue_free)

# --- アップグレード選択（ラン中）---

func _show_upgrade_choice() -> void:
	# 1回目: 2ndスキル（空スロットに新スキル追加）
	# なぜ最初にスキル: セカンドスキルが遅すぎる→即新スキルで戦術の幅を広げる
	if upgrade_events_given == 1:
		var empty_slot := -1
		for i in range(tower.max_slots):
			if tower.get_module(i) == null:
				empty_slot = i
				break
		if empty_slot >= 0:
			var equipped: Array[String] = []
			for i in range(tower.max_slots):
				var m: Variant = tower.get_module(i)
				if m != null:
					equipped.append(m.skill_id)
			var skill_ids: Array = build_system.get_random_skill_ids(3, equipped)
			upgrade_ui.show_skill_choice(empty_slot, skill_ids)
			return

	# 2回目: 強力サポート保証（chain/fork/pierce）
	if upgrade_events_given == 2:
		var guaranteed_supports: Array = ["chain", "fork", "pierce"]
		upgrade_ui.show_support_choice(guaranteed_supports)
		return

	# 3回目: まだ手動移動ならMove AIチップを提示
	if upgrade_events_given == 3:
		var move_chip: Dictionary = build_system.get_equipped_chip("move")
		var move_id: String = move_chip.get("id", "manual")
		if move_id == "manual" or move_id == "":
			var move_chips: Array[Dictionary] = build_system.get_chips_by_category("move")
			if not move_chips.is_empty():
				upgrade_ui.show_chip_choice("Move AI Unlock", move_chips)
				return

	# 4回目以降: 空スロットがあればスキル追加
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

func _show_boss_warning() -> void:
	var label := Label.new()
	label.text = "BOSS IN 10s"
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3, 1.0))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(640 - 150, 160)
	label.custom_minimum_size = Vector2(300, 0)
	label.z_index = 200
	ui_layer.add_child(label)
	# パルスアニメーション→フェードアウト
	var tween := label.create_tween()
	tween.tween_property(label, "modulate:a", 0.3, 0.4).set_trans(Tween.TRANS_SINE)
	tween.tween_property(label, "modulate:a", 1.0, 0.4).set_trans(Tween.TRANS_SINE)
	tween.tween_property(label, "modulate:a", 0.3, 0.4).set_trans(Tween.TRANS_SINE)
	tween.tween_property(label, "modulate:a", 1.0, 0.4).set_trans(Tween.TRANS_SINE)
	tween.tween_property(label, "modulate:a", 0.0, 0.5).set_delay(0.5)
	tween.tween_callback(label.queue_free)

## --- Shrine（中盤イベント） ---

func _show_shrine() -> void:
	## ゲームを止めずに3択UIを表示。10秒で自動選択
	shrine_timer = SHRINE_AUTO_SELECT_TIME
	SFX.play_ui_select()

	shrine_ui = Control.new()
	shrine_ui.name = "ShrineUI"
	shrine_ui.z_index = 190

	# 半透明背景（小さめ、画面下部）
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.05, 0.2, 0.85)
	bg.position = Vector2(240, 500)
	bg.size = Vector2(800, 160)
	shrine_ui.add_child(bg)

	# タイトル
	var title := Label.new()
	title.text = "SHRINE DISCOVERED"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(240, 505)
	title.custom_minimum_size = Vector2(800, 0)
	shrine_ui.add_child(title)

	# 3択ボタン
	var choices := [
		{"name": "OVERCHARGE", "desc": "Projectile +2\nCooldown +30% slower", "color": Color(1.0, 0.4, 0.2)},
		{"name": "GREED", "desc": "Pickup range +200\nDamage -15%", "color": Color(0.3, 1.0, 0.3)},
		{"name": "DISCIPLINE", "desc": "Damage +25%\nMove speed -20%", "color": Color(0.4, 0.6, 1.0)},
	]

	for i in choices.size():
		var btn := Button.new()
		btn.text = choices[i]["name"] + "\n" + choices[i]["desc"]
		btn.position = Vector2(260 + i * 260, 530)
		btn.custom_minimum_size = Vector2(240, 110)
		btn.add_theme_font_size_override("font_size", 13)
		# ボタンスタイル
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.15, 0.1, 0.25, 0.9)
		style.border_color = choices[i]["color"]
		style.set_border_width_all(2)
		style.set_corner_radius_all(6)
		btn.add_theme_stylebox_override("normal", style)
		var hover := style.duplicate() as StyleBoxFlat
		hover.bg_color = Color(0.25, 0.15, 0.35, 0.95)
		btn.add_theme_stylebox_override("hover", hover)
		btn.add_theme_color_override("font_color", choices[i]["color"])
		btn.pressed.connect(_on_shrine_chosen.bind(i))
		shrine_ui.add_child(btn)

	ui_layer.add_child(shrine_ui)

	# フェードイン
	shrine_ui.modulate.a = 0.0
	var tween := shrine_ui.create_tween()
	tween.tween_property(shrine_ui, "modulate:a", 1.0, 0.3)

func _on_shrine_chosen(choice: int) -> void:
	if shrine_ui == null:
		return
	SFX.play_ui_select()

	match choice:
		0:  # OVERCHARGE: projectile+2, cooldown+30%悪化
			if tower:
				tower.projectile_bonus += 2
				tower.cooldown_mult *= 1.3
		1:  # GREED: pickup attract+200, damage-15%
			if tower:
				tower.attract_range_bonus += 200.0
				tower.damage_mult *= 0.85
		2:  # DISCIPLINE: damage+25%, move speed-20%
			if tower:
				tower.damage_mult *= 1.25
				tower.move_speed_mult *= 0.8

	# 選択結果のトースト
	var names := ["OVERCHARGE", "GREED", "DISCIPLINE"]
	var colors := [Color(1.0, 0.4, 0.2), Color(0.3, 1.0, 0.3), Color(0.4, 0.6, 1.0)]
	_show_shrine_toast(names[choice], colors[choice])
	_dismiss_shrine()

func _shrine_auto_select() -> void:
	## タイムアウト: ランダムに1つ選択
	var choice := randi() % 3
	_on_shrine_chosen(choice)

func _dismiss_shrine() -> void:
	if shrine_ui:
		var tween := shrine_ui.create_tween()
		tween.tween_property(shrine_ui, "modulate:a", 0.0, 0.3)
		tween.tween_callback(shrine_ui.queue_free)
		shrine_ui = null
		shrine_timer = 0.0

func _show_shrine_toast(choice_name: String, color: Color) -> void:
	var label := Label.new()
	label.text = "SHRINE: " + choice_name + " ACTIVATED"
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(640 - 200, 350)
	label.custom_minimum_size = Vector2(400, 0)
	label.z_index = 200
	ui_layer.add_child(label)
	var tween := label.create_tween()
	tween.tween_property(label, "modulate:a", 0.0, 1.5).set_delay(1.0)
	tween.tween_callback(label.queue_free)

func _spawn_boss() -> void:
	if enemy_scene == null:
		return
	boss_spawned = true
	SFX.play_boss_entrance()

	var boss := enemy_scene.instantiate() as CharacterBody2D
	# ボスは上方から出現
	var cam_pos := tower.global_position
	boss.position = Vector2(cam_pos.x, cam_pos.y - 500)

	var distance_m: float = float(tower.distance_traveled) / 10.0
	var progress_scale := 1.0 + distance_m / 50.0 + run_time / 120.0
	var hp_val := 35.0 * progress_scale  # v0.3.1: HP+40%
	var speed_val := 75.0 + distance_m * 0.12 + run_time * 0.12  # v0.3.1: 速度+15%
	var dmg_val := 14.0 + distance_m * 0.03  # v0.3: 10→14（緊張感UP）

	boss.init(tower, speed_val, hp_val, dmg_val, "boss")
	boss.add_to_group("enemies")
	boss.died.connect(_on_boss_died)
	boss.boss_hp_changed.connect(_on_boss_hp_changed)
	boss.boss_phase_changed.connect(_on_boss_phase_changed)
	enemies_alive += 1
	add_child(boss)

	# Boss HP bar（画面上部中央）
	_create_boss_hp_bar(boss)

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
	SFX.play_wave_clear()
	# ボス撃破: 大きなシェイク
	tower.shake(8.0)
	# コンボ: ボスは+3カウント
	combo_count += 3
	combo_timer = COMBO_WINDOW
	_update_combo_display()
	# ボスキル: 長めのヒットストップ + タワーグロー
	_do_hitstop(0.12)
	_flash_tower_kill_glow()

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

	# Boss HP bar除去
	_remove_boss_hp_bar()

func _create_boss_hp_bar(boss: Node2D) -> void:
	## ボス専用HPバー（画面上部中央）
	boss_hp_bar = ProgressBar.new()
	boss_hp_bar.name = "BossHPBar"
	boss_hp_bar.position = Vector2(340, 80)
	boss_hp_bar.custom_minimum_size = Vector2(600, 14)
	boss_hp_bar.size = Vector2(600, 14)
	boss_hp_bar.max_value = boss.max_hp
	boss_hp_bar.value = boss.hp
	boss_hp_bar.show_percentage = false

	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.06, 0.03, 0.12, 0.85)
	bar_bg.border_color = Color(0.5, 0.2, 0.7, 0.8)
	bar_bg.set_border_width_all(1)
	bar_bg.set_corner_radius_all(3)
	boss_hp_bar.add_theme_stylebox_override("background", bar_bg)

	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color(0.6, 0.2, 0.9, 1.0)
	bar_fill.set_corner_radius_all(2)
	boss_hp_bar.add_theme_stylebox_override("fill", bar_fill)
	boss_hp_bar.z_index = 180
	ui_layer.add_child(boss_hp_bar)

	# Boss name label
	boss_hp_label = Label.new()
	boss_hp_label.name = "BossHPLabel"
	boss_hp_label.text = "BOSS"
	boss_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_hp_label.position = Vector2(440, 60)
	boss_hp_label.custom_minimum_size = Vector2(400, 0)
	boss_hp_label.add_theme_font_size_override("font_size", 14)
	boss_hp_label.add_theme_color_override("font_color", Color(0.7, 0.4, 1.0, 0.9))
	boss_hp_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	boss_hp_label.add_theme_constant_override("shadow_offset_x", 1)
	boss_hp_label.add_theme_constant_override("shadow_offset_y", 1)
	boss_hp_label.z_index = 180
	ui_layer.add_child(boss_hp_label)

	# Phase indicator
	boss_phase_label = Label.new()
	boss_phase_label.name = "BossPhaseLabel"
	boss_phase_label.text = "Phase 1"
	boss_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	boss_phase_label.position = Vector2(740, 96)
	boss_phase_label.custom_minimum_size = Vector2(200, 0)
	boss_phase_label.add_theme_font_size_override("font_size", 12)
	boss_phase_label.add_theme_color_override("font_color", Color(0.5, 0.3, 0.8, 0.7))
	boss_phase_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	boss_phase_label.add_theme_constant_override("shadow_offset_x", 1)
	boss_phase_label.add_theme_constant_override("shadow_offset_y", 1)
	boss_phase_label.z_index = 180
	ui_layer.add_child(boss_phase_label)

func _remove_boss_hp_bar() -> void:
	if boss_hp_bar:
		boss_hp_bar.queue_free()
		boss_hp_bar = null
	if boss_hp_label:
		boss_hp_label.queue_free()
		boss_hp_label = null
	if boss_phase_label:
		boss_phase_label.queue_free()
		boss_phase_label = null

func _on_boss_hp_changed(current: float, max_val: float) -> void:
	if boss_hp_bar:
		boss_hp_bar.value = current
		# HP割合でバー色変化（紫→赤）
		var pct := current / max_val
		var fill := boss_hp_bar.get_theme_stylebox("fill") as StyleBoxFlat
		if fill:
			if pct > 0.66:
				fill.bg_color = Color(0.6, 0.2, 0.9, 1.0)
			elif pct > 0.33:
				fill.bg_color = Color(0.9, 0.5, 0.2, 1.0)
			else:
				fill.bg_color = Color(0.9, 0.15, 0.1, 1.0)

func _on_boss_phase_changed(phase: int, _hp_pct: float) -> void:
	if boss_phase_label:
		boss_phase_label.text = "Phase %d" % phase
		# フェーズ移行時のラベルフラッシュ
		boss_phase_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3, 1.0))
		var tween := boss_phase_label.create_tween()
		tween.tween_property(boss_phase_label, "theme_override_colors/font_color", Color(0.5, 0.3, 0.8, 0.7), 0.5)

	# フェーズ移行: 中シェイク
	tower.shake(5.0)

	# "PHASE X" テキスト
	var label := Label.new()
	label.text = "PHASE %d" % phase
	label.add_theme_font_size_override("font_size", 30)
	label.add_theme_color_override("font_color", Color(0.8, 0.4, 1.0, 1.0))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(490, 150)
	label.custom_minimum_size = Vector2(300, 0)
	label.z_index = 200
	label.modulate.a = 0.0
	ui_layer.add_child(label)

	var text_tween := label.create_tween()
	text_tween.tween_property(label, "modulate:a", 1.0, 0.1)
	text_tween.tween_property(label, "scale", Vector2(1.2, 1.2), 0.1).set_trans(Tween.TRANS_BACK)
	text_tween.tween_property(label, "scale", Vector2(1.0, 1.0), 0.1)
	text_tween.tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.5)
	text_tween.tween_callback(label.queue_free)

## v0.3.3: 近距離初期波 — Dead Time序盤空白を潰す
func _spawn_initial_wave() -> void:
	if enemy_scene == null:
		return
	var cam_pos := tower.global_position
	for i in 4:
		var enemy := enemy_scene.instantiate() as CharacterBody2D
		# 150-250px圏内にランダム配置（通常スポーンの400-550pxより大幅に近い）
		var angle := randf() * TAU
		var dist := randf_range(150.0, 250.0)
		enemy.global_position = cam_pos + Vector2(cos(angle), sin(angle)) * dist
		add_child(enemy)
		enemies_alive += 1

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
	var stage_hp: float = STAGE_HP_MULT[current_stage - 1]
	var hp_val: float = 35.0 * progress_scale * stage_hp  # v0.3.2: ステージ別HP倍率
	var speed_val := 75.0 + distance_m * 0.12 + run_time * 0.12
	var dmg_val := 14.0 + distance_m * 0.03  # v0.3: 10→14（HP500に対して体感できるダメージ）

	# 敵タイプ選択: ステージ別ゲーティング（v0.3.2）
	# Stage 1: normal only / Stage 2: +swarmer / Stage 3: +tank
	var type_roll := randf()
	var etype := "normal"
	if current_stage >= 2 and type_roll < 0.25:
		etype = "swarmer"
	elif current_stage >= 3 and type_roll >= 0.25 and type_roll < 0.40:
		etype = "tank"

	enemy.init(tower, speed_val, hp_val, dmg_val, etype)
	enemy.add_to_group("enemies")
	enemy.died.connect(_on_enemy_died)
	enemies_alive += 1
	add_child(enemy)

func _on_enemy_died(_enemy: Node2D) -> void:
	enemies_alive -= 1
	kill_count += 1
	tower.enemy_killed.emit()
	SFX.play_kill()
	# 小さなシェイク（爽快感）
	tower.shake(2.0)
	# コンボカウント
	combo_count += 1
	combo_timer = COMBO_WINDOW
	_update_combo_display()
	# ヒットストップ（キル時の一瞬の停止 = 重い手応え）
	_do_hitstop(0.03)
	# タワーキルグロー（シアンの瞬間パルス）
	_flash_tower_kill_glow()

func _update_combo_display() -> void:
	if combo_label_node == null:
		return
	if combo_count < 3:
		combo_label_node.visible = false
		return

	combo_label_node.visible = true
	var tier_text := ""
	var tier_color := Color(1.0, 0.6, 0.2, 1.0)  # デフォルト: オレンジ

	if combo_count >= 30:
		tier_text = "GODLIKE!"
		tier_color = Color(1.0, 0.2, 0.9, 1.0)  # マゼンタ
	elif combo_count >= 15:
		tier_text = "MASSACRE!"
		tier_color = Color(1.0, 0.15, 0.1, 1.0)  # 赤
	elif combo_count >= 8:
		tier_text = "RAMPAGE!"
		tier_color = Color(1.0, 0.5, 0.1, 1.0)  # 濃いオレンジ
	else:
		tier_text = "COMBO"
		tier_color = Color(1.0, 0.75, 0.3, 1.0)  # 黄色

	combo_label_node.text = "%s x%d" % [tier_text, combo_count]
	combo_label_node.add_theme_color_override("font_color", tier_color)
	best_combo = maxi(best_combo, combo_count)

	# ティアが上がった瞬間のスケールパンチ（3, 8, 15, 30のタイミング）
	if combo_count in [3, 8, 15, 30]:
		var tween := combo_label_node.create_tween()
		tween.tween_property(combo_label_node, "scale", Vector2(1.3, 1.3), 0.08).set_trans(Tween.TRANS_BACK)
		tween.tween_property(combo_label_node, "scale", Vector2(1.0, 1.0), 0.12)

# --- タワーイベント ---

var hp_bar_last_value := -1.0  # heal flash検出用

func _on_tower_damaged(current: float, max_val: float) -> void:
	# Heal flash（HP増加を検出）
	if hp_bar_last_value >= 0 and current > hp_bar_last_value:
		_flash_hp_bar_heal()
	# 被弾SE（HP減少時のみ）
	elif hp_bar_last_value >= 0 and current < hp_bar_last_value:
		SFX.play_damage_taken()
	hp_bar_last_value = current

	hp_bar.value = current
	_update_hp_label(current, max_val)

	# HP低下で連続的な色変化（smooth lerp）
	var pct := current / max_val
	var fill_style := hp_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill_style == null:
		return

	var hp_color := Color.WHITE
	if pct > 0.5:
		# 100%~50%: cyan
		hp_color = Color(0.28, 0.6, 0.8, 1.0)
	elif pct > 0.25:
		# 50%~25%: cyan → yellow（smooth lerp）
		var t: float = (pct - 0.25) / 0.25  # 1.0 at 50%, 0.0 at 25%
		hp_color = Color(0.28, 0.6, 0.8, 1.0).lerp(Color(0.85, 0.75, 0.2, 1.0), 1.0 - t)
	else:
		# 25%~0%: yellow → red（smooth lerp）
		var t: float = pct / 0.25  # 1.0 at 25%, 0.0 at 0%
		hp_color = Color(0.85, 0.75, 0.2, 1.0).lerp(Color(0.9, 0.2, 0.15, 1.0), 1.0 - t)
	fill_style.bg_color = hp_color

	# HP label色もバーに連動
	hp_label.add_theme_color_override("font_color", hp_color.lightened(0.3))

	# Low HP pulse（25%以下でバーの境界線が脈動）
	var bar_bg := hp_bar.get_theme_stylebox("background") as StyleBoxFlat
	if bar_bg:
		if pct <= 0.25 and pct > 0:
			# 危険: 赤い境界線
			bar_bg.border_color = Color(0.9, 0.2, 0.15, 0.9)
			bar_bg.set_border_width_all(2)
		elif tower.crush_active:
			# Crush中: 赤い境界線（HP状態と連動）
			bar_bg.border_color = Color(1.0, 0.3, 0.2, 0.7)
			bar_bg.set_border_width_all(2)
		else:
			bar_bg.border_color = Color(0.2, 0.18, 0.3, 0.8)
			bar_bg.set_border_width_all(1)

func _flash_hp_bar_heal() -> void:
	## HP回復時のバー緑フラッシュ
	var fill_style := hp_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill_style == null:
		return
	var original := fill_style.bg_color
	fill_style.bg_color = Color(0.3, 0.9, 0.4, 1.0)
	var tween := hp_bar.create_tween()
	tween.tween_property(fill_style, "bg_color", original, 0.2)

func _on_xp_gained(total_xp: int, current_level: int) -> void:
	var next_xp: int = tower.get_xp_for_next_level()
	wave_label.text = "Lv.%d  XP: %d/%d" % [current_level, total_xp, next_xp]
	# XPバー更新
	if xp_bar:
		xp_bar.max_value = next_xp
		xp_bar.value = total_xp

func _on_crush_changed(active: bool, count: int) -> void:
	if active:
		crush_label.text = "SURROUNDED x%d" % count
		crush_label.visible = true
		# 包囲開始: 警告シェイク
		tower.shake(4.0)
		# Warning labelは非表示に（crushが上位表示）
		if crush_warning_label:
			crush_warning_label.visible = false
	else:
		crush_label.visible = false

func _setup_crush_ring() -> void:
	## タワー周囲のCRUSH_RADIUSを示すリング（ワールド座標、タワーの子）
	crush_ring = Line2D.new()
	crush_ring.name = "CrushRing"
	crush_ring.width = 1.5
	crush_ring.default_color = Color(1.0, 0.3, 0.2, 0.0)  # 初期は透明
	crush_ring.z_index = 50
	var pts: PackedVector2Array = []
	for i in range(25):  # 24セグメント + 閉じる
		var a := i * TAU / 24
		pts.append(Vector2(cos(a), sin(a)) * tower.CRUSH_RADIUS)
	crush_ring.points = pts
	tower.add_child(crush_ring)

	# Pre-crush warning label（UI空間）
	crush_warning_label = Label.new()
	crush_warning_label.name = "CrushWarning"
	crush_warning_label.text = "DANGER"
	crush_warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crush_warning_label.position = Vector2(540, 365)
	crush_warning_label.custom_minimum_size = Vector2(200, 0)
	crush_warning_label.add_theme_font_size_override("font_size", 18)
	crush_warning_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2, 0.9))
	crush_warning_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	crush_warning_label.add_theme_constant_override("shadow_offset_x", 1)
	crush_warning_label.add_theme_constant_override("shadow_offset_y", 1)
	crush_warning_label.visible = false
	ui_layer.add_child(crush_warning_label)

func _update_crush_ring() -> void:
	## Crush ringの色・透明度を状態に応じて更新
	if crush_ring == null:
		return

	if tower.crush_active:
		# Crush中: 赤く脈動（duration長いほど濃く）
		var pulse := 0.5 + sin(run_time * 6.0) * 0.2
		var alpha := minf(0.4 + tower.crush_duration * 0.08, 0.8)
		crush_ring.default_color = Color(1.0, 0.2, 0.1, alpha * pulse + 0.2)
		crush_ring.width = 2.0
	elif tower.crush_count > 0:
		# Pre-crush: 黄色で警告
		var alpha: float = 0.15 + float(tower.crush_count) * 0.1
		crush_ring.default_color = Color(1.0, 0.8, 0.2, alpha)
		crush_ring.width = 1.5
	else:
		# 安全: 非表示
		crush_ring.default_color = Color(1.0, 0.3, 0.2, 0.0)

func _on_crush_warning(count: int) -> void:
	if crush_warning_label == null:
		return
	if count >= 2 and not tower.crush_active:
		crush_warning_label.text = "DANGER x%d" % count
		crush_warning_label.visible = true
	elif count == 1:
		crush_warning_label.visible = false
	else:
		crush_warning_label.visible = false

func _on_crush_breakout() -> void:
	## Breakout burst VFX: 金色の衝撃波リング
	var ring := Polygon2D.new()
	var pts: PackedVector2Array = []
	for i in range(24):
		var a := i * TAU / 24
		pts.append(Vector2(cos(a), sin(a)) * 15.0)
	ring.polygon = pts
	ring.color = Color(1.0, 0.85, 0.3, 0.7)
	ring.global_position = tower.global_position
	ring.z_index = 140
	add_child(ring)

	var tween := ring.create_tween()
	tween.set_parallel(true)
	var target_scale: float = tower.CRUSH_BREAKOUT_RADIUS / 15.0
	tween.tween_property(ring, "scale", Vector2(target_scale, target_scale), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring, "modulate:a", 0.0, 0.35)
	tween.chain().tween_callback(ring.queue_free)

	# "BREAKOUT!" テキスト
	var label := Label.new()
	label.text = "BREAKOUT!"
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3, 1.0))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(540, 280)
	label.custom_minimum_size = Vector2(200, 0)
	label.z_index = 200
	ui_layer.add_child(label)

	var text_tween := label.create_tween()
	text_tween.tween_property(label, "scale", Vector2(1.2, 1.2), 0.1).set_trans(Tween.TRANS_BACK)
	text_tween.tween_property(label, "scale", Vector2(1.0, 1.0), 0.1)
	text_tween.tween_property(label, "modulate:a", 0.0, 1.0).set_delay(0.5)
	text_tween.tween_callback(label.queue_free)

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
	SFX.play_level_up()
	# 奇数レベル(3,5,7...): ビルドアップグレード（スキル/サポート/Mod）
	# 偶数レベル(2,4,6...): ステータスアップグレード
	# なぜ: _show_upgrade_choiceが未接続で2nd skillが取得不可能だった
	if new_level >= 3 and new_level % 2 == 1:
		upgrade_events_given += 1
		_show_upgrade_choice()
	else:
		var pool := levelup_pool.duplicate()
		pool.shuffle()
		var choices: Array[Dictionary] = []
		for i in range(mini(3, pool.size())):
			choices.append(pool[i])
		upgrade_ui.show_levelup_choice(new_level, choices)

	# XPバーリセット（次のレベルの目標に合わせる）
	if xp_bar:
		xp_bar.max_value = tower.get_xp_for_next_level()
		xp_bar.value = tower.xp
		# レベルアップフラッシュ: バーが一瞬光る
		var xp_fill := xp_bar.get_theme_stylebox("fill") as StyleBoxFlat
		if xp_fill:
			var original_color := Color(0.35, 0.85, 0.45, 0.8)
			xp_fill.bg_color = Color(1.0, 1.0, 0.6, 1.0)
			var bar_tween := xp_bar.create_tween()
			bar_tween.tween_property(xp_fill, "bg_color", original_color, 0.3)

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
	# ヒットフリーズ（80ms）— レベルアップの「重み」を演出
	_do_hitstop(0.08)

	var pos := tower.global_position

	# 金色の拡散リング（2重）
	for ring_i in range(2):
		var ring := Polygon2D.new()
		var pts: PackedVector2Array = []
		for i in range(16):
			var a := i * TAU / 16
			pts.append(Vector2(cos(a), sin(a)) * 20.0)
		ring.polygon = pts
		ring.color = Color(1.0, 0.9, 0.4, 0.6 - ring_i * 0.2)
		ring.global_position = pos
		ring.z_index = 150
		add_child(ring)

		var target_scale := 4.0 + ring_i * 2.0
		var duration := 0.4 + ring_i * 0.15
		var tween := ring.create_tween()
		tween.set_parallel(true)
		tween.tween_property(ring, "scale", Vector2(target_scale, target_scale), duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(ring, "modulate:a", 0.0, duration)
		tween.chain().tween_callback(ring.queue_free)

	# パーティクル爆散（12個の金色破片）
	for i in range(12):
		var frag := Polygon2D.new()
		var angle := randf() * TAU
		var size := randf_range(3.0, 6.0)
		frag.polygon = PackedVector2Array([
			Vector2(-size, -size * 0.4),
			Vector2(size, 0),
			Vector2(-size, size * 0.4),
		])
		frag.color = Color(1.0, 0.85 + randf() * 0.15, 0.3 + randf() * 0.3, 0.9)
		frag.global_position = pos
		frag.rotation = angle
		frag.z_index = 151
		add_child(frag)

		var dist := randf_range(40.0, 100.0)
		var target_pos := pos + Vector2(cos(angle), sin(angle)) * dist
		var frag_tween := frag.create_tween()
		frag_tween.set_parallel(true)
		frag_tween.tween_property(frag, "global_position", target_pos, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		frag_tween.tween_property(frag, "modulate:a", 0.0, 0.35).set_delay(0.1)
		frag_tween.tween_property(frag, "scale", Vector2(0.2, 0.2), 0.35)
		frag_tween.chain().tween_callback(frag.queue_free)

	# 画面フラッシュ（金色、レベルアップの喜び）
	var flash := ColorRect.new()
	flash.color = Color(1.0, 0.9, 0.4, 0.2)
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ui := get_node_or_null("UI")
	if ui:
		ui.add_child(flash)
	else:
		add_child(flash)
	var flash_tween := flash.create_tween()
	flash_tween.tween_property(flash, "color:a", 0.0, 0.2)
	flash_tween.tween_callback(flash.queue_free)

	# スクリーンシェイク
	tower.shake(4.0)

func _update_offscreen_indicators() -> void:
	## 画面外の敵に対して画面端に赤い矢印を表示
	var cam := tower.get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		return

	var cam_pos := cam.get_screen_center_position()
	var half_w := 640.0
	var half_h := 360.0
	var view_left := cam_pos.x - half_w
	var view_right := cam_pos.x + half_w
	var view_top := cam_pos.y - half_h
	var view_bottom := cam_pos.y + half_h

	# 画面外の敵を距離順で収集
	var offscreen_enemies: Array[Dictionary] = []
	for child in get_children():
		if not child is Node2D:
			continue
		if not child.is_in_group("enemies"):
			continue
		if not is_instance_valid(child):
			continue
		var enemy_node: Node2D = child as Node2D
		var epos: Vector2 = enemy_node.global_position
		if epos.x >= view_left and epos.x <= view_right and epos.y >= view_top and epos.y <= view_bottom:
			continue  # 画面内 → スキップ
		var dist: float = tower.global_position.distance_to(epos)
		var is_boss_flag: bool = enemy_node.get("is_boss") == true
		offscreen_enemies.append({"pos": epos, "dist": dist, "boss": is_boss_flag})

	# ボス優先、近い順にソート
	offscreen_enemies.sort_custom(func(a, b):
		if a.boss != b.boss:
			return a.boss  # ボスが先
		return a.dist < b.dist
	)

	# インジケータープール拡張
	while indicator_pool.size() < MAX_INDICATORS:
		var arrow := Polygon2D.new()
		arrow.polygon = PackedVector2Array([
			Vector2(0, -10), Vector2(8, 6), Vector2(-8, 6),
		])
		arrow.z_index = 150
		arrow.visible = false
		ui_layer.add_child(arrow)
		indicator_pool.append(arrow)

	# 全非表示にしてから必要な分だけ表示
	for arrow in indicator_pool:
		arrow.visible = false

	var count := mini(offscreen_enemies.size(), MAX_INDICATORS)
	for i in range(count):
		var data: Dictionary = offscreen_enemies[i]
		var epos: Vector2 = data.pos
		var arrow := indicator_pool[i]

		# 敵方向のベクトル
		var dir := (epos - cam_pos).normalized()

		# 画面端にクランプ（マージン付き）
		var margin := SCREEN_MARGIN
		var screen_pos := Vector2.ZERO
		# dirからスクリーン端の交点を計算
		var t_x := INF
		var t_y := INF
		if abs(dir.x) > 0.001:
			t_x = ((half_w - margin) / abs(dir.x))
		if abs(dir.y) > 0.001:
			t_y = ((half_h - margin) / abs(dir.y))
		var t := minf(t_x, t_y)
		screen_pos = dir * t

		# スクリーン座標に変換（UIレイヤーは画面座標）
		arrow.position = Vector2(640 + screen_pos.x, 360 + screen_pos.y)
		arrow.rotation = dir.angle() + PI / 2.0  # 矢印が敵方向を指す
		arrow.visible = true

		# ボスは紫で大きく、通常敵は赤
		if data.boss:
			arrow.color = Color(0.7, 0.3, 1.0, 0.85)
			arrow.scale = Vector2(1.5, 1.5)
		else:
			# 距離に応じてアルファを変化（近いほど濃い）
			var alpha := clampf(1.0 - data.dist / 800.0, 0.3, 0.8)
			arrow.color = Color(1.0, 0.25, 0.2, alpha)
			arrow.scale = Vector2(1.0, 1.0)

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

	SFX.play_wave_clear()

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
	_reset_time_scale()
	SFX.stop_bgm()
	_show_result_screen(false)

func _win_game() -> void:
	game_over = true
	_reset_time_scale()
	SFX.stop_bgm()
	_show_result_screen(true)

func _show_result_screen(is_victory: bool) -> void:
	## リザルト画面: 暗転 → タイトル → スタッツ → リトライ
	_save_unlocked_chips()
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
		["Best Combo", "x%d" % best_combo],
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

	# Chip Vault表示: 解放済みチップを表示
	var save_mgr := get_node_or_null("/root/SaveManager")
	if save_mgr and save_mgr.has_any_unlock():
		var chip_spacer := Control.new()
		chip_spacer.custom_minimum_size = Vector2(0, 8)
		vbox.add_child(chip_spacer)
		var chip_sep := HSeparator.new()
		chip_sep.custom_minimum_size = Vector2(200, 2)
		chip_sep.modulate.a = 0.0
		vbox.add_child(chip_sep)
		stat_labels.append(chip_sep)
		var chips_saved: Dictionary = save_mgr.get_unlocked_chips()
		var chip_names: Array[String] = []
		for cat in ["move", "attack", "skill"]:
			var cid: String = chips_saved.get(cat, "")
			if cid != "manual" and cid != "manual_aim" and cid != "auto_cast":
				chip_names.append(cid.replace("_", " ").capitalize())
		if chip_names.size() > 0:
			var vault_lbl := Label.new()
			vault_lbl.text = "CHIP VAULT: %s" % ", ".join(chip_names)
			vault_lbl.add_theme_font_size_override("font_size", 20)
			vault_lbl.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0, 1.0))
			vault_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
			vault_lbl.add_theme_constant_override("shadow_offset_x", 1)
			vault_lbl.add_theme_constant_override("shadow_offset_y", 1)
			vault_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			vault_lbl.modulate.a = 0.0
			vbox.add_child(vault_lbl)
			stat_labels.append(vault_lbl)

	# スペーサー
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer)

	# リトライ
	var retry := Label.new()
	retry.text = "Press R to Retry  |  Press T for Title"
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

func _save_unlocked_chips() -> void:
	## Chip Vault: 今ランで装備したチップを永続セーブに反映
	var save_mgr := get_node_or_null("/root/SaveManager")
	if save_mgr == null:
		return
	var newly_unlocked: Array[String] = []
	for category in build_system.equipped_chips.keys():
		var chip_id: String = build_system.equipped_chips[category]
		if save_mgr.unlock_chip(category, chip_id):
			newly_unlocked.append("%s: %s" % [category, chip_id])
	if newly_unlocked.size() > 0:
		print("Chip Vault: unlocked ", ", ".join(newly_unlocked))

func _do_hitstop(duration: float) -> void:
	## 一瞬のタイムスケール低下で「重い手応え」を演出
	## リエントラント安全: 複数同時呼び出しでも最後の1つが復帰するまで凍結維持
	_hitstop_depth += 1
	Engine.time_scale = 0.05
	# process_always=true タイマーで time_scale の影響を受けない
	get_tree().create_timer(duration, true, false, true).timeout.connect(func():
		_hitstop_depth -= 1
		if _hitstop_depth <= 0:
			_hitstop_depth = 0
			Engine.time_scale = 1.0
	)

func _reset_time_scale() -> void:
	## game over / scene遷移時の安全弁: hitstop状態を強制解除
	_hitstop_depth = 0
	Engine.time_scale = 1.0

func _exit_tree() -> void:
	## シーン破棄時にtime_scaleが残留しないよう強制リセット
	Engine.time_scale = 1.0
	_hitstop_depth = 0

func _flash_tower_kill_glow() -> void:
	## キル時にタワーがシアンに一瞬光る（報酬フィードバック）
	var glow := tower.get_node_or_null("StylizedVisual")
	if glow == null:
		return
	glow.modulate = Color(1.5, 2.0, 2.5, 1.0)
	var tween := glow.create_tween()
	tween.tween_property(glow, "modulate", Color.WHITE, 0.15)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_R and game_over:
			_reset_time_scale()
			get_tree().paused = false
			get_tree().reload_current_scene()
		elif event.keycode == KEY_T and game_over:
			_reset_time_scale()
			get_tree().paused = false
			get_tree().change_scene_to_file("res://scenes/title.tscn")
		elif event.keycode == KEY_ESCAPE and not game_over:
			get_tree().paused = not get_tree().paused
			if get_tree().paused:
				SFX.play_ui_cancel()
				wave_label.text = "PAUSED"
