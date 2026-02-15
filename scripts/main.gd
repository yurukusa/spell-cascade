extends Node2D

## Main - ゲームのエントリーポイント。
## プレイヤー、敵スポーン、Wave管理、UI、オーブ選択、タイマーを統合。

@onready var player: CharacterBody2D = $Player
@onready var wave_manager: Node = $WaveManager
@onready var ui_layer: CanvasLayer = $UI
@onready var hp_bar: ProgressBar = $UI/HPBar
@onready var wave_label: Label = $UI/WaveLabel
@onready var timer_label: Label = $UI/TimerLabel
@onready var orb_label: Label = $UI/OrbLabel
@onready var restart_label: Label = $UI/RestartLabel

var upgrade_ui: Node  # UpgradeUI (CanvasLayer)
var run_time := 0.0
var max_run_time := 600.0  # 10分
var game_over := false
var player_orbs: Array[int] = []  # OrbData.OrbType のリスト

func _ready() -> void:
	# プレイヤーのシグナル接続
	player.hp_changed.connect(_on_player_hp_changed)
	player.died.connect(_on_player_died)

	# Wave管理
	wave_manager.wave_started.connect(_on_wave_started)
	wave_manager.wave_cleared.connect(_on_wave_cleared)
	wave_manager.all_waves_cleared.connect(_on_all_waves_cleared)

	# UpgradeUI生成（CanvasLayerベース）
	var upgrade_script := load("res://scripts/upgrade_ui.gd")
	upgrade_ui = CanvasLayer.new()
	upgrade_ui.set_script(upgrade_script)
	upgrade_ui.name = "UpgradeUI"
	add_child(upgrade_ui)
	upgrade_ui.orb_selected.connect(_on_orb_selected)

	# UI初期化
	hp_bar.max_value = player.max_hp
	hp_bar.value = player.max_hp
	restart_label.visible = false

	# ゲーム開始
	wave_manager.start(player)

func _process(delta: float) -> void:
	if game_over:
		return

	# ランタイマー
	run_time += delta
	_update_timer_display()

	# 10分経過 → 勝利
	if run_time >= max_run_time:
		_win_game()

func _update_timer_display() -> void:
	var remaining := max_run_time - run_time
	if remaining < 0:
		remaining = 0
	var total_sec := floori(remaining)
	var minutes := total_sec / 60
	var seconds := total_sec % 60
	timer_label.text = "%d:%02d" % [minutes, seconds]

func _update_orb_display() -> void:
	if player_orbs.is_empty():
		orb_label.text = ""
		return

	var names: PackedStringArray = []
	for orb_type in player_orbs:
		var info = OrbData.get_orb(orb_type)
		if info:
			names.append(info.name)
	orb_label.text = "Orbs: " + ", ".join(names)

	# シナジーチェック
	var synergies = OrbData.check_synergies(player_orbs)
	if not synergies.is_empty():
		var syn_names: PackedStringArray = []
		for s in synergies:
			syn_names.append(s.name)
		orb_label.text += "\nSynergy: " + ", ".join(syn_names)

func _on_orb_selected(orb_type: int) -> void:
	player_orbs.append(orb_type)
	_apply_orb_effect(orb_type)
	_update_orb_display()

func _apply_orb_effect(orb_type: int) -> void:
	var info = OrbData.get_orb(orb_type)
	if info == null:
		return

	var effect: Dictionary = info.effect
	var auto_attack := player.get_node("AutoAttack")

	# 攻撃速度倍率
	if effect.has("attack_speed_mult"):
		auto_attack.fire_rate /= effect["attack_speed_mult"]

	# ダメージ倍率
	if effect.has("damage_mult"):
		auto_attack.bullet_damage *= effect["damage_mult"]

	# HP回復（process内で毎フレーム回復する仕組みは後で追加）

func _on_player_hp_changed(current: float, _maximum: float) -> void:
	hp_bar.value = current

func _on_player_died() -> void:
	game_over = true
	wave_label.text = "GAME OVER"
	restart_label.visible = true
	restart_label.text = "Press R to Restart"

func _on_wave_started(wave_num: int) -> void:
	wave_label.text = "Wave %d / 20" % wave_num

func _on_wave_cleared(wave_num: int) -> void:
	wave_label.text = "Wave %d Cleared!" % wave_num

	# 3択のオーブ選択を表示
	var choices = OrbData.get_random_orbs(3)
	if not choices.is_empty():
		upgrade_ui.show_choices(choices)

func _on_all_waves_cleared() -> void:
	_win_game()

func _win_game() -> void:
	game_over = true
	wave_label.text = "YOU WIN!"
	restart_label.visible = true
	restart_label.text = "Press R to Restart"

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		# Rキーでリスタート
		if event.keycode == KEY_R and game_over:
			get_tree().paused = false
			get_tree().reload_current_scene()
		# Escキーで一時停止トグル
		elif event.keycode == KEY_ESCAPE and not game_over:
			get_tree().paused = not get_tree().paused
			if get_tree().paused:
				wave_label.text = "PAUSED"
			else:
				wave_label.text = "Wave %d / 20" % wave_manager.current_wave
