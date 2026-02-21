extends Node

## WaveManager - Wave制御。Wave 1-20、各Waveで敵数増加。
## v0.4: 敵タイプ混合スポーン（swarmer/tank/shooter/splitter/healer）

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

	# 敵数: Wave * 3 + 2（後半はさらに増加）
	var enemy_count := current_wave * 3 + 2
	if current_wave > 10:
		enemy_count += (current_wave - 10) * 2
	enemies_alive = enemy_count

	# タイプ混合テーブル: waveに応じて出現タイプと割合を決定
	var type_pool := _get_wave_type_pool()

	for i in range(enemy_count):
		var enemy_type := _pick_type(type_pool)
		_spawn_enemy(enemy_type)

## Wave毎の敵タイプ出現テーブル
## [{"type": String, "weight": int}] の配列を返す
func _get_wave_type_pool() -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	# normalは常に出現
	pool.append({"type": "normal", "weight": 100})

	# Wave 3+: swarmer（速くて弱い群体）
	if current_wave >= 3:
		pool.append({"type": "swarmer", "weight": 40 + current_wave * 3})

	# Wave 5+: shooter（遠距離攻撃、距離を保つ）
	if current_wave >= 5:
		pool.append({"type": "shooter", "weight": 25 + current_wave * 2})

	# Wave 8+: tank（硬くて遅い）
	if current_wave >= 8:
		pool.append({"type": "tank", "weight": 15 + current_wave})

	# Wave 10+: splitter（死亡時にswarmer×2に分裂）
	if current_wave >= 10:
		pool.append({"type": "splitter", "weight": 15 + (current_wave - 10) * 3})

	# Wave 12+: healer（近くの味方を回復）
	if current_wave >= 12:
		pool.append({"type": "healer", "weight": 10 + (current_wave - 12) * 2})

	# Wave 18+: phantom（周期的無敵フェーズ。v0.9.7: Stage3体験の差別化）
	# Why: Wave15-20は全体の20%を占めるがプレイ感が単調。phantomは「数値スケール」
	# ではなく「行動パターン変化」で難度を上げる。エリート50%と相乗効果。
	if current_wave >= 18:
		pool.append({"type": "phantom", "weight": 20 + (current_wave - 18) * 8})

	return pool

func _pick_type(pool: Array[Dictionary]) -> String:
	var total := 0
	for entry in pool:
		total += entry.get("weight", 0)
	var roll := randi() % maxi(total, 1)
	var cumulative := 0
	for entry in pool:
		cumulative += entry.get("weight", 0)
		if roll < cumulative:
			return entry["type"]
	return "normal"

func _spawn_enemy(type: String = "normal") -> void:
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

	# Wave に応じてスケール（線形+二次曲線でプレイヤー火力に追従）
	var hp_scale := 1.0 + (current_wave - 1) * 0.2
	if current_wave > 5:
		hp_scale += pow((current_wave - 5) * 0.15, 2)
	var speed_scale := 1.0 + (current_wave - 1) * 0.05

	enemy.init(player, 80.0 * speed_scale, 30.0 * hp_scale, 10.0, type, current_wave)

	# Wave段階に応じたテクスチャ割り当て
	var tex_index := 0
	if current_wave >= 15:
		tex_index = 2
	elif current_wave >= 8:
		tex_index = 1
	if not enemy_textures.is_empty():
		enemy.set_texture(enemy_textures[tex_index])

	enemy.died.connect(_on_enemy_died)

	# splitter死亡時にswarmerを生成するシグナル接続
	if type == "splitter" and enemy.has_signal("split_on_death"):
		enemy.split_on_death.connect(_on_splitter_died)

	get_tree().current_scene.add_child(enemy)

func _on_enemy_died(_enemy: Node2D) -> void:
	enemies_alive -= 1
	if enemies_alive <= 0 and wave_active:
		wave_active = false
		wave_cleared.emit(current_wave)

		# 次のWaveまで少し待つ
		if not is_inside_tree():
			return
		await get_tree().create_timer(1.5).timeout
		if not is_inside_tree():
			return
		_next_wave()

func _on_splitter_died(pos: Vector2) -> void:
	# splitter死亡時: swarmer×2をスポーン（enemies_aliveに加算）
	for i in range(2):
		if enemy_scene == null:
			return
		var swarmer := enemy_scene.instantiate() as CharacterBody2D
		swarmer.position = pos + Vector2(randf_range(-20, 20), randf_range(-20, 20))
		var hp_scale := 1.0 + (current_wave - 1) * 0.2
		if current_wave > 5:
			hp_scale += pow((current_wave - 5) * 0.15, 2)
		var speed_scale := 1.0 + (current_wave - 1) * 0.05
		swarmer.init(player, 80.0 * speed_scale, 30.0 * hp_scale, 10.0, "swarmer")
		swarmer.died.connect(_on_enemy_died)
		enemies_alive += 1
		get_tree().current_scene.add_child(swarmer)
