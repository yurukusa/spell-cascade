extends Node2D

## ProceduralBackground - 縦スクロール用の手続き型背景。
## カメラ移動に応じてダンジョンの床タイルを生成・破棄。
## v0.9: Kenney tiny-dungeon タイルテクスチャ使用。
## z_index = -100 で全ゲーム要素の背後に描画。

# Kenney tiny-dungeon floor tile textures (16x16, CC0)
# Stone floor variations — deterministic selection per tile position
var _floor_textures: Array[Texture2D] = []

# タイル管理
const TILE_SIZE := 128.0  # 1タイルの大きさ（px）
const COLS := 12  # 画面幅1280/128 ≈ 10、余裕込みで12
const VISIBLE_ROWS := 8  # 画面高720/128 ≈ 6、余裕込みで8
const CLEANUP_DISTANCE := 600.0  # カメラからこれ以上離れたら削除

var camera_ref: Camera2D = null
var generated_rows: Dictionary = {}  # row_index → Node2D (row container)
var last_camera_y := INF  # 最後にチェックしたカメラY（上方向=負）

# 装飾パターンのシード（同じ座標なら同じ装飾）
var world_seed := 0

func _ready() -> void:
	z_index = -100
	world_seed = randi()
	# Load Kenney tiny-dungeon floor textures (stone variations)
	for tile_id in [36, 37, 38, 48, 49]:
		var path := "res://assets/sprites/kenney/tiny-dungeon/Tiles/tile_%04d.png" % tile_id
		var tex: Texture2D = load(path)
		if tex:
			_floor_textures.append(tex)

func _process(_delta: float) -> void:
	if camera_ref == null:
		_find_camera()
		if camera_ref == null:
			return

	var cam_y := camera_ref.get_screen_center_position().y
	var cam_x := camera_ref.get_screen_center_position().x

	# 現在のカメラ位置に基づいて必要な行を計算
	@warning_ignore("integer_division")
	var center_row := int(floor(cam_y / TILE_SIZE))
	var half_rows := VISIBLE_ROWS / 2 + 1

	# 必要な行を生成
	for row in range(center_row - half_rows, center_row + half_rows + 1):
		if not generated_rows.has(row):
			_generate_row(row, cam_x)

	# 遠くの行をクリーンアップ
	var rows_to_remove: Array = []
	for row_idx in generated_rows:
		var row_y: float = float(row_idx) * TILE_SIZE
		if absf(row_y - cam_y) > CLEANUP_DISTANCE:
			rows_to_remove.append(row_idx)

	for row_idx in rows_to_remove:
		var row_node: Node2D = generated_rows[row_idx]
		row_node.queue_free()
		generated_rows.erase(row_idx)

func _find_camera() -> void:
	# Tower内のCameraを探す
	var tower := get_parent().get_node_or_null("Tower")
	if tower:
		var cam := tower.get_node_or_null("Camera")
		if cam and cam is Camera2D:
			camera_ref = cam

func _generate_row(row_index: int, _cam_x: float) -> void:
	var row_container := Node2D.new()
	row_container.name = "Row_%d" % row_index
	row_container.position.y = row_index * TILE_SIZE
	add_child(row_container)
	generated_rows[row_index] = row_container

	# 決定論的シード（同じ座標なら同じパターン）
	var row_seed := world_seed + row_index * 7919

	for col in range(COLS):
		var tile_x := (col - COLS / 2) * TILE_SIZE + TILE_SIZE * 0.5
		var tile_seed := row_seed + col * 31
		_draw_floor_tile(row_container, tile_x, tile_seed)

	# 行ごとの装飾（確率ベース）
	_maybe_add_decorations(row_container, row_index, row_seed)

