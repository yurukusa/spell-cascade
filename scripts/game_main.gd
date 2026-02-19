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
var total_damage_dealt := 0.0  # 改善162: ダメージ累計（リザルト画面でDPS表示用）
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
var _boss_hp_root: Control = null  # 改善187: 全ボスHP UI要素のコンテナ（フェードイン管理+クリーンアップ用）

# 改善189: スロット別クールダウンバー（スキルのリチャージ状態を可視化）
var _cd_bar_container: Control = null
var _cd_bars: Array = []  # slot_index → ProgressBar or null
var _cd_bar_was_full: Array = []  # 改善210: 満タン遷移検知用（閃光の二重発火防止）

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

# 画面ビネット（低HP時の周辺暗化: 改善35）
var _vignette: ColorRect = null
var _vignette_pulse_tween: Tween = null  # 改善211: 低HP鼓動パルス制御
var _vignette_critical := false  # 改善211: クリティカル状態フラグ（初入検知）

# ボスHP臨界パルス（改善86/98: <15%でラベルとバーが赤く点滅）
var _boss_hp_crit_tween: Tween = null

# コンボタイマーバー（改善100: コンボウィンドウの残り時間を視覚化）
var _combo_timer_bar: ProgressBar = null

# タイマー警告フラグ（改善68: 残り時間の重要節目でシェイク演出）
var _timer_30s_warned := false
var _timer_10s_warned := false

# 改善118: 圧力インジケーター（敵数が多い時の緊張感強化）
var _pressure_label: Label = null
var _pressure_active := false

# 改善128: OVERTIMEラベル（9分到達で表示）
var _overtime_announced := false

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
var _desperate_push_announced := false  # デスパレートプッシュ告知フラグ（1回のみ）

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
	_rebuild_cd_bars()  # 改善189
	var initial_xp_target: int = tower.get_xp_for_next_level()
	wave_label.text = "Lv.1  XP: 0/%d" % initial_xp_target
	game_started = true
	SFX.play_bgm()

	# Onboarding overlay（操作説明 + 目的）
	_show_onboarding()

	# 画面ビネット（低HP演出: 改善35）
	_setup_vignette()

	# v0.3.3: 初期波（近距離スポーンで序盤Dead Time削減）
	_spawn_initial_wave()

	# v0.2.6: 距離ベースupgrade完全削除。XP levelupのみ

