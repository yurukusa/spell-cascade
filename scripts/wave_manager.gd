extends Node

## WaveManager - Wave制御。Wave 1-20、各Waveで敵数増加。

signal wave_started(wave_num: int)
signal wave_cleared(wave_num: int)
signal all_waves_cleared

@export var enemy_scene: PackedScene

var current_wave := 0
var max_waves := 20
var enemies_alive := 0
var wave_active := false
var player: Node2D
var spawn_area: Rect2

# Wave段階に応じた敵テクスチャ
var enemy_textures: Array[Texture2D] = []

func _ready() -> void:
	# スポーンエリアはビューポートの外周
	var vp := get_tree().root.get_visible_rect().size
	spawn_area = Rect2(Vector2.ZERO, vp)

	# 敵テクスチャをロード（スライム→デーモン→ゴースト）
	enemy_textures = [
		load("res://assets/kenney-tiny-dungeon/tile_0108.png"),  # 緑スライム (Wave 1-7)
		load("res://assets/kenney-tiny-dungeon/tile_0110.png"),  # 赤デーモン (Wave 8-14)
		load("res://assets/kenney-tiny-dungeon/tile_0121.png"),  # ゴースト (Wave 15-20)
	]

func start(target_player: Node2D) -> void:
	player = target_player
	current_wave = 0
	_next_wave()

func _next_wave() -> void:
	current_wave += 1
	if current_wave > max_waves:
		all_waves_cleared.emit()
		return

	wave_active = true
	wave_started.emit(current_wave)

	# 敵数: Wave * 3 + 2
	var enemy_count := current_wave * 3 + 2
	enemies_alive = enemy_count

	for i in range(enemy_count):
		_spawn_enemy()

func _spawn_enemy() -> void:
	if enemy_scene == null:
		return

	var enemy := enemy_scene.instantiate() as CharacterBody2D

	# スポーン位置: 画面外の端からランダム
	var vp := get_tree().root.get_visible_rect().size
	var side := randi() % 4
	var spawn_pos := Vector2.ZERO

	match side:
		0: # 上
			spawn_pos = Vector2(randf_range(0, vp.x), -40)
		1: # 下
			spawn_pos = Vector2(randf_range(0, vp.x), vp.y + 40)
		2: # 左
			spawn_pos = Vector2(-40, randf_range(0, vp.y))
		3: # 右
			spawn_pos = Vector2(vp.x + 40, randf_range(0, vp.y))

	enemy.position = spawn_pos

	# Wave に応じてスケール
	var hp_scale := 1.0 + (current_wave - 1) * 0.15
	var speed_scale := 1.0 + (current_wave - 1) * 0.05

	enemy.init(player, 80.0 * speed_scale, 30.0 * hp_scale, 10.0)

	# Wave段階に応じたテクスチャ割り当て
	var tex_index := 0
	if current_wave >= 15:
		tex_index = 2
	elif current_wave >= 8:
		tex_index = 1
	if not enemy_textures.is_empty():
		enemy.set_texture(enemy_textures[tex_index])

	enemy.died.connect(_on_enemy_died)

	get_tree().current_scene.add_child(enemy)

func _on_enemy_died(_enemy: Node2D) -> void:
	enemies_alive -= 1
	if enemies_alive <= 0 and wave_active:
		wave_active = false
		wave_cleared.emit(current_wave)

		# 次のWaveまで少し待つ
		await get_tree().create_timer(1.5).timeout
		_next_wave()