func _draw_floor_tile(parent: Node2D, x: float, seed_val: int) -> void:
	## v0.9: Kenney tiny-dungeon floor sprite replaces polygon placeholder.
	## 16x16 tiles scaled to TILE_SIZE (128px) with slight color variation.
	var hash_val := _simple_hash(seed_val)

	if _floor_textures.is_empty():
		return  # fallback: no textures loaded

	# Deterministic texture selection
	var tex_idx := hash_val % _floor_textures.size()
	var sprite := Sprite2D.new()
	sprite.texture = _floor_textures[tex_idx]
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Scale 16px tile to fill TILE_SIZE (128px) = 8x
	var tile_scale := TILE_SIZE / 16.0
	sprite.scale = Vector2(tile_scale, tile_scale)
	sprite.position.x = x
	# Slight brightness variation per tile (dungeon feel)
	var brightness := 0.55 + float(hash_val % 30) * 0.015  # 0.55 ~ 1.0
	sprite.modulate = Color(brightness, brightness * 0.9, brightness, 1.0)
	parent.add_child(sprite)

func _draw_crack(parent: Node2D, x: float, hash_val: int) -> void:
	## タイル上のひび割れ線
	var crack := Line2D.new()
	crack.width = 1.0
	crack.default_color = Color(0.02, 0.015, 0.03, 0.5)

	# 2-3点のジグザグ
	var pts: PackedVector2Array = []
	var start_x := x + float((hash_val % 40) - 20)
	var start_y := float(((hash_val / 10) % 40) - 20)
	pts.append(Vector2(start_x, start_y))
	pts.append(Vector2(start_x + float((hash_val % 30) - 15), start_y + float(((hash_val / 7) % 30) - 15)))
	if hash_val % 3 == 0:
		pts.append(Vector2(start_x + float((hash_val % 20) - 10) + 10, start_y + float(((hash_val / 3) % 20))))
	crack.points = pts
	parent.add_child(crack)

func _maybe_add_decorations(parent: Node2D, row_index: int, row_seed: int) -> void:
	## 行ごとに確率で装飾を追加
	var hash1 := _simple_hash(row_seed + 1)
	var hash2 := _simple_hash(row_seed + 2)
	var hash3 := _simple_hash(row_seed + 3)

	# ルーンサークル（5%の確率）
	if hash1 % 20 == 0:
		var cx := float((hash1 % 800) - 400)
		_draw_rune_circle(parent, cx, TILE_SIZE * 0.5, row_seed)

	# 柱の切り株（8%の確率）
	if hash2 % 12 == 0:
		var cx := float((hash2 % 600) - 300)
		_draw_column_stump(parent, cx, float((hash2 / 100) % int(TILE_SIZE)))

	# 小さな瓦礫（15%の確率）
	if hash3 % 7 == 0:
		var cx := float((hash3 % 700) - 350)
		_draw_debris(parent, cx, float((hash3 / 50) % int(TILE_SIZE)), hash3)

	# 距離マーカー（10行ごと = 約128mごと）
	if row_index % 10 == 0 and row_index != 0:
		_draw_distance_marker(parent, row_index)