func _process(delta: float) -> void:
	if game_over or not game_started:
		return

	run_time += delta
	_update_timer_display()
	_update_distance_display()
	_update_cd_bars()  # 改善189: スロットCDバー更新

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

	# ステージ遷移告知（J-8: 重要な局面変化を大きく提示）
	if current_stage != prev_stage:
		_announce_stage(current_stage)
		# 改善75: ステージ遷移で全画面フラッシュ（「ステージが変わった」衝撃を全身で感じる）
		var stage_color := Color(0.9, 0.5, 0.05, 0.35) if current_stage == 2 else Color(0.8, 0.1, 0.05, 0.45)
		var stg_flash := ColorRect.new()
		stg_flash.color = stage_color
		stg_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
		stg_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stg_flash.z_index = 170
		ui_layer.add_child(stg_flash)
		var sf_tw := stg_flash.create_tween()
		sf_tw.tween_property(stg_flash, "color:a", 0.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		sf_tw.tween_callback(stg_flash.queue_free)

	# 敵スポーン（縦スクロール: 上方スポーン中心）
	spawn_timer += delta
	var stage_spawn: float = STAGE_SPAWN_MULT[current_stage - 1]
	# 最後15秒: desperate push（スポーン加速 ×1.6）
	if run_time >= DESPERATE_PUSH_TIME:
		stage_spawn *= 1.6
		if not _desperate_push_announced:
			_desperate_push_announced = true
			_announce_desperate_push()
	var current_interval := maxf(spawn_interval - run_time * 0.002, 0.4) / stage_spawn
	# ボス出現後は雑魚スポーンを25%に抑制（ボス戦に集中）
	if boss_spawned:
		current_interval *= 4.0
	if spawn_timer >= current_interval:
		spawn_timer = 0.0
		_spawn_enemy()

	# スポーンフロア: t=3s以降、最低N体を維持（v0.7.0: 時間で増加 → 数の圧力で緊張維持）
	# 6体(0s) → 8体(1分) → 10体(2分) → 最大15体。プレイヤーが強くなるほど敵も多くする。
	var min_alive: int = mini(6 + int(run_time / 30), 15)
	if run_time >= 3.0 and enemies_alive < min_alive and not boss_spawned and spawn_timer >= current_interval * 0.5:
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

	# 改善118: 敵数圧力インジケーター（12体以上で "PRESSURE!" 表示）
	var pressure_threshold := 12
	if enemies_alive >= pressure_threshold and not boss_spawned:
		if not _pressure_active:
			_pressure_active = true
			_show_pressure_label()
	else:
		if _pressure_active:
			_pressure_active = false
			if _pressure_label and is_instance_valid(_pressure_label):
				_pressure_label.visible = false

	# 改善128: 9分経過でOVERTIMEラベル（「10分まで粘ろう」動機付け）
	if not _overtime_announced and run_time >= 540.0:
		_overtime_announced = true
		_announce_overtime()

	# Onboarding overlay タイマー
	if onboarding_panel and onboarding_timer > 0:
		onboarding_timer -= delta
		if onboarding_timer <= 0:
			_dismiss_onboarding()

	# Kill combo タイマー減衰
	if combo_count > 0:
		combo_timer -= delta
		# 改善100: コンボタイマーバーの更新（残り時間の視覚化）
		if _combo_timer_bar != null and is_instance_valid(_combo_timer_bar):
			_combo_timer_bar.value = combo_timer
		if combo_timer <= 0:
			var was_combo := combo_count
			combo_count = 0
			_update_combo_display()
			# コンボブレイク告知（5連続以上の場合のみ: 達成の余韻を示す）
			if was_combo >= 5:
				_show_combo_break(was_combo)
	else:
		# コンボなし: バーを非表示
		if _combo_timer_bar != null and is_instance_valid(_combo_timer_bar):
			_combo_timer_bar.visible = false

func record_damage(amount: float) -> void:
	# 改善162: enemy.gd の take_damage から呼ばれ、ダメージ累計を記録
	total_damage_dealt += amount

func _update_timer_display() -> void:
	var remaining := maxf(max_run_time - run_time, 0.0)
	var total_sec: int = floori(remaining)
	@warning_ignore("integer_division")
	var minutes: int = total_sec / 60
	var seconds: int = total_sec % 60
	timer_label.text = "%d:%02d" % [minutes, seconds]
	# カウントダウン演出: 残り60秒以下で赤く、30秒以下でパルス（J-7: 色による区分）
	if remaining <= 30.0:
		var pulse: float = abs(sin(run_time * 3.0))  # 改善144: 型推論警告修正（毎秒3回点滅）
		timer_label.add_theme_color_override("font_color", Color(1.0, 0.3 + pulse * 0.4, 0.2, 1.0))
	elif remaining <= 60.0:
		timer_label.add_theme_color_override("font_color", Color(0.95, 0.55, 0.2, 1.0))  # オレンジ
	else:
		timer_label.add_theme_color_override("font_color", Color(0.9, 0.88, 0.95, 1.0))  # デフォルト

	# 改善68: 残り30秒・10秒の節目で一度だけシェイク（終盤の緊張感を身体で感じる）
	if not _timer_30s_warned and remaining <= 30.0:
		_timer_30s_warned = true
		tower.shake(4.0)
		# 改善213: タイマーラベルのスケールパンチ（「30秒！」を視覚的に叩き込む）
		# Why: シェイクは画面全体の揺れ。ラベル自体が跳ねることで「時計が叫んでいる」感。
		var t30 := timer_label.create_tween()
		t30.tween_property(timer_label, "scale", Vector2(1.35, 1.35), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t30.tween_property(timer_label, "scale", Vector2(1.0, 1.0), 0.12).set_trans(Tween.TRANS_QUAD)
	if not _timer_10s_warned and remaining <= 10.0:
		_timer_10s_warned = true
		tower.shake(6.0)
		# 改善213: 10秒最終警告スケールパンチ（30秒より強くて最後の一押し）
		var t10 := timer_label.create_tween()
		t10.tween_property(timer_label, "scale", Vector2(1.6, 1.6), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t10.tween_property(timer_label, "scale", Vector2(1.0, 1.0), 0.1).set_trans(Tween.TRANS_QUAD)

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

	# 改善100: コンボタイマーバー（残りコンボウィンドウを細いバーで可視化）
	_combo_timer_bar = ProgressBar.new()
	_combo_timer_bar.name = "ComboTimerBar"
	_combo_timer_bar.position = Vector2(1080, 70)
	_combo_timer_bar.custom_minimum_size = Vector2(180, 5)
	_combo_timer_bar.size = Vector2(180, 5)
	_combo_timer_bar.max_value = COMBO_WINDOW
	_combo_timer_bar.value = 0.0
	_combo_timer_bar.show_percentage = false
	_combo_timer_bar.visible = false
	var ctb_fill := StyleBoxFlat.new()
	ctb_fill.bg_color = Color(1.0, 0.6, 0.2, 0.85)
	ctb_fill.set_corner_radius_all(1)
	_combo_timer_bar.add_theme_stylebox_override("fill", ctb_fill)
	var ctb_bg := StyleBoxFlat.new()
	ctb_bg.bg_color = Color(0.15, 0.12, 0.2, 0.7)
	_combo_timer_bar.add_theme_stylebox_override("background", ctb_bg)
	_combo_timer_bar.z_index = 100
	ui_layer.add_child(_combo_timer_bar)

	# Kill counter label (画面左下、distanceの下: 連続感と達成感）
	var kill_label := Label.new()
	kill_label.name = "KillCountLabel"
	kill_label.position = Vector2(10, 85)
	kill_label.add_theme_font_size_override("font_size", 13)
	kill_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7, 0.85))
	kill_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	kill_label.add_theme_constant_override("shadow_offset_x", 1)
	kill_label.add_theme_constant_override("shadow_offset_y", 1)
	kill_label.text = "Kills: 0"
	kill_label.z_index = 90
	ui_layer.add_child(kill_label)

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
	_rebuild_cd_bars()  # 改善189: スロット変更時にバーを再構築

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

func _rebuild_cd_bars() -> void:
	## 改善189: タワー各スロットのリチャージバーを再構築（スロット変更時に呼ぶ）
	if _cd_bar_container and is_instance_valid(_cd_bar_container):
		_cd_bar_container.queue_free()
	_cd_bar_container = null
	_cd_bars.clear()
	_cd_bar_was_full.clear()  # 改善210

	_cd_bar_container = Control.new()
	_cd_bar_container.name = "CDBarsContainer"
	_cd_bar_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(_cd_bar_container)

	const BAR_W := 80.0
	const BAR_H := 5.0
	const BAR_GAP := 8.0
	const X_START := 20.0
	const Y_START := 163.0
	# スロットごとに色を変えて識別しやすくする（青→紫→シアン）
	var slot_hues := [0.58, 0.67, 0.50]

	for i in range(tower.max_slots):
		_cd_bars.append(null)
		_cd_bar_was_full.append(false)  # 改善210
		if tower.get_module(i) == null:
			continue

		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = 1.0
		bar.value = 0.0
		bar.show_percentage = false
		bar.position = Vector2(X_START, Y_START + float(i) * (BAR_H + BAR_GAP))
		bar.custom_minimum_size = Vector2(BAR_W, BAR_H)
		bar.size = Vector2(BAR_W, BAR_H)

		var bg_style := StyleBoxFlat.new()
		bg_style.bg_color = Color(0.08, 0.05, 0.15, 0.7)
		bg_style.set_corner_radius_all(2)
		bar.add_theme_stylebox_override("background", bg_style)

		var fill_style := StyleBoxFlat.new()
		var hue: float = slot_hues[mini(i, slot_hues.size() - 1)]
		fill_style.bg_color = Color.from_hsv(hue, 0.8, 0.95, 0.9)
		fill_style.set_corner_radius_all(2)
		bar.add_theme_stylebox_override("fill", fill_style)

		_cd_bar_container.add_child(bar)
		_cd_bars[i] = bar

func _update_cd_bars() -> void:
	## 改善189: 毎フレーム各スロットのCD充填率をバーに反映
	if _cd_bar_container == null or not is_instance_valid(_cd_bar_container):
		return
	for atk in get_tree().get_nodes_in_group("tower_attacks"):
		var idx: int = atk.slot_index
		if idx < _cd_bars.size() and _cd_bars[idx] != null:
			var cooldown: float = atk.stats.get("cooldown", 1.0)
			if "cooldown_mult" in tower:
				cooldown *= tower.cooldown_mult
			var new_val := clampf(atk.timer / maxf(cooldown, 0.001), 0.0, 1.0)
			_cd_bars[idx].value = new_val
			# 改善210: CDバー満タン瞬間の閃光（<1.0→1.0 遷移時のみ。毎フレーム発火しない）
			# Why: 小さなバーは「撃てる」状態を色だけで伝えにくい。
			# 白い閃光でフィードバックを与え、次の一撃のタイミングを直感的に教える。
			var was_full: bool = idx < _cd_bar_was_full.size() and _cd_bar_was_full[idx]
			if new_val >= 1.0 and not was_full:
				var flash := _cd_bars[idx].create_tween()
				flash.tween_property(_cd_bars[idx], "modulate", Color(2.5, 2.5, 2.5, 1.0), 0.04)
				flash.tween_property(_cd_bars[idx], "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.25).set_trans(Tween.TRANS_EXPO)
			if idx < _cd_bar_was_full.size():
				_cd_bar_was_full[idx] = new_val >= 1.0

# --- 敵スポーン ---

func _show_boss_warning() -> void:
	SFX.play_boss_warning()  # 改善184: 遠くで何かが来る低い予告音
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
	# 改善215: スケールパンチイン（STAGE告知・FINAL PUSH等と一貫した「登場の一撃」）
	# Why: 他の重要告知ラベルは全て scale 2.x→1.0 の登場演出を持つのに
	# BOSS IN 10s だけが即時表示のままで「ボス前の最重要警告」として存在感が薄かった。
	label.scale = Vector2(1.8, 1.8)
	ui_layer.add_child(label)
	# スケールパンチ → パルスアニメーション→フェードアウト
	var tween := label.create_tween()
	tween.tween_property(label, "scale", Vector2(1.0, 1.0), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.3, 0.4).set_trans(Tween.TRANS_SINE)
	tween.tween_property(label, "modulate:a", 1.0, 0.4).set_trans(Tween.TRANS_SINE)
	tween.tween_property(label, "modulate:a", 0.3, 0.4).set_trans(Tween.TRANS_SINE)
	tween.tween_property(label, "modulate:a", 1.0, 0.4).set_trans(Tween.TRANS_SINE)
	tween.tween_property(label, "modulate:a", 0.0, 0.5).set_delay(0.5)
	tween.tween_callback(label.queue_free)

	# 改善89: ボス警告時に赤いビネットが点滅（「来るぞ！」の緊張感を全画面で演出）
	var bw_flash := ColorRect.new()
	bw_flash.color = Color(0.6, 0.0, 0.0, 0.28)
	bw_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	bw_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bw_flash.z_index = 150
	ui_layer.add_child(bw_flash)
	var bw_tween := bw_flash.create_tween()
	bw_tween.tween_property(bw_flash, "color:a", 0.0, 1.5)
	bw_tween.tween_callback(bw_flash.queue_free)

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
	title.text = "SHRINE DISCOVERED — 神殿発見"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(240, 505)
	title.custom_minimum_size = Vector2(800, 0)
	shrine_ui.add_child(title)

	# 改善97: カウントダウン進捗バー（「残り時間」を直感的に伝える）
	var countdown_bar := ProgressBar.new()
	countdown_bar.position = Vector2(240, 492)
	countdown_bar.custom_minimum_size = Vector2(800, 6)
	countdown_bar.max_value = SHRINE_AUTO_SELECT_TIME
	countdown_bar.value = SHRINE_AUTO_SELECT_TIME
	countdown_bar.show_percentage = false
	var cb_fill := StyleBoxFlat.new()
	cb_fill.bg_color = Color(1.0, 0.85, 0.3, 0.8)
	countdown_bar.add_theme_stylebox_override("fill", cb_fill)
	var cb_bg := StyleBoxFlat.new()
	cb_bg.bg_color = Color(0.15, 0.1, 0.25, 0.5)
	countdown_bar.add_theme_stylebox_override("background", cb_bg)
	shrine_ui.add_child(countdown_bar)
	var cdb_tween := countdown_bar.create_tween()
	cdb_tween.tween_property(countdown_bar, "value", 0.0, SHRINE_AUTO_SELECT_TIME).set_trans(Tween.TRANS_LINEAR)

	# 3択ボタン（日英バイリンガル）
	var choices := [
		{"name": "OVERCHARGE\n過負荷", "desc": "弾数 +2\nクールダウン +30%遅", "color": Color(1.0, 0.4, 0.2)},
		{"name": "GREED\n強欲", "desc": "取得範囲 +200\nダメージ -15%", "color": Color(0.3, 1.0, 0.3)},
		{"name": "DISCIPLINE\n規律", "desc": "ダメージ +25%\n移動速度 -20%", "color": Color(0.4, 0.6, 1.0)},
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

	# 改善192: スライドアップ + フェードイン（神殿が地面から「湧き出る」感触）
	# 下から80pxオフセットした位置から正位置へスライド
	shrine_ui.modulate.a = 0.0
	shrine_ui.position = Vector2(0, 80)
	var tween := shrine_ui.create_tween()
	tween.set_parallel(true)
	tween.tween_property(shrine_ui, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(shrine_ui, "position:y", 0.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

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
		# 改善192: スライドダウン退場（入場と対称）
		var tween := shrine_ui.create_tween()
		tween.set_parallel(true)
		tween.tween_property(shrine_ui, "modulate:a", 0.0, 0.25).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(shrine_ui, "position:y", 80.0, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.chain().tween_callback(shrine_ui.queue_free)
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
	# 改善208: Shrine Toastスケールポップイン（Shrine選択確認を「登場の一撃」で伝える）
	label.scale = Vector2(0.5, 0.5)
	label.modulate.a = 0.0
	ui_layer.add_child(label)
	var tween := label.create_tween()
	tween.tween_property(label, "scale", Vector2(1.1, 1.1), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.set_parallel(true)
	tween.tween_property(label, "modulate:a", 1.0, 0.12)
	tween.chain().tween_property(label, "scale", Vector2(1.0, 1.0), 0.1).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(label, "modulate:a", 0.0, 1.5).set_delay(1.0)
	tween.chain().tween_callback(label.queue_free)
	# 改善131: Shrine選択時の色カラーフラッシュ（「何かが変わった」瞬間を全画面で演出）
	var shrine_flash := ColorRect.new()
	shrine_flash.color = Color(color.r, color.g, color.b, 0.18)
	shrine_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	shrine_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shrine_flash.z_index = 155
	ui_layer.add_child(shrine_flash)
	var sft := shrine_flash.create_tween()
	sft.tween_property(shrine_flash, "color:a", 0.0, 0.5).set_trans(Tween.TRANS_QUAD)
	sft.tween_callback(shrine_flash.queue_free)

func _spawn_boss() -> void:
	if enemy_scene == null:
		return
	boss_spawned = true
	SFX.play_boss_entrance()
	SFX.switch_bgm("boss")  # 改善193: ボス出現でボス専用BGMに切替

	var boss := enemy_scene.instantiate() as CharacterBody2D
	# ボスは上方から出現
	var cam_pos := tower.global_position
	boss.position = Vector2(cam_pos.x, cam_pos.y - 500)

	var distance_m: float = float(tower.distance_traveled) / 10.0
	# v0.7.0: ボスも指数スケーリング（ただし雑魚より×2倍HP）
	var time_factor := pow(1.0 + run_time / 90.0, 1.6)
	var progress_scale := (1.0 + distance_m / 50.0) * time_factor
	var hp_val := 35.0 * progress_scale * 2.0  # ボスは雑魚の2倍HP
	var speed_val := 75.0 + distance_m * 0.15 + run_time * 0.25  # v0.7.0: 速度圧力UP
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

	# 全画面赤フラッシュ（改善38: ボス登場の衝撃感）
	var boss_flash := ColorRect.new()
	boss_flash.color = Color(0.6, 0.0, 0.0, 0.5)
	boss_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	boss_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_flash.z_index = 180
	ui_layer.add_child(boss_flash)
	var flash_tw := boss_flash.create_tween()
	flash_tw.tween_property(boss_flash, "color:a", 0.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	flash_tw.tween_callback(boss_flash.queue_free)

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
	SFX.play_boss_kill()  # 改善180: ボス専用SFX（爆発+上昇フレア）
	# 改善193: ボス撃破後のBGM復帰（HP状況で battle / intense を選択）
	var post_boss_bgm := "intense" if (tower.hp / tower.max_hp) < 0.4 else "battle"
	SFX.switch_bgm(post_boss_bgm)
	# ボス撃破: 大きなシェイク
	tower.shake(8.0)
	# コンボ: ボスは+3カウント
	combo_count += 3
	combo_timer = COMBO_WINDOW
	_update_combo_display()
	# ボスキル: 長めのヒットストップ + タワーグロー
	# v0.7.0: 0.12→0.08（Design Lock: 最大80ms制限に準拠）
	_do_hitstop(0.08)
	_flash_tower_kill_glow()

	# 改善200: ボス撃破のお祝い表示 — スケールポップイン追加
	# Why: 「BOSS INCOMING!」は TRANS_BOUNCE でポップインするのに、「BOSS DEFEATED!」は瞬時表示のみ。
	# 最高潮の達成感シーンにこそ入場演出が必要。TRANS_BACK でジューシーなポップイン。
	var label := Label.new()
	label.text = "BOSS DEFEATED! / ボス撃破！"
	label.add_theme_font_size_override("font_size", 36)
	label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4, 1.0))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(640 - 200, 120)
	label.custom_minimum_size = Vector2(400, 0)
	label.z_index = 200
	label.scale = Vector2(0.3, 0.3)
	ui_layer.add_child(label)

	var tween := label.create_tween()
	tween.tween_property(label, "scale", Vector2(1.25, 1.25), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "scale", Vector2(1.0, 1.0), 0.1).set_trans(Tween.TRANS_QUAD)
	tween.tween_interval(1.3)
	tween.tween_property(label, "modulate:a", 0.0, 1.5)
	tween.tween_callback(label.queue_free)

	# 改善122: ボス撃破の黄金フラッシュ（最高の達成感を全画面で演出）
	var boss_flash := ColorRect.new()
	boss_flash.color = Color(1.0, 0.85, 0.2, 0.25)
	boss_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	boss_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_flash.z_index = 165
	ui_layer.add_child(boss_flash)
	var bft := boss_flash.create_tween()
	bft.tween_property(boss_flash, "color:a", 0.0, 0.7).set_trans(Tween.TRANS_CUBIC)
	bft.tween_callback(boss_flash.queue_free)

	# Boss HP bar除去
	_remove_boss_hp_bar()

	# v0.7.0: ボス撃破報酬 — HP回復 + 特別シュライン（強力な3択）
	# 2秒後に表示（演出と重ならないよう遅延）
	tower.hp = mini(tower.hp + 100, tower.max_hp)
	await get_tree().create_timer(2.0).timeout
	if is_inside_tree() and shrine_ui == null:  # 既存シュライン表示中は出さない
		_show_boss_reward_shrine()

func _show_boss_reward_shrine() -> void:
	## ボス撃破時の特別報酬シュライン（強力 + HP回復演出）
	SFX.play_ui_select()
	shrine_timer = SHRINE_AUTO_SELECT_TIME

	shrine_ui = Control.new()
	shrine_ui.name = "ShrineUI"
	shrine_ui.z_index = 190

	# 背景（通常シュラインより派手な金色ボーダー）
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.06, 0.02, 0.9)
	bg.position = Vector2(160, 470)
	bg.size = Vector2(960, 190)
	shrine_ui.add_child(bg)

	# タイトル（日英バイリンガル）
	var title := Label.new()
	title.text = "BOSS DEFEATED — 報酬を選べ"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(160, 476)
	title.custom_minimum_size = Vector2(960, 0)
	shrine_ui.add_child(title)

	var choices := [
		{
			"name": "TRANSCENDENCE\n超越",
			"desc": "全弾ダメージ +30%\n貫通 +1",
			"color": Color(1.0, 0.6, 0.0),
		},
		{
			"name": "PHOENIX\n不死鳥",
			"desc": "HP全回復\n攻撃速度 +25%",
			"color": Color(0.9, 0.2, 0.2),
		},
		{
			"name": "RUIN\n崩壊",
			"desc": "ダメージ +60%\nクールダウン +25%遅",
			"color": Color(0.5, 0.0, 0.9),
		},
	]

	for i in choices.size():
		var btn := Button.new()
		btn.text = choices[i]["name"] + "\n" + choices[i]["desc"]
		btn.position = Vector2(185 + i * 310, 505)
		btn.custom_minimum_size = Vector2(285, 135)
		btn.add_theme_font_size_override("font_size", 14)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.18, 0.1, 0.05, 0.92)
		style.border_color = choices[i]["color"]
		style.set_border_width_all(3)
		style.set_corner_radius_all(8)
		btn.add_theme_stylebox_override("normal", style)
		var hover := style.duplicate() as StyleBoxFlat
		hover.bg_color = Color(0.28, 0.16, 0.06, 0.96)
		btn.add_theme_stylebox_override("hover", hover)
		btn.add_theme_color_override("font_color", choices[i]["color"])
		btn.pressed.connect(_on_boss_reward_chosen.bind(i))
		shrine_ui.add_child(btn)

	ui_layer.add_child(shrine_ui)

	# 改善194: 通常シュライン（#192）と同じスライドアップ + フェードイン（演出の統一感）
	# 特別報酬なので少し速め (0.28s) かつスライド幅を大きめ (100px) にして重みを出す
	shrine_ui.modulate.a = 0.0
	shrine_ui.position = Vector2(0, 100)
	var tween := shrine_ui.create_tween()
	tween.set_parallel(true)
	tween.tween_property(shrine_ui, "modulate:a", 1.0, 0.35).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(shrine_ui, "position:y", 0.0, 0.40).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_boss_reward_chosen(idx: int) -> void:
	## ボス撃破報酬の適用
	if shrine_ui and is_instance_valid(shrine_ui):
		shrine_ui.queue_free()
		shrine_ui = null
	shrine_timer = 0.0
	match idx:
		0:  # TRANSCENDENCE（超越）: ダメージ +30% + 追加弾 +1
			tower.damage_mult *= 1.30
			tower.projectile_bonus += 1
		1:  # PHOENIX（不死鳥）: HP全回復 + 攻撃速度 +25%（cooldown短縮）
			tower.hp = tower.max_hp
			tower.cooldown_mult = maxf(tower.cooldown_mult * 0.80, 0.1)
		2:  # RUIN（崩壊）: ダメージ +60% / クールダウン +25%遅
			tower.damage_mult *= 1.60
			tower.cooldown_mult *= 1.25

func _create_boss_hp_bar(boss: Node2D) -> void:
	## ボス専用HPバー（画面上部中央）
	## 改善187: 全要素を_boss_hp_rootに集約→フェードイン + クリーンアップ一括化（フェーズマーカーのリーク修正）
	_boss_hp_root = Control.new()
	_boss_hp_root.name = "BossHPRoot"
	_boss_hp_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_boss_hp_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_hp_root.z_index = 180
	_boss_hp_root.modulate.a = 0.0  # フェードイン開始位置
	ui_layer.add_child(_boss_hp_root)

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
	_boss_hp_root.add_child(boss_hp_bar)

	# フェーズマーカー（33%/66%の境界線: フェーズ移行を視覚的に予告する）
	# ボスHP66%でPhase2、33%でPhase3に移行するのでバーのその位置に白いラインを引く
	for phase_pct in [0.66, 0.33]:
		var marker := Polygon2D.new()
		marker.polygon = PackedVector2Array([
			Vector2(0, -2), Vector2(2, -2), Vector2(2, 16), Vector2(0, 16),
		])
		marker.color = Color(1.0, 1.0, 1.0, 0.6)
		marker.position = Vector2(340.0 + 600.0 * phase_pct - 1.0, 80.0)
		_boss_hp_root.add_child(marker)  # 改善187: rootに集約（以前はui_layerリーク）

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
	_boss_hp_root.add_child(boss_hp_label)

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
	_boss_hp_root.add_child(boss_phase_label)

	# フェードイン: ボス登場を劇的に演出（0.5sかけて出現）
	var fade_t := _boss_hp_root.create_tween()
	fade_t.tween_property(_boss_hp_root, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_QUAD)

func _remove_boss_hp_bar() -> void:
	## 改善187: rootを消すだけで全要素（bar/labels/markers）を一括解放
	if _boss_hp_root and is_instance_valid(_boss_hp_root):
		_boss_hp_root.queue_free()
		_boss_hp_root = null
	boss_hp_bar = null
	boss_hp_label = null
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
		# HP%テキスト更新（J-8: 重要情報は大きく表示）
		if boss_hp_label:
			var hp_pct_int := int(pct * 100)
			boss_hp_label.text = "BOSS  %d%%" % hp_pct_int
			# 改善161: ボスHP被弾のたびにラベルがマイクロバウンス（「当たってる！」即時確認）
			var lb_t := boss_hp_label.create_tween()
			lb_t.tween_property(boss_hp_label, "scale", Vector2(1.06, 1.06), 0.04)
			lb_t.tween_property(boss_hp_label, "scale", Vector2(1.0, 1.0), 0.07)
			# 低HP時にラベルも赤に
			if pct <= 0.33:
				boss_hp_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2, 1.0))
			elif pct <= 0.66:
				boss_hp_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2, 1.0))
			else:
				boss_hp_label.add_theme_color_override("font_color", Color(0.8, 0.5, 1.0, 0.9))

		# 改善86+98: HP15%以下でバーとラベルが赤く点滅（「あと少し！」の高揚感と緊張の融合）
		if pct <= 0.15:
			if _boss_hp_crit_tween == null or not _boss_hp_crit_tween.is_running():
				_boss_hp_crit_tween = boss_hp_bar.create_tween()
				_boss_hp_crit_tween.set_loops()
				_boss_hp_crit_tween.tween_property(boss_hp_bar, "modulate", Color(2.0, 0.5, 0.5, 1.0), 0.22).set_trans(Tween.TRANS_SINE)
				_boss_hp_crit_tween.tween_property(boss_hp_bar, "modulate", Color.WHITE, 0.22).set_trans(Tween.TRANS_SINE)
		else:
			if _boss_hp_crit_tween != null and _boss_hp_crit_tween.is_running():
				_boss_hp_crit_tween.kill()
				_boss_hp_crit_tween = null
				boss_hp_bar.modulate = Color.WHITE

