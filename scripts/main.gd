extends Node2D

## Main - ゲームのエントリーポイント。
## プレイヤー、敵スポーン、Wave管理、UIを統合。

@onready var player: CharacterBody2D = $Player
@onready var wave_manager: Node = $WaveManager
@onready var ui_layer: CanvasLayer = $UI
@onready var hp_bar: ProgressBar = $UI/HPBar
@onready var wave_label: Label = $UI/WaveLabel

func _ready() -> void:
	# プレイヤーのシグナル接続
	player.hp_changed.connect(_on_player_hp_changed)
	player.died.connect(_on_player_died)

	# Wave開始
	wave_manager.wave_started.connect(_on_wave_started)
	wave_manager.wave_cleared.connect(_on_wave_cleared)
	wave_manager.all_waves_cleared.connect(_on_all_waves_cleared)

	# UI初期化
	hp_bar.max_value = player.max_hp
	hp_bar.value = player.max_hp

	# ゲーム開始
	wave_manager.start(player)

func _on_player_hp_changed(current: float, _maximum: float) -> void:
	hp_bar.value = current

func _on_player_died() -> void:
	wave_label.text = "GAME OVER"
	get_tree().paused = true

func _on_wave_started(wave_num: int) -> void:
	wave_label.text = "Wave %d / 20" % wave_num

func _on_wave_cleared(wave_num: int) -> void:
	wave_label.text = "Wave %d Cleared!" % wave_num

func _on_all_waves_cleared() -> void:
	wave_label.text = "YOU WIN!"
	get_tree().paused = true