func _draw_rune_circle(parent: Node2D, x: float, y: float, seed_val: int) -> void:
	## 淡く光るルーンサークル（ダンジョンの床装飾）
	var radius := 30.0 + float(seed_val % 20)

	# 外周リング
	var ring := Line2D.new()
	ring.width = 1.5
	ring.default_color = Color(0.15, 0.08, 0.25, 0.3)
	var ring_pts: PackedVector2Array = []
	for i in range(17):
		var a := i * TAU / 16
		ring_pts.append(Vector2(x + cos(a) * radius, y + sin(a) * radius))
	ring.points = ring_pts
	parent.add_child(ring)

	# 内側の模様（十字＋対角線）
	var cross := Line2D.new()
	cross.width = 1.0
	cross.default_color = Color(0.12, 0.06, 0.2, 0.2)
	var r2 := radius * 0.6
	cross.points = PackedVector2Array([
		Vector2(x - r2, y), Vector2(x + r2, y),
	])
	parent.add_child(cross)

	var cross2 := Line2D.new()
	cross2.width = 1.0
	cross2.default_color = Color(0.12, 0.06, 0.2, 0.2)
	cross2.points = PackedVector2Array([
		Vector2(x, y - r2), Vector2(x, y + r2),
	])
	parent.add_child(cross2)

	# 中心の微光（ごく淡い）
	var glow := Polygon2D.new()
	var glow_pts: PackedVector2Array = []
	for i in range(8):
		var a := i * TAU / 8
		glow_pts.append(Vector2(x + cos(a) * 8.0, y + sin(a) * 8.0))
	glow.polygon = glow_pts
	glow.color = Color(0.2, 0.1, 0.35, 0.15)
	parent.add_child(glow)

	# 改善201: ルーンサークルの微光パルス（静的な背景に「生きている」感を与える）
	# Why: 背景全体が完全静止していてゲーム世界が「死んでいる」。
	# ルーンが2〜3秒周期でゆっくり呼吸することで魔法的雰囲気を強化する。
	# サークルごとに周期をずらして同期を避ける（seed_valで個別化）。
	var pulse_period := 2.0 + float(seed_val % 12) * 0.1  # 2.0〜3.1s の間でバラつく
	var glow_pulse := glow.create_tween()
	glow_pulse.set_loops()
	glow_pulse.tween_property(glow, "modulate:a", 1.8, pulse_period).set_trans(Tween.TRANS_SINE)
	glow_pulse.tween_property(glow, "modulate:a", 0.4, pulse_period).set_trans(Tween.TRANS_SINE)
	var ring_pulse := ring.create_tween()
	ring_pulse.set_loops()
	ring_pulse.tween_property(ring, "modulate:a", 1.6, pulse_period * 1.05).set_trans(Tween.TRANS_SINE)
	ring_pulse.tween_property(ring, "modulate:a", 0.35, pulse_period * 1.05).set_trans(Tween.TRANS_SINE)

func _draw_column_stump(parent: Node2D, x: float, y: float) -> void:
	## 壊れた柱の切り株（暗灰色の八角形）
	var stump := Polygon2D.new()
	var pts: PackedVector2Array = []
	var radius := 18.0
	for i in range(8):
		var a := i * TAU / 8
		pts.append(Vector2(x + cos(a) * radius, y + sin(a) * radius))
	stump.polygon = pts
	stump.color = Color(0.09, 0.08, 0.11, 0.8)
	parent.add_child(stump)

	# 上面のハイライト（わずかに明るい）
	var top := Polygon2D.new()
	var top_pts: PackedVector2Array = []
	var r2 := radius * 0.7
	for i in range(8):
		var a := i * TAU / 8
		top_pts.append(Vector2(x + cos(a) * r2, y + sin(a) * r2))
	top.polygon = top_pts
	top.color = Color(0.11, 0.10, 0.14, 0.7)
	parent.add_child(top)

func _draw_debris(parent: Node2D, x: float, y: float, hash_val: int) -> void:
	## 小さな瓦礫の散乱（2-4個の小さな多角形）
	var count := 2 + hash_val % 3
	for i in range(count):
		var dx := float(((hash_val + i * 37) % 30) - 15)
		var dy := float(((hash_val + i * 53) % 20) - 10)
		var size := 2.0 + float((hash_val + i * 17) % 4)

		var debris := Polygon2D.new()
		var pts: PackedVector2Array = []
		var sides := 3 + (hash_val + i) % 3  # 三角〜五角形
		for j in range(sides):
			var a := j * TAU / sides + float(hash_val % 10) * 0.1
			pts.append(Vector2(x + dx + cos(a) * size, y + dy + sin(a) * size))
		debris.polygon = pts
		debris.color = Color(0.07, 0.06, 0.09, 0.5)
		parent.add_child(debris)

func _draw_distance_marker(parent: Node2D, row_index: int) -> void:
	## 地面の距離マーカー線（薄い横線）- 進行感の補助
	var line := Line2D.new()
	line.width = 1.0
	line.default_color = Color(0.1, 0.08, 0.15, 0.25)
	line.points = PackedVector2Array([
		Vector2(-600, TILE_SIZE * 0.5),
		Vector2(600, TILE_SIZE * 0.5),
	])
	parent.add_child(line)

func _simple_hash(val: int) -> int:
	## 簡易ハッシュ（決定論的な疑似乱数として使用）
	var h := val
	h = ((h >> 16) ^ h) * 0x45d9f3b
	h = ((h >> 16) ^ h) * 0x45d9f3b
	h = (h >> 16) ^ h
	return absi(h)