func _on_boss_phase_changed(phase: int, _hp_pct: float) -> void:
	SFX.play_boss_phase()  # 改善181: フェーズ移行の恐怖感を音で演出
	if boss_phase_label:
		boss_phase_label.text = "Phase %d" % phase
		# フェーズ移行時のラベルフラッシュ
		boss_phase_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3, 1.0))
		var tween := boss_phase_label.create_tween()
		tween.tween_property(boss_phase_label, "theme_override_colors/font_color", Color(0.5, 0.3, 0.8, 0.7), 0.5)
	# フェーズ移行: 画面フラッシュ + 大きなシェイク（無敵中なので迫力ある演出OK）
	_do_hitstop(0.12)
	tower.shake(8.0)
	var phase_flash := ColorRect.new()
	phase_flash.color = Color(0.6, 0.2, 0.9, 0.35)
	phase_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	phase_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	phase_flash.z_index = 200
	var ui := get_node_or_null("UI")
	if ui:
		ui.add_child(phase_flash)
	else:
		add_child(phase_flash)
	var flash_tween := phase_flash.create_tween()
	flash_tween.tween_property(phase_flash, "color:a", 0.0, 0.4)
	flash_tween.tween_callback(phase_flash.queue_free)
	# フェーズテキスト表示
	var phase_txt := Label.new()
	phase_txt.text = "PHASE %d" % phase
	phase_txt.add_theme_font_size_override("font_size", 40)
	phase_txt.add_theme_color_override("font_color", Color(1.0, 0.4, 1.0, 1.0))
	phase_txt.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	phase_txt.add_theme_constant_override("shadow_offset_x", 2)
	phase_txt.add_theme_constant_override("shadow_offset_y", 2)
	phase_txt.z_index = 201
	phase_txt.global_position = tower.global_position + Vector2(-60, -120)
	# 改善212: PHASE Nスケールポップイン（フェーズ移行の「衝撃」を登場演出で最大化）
	# Why: 画面フラッシュ+シェイクがあるのに、テキスト自体がただ出るだけでは締まらない。
	# スケールパンチで「局面が変わった」瞬間を一撃で印象付ける。
	phase_txt.scale = Vector2(0.3, 0.3)
	add_child(phase_txt)
	var pt_tween := phase_txt.create_tween()
	# スケールポップ（sequential先行: pop後に浮上フェードを並行開始）
	pt_tween.tween_property(phase_txt, "scale", Vector2(1.4, 1.4), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pt_tween.tween_property(phase_txt, "scale", Vector2(1.0, 1.0), 0.12).set_trans(Tween.TRANS_QUAD)
	pt_tween.set_parallel(true)
	pt_tween.tween_property(phase_txt, "global_position:y", phase_txt.global_position.y - 50, 1.0).set_trans(Tween.TRANS_QUAD)
	pt_tween.tween_property(phase_txt, "modulate:a", 0.0, 1.0).set_delay(0.5)
	pt_tween.chain().tween_callback(phase_txt.queue_free)

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

	# 改善158: ボスHPバーのフィル色をフェーズに合わせて変更（Phase2=橙, Phase3=赤）
	if boss_hp_bar and is_instance_valid(boss_hp_bar):
		var phase_fill_color := Color(0.9, 0.5, 0.1, 1.0) if phase == 2 else Color(0.9, 0.15, 0.1, 1.0)
		var bf := boss_hp_bar.get_theme_stylebox("fill") as StyleBoxFlat
		if bf:
			bf.bg_color = phase_fill_color

	# 改善132: Phase別カラースパーク（Phase2=橙/Phase3=赤で脅威レベルを粒子で印象付け）
	var phase_spark_color := Color(1.0, 0.5, 0.1, 0.9)  # Phase2: 橙
	if phase == 3:
		phase_spark_color = Color(1.0, 0.15, 0.1, 0.9)  # Phase3: 赤
	for _pi in range(12):
		var pa := float(_pi) * TAU / 12.0
		var pp := Polygon2D.new()
		pp.polygon = PackedVector2Array([
			Vector2(-2.0, -0.7), Vector2(2.0, 0.0), Vector2(-2.0, 0.7),
		])
		pp.color = phase_spark_color
		pp.rotation = pa
		pp.global_position = tower.global_position
		pp.z_index = 202
		add_child(pp)
		var pt := pp.create_tween()
		pt.set_parallel(true)
		pt.tween_property(pp, "global_position",
			tower.global_position + Vector2(cos(pa), sin(pa)) * randf_range(55.0, 100.0), 0.5
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		pt.tween_property(pp, "modulate:a", 0.0, 0.5).set_delay(0.15)
		pt.chain().tween_callback(pp.queue_free)

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
		# v0.5.1 bugfix: init()未呼出 → player=null → 敵が動かない、XPも出ないバグ
		enemy.init(tower, 75.0, 25.0, 10.0, "normal")
		enemy.add_to_group("enemies")
		enemy.died.connect(_on_enemy_died)
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
	# v0.7.0: 時間成分を指数関数化 — 線形スケールはプレイヤーの乗算的成長に追いつけない
	# pow(1+t/90, 1.6): 序盤ゆるやか→中盤加速→後半高難度。放置プレイ抑止。
	var time_factor := pow(1.0 + run_time / 90.0, 1.6)
	var progress_scale := (1.0 + distance_m / 50.0) * time_factor
	var stage_hp: float = STAGE_HP_MULT[current_stage - 1]
	var hp_val: float = 35.0 * progress_scale * stage_hp  # v0.3.2: ステージ別HP倍率
	# v0.7.0: 後半の速度圧力を高め、位置取りに意味を持たせる（桜井: 押し引き維持）
	var speed_val := 75.0 + distance_m * 0.15 + run_time * 0.25
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

func _on_enemy_died(enemy: Node2D) -> void:
	enemies_alive -= 1
	kill_count += 1
	tower.enemy_killed.emit()
	SFX.play_kill()
	# キルカウンターHUD更新（改善63: テキスト更新時にスケールポップで「積み上げ感」）
	var kc_lbl := ui_layer.get_node_or_null("KillCountLabel") as Label
	if kc_lbl:
		kc_lbl.text = "Kills: %d" % kill_count
		# 改善83: キル数で色が段階変化（灰→黄→赤→紫: 積み上げ感と「やばい数字」感を同時に演出）
		var kc_color: Color
		if kill_count >= 100:
			kc_color = Color(1.0, 0.2, 0.85, 1.0)  # 紫/マゼンタ: 100+
		elif kill_count >= 50:
			kc_color = Color(1.0, 0.3, 0.15, 1.0)  # 赤: 50+
		elif kill_count >= 10:
			kc_color = Color(1.0, 0.75, 0.2, 1.0)  # 黄: 10+
		else:
			kc_color = Color(0.6, 0.6, 0.7, 0.85)  # 灰（デフォルト）
		kc_lbl.add_theme_color_override("font_color", kc_color)
		var kc_tween := kc_lbl.create_tween()
		kc_tween.tween_property(kc_lbl, "scale", Vector2(1.2, 1.2), 0.06).set_trans(Tween.TRANS_BACK)
		kc_tween.tween_property(kc_lbl, "scale", Vector2(1.0, 1.0), 0.09)
	# 小さなシェイク（爽快感）
	tower.shake(2.0)
	# コンボカウント
	combo_count += 1
	combo_timer = COMBO_WINDOW
	_update_combo_display()
	# ヒットストップ（キル時の一瞬の停止 = 重い手応え、コンボ段階で強化）
	var hitstop_dur := 0.03
	if combo_count >= 15:
		hitstop_dur = 0.06  # 高コンボ: より重い停止感
	elif combo_count >= 8:
		hitstop_dur = 0.045
	_do_hitstop(hitstop_dur)
	# タワーキルグロー（シアンの瞬間パルス）
	_flash_tower_kill_glow()
	# キル位置にフローティングキルテキスト（コンボ段階に応じてスタイル変化）
	if is_instance_valid(enemy):
		var kill_pos := enemy.global_position
		var ktext := Label.new()
		if combo_count >= 15:
			ktext.text = "KILL! x%d" % combo_count
			ktext.add_theme_font_size_override("font_size", 18)
			ktext.add_theme_color_override("font_color", Color(1.0, 0.3, 0.9, 0.95))
		elif combo_count >= 8:
			ktext.text = "+KILL!"
			ktext.add_theme_font_size_override("font_size", 16)
			ktext.add_theme_color_override("font_color", Color(1.0, 0.5, 0.1, 0.9))
		else:
			ktext.text = "+%d" % kill_count
			ktext.add_theme_font_size_override("font_size", 13)
			ktext.add_theme_color_override("font_color", Color(0.4, 0.9, 0.5, 0.8))
		ktext.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
		ktext.add_theme_constant_override("shadow_offset_x", 1)
		ktext.add_theme_constant_override("shadow_offset_y", 1)
		ktext.z_index = 95
		ktext.global_position = kill_pos + Vector2(randf_range(-20, 20), -15)
		add_child(ktext)
		var kt := ktext.create_tween()
		kt.set_parallel(true)
		kt.tween_property(ktext, "global_position:y", ktext.global_position.y - 35, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		kt.tween_property(ktext, "modulate:a", 0.0, 0.55).set_delay(0.2)
		kt.chain().tween_callback(ktext.queue_free)

	# 改善123: キル位置に小さなリング（「敵を倒した」確認フィードバック）
	# 改善157: 敵タイプ別リング色（タイプの違いを倒した瞬間に確認できる）
	if is_instance_valid(enemy):
		var dr_pts := PackedVector2Array()
		for _dri in range(8):
			dr_pts.append(Vector2(cos(_dri * TAU / 8.0), sin(_dri * TAU / 8.0)) * 8.0)
		var death_ring := Polygon2D.new()
		death_ring.polygon = dr_pts
		var etype: String = enemy.get("enemy_type") if "enemy_type" in enemy else ""
		var dr_color: Color
		match etype:
			"swarmer": dr_color = Color(0.4, 0.9, 0.3, 0.7)    # 緑
			"tank":    dr_color = Color(1.0, 0.55, 0.1, 0.75)   # 橙
			"shooter": dr_color = Color(0.3, 0.7, 1.0, 0.7)     # 青
			"healer":  dr_color = Color(1.0, 0.3, 0.7, 0.7)     # ピンク
			"splitter":dr_color = Color(0.7, 0.3, 1.0, 0.7)     # 紫
			_:         dr_color = Color(1.0, 0.82, 0.2, 0.7)    # デフォルト: 金
		death_ring.color = dr_color
		death_ring.global_position = enemy.global_position
		death_ring.z_index = 85
		add_child(death_ring)
		var drt := death_ring.create_tween()
		drt.set_parallel(true)
		drt.tween_property(death_ring, "scale", Vector2(3.5, 3.5), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		drt.tween_property(death_ring, "modulate:a", 0.0, 0.25)
		drt.chain().tween_callback(death_ring.queue_free)

	# 改善133: 高XP敵（tank/boss等）の大きなデスリング（「強敵を倒した」を空間で表現）
	if is_instance_valid(enemy) and "xp_value" in enemy and enemy.xp_value >= 3:
		var big_ring := Polygon2D.new()
		var br_pts := PackedVector2Array()
		for _bri in range(12):
			br_pts.append(Vector2(cos(_bri * TAU / 12.0), sin(_bri * TAU / 12.0)) * 20.0)
		big_ring.polygon = br_pts
		big_ring.color = Color(1.0, 0.6, 0.15, 0.85)  # 橙: 強敵撃破の達成感
		big_ring.global_position = enemy.global_position
		big_ring.z_index = 86
		add_child(big_ring)
		var brt := big_ring.create_tween()
		brt.set_parallel(true)
		brt.tween_property(big_ring, "scale", Vector2(5.5, 5.5), 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		brt.tween_property(big_ring, "modulate:a", 0.0, 0.4)
		brt.chain().tween_callback(big_ring.queue_free)

	# 改善159: 高XP敵（xp_value≥2）にフローティング"+N XP"ピップ（XP獲得量の即時確認）
	if is_instance_valid(enemy) and "xp_value" in enemy and enemy.xp_value >= 2:
		var xp_pip := Label.new()
		xp_pip.text = "+%d XP" % enemy.xp_value
		xp_pip.add_theme_font_size_override("font_size", 15)
		xp_pip.add_theme_color_override("font_color", Color(0.3, 0.95, 0.5, 0.95))
		xp_pip.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
		xp_pip.add_theme_constant_override("shadow_offset_x", 1)
		xp_pip.add_theme_constant_override("shadow_offset_y", 1)
		xp_pip.z_index = 93
		xp_pip.global_position = enemy.global_position + Vector2(randf_range(-15, 15), -35)
		add_child(xp_pip)
		var xpt := xp_pip.create_tween()
		xpt.set_parallel(true)
		xpt.tween_property(xp_pip, "global_position:y", xp_pip.global_position.y - 45.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		xpt.tween_property(xp_pip, "modulate:a", 0.0, 0.7).set_delay(0.25)
		xpt.chain().tween_callback(xp_pip.queue_free)

	# 改善166: upgrade_on_kill_chance mod — kill時にボーナスアップグレードを得る
	if not upgrade_ui.visible:
		for atk in get_tree().get_nodes_in_group("tower_attacks"):
			var s: Dictionary = atk.get("stats") if atk.get("stats") != null else {}
			var chance: float = s.get("upgrade_on_kill_chance", 0.0)
			if chance > 0.0 and randf() < chance:
				upgrade_events_given += 1
				_show_upgrade_choice()
				break  # 複数スロットで重複発動しない

	# キルマイルストーン（10, 25, 50, 100, 200キル: 達成感の積み上げ）
	if kill_count in [10, 25, 50, 100, 200]:
		_announce_kill_milestone(kill_count)

	# 全敵撃破通知（改善45: ウェーブ完了の達成感）
	if enemies_alive <= 0:
		_show_area_cleared()

func _show_area_cleared() -> void:
	## 全敵撃破時のフラッシュ + "CLEARED!" テキスト（改善45）
	var lbl := Label.new()
	lbl.text = "CLEARED!"
	lbl.add_theme_font_size_override("font_size", 36)
	lbl.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6, 1.0))
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("shadow_offset_x", 2)
	lbl.add_theme_constant_override("shadow_offset_y", 2)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.position = Vector2(640 - 120, 250)
	lbl.custom_minimum_size = Vector2(240, 0)
	lbl.z_index = 200
	ui_layer.add_child(lbl)
	var tween := lbl.create_tween()
	tween.tween_property(lbl, "scale", Vector2(1.2, 1.2), 0.1).set_trans(Tween.TRANS_BACK)
	tween.chain().tween_property(lbl, "scale", Vector2(1.0, 1.0), 0.08)
	tween.chain().tween_interval(0.8)
	tween.chain().tween_property(lbl, "modulate:a", 0.0, 0.4)
	tween.chain().tween_callback(lbl.queue_free)
	tower.shake(3.0)

	# 改善126: 上から降る紙吹雪（クリア感を空間全体で表現）
	for _conf_i in range(14):
		var conf := Polygon2D.new()
		conf.polygon = PackedVector2Array([
			Vector2(-3, -3), Vector2(3, -3), Vector2(3, 3), Vector2(-3, 3)
		])
		var conf_colors := [Color(0.4, 1.0, 0.6), Color(1.0, 0.85, 0.2), Color(0.5, 0.8, 1.0), Color(1.0, 0.4, 0.7)]
		conf.color = conf_colors[_conf_i % conf_colors.size()]
		conf.global_position = Vector2(randf_range(200, 1080), -20)
		conf.z_index = 195
		add_child(conf)
		var cfx: float = conf.global_position.x + randf_range(-80, 80)
		var cfy: float = conf.global_position.y + randf_range(500, 700)
		var ct := conf.create_tween()
		ct.set_parallel(true)
		ct.tween_property(conf, "global_position", Vector2(cfx, cfy), randf_range(1.2, 2.0)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		ct.tween_property(conf, "rotation", randf_range(-TAU, TAU), 2.0)
		ct.tween_property(conf, "modulate:a", 0.0, 2.0).set_delay(0.6)
		ct.chain().tween_callback(conf.queue_free)

	# 改善65: タワー位置から放射状パーティクルバースト（「エリア制圧」の爽快感）
	var pos := tower.global_position
	for _ci in range(10):
		var frag := Polygon2D.new()
		var fangle := randf() * TAU
		var fsize := randf_range(3.0, 6.0)
		frag.polygon = PackedVector2Array([
			Vector2(-fsize * 0.5, 0), Vector2(fsize * 0.5, 0), Vector2(0, -fsize),
		])
		frag.color = Color(0.4 + randf() * 0.3, 1.0, 0.5 + randf() * 0.3, 0.9)
		frag.global_position = pos
		frag.rotation = fangle
		frag.z_index = 160
		add_child(frag)
		var fdist := randf_range(50.0, 120.0)
		var ct := frag.create_tween()
		ct.set_parallel(true)
		ct.tween_property(frag, "global_position", pos + Vector2(cos(fangle), sin(fangle)) * fdist, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		ct.tween_property(frag, "modulate:a", 0.0, 0.5).set_delay(0.15)
		ct.chain().tween_callback(frag.queue_free)

	# 改善146: 全敵撃破時の2重エメラルドリング波紋（「制圧完了」の爽快感を空間全体で表現）
	for _ri in range(2):
		var aring := Polygon2D.new()
		var aring_pts := PackedVector2Array()
		for _api in range(20):
			aring_pts.append(Vector2(cos(_api * TAU / 20.0), sin(_api * TAU / 20.0)) * 22.0)
		aring.polygon = aring_pts
		aring.color = Color(0.2, 0.95, 0.5, 0.7)
		aring.global_position = pos
		aring.z_index = 155
		add_child(aring)
		var art := aring.create_tween()
		art.set_parallel(true)
		art.tween_property(aring, "scale", Vector2(8.0, 8.0), 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(float(_ri) * 0.18)
		art.tween_property(aring, "modulate:a", 0.0, 0.7).set_delay(float(_ri) * 0.18)
		art.chain().tween_callback(aring.queue_free)

func _announce_kill_milestone(count: int) -> void:
	## キルマイルストーン告知（J-8: 達成を大きく演出）
	# 改善183: キルマイルストーンSFX（既存コンボ音を段階的に使用してコスト0で強化）
	match count:
		10:   SFX.play_level_up()         # 小さな達成
		25:   SFX.play_combo_tier(1)      # RAMPAGE相当（中達成）
		50:   SFX.play_combo_tier(2)      # MASSACRE相当（大達成）
		100:  SFX.play_combo_tier(3)      # GODLIKE相当（最大達成）
		200:  SFX.play_wave_clear()       # 超達成: ウェーブクリア音で差別化
	var milestone_texts := {10: "10 KILLS!", 25: "25 KILLS!", 50: "MASSACRE x50!", 100: "SLAUGHTERER x100!", 200: "DESTROYER x200!"}
	var milestone_colors := {10: Color(0.7, 0.9, 0.3, 1.0), 25: Color(1.0, 0.75, 0.2, 1.0), 50: Color(1.0, 0.5, 0.1, 1.0), 100: Color(1.0, 0.25, 0.8, 1.0), 200: Color(0.6, 0.2, 1.0, 1.0)}
	var msg: String = milestone_texts.get(count, "%d KILLS!" % count)
	var col: Color = milestone_colors.get(count, Color(1.0, 0.7, 0.2, 1.0))
	# 改善94: 50キル以上のマイルストーンは大きなシェイク（節目の重みを体感させる）
	var shake_intensity := 3.5 if count < 50 else (6.0 if count < 100 else 9.0)
	tower.shake(shake_intensity)
	# 改善125: マイルストーン爆発リング（達成の瞬間を空間で表現）
	var n_rings := 1 if count < 50 else (2 if count < 100 else 3)
	for ri in range(n_rings):
		var mring := Polygon2D.new()
		var mrpts := PackedVector2Array()
		for _mri in range(16):
			mrpts.append(Vector2(cos(_mri * TAU / 16.0), sin(_mri * TAU / 16.0)) * 18.0)
		mring.polygon = mrpts
		mring.color = col
		mring.global_position = tower.global_position
		mring.z_index = 172
		mring.modulate.a = 0.65 - ri * 0.15
		add_child(mring)
		var mrt := mring.create_tween()
		mrt.set_parallel(true)
		var delay := ri * 0.12
		mrt.tween_property(mring, "scale", Vector2(7.0 + ri * 2.0, 7.0 + ri * 2.0), 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT).set_delay(delay)
		mrt.tween_property(mring, "modulate:a", 0.0, 0.55).set_delay(delay)
		mrt.chain().tween_callback(mring.queue_free)
	var ann := Label.new()
	ann.text = msg
	ann.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ann.add_theme_font_size_override("font_size", 32)
	ann.add_theme_color_override("font_color", col)
	ann.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	ann.add_theme_constant_override("shadow_offset_x", 3)
	ann.add_theme_constant_override("shadow_offset_y", 3)
	ann.custom_minimum_size = Vector2(760, 0)
	ann.position = Vector2(200, 300)
	# 改善205: キルマイルストーンスケールポップイン（STAGE告知・FINAL PUSHとの一貫性）
	# Why: position slide は既にあるが、scale pop がなく「ステージ告知より存在感が薄い」矛盾。
	# カウントが大きいほど初期スケールを大きくして達成感を段階的に強調する。
	var entry_scale := 1.6 + minf(float(count) / 100.0, 0.6)  # 10kill=1.7 ～ 100kill+=2.2
	ann.scale = Vector2(entry_scale, entry_scale)
	ann.z_index = 180
	ui_layer.add_child(ann)
	var tween := ann.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ann, "position:y", 265.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(ann, "scale", Vector2(1.0, 1.0), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(ann, "modulate:a", 0.0, 2.0).set_delay(0.7)
	tween.chain().tween_callback(ann.queue_free)

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

	# 改善61: ティアが上がるほどフォントが大きくなり「積み上げ感」を強調
	var combo_font_size := 18
	if combo_count >= 30:
		combo_font_size = 32
	elif combo_count >= 15:
		combo_font_size = 26
	elif combo_count >= 8:
		combo_font_size = 22
	combo_label_node.add_theme_font_size_override("font_size", combo_font_size)
	combo_label_node.text = "%s x%d" % [tier_text, combo_count]
	combo_label_node.add_theme_color_override("font_color", tier_color)
	best_combo = maxi(best_combo, combo_count)

	# 改善152: 毎キルでの微小スケールバウンス（コンボが積み上がる「リズム感」）
	if combo_count >= 3 and combo_count not in [3, 8, 15, 30]:
		var micro_tween := combo_label_node.create_tween()
		var micro_scale := 1.08 + minf(float(combo_count) / 200.0, 0.12)  # コンボ多いほど少し大きく
		micro_tween.tween_property(combo_label_node, "scale", Vector2(micro_scale, micro_scale), 0.05).set_trans(Tween.TRANS_BACK)
		micro_tween.tween_property(combo_label_node, "scale", Vector2(1.0, 1.0), 0.07)

	# 改善100: コンボタイマーバーをコンボ中は表示し、色もティアに合わせる
	if _combo_timer_bar != null and is_instance_valid(_combo_timer_bar):
		_combo_timer_bar.visible = true
		_combo_timer_bar.value = combo_timer
		var ctb_fill := _combo_timer_bar.get_theme_stylebox("fill") as StyleBoxFlat
		if ctb_fill:
			ctb_fill.bg_color = tier_color

	# ティアが上がった瞬間のスケールパンチ（3, 8, 15, 30のタイミング）
	if combo_count in [3, 8, 15, 30]:
		var tween := combo_label_node.create_tween()
		tween.tween_property(combo_label_node, "scale", Vector2(1.3, 1.3), 0.08).set_trans(Tween.TRANS_BACK)
		tween.tween_property(combo_label_node, "scale", Vector2(1.0, 1.0), 0.12)
		# 改善174: コンボティアアップSE（視覚的スケールパンチに対応する音）
		# tier 0=3kills, 1=8kills, 2=15kills, 3=30kills
		var sfx_tier := [3, 8, 15, 30].find(combo_count)
		SFX.play_combo_tier(sfx_tier)
		# 改善64: ティアアップ時はタワーにも振動（スクリーン全体で「昇格」を感じる）
		var shake_lvl := 2.5 if combo_count == 8 else (3.5 if combo_count == 15 else 5.0)
		if is_instance_valid(tower):
			tower.shake(shake_lvl)
		# 改善124: ティアアップ時のタワー位置から放射リング（「強化」の視覚的アンカー）
		var tier_ring := Polygon2D.new()
		var trpts := PackedVector2Array()
		for _tri in range(12):
			trpts.append(Vector2(cos(_tri * TAU / 12.0), sin(_tri * TAU / 12.0)) * 14.0)
		tier_ring.polygon = trpts
		tier_ring.color = tier_color
		tier_ring.global_position = tower.global_position
		tier_ring.z_index = 170
		add_child(tier_ring)
		var rtt := tier_ring.create_tween()
		rtt.set_parallel(true)
		var tier_scale := 3.5 if combo_count < 30 else 5.0
		rtt.tween_property(tier_ring, "scale", Vector2(tier_scale, tier_scale), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		rtt.tween_property(tier_ring, "modulate:a", 0.0, 0.35)
		rtt.chain().tween_callback(tier_ring.queue_free)

func _announce_stage(stage: int) -> void:
	## ステージ遷移告知: プレイヤーに新しい局面を知らせる（J-8: 重要情報を大きく）
	var msgs := ["", "STAGE 2: SURGE!", "STAGE 3: CRISIS!"]
	var colors := [Color.WHITE, Color(1.0, 0.6, 0.15, 1.0), Color(1.0, 0.18, 0.1, 1.0)]
	if stage < 1 or stage >= msgs.size() + 1:
		return
	# 改善182: ステージ警告SE (stage2=0=SURGE, stage3=1=CRISIS)
	SFX.play_stage_alert(stage - 2)  # stage2→0, stage3→1
	# 改善193: STAGE3でインテンスBGMに切替（ボス前の緊張感を音で演出）
	if stage >= 3 and not boss_spawned:
		SFX.switch_bgm("intense")
	var ann := Label.new()
	ann.text = msgs[stage - 1] if stage > 1 else ""
	if ann.text.is_empty():
		ann.queue_free()
		return
	ann.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ann.add_theme_font_size_override("font_size", 40)
	ann.add_theme_color_override("font_color", colors[stage - 1])
	ann.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	ann.add_theme_constant_override("shadow_offset_x", 3)
	ann.add_theme_constant_override("shadow_offset_y", 3)
	ann.custom_minimum_size = Vector2(760, 0)
	ann.position = Vector2(200, 240)
	# 改善90: 大きくスケールインして存在感を強調（「ステージが変わった！」という驚きと緊張）
	ann.scale = Vector2(2.0, 2.0)
	ann.z_index = 200
	ui_layer.add_child(ann)
	var tween := ann.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ann, "position:y", 195.0, 0.38).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(ann, "scale", Vector2(1.0, 1.0), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(ann, "modulate:a", 0.0, 2.5).set_delay(0.85)
	tween.chain().tween_callback(ann.queue_free)
	tower.shake(3.5)
	# 改善153: ステージ遷移時の画面カラーフラッシュ（STAGE2=橙, STAGE3=赤）
	var st_flash := ColorRect.new()
	st_flash.color = Color(colors[stage - 1].r, colors[stage - 1].g, colors[stage - 1].b, 0.22)
	st_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	st_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	st_flash.z_index = 175
	ui_layer.add_child(st_flash)
	var stft := st_flash.create_tween()
	stft.tween_property(st_flash, "color:a", 0.0, 0.6).set_trans(Tween.TRANS_CUBIC)
	stft.tween_callback(st_flash.queue_free)

func _announce_desperate_push() -> void:
	## デスパレートプッシュ告知: 最後15秒の総力戦を伝える（H-1: 緊張の頂点）
	SFX.play_stage_alert(2)  # 改善182: FINAL PUSH急速サイレン
	var ann := Label.new()
	ann.text = "FINAL PUSH!"
	ann.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ann.add_theme_font_size_override("font_size", 44)
	ann.add_theme_color_override("font_color", Color(1.0, 0.18, 0.1, 1.0))
	ann.add_theme_color_override("font_shadow_color", Color(0.6, 0.0, 0.0, 0.9))
	ann.add_theme_constant_override("shadow_offset_x", 4)
	ann.add_theme_constant_override("shadow_offset_y", 4)
	ann.custom_minimum_size = Vector2(760, 0)
	ann.position = Vector2(200, 230)
	# 改善203: FINAL PUSHスケールパンチイン（STAGE 2/3と同様の登場演出 + より大きく）
	# Why: STAGE告知に scale 2.0→1.0 があるのに最重要局面の FINAL PUSH にない。
	# ゲームのクライマックスなので STAGE 告知より誇張した 2.4→1.0 にする。
	ann.scale = Vector2(2.4, 2.4)
	ann.z_index = 200
	ui_layer.add_child(ann)
	var tween := ann.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ann, "position:y", 185.0, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(ann, "scale", Vector2(1.0, 1.0), 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(ann, "modulate:a", 0.0, 3.0).set_delay(1.0)
	tween.chain().tween_callback(ann.queue_free)
	tower.shake(5.0)

	# 改善87: FINAL PUSH時に赤いビネットがフラッシュ（「最終局面」の緊張感を全画面で演出）
	var dp_flash := ColorRect.new()
	dp_flash.color = Color(0.8, 0.0, 0.0, 0.35)
	dp_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	dp_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dp_flash.z_index = 150
	ui_layer.add_child(dp_flash)
	var dp_tween := dp_flash.create_tween()
	dp_tween.tween_property(dp_flash, "color:a", 0.0, 0.8)
	dp_tween.tween_callback(dp_flash.queue_free)

func _show_combo_break(count: int) -> void:
	## コンボ切れ告知: 「あそこでコンボが切れた」という記憶の刻印
	if combo_label_node == null:
		return
	var br := Label.new()
	# 改善85: NEW RECORDなら特別表記（「更新した！」の達成感を強調）
	var is_new_record := (count >= 8 and count == best_combo)
	br.text = "COMBO BREAK  x%d%s" % [count, "  ★BEST!" if is_new_record else ""]
	br.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	br.add_theme_font_size_override("font_size", 13)
	br.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65, 0.75))
	br.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	br.add_theme_constant_override("shadow_offset_x", 1)
	br.add_theme_constant_override("shadow_offset_y", 1)
	br.custom_minimum_size = Vector2(180, 0)
	br.position = combo_label_node.position + Vector2(0, 26)
	br.z_index = 90
	ui_layer.add_child(br)
	var tween := br.create_tween()
	tween.tween_property(br, "modulate:a", 0.0, 1.4).set_delay(0.4)
	tween.chain().tween_callback(br.queue_free)
	# 改善130: 高コンボブレーク時のシェイク（15連続以上が途切れた瞬間の喪失感を体感させる）
	if count >= 15 and is_instance_valid(tower):
		tower.shake(3.5)
	elif count >= 8 and is_instance_valid(tower):
		tower.shake(2.0)
	# 改善156: コンボラベルの崩壊演出（コンボ途切れの「喪失感」を視覚的に伝える）
	if count >= 3 and combo_label_node != null and is_instance_valid(combo_label_node):
		var cl_break_tween := combo_label_node.create_tween()
		cl_break_tween.set_parallel(true)
		cl_break_tween.tween_property(combo_label_node, "modulate", Color(1.0, 0.3, 0.2, 1.0), 0.06)
		cl_break_tween.tween_property(combo_label_node, "scale", Vector2(1.2, 0.7), 0.06).set_trans(Tween.TRANS_BACK)
		cl_break_tween.chain().tween_property(combo_label_node, "modulate", Color.WHITE, 0.25)
		cl_break_tween.chain().tween_property(combo_label_node, "scale", Vector2(0.0, 0.0), 0.12).set_trans(Tween.TRANS_QUAD)
		cl_break_tween.chain().tween_callback(func(): if is_instance_valid(combo_label_node): combo_label_node.scale = Vector2(1.0, 1.0); combo_label_node.visible = false)

# --- タワーイベント ---

var hp_bar_last_value := -1.0  # heal flash検出用
var _hp_danger_tween: Tween = null  # 低HP時のパルスtween（重複防止）
var _berserker_tween: Tween = null  # 改善173: berserker発動中の橙パルス

func _on_tower_damaged(current: float, max_val: float) -> void:
	# Heal flash（HP増加を検出）
	if hp_bar_last_value >= 0 and current > hp_bar_last_value:
		_flash_hp_bar_heal()
	# 被弾: SE + ダメージフラッシュ（白く光る）
	elif hp_bar_last_value >= 0 and current < hp_bar_last_value:
		SFX.play_damage_taken()
		_flash_hp_bar_damage()
		# 改善190: 被弾シェイク（ダメージ割合でスケール: 小=2.5 大=6.0）
		# ダメージの重さを「揺れ」で体感させる。HP比例でスケール。
		var dmg_taken := hp_bar_last_value - current
		var shake_str := clampf(dmg_taken / max_val * 15.0, 2.5, 6.0)
		tower.shake(shake_str)
		var thorns_pct := 0.0
		var thorns_radius := 0.0
		for atk in get_tree().get_nodes_in_group("tower_attacks"):
			var s: Dictionary = atk.get("stats") if atk.get("stats") != null else {}
			var tp: float = s.get("thorns_pct", 0.0)
			if tp > thorns_pct:
				thorns_pct = tp
				thorns_radius = s.get("thorns_radius", 80.0)
		if thorns_pct > 0.0 and thorns_radius > 0.0:
			var thorns_dmg := int(dmg_taken * thorns_pct)
			if thorns_dmg > 0:
				for e in get_tree().get_nodes_in_group("enemies"):
					if is_instance_valid(e) and e.global_position.distance_to(tower.global_position) <= thorns_radius:
						if e.has_method("take_damage"):
							e.take_damage(float(thorns_dmg))
		# 改善121: 被弾時の赤い画面フラッシュ（「痛い！」を全画面で体感）
		var dmg_flash := ColorRect.new()
		dmg_flash.color = Color(0.8, 0.05, 0.05, 0.18)
		dmg_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
		dmg_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dmg_flash.z_index = 160
		ui_layer.add_child(dmg_flash)
		var dft := dmg_flash.create_tween()
		dft.tween_property(dmg_flash, "color:a", 0.0, 0.35).set_trans(Tween.TRANS_QUAD)
		dft.tween_callback(dmg_flash.queue_free)
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

	# 改善193: HP25%以下でインテンスBGMに切替（ボス戦中は変えない）
	if pct <= 0.25 and not boss_spawned:
		SFX.switch_bgm("intense")
	elif pct > 0.40 and not boss_spawned:
		SFX.switch_bgm("battle")

	# Low HP pulse（25%以下でバーの境界線が脈動 + ループアニメ起動）
	var bar_bg := hp_bar.get_theme_stylebox("background") as StyleBoxFlat
	if bar_bg:
		if pct <= 0.25 and pct > 0:
			# 危険: 赤い境界線
			bar_bg.border_color = Color(0.9, 0.2, 0.15, 0.9)
			bar_bg.set_border_width_all(2)
			# ループするパルスアニメ（重複防止: 既存のtwenが動いていれば再起動しない）
			if _hp_danger_tween == null or not _hp_danger_tween.is_running():
				_hp_danger_tween = hp_bar.create_tween()
				_hp_danger_tween.set_loops()
				_hp_danger_tween.tween_property(hp_bar, "modulate", Color(1.3, 0.7, 0.7, 1.0), 0.4).set_trans(Tween.TRANS_SINE)
				_hp_danger_tween.tween_property(hp_bar, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.4).set_trans(Tween.TRANS_SINE)
		elif tower.crush_active:
			# Crush中: 赤い境界線（HP状態と連動）
			bar_bg.border_color = Color(1.0, 0.3, 0.2, 0.7)
			bar_bg.set_border_width_all(2)
		else:
			bar_bg.border_color = Color(0.2, 0.18, 0.3, 0.8)
			bar_bg.set_border_width_all(1)
			# 危険ゾーンを脱出したらパルス停止・色リセット
			if _hp_danger_tween != null and _hp_danger_tween.is_running():
				_hp_danger_tween.kill()
				_hp_danger_tween = null
				hp_bar.modulate = Color(1.0, 1.0, 1.0, 1.0)

	# ビネット更新（改善35）
	_update_vignette(pct)

	# 改善173: berserker発動視覚インジケーター
	# berserker modが装備中かつHP<50%の時、タワービジュアルに橙パルスを表示
	var bz_threshold := 0.0
	for atk in get_tree().get_nodes_in_group("tower_attacks"):
		var s: Dictionary = atk.get("stats") if atk.get("stats") != null else {}
		var bt: float = s.get("berserker_threshold", 0.0)
		if bt > bz_threshold:
			bz_threshold = bt
	var tower_visual := tower.get_node_or_null("Visual") as Node2D
	if tower_visual and bz_threshold > 0.0:
		var berserker_active := pct < bz_threshold
		if berserker_active:
			if _berserker_tween == null or not _berserker_tween.is_running():
				_berserker_tween = tower_visual.create_tween()
				_berserker_tween.set_loops()
				_berserker_tween.tween_property(tower_visual, "modulate", Color(1.5, 0.7, 0.2, 1.0), 0.5).set_trans(Tween.TRANS_SINE)
				_berserker_tween.tween_property(tower_visual, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.5).set_trans(Tween.TRANS_SINE)
		else:
			if _berserker_tween != null and _berserker_tween.is_running():
				_berserker_tween.kill()
				_berserker_tween = null
				tower_visual.modulate = Color.WHITE

func _flash_hp_bar_damage() -> void:
	## 被弾時のバー白フラッシュ（ダメージ感）
	var fill_style := hp_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill_style == null:
		return
	var original := fill_style.bg_color
	fill_style.bg_color = Color(1.5, 1.5, 1.5, 1.0)
	var tween := hp_bar.create_tween()
	tween.tween_property(fill_style, "bg_color", original, 0.15)

func _flash_hp_bar_heal() -> void:
	## HP回復時のバー緑フラッシュ
	## 改善197: スケールバウンス追加（XPバーのレベルアップバウンスと対称、「回復した！」達成感）
	var fill_style := hp_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill_style == null:
		return
	var original := fill_style.bg_color
	fill_style.bg_color = Color(0.3, 0.9, 0.4, 1.0)
	var tween := hp_bar.create_tween()
	tween.tween_property(fill_style, "bg_color", original, 0.2)
	# 改善197: HPバーが縦方向にバウンス（XPバーのTRANS_ELASTICと対称。回復の「ぷよっと感」）
	var bounce := hp_bar.create_tween()
	bounce.tween_property(hp_bar, "scale", Vector2(1.0, 1.35), 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	bounce.tween_property(hp_bar, "scale", Vector2(1.0, 1.0), 0.16).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

func _setup_vignette() -> void:
	## 画面周辺暗化レイヤーを生成（改善35: 低HP危機感の視覚化）
	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.color = Color(0.0, 0.0, 0.0, 0.0)
	_vignette.z_index = 50
	ui_layer.add_child(_vignette)

func _update_vignette(hp_pct: float) -> void:
	## HP割合に応じてビネット透明度を更新（30%以下で出現、0%で最大0.42）
	if _vignette == null or not is_instance_valid(_vignette):
		return
	if hp_pct > 0.30:
		_vignette.color.a = 0.0
		# 改善211: クリティカル離脱 → パルス停止・modulate戻す
		if _vignette_critical:
			_vignette_critical = false
			if _vignette_pulse_tween and _vignette_pulse_tween.is_running():
				_vignette_pulse_tween.kill()
			_vignette.modulate.a = 1.0
	else:
		var intensity := (0.30 - hp_pct) / 0.30 * 0.42
		_vignette.color = Color(0.0, 0.0, 0.0, intensity)
		# 改善211: 低HP鼓動パルス（「もうすぐ死ぬ」緊張感をリズムで体感させる）
		# Why: 静的な暗化より動きのあるパルスの方が「危険」を脳に強く刻む。
		# 初入時のみ開始し、ループ継続。HP回復で自動停止。
		if not _vignette_critical:
			_vignette_critical = true
			_vignette_pulse_tween = _vignette.create_tween()
			_vignette_pulse_tween.set_loops()
			_vignette_pulse_tween.tween_property(_vignette, "modulate:a", 0.4, 0.55).set_trans(Tween.TRANS_SINE)
			_vignette_pulse_tween.tween_property(_vignette, "modulate:a", 1.0, 0.38).set_trans(Tween.TRANS_SINE)

func _on_xp_gained(total_xp: int, current_level: int) -> void:
	var next_xp: int = tower.get_xp_for_next_level()
	wave_label.text = "Lv.%d  XP: %d/%d" % [current_level, total_xp, next_xp]
	# XPバー更新
	if xp_bar:
		xp_bar.max_value = next_xp
		xp_bar.value = total_xp
		# もうすぐレベルアップグロー（80%以上: XPバーを金色にして「もうすぐ！」感を演出）
		var xp_fill := xp_bar.get_theme_stylebox("fill") as StyleBoxFlat
		if xp_fill:
			var xp_ratio := float(total_xp) / float(next_xp) if next_xp > 0 else 0.0
			if xp_ratio >= 0.85:
				xp_fill.bg_color = Color(1.0, 0.85, 0.25, 0.9)  # 金色: ほぼ満タン
			elif xp_ratio >= 0.65:
				xp_fill.bg_color = Color(0.5, 0.95, 0.5, 0.85)  # 明るい緑
			else:
				xp_fill.bg_color = Color(0.35, 0.85, 0.45, 0.8)  # 標準緑
		# 改善84: XP取得ごとにバーが一瞬輝く（「集めている！」の即時フィードバック）
		var xp_flash := xp_bar.create_tween()
		xp_flash.tween_property(xp_bar, "modulate", Color(1.5, 2.0, 1.5, 1.0), 0.06)
		xp_flash.tween_property(xp_bar, "modulate", Color.WHITE, 0.14)

func _on_crush_changed(active: bool, count: int) -> void:
	if active:
		crush_label.text = "SURROUNDED x%d" % count
		crush_label.visible = true
		# 包囲開始: 警告シェイク + 改善188 CRUSH SE
		SFX.play_crush_start()
		tower.shake(4.0)
		# Warning labelは非表示に（crushが上位表示）
		if crush_warning_label:
			crush_warning_label.visible = false
		# 改善93: CRUSH開始時に画面が赤くフラッシュ（「包囲された！」の緊急性を全画面で伝える）
		var crush_flash := ColorRect.new()
		crush_flash.color = Color(0.8, 0.0, 0.0, 0.28)
		crush_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
		crush_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		crush_flash.z_index = 160
		ui_layer.add_child(crush_flash)
		var cf_tween := crush_flash.create_tween()
		cf_tween.tween_property(crush_flash, "color:a", 0.0, 0.6)
		cf_tween.tween_callback(crush_flash.queue_free)
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
	## Breakout burst VFX: 金色の衝撃波リング + 改善188 BREAKOUT SE
	SFX.play_breakout()
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

	# 改善67: 2本目シアンリング（やや遅れて展開 → 層状の衝撃波で迫力増幅）
	var ring2 := Polygon2D.new()
	var pts2: PackedVector2Array = []
	for i in range(24):
		var a := i * TAU / 24
		pts2.append(Vector2(cos(a), sin(a)) * 15.0)
	ring2.polygon = pts2
	ring2.color = Color(0.3, 0.9, 1.0, 0.55)
	ring2.global_position = tower.global_position
	ring2.z_index = 138
	add_child(ring2)
	var tween2 := ring2.create_tween()
	tween2.set_parallel(true)
	var target_scale2: float = tower.CRUSH_BREAKOUT_RADIUS / 15.0 * 1.3
	tween2.tween_property(ring2, "scale", Vector2(target_scale2, target_scale2), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT).set_delay(0.08)
	tween2.tween_property(ring2, "modulate:a", 0.0, 0.5).set_delay(0.08)
	tween2.chain().tween_callback(ring2.queue_free)

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
		# 改善134: XPバーのスケールバウンス（「満タンになって弾けた！」の感触）
		var xb_tween := xp_bar.create_tween()
		xb_tween.tween_property(xp_bar, "scale", Vector2(1.0, 1.5), 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		xb_tween.tween_property(xp_bar, "scale", Vector2(1.0, 1.0), 0.15).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

	# 改善62: レベルアップ時タワーが金色フラッシュ（「強くなった！」瞬間の視覚的報酬）
	if is_instance_valid(tower):
		tower.modulate = Color(3.0, 2.5, 0.5, 1.0)
		var lv_tween := tower.create_tween()
		lv_tween.tween_property(tower, "modulate", Color.WHITE, 0.45)

	# レベルアップフラッシュVFX
	_spawn_levelup_vfx()

	# 改善116: 全画面黄金パルスオーバーレイ（達成感を全身で体感させる）
	var lv_glow := ColorRect.new()
	lv_glow.color = Color(0.9, 0.75, 0.15, 0.20)
	lv_glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	lv_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lv_glow.z_index = 148
	ui_layer.add_child(lv_glow)
	var lv_glow_t := lv_glow.create_tween()
	lv_glow_t.tween_property(lv_glow, "color:a", 0.0, 0.5).set_trans(Tween.TRANS_QUAD)
	lv_glow_t.tween_callback(lv_glow.queue_free)

	# 改善160: "LEVEL UP! Lv.N" フローティングテキスト（「強くなった！」の言語的確認）
	var lv_label := Label.new()
	lv_label.text = "LEVEL UP!  Lv.%d" % new_level
	lv_label.add_theme_font_size_override("font_size", 28)
	lv_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.35, 1.0))
	lv_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	lv_label.add_theme_constant_override("shadow_offset_x", 2)
	lv_label.add_theme_constant_override("shadow_offset_y", 2)
	lv_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv_label.position = Vector2(640 - 180, 310)
	lv_label.custom_minimum_size = Vector2(360, 0)
	lv_label.z_index = 195
	ui_layer.add_child(lv_label)
	var lv_lt := lv_label.create_tween()
	lv_lt.tween_property(lv_label, "scale", Vector2(1.25, 1.25), 0.1).set_trans(Tween.TRANS_BACK)
	lv_lt.tween_property(lv_label, "scale", Vector2(1.0, 1.0), 0.1)
	lv_lt.tween_interval(0.65)
	lv_lt.tween_property(lv_label, "modulate:a", 0.0, 0.4)
	lv_lt.tween_callback(lv_label.queue_free)

func _apply_levelup_stat(stat_id: String) -> void:
	# スタット名と確認テキストのマップ（改善43: 選んだ効果を即時フィードバック）
	var stat_labels := {
		"damage": "ATK +25%", "fire_rate": "SPD +20%", "projectile": "+1 SHOT",
		"move_speed": "MOV +15%", "max_hp": "HP +50", "attract": "RANGE +"
	}
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

	# フローティング確認テキスト（改善43）
	if stat_id in stat_labels:
		_spawn_stat_text(stat_labels[stat_id])

func _spawn_stat_text(text: String) -> void:
	## スタット強化確認テキスト（改善43: 選択結果を画面中央で一瞬表示）
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6, 1.0))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(640 - 120, 300)
	label.custom_minimum_size = Vector2(240, 0)
	label.z_index = 210
	# 改善209: 強化確認テキストのスケールポップイン（「決まった！」を一撃で伝える）
	# Why: 今まで instant表示で浮かびあがるだけ。0.3→1.5→1.0のポップで「選択が確定した」感を強化。
	label.scale = Vector2(0.3, 0.3)
	ui_layer.add_child(label)
	var tween := label.create_tween()
	# まずスケールポップ（sequential）
	tween.tween_property(label, "scale", Vector2(1.5, 1.5), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "scale", Vector2(1.0, 1.0), 0.1).set_trans(Tween.TRANS_QUAD)
	# ポップ後: 浮上 + フェードアウトを並行
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 50.0, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.35)
	tween.chain().tween_callback(label.queue_free)

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

	# "LEVEL UP!" テキスト（J-8: 重要情報は大きく）
	var lv_label := Label.new()
	lv_label.text = "LEVEL UP!"
	lv_label.add_theme_font_size_override("font_size", 32)
	lv_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.3, 1.0))
	lv_label.add_theme_color_override("font_shadow_color", Color(0.4, 0.2, 0.0, 0.9))
	lv_label.add_theme_constant_override("shadow_offset_x", 2)
	lv_label.add_theme_constant_override("shadow_offset_y", 2)
	lv_label.z_index = 200
	lv_label.global_position = tower.global_position + Vector2(-60, -80)
	add_child(lv_label)
	var lv_tween := lv_label.create_tween()
	lv_tween.set_parallel(true)
	lv_tween.tween_property(lv_label, "global_position:y", lv_label.global_position.y - 60, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	lv_tween.tween_property(lv_label, "scale", Vector2(1.4, 1.4), 0.12).set_trans(Tween.TRANS_BACK)
	lv_tween.chain().tween_property(lv_label, "scale", Vector2(1.0, 1.0), 0.1)
	lv_tween.chain().tween_property(lv_label, "modulate:a", 0.0, 0.4).set_delay(0.3)
	lv_tween.chain().tween_callback(lv_label.queue_free)

func _show_pressure_label() -> void:
	## 改善118: 敵数圧力インジケーター（12体以上の状況での緊張感強化）
	if _pressure_label and is_instance_valid(_pressure_label):
		_pressure_label.visible = true
		return
	_pressure_label = Label.new()
	_pressure_label.text = "⚠ PRESSURE"
	_pressure_label.add_theme_font_size_override("font_size", 14)
	_pressure_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.15, 1.0))
	_pressure_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_pressure_label.add_theme_constant_override("shadow_offset_x", 1)
	_pressure_label.add_theme_constant_override("shadow_offset_y", 1)
	_pressure_label.position = Vector2(640, 96)
	_pressure_label.z_index = 175
	ui_layer.add_child(_pressure_label)
	# ゆっくり点滅
	var pt := _pressure_label.create_tween()
	pt.set_loops()
	pt.tween_property(_pressure_label, "modulate:a", 0.4, 0.5).set_trans(Tween.TRANS_SINE)
	pt.tween_property(_pressure_label, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE)

func _announce_overtime() -> void:
	## 改善128: 9分到達でOVERTIME告知（「あと1分！ゴールは近い」）
	var lbl := Label.new()
	lbl.text = "OVERTIME!"
	lbl.add_theme_font_size_override("font_size", 36)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.7, 0.1, 1.0))
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("shadow_offset_x", 3)
	lbl.add_theme_constant_override("shadow_offset_y", 3)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.custom_minimum_size = Vector2(760, 0)
	lbl.position = Vector2(200, 270)
	lbl.z_index = 180
	# 改善208: OVERTIMEスケールパンチイン（「残り1分！」の緊張感を登場演出で最大化）
	lbl.scale = Vector2(2.2, 2.2)
	ui_layer.add_child(lbl)
	tower.shake(5.0)
	var t := lbl.create_tween()
	t.tween_property(lbl, "scale", Vector2(1.0, 1.0), 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.set_parallel(true)
	t.tween_property(lbl, "position:y", 230.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(lbl, "modulate:a", 0.0, 2.0).set_delay(0.6)
	t.chain().tween_callback(lbl.queue_free)

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
	# 改善217: 距離マイルストーンのスケールパンチイン（STAGE/OVERTIME等と一貫した「到達の一撃」）
	# Why: フェードイン+微小バウンス（1.0→1.15）は他の告知ラベルと比べて存在感が薄かった。
	# 100m/200m/300m達成は明確な節目なので scale 2.0→1.0 TRANS_BACK で「到達した！」を体感させる。
	label.scale = Vector2(2.0, 2.0)
	ui_layer.add_child(label)

	var tween := label.create_tween()
	tween.tween_property(label, "scale", Vector2(1.0, 1.0), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
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

	# マイルストーンにスクリーンシェイク（改善49: 距離達成の重み）
	tower.shake(4.0)

func _on_tower_destroyed() -> void:
	# 改善151: ゲームオーバー時の赤フラッシュ＋破壊パーティクル（「敗北の衝撃」を体感させる）
	var death_flash := ColorRect.new()
	death_flash.color = Color(0.9, 0.05, 0.05, 0.55)
	death_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	death_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	death_flash.z_index = 180
	ui_layer.add_child(death_flash)
	var dft := death_flash.create_tween()
	dft.tween_property(death_flash, "color:a", 0.0, 1.2).set_trans(Tween.TRANS_CUBIC)
	dft.tween_callback(death_flash.queue_free)
	# 破壊パーティクル（タワー位置から放射状に赤いシャード）
	if is_instance_valid(tower):
		for _di in range(16):
			var da := float(_di) * TAU / 16.0
			var dp := Polygon2D.new()
			dp.polygon = PackedVector2Array([Vector2(-2.0, 0), Vector2(2.0, 0), Vector2(0, -6.0)])
			dp.color = Color(1.0, 0.15 + randf() * 0.3, 0.1, 0.9)
			dp.rotation = da
			dp.global_position = tower.global_position
			dp.z_index = 202
			add_child(dp)
			var dt := dp.create_tween()
			dt.set_parallel(true)
			dt.tween_property(dp, "global_position",
				tower.global_position + Vector2(cos(da), sin(da)) * randf_range(60.0, 140.0), 0.8
			).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			dt.tween_property(dp, "modulate:a", 0.0, 0.8).set_delay(0.2)
			dt.chain().tween_callback(dp.queue_free)
	game_over = true
	_reset_time_scale()
	SFX.stop_bgm()
	SFX.play_game_over()  # 改善178: 下降スイープで敗北の重さを演出
	_show_result_screen(false)

func _win_game() -> void:
	game_over = true
	_reset_time_scale()
	SFX.stop_bgm()
	SFX.play_victory()  # 改善179: 上昇ファンファーレで勝利の喜びを音で完結
	_show_result_screen(true)

func _show_result_screen(is_victory: bool) -> void:
	## リザルト画面: 暗転 → タイトル → スタッツ → リトライ
	_save_unlocked_chips()
	# 改善177: クロスランベストレコード確認 + 保存
	# Why: ランをまたいで記録を残すことで「もう一度！」の動機を生む
	var save_mgr_rec := get_node_or_null("/root/SaveManager")
	var broken_records: Array[String] = []
	if save_mgr_rec and save_mgr_rec.has_method("update_best_records"):
		broken_records = save_mgr_rec.update_best_records(kill_count, best_combo, run_time, current_stage)
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
	# 改善191: スケールパンチイン（小さくからじゃなくて大きくから縮む「パンチ感」）
	title.scale = Vector2(1.35, 1.35)
	vbox.add_child(title)

	# 区切り線
	var sep := HSeparator.new()
	sep.custom_minimum_size = Vector2(300, 2)
	sep.modulate.a = 0.0
	vbox.add_child(sep)

	# 改善88: スター評価（キル数で1〜3段階。「また挑戦したい」動機付け）
	var star_count := 1
	if kill_count >= 75:
		star_count = 3
	elif kill_count >= 25:
		star_count = 2
	var star_lbl := Label.new()
	star_lbl.text = "★".repeat(star_count) + "☆".repeat(3 - star_count)
	star_lbl.add_theme_font_size_override("font_size", 36)
	star_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2, 1.0))
	star_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	star_lbl.add_theme_constant_override("shadow_offset_x", 2)
	star_lbl.add_theme_constant_override("shadow_offset_y", 2)
	star_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	star_lbl.modulate.a = 0.0
	# 改善202: スケールポップイン準備（小さく始める）
	star_lbl.scale = Vector2(0.4, 0.4)
	vbox.add_child(star_lbl)

	# スタッツ
	var distance_m: float = float(tower.distance_traveled) / 10.0
	var time_sec := int(run_time)
	@warning_ignore("integer_division")
	var t_min := time_sec / 60
	var t_sec := time_sec % 60
	# stat_labelsをここで宣言: NEW RECORDバナー追加より前に初期化が必要
	var stat_labels: Array[Label] = []
	var stat_color := Color(0.85, 0.82, 0.92, 1.0)

	# 改善177: NEW RECORD!バナー（1件以上の記録更新があった場合）
	if broken_records.size() > 0:
		var nr_lbl := Label.new()
		nr_lbl.text = "★ NEW PERSONAL BEST! ★"
		nr_lbl.add_theme_font_size_override("font_size", 26)
		nr_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.1, 1.0))
		nr_lbl.add_theme_color_override("font_shadow_color", Color(0.5, 0.2, 0.0, 0.9))
		nr_lbl.add_theme_constant_override("shadow_offset_x", 2)
		nr_lbl.add_theme_constant_override("shadow_offset_y", 2)
		nr_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nr_lbl.modulate.a = 0.0
		vbox.add_child(nr_lbl)
		stat_labels.append(nr_lbl)

	# 改善76: Stage Reached をリザルトに追加（ゲームの進行感を数値で示す）
	# 改善177: 記録更新した項目に「★NEW!」サフィックス付与
	var _kills_str := "%d" % kill_count
	if "kills" in broken_records: _kills_str += "  ★NEW!"
	var _combo_str := "x%d" % best_combo
	if "combo" in broken_records: _combo_str += "  ★NEW!"
	var _time_str := "%d:%02d" % [t_min, t_sec]
	if "time" in broken_records: _time_str += "  ★NEW!"
	var _stage_str := "Stage %d" % current_stage
	if "stage" in broken_records: _stage_str += "  ★NEW!"
	var stats_data: Array[Array] = [
		["Distance", "%dm" % int(distance_m)],
		["Stage Reached", _stage_str],
		["Level", "%d" % tower.level],
		["Kills", _kills_str],
		["Best Combo", _combo_str],
		["Damage Dealt", "%d" % int(total_damage_dealt)],  # 改善162: 総ダメージ量
		["DPS", "%.1f" % (total_damage_dealt / maxf(float(time_sec), 1.0))],  # 改善163: DPS（連続性の指標）
		["Time", _time_str],
	]

	for stat in stats_data:
		var lbl := Label.new()
		lbl.text = "%s:  %s" % [stat[0], stat[1]]
		lbl.add_theme_font_size_override("font_size", 24)
		# 改善99: Best Combo の数値を色分け（金=10+, ピンク=30+, 通常=灰）
		var lbl_color := stat_color
		if stat[0] == "Best Combo":
			if best_combo >= 30:
				lbl_color = Color(1.0, 0.3, 0.85, 1.0)  # ピンク: GODLIKE域
			elif best_combo >= 10:
				lbl_color = Color(1.0, 0.82, 0.2, 1.0)  # 金: 高コンボ達成
		lbl.add_theme_color_override("font_color", lbl_color)
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

	# Ko-fi CTA — 応援リンクを目立たせすぎず添える
	var cta_spacer := Control.new()
	cta_spacer.custom_minimum_size = Vector2(0, 14)
	vbox.add_child(cta_spacer)

	var cta_lbl := Label.new()
	cta_lbl.text = "☕ Enjoyed the game? Support dev → ko-fi.com/yurukusa"
	cta_lbl.add_theme_font_size_override("font_size", 15)
	cta_lbl.add_theme_color_override("font_color", Color(0.85, 0.75, 0.55, 1.0))
	cta_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	cta_lbl.add_theme_constant_override("shadow_offset_x", 1)
	cta_lbl.add_theme_constant_override("shadow_offset_y", 1)
	cta_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cta_lbl.modulate.a = 0.0
	vbox.add_child(cta_lbl)

	# 改善191: タイトルのスケールパンチイン（1.35→1.0 TRANS_BACK、フェードと並行）
	var title_punch := title.create_tween()
	title_punch.tween_property(title, "scale", Vector2(1.0, 1.0), 0.4).set_delay(0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# 順番にフェードインするアニメーション
	var anim := create_tween()
	anim.tween_property(title, "modulate:a", 1.0, 0.3).set_delay(0.5)
	anim.tween_property(sep, "modulate:a", 0.4, 0.2)
	anim.tween_property(star_lbl, "modulate:a", 1.0, 0.2)
	# 改善202: スター評価スケールポップ（フェードと同時にばね感のあるポップイン）
	# Why: ★★★評価は最重要フィードバック。フェードだけでは埋もれる。TRANS_BACKで瞬間的な達成感を演出。
	anim.tween_callback(func():
		var sp := star_lbl.create_tween()
		sp.tween_property(star_lbl, "scale", Vector2(1.25, 1.25), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		sp.tween_property(star_lbl, "scale", Vector2(1.0, 1.0), 0.1).set_trans(Tween.TRANS_QUAD)
	)
	# 改善198: ★NEW!付きラベルをフェードイン後にスケールポップ（「新記録！」の瞬間を強調）
	# Why: 全ラベルが均等にフェードインするだけだと新記録ラベルが埋もれる。ポップで目立たせる。
	for lbl in stat_labels:
		anim.tween_property(lbl, "modulate:a", 1.0, 0.15)
		if lbl is Label and "★NEW!" in (lbl as Label).text:
			var captured_lbl := lbl as Label
			anim.tween_callback(func():
				var pt := captured_lbl.create_tween()
				pt.tween_property(captured_lbl, "scale", Vector2(1.12, 1.12), 0.07).set_trans(Tween.TRANS_BACK)
				pt.tween_property(captured_lbl, "scale", Vector2(1.0, 1.0), 0.09)
			)
	anim.tween_property(retry, "modulate:a", 1.0, 0.3).set_delay(0.3)
	anim.tween_property(cta_lbl, "modulate:a", 0.75, 0.4).set_delay(0.5)

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
