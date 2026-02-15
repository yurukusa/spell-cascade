extends Node

## BuildSystem - PoEエッセンスのコア。
## JSONからスキル/サポート/Mod/シナジーを読み込み、
## リンク構成に基づいて最終ステータスを計算する。
## コード側は「適用エンジン」のみ。コンテンツはJSON。

# データカタログ
var skills: Dictionary = {}       # id -> skill data
var supports: Dictionary = {}     # id -> support data
var prefixes: Array = []          # prefix mod pool
var suffixes: Array = []          # suffix mod pool
var synergies: Array = []         # synergy definitions

func _ready() -> void:
	_load_data()

func _load_data() -> void:
	skills = _load_json("res://data/skills.json", "skills", "id")
	supports = _load_json("res://data/supports.json", "supports", "id")

	var mods_data: Variant = _load_json_raw("res://data/mods.json")
	if mods_data:
		prefixes = mods_data.get("prefixes", [])
		suffixes = mods_data.get("suffixes", [])

	var syn_data: Variant = _load_json_raw("res://data/synergies.json")
	if syn_data:
		synergies = syn_data.get("synergies", [])

func _load_json(path: String, array_key: String, id_key: String) -> Dictionary:
	var result: Dictionary = {}
	var raw: Variant = _load_json_raw(path)
	if raw and raw.has(array_key):
		for item in raw[array_key]:
			if item.has(id_key):
				result[item[id_key]] = item
	return result

func _load_json_raw(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("BuildSystem: Failed to open %s" % path)
		return null
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	if err != OK:
		push_error("BuildSystem: JSON parse error in %s: %s" % [path, json.get_error_message()])
		return null
	return json.data

# --- モジュール構成 ---

## TowerModule: タワーの1スロット分の構成
## { skill: String, supports: [String, String], prefix: Dict?, suffix: Dict? }
class TowerModule:
	var skill_id: String
	var support_ids: Array[String]
	var prefix: Dictionary  # mod data or empty
	var suffix: Dictionary  # mod data or empty

	func _init(s: String = "", sup: Array[String] = [], pre: Dictionary = {}, suf: Dictionary = {}) -> void:
		skill_id = s
		support_ids = sup
		prefix = pre
		suffix = suf

# --- ステータス計算 ---

## モジュールの最終ステータスを計算
func calculate_module_stats(module: TowerModule) -> Dictionary:
	var skill_data: Dictionary = skills.get(module.skill_id, {})
	if skill_data.is_empty():
		return {}

	var stats := {
		"skill_id": module.skill_id,
		"name": skill_data.get("name", "Unknown"),
		"tags": skill_data.get("tags", []).duplicate(),
		"damage": skill_data.get("base_damage", 0),
		"cooldown": skill_data.get("base_cooldown", 1.0),
		"range": skill_data.get("base_range", 200),
		"behaviors": [],  # サポートの挙動リスト
		"on_hit": skill_data.get("on_hit", {}).duplicate(),
		"projectile_count": skill_data.get("projectile_count", 1),
		"spread_angle": skill_data.get("spread_angle", 0),
		"area_radius": skill_data.get("area_radius", 0),
		"pierce": skill_data.get("pierce", false),
		# Mod系デフォルト値（未定義参照防止）
		"crit_chance": 0.0,
		"crit_mult": 1.0,
		"freeze_chance": 0.0,
		"freeze_duration": 0.0,
		"splash_radius": 0.0,
		"splash_damage_pct": 0.0,
		"life_on_hit": 0.0,
		"first_strike_instant": false,
		"misfire_chance": 0.0,
		"self_damage_per_attack": 0.0,
		"add_dot": {},
	}

	# サポート適用（挙動変化）
	for sup_id in module.support_ids:
		var sup_data: Dictionary = supports.get(sup_id, {})
		if sup_data.is_empty():
			continue

		# タグ要件チェック
		var req_tag: String = sup_data.get("requires_tag", "")
		if req_tag != "" and req_tag not in stats["tags"]:
			continue  # タグ不一致はスキップ

		# 挙動追加
		var behavior: Dictionary = sup_data.get("behavior", {})
		if not behavior.is_empty():
			stats["behaviors"].append(behavior)

		# サポートのタグも追加
		for tag in sup_data.get("tags", []):
			if tag not in stats["tags"]:
				stats["tags"].append(tag)

	# Prefix Mod適用
	if not module.prefix.is_empty():
		_apply_mod(stats, module.prefix)

	# Suffix Mod適用
	if not module.suffix.is_empty():
		_apply_mod(stats, module.suffix)

	return stats

func _apply_mod(stats: Dictionary, mod: Dictionary) -> void:
	var bonus: Dictionary = mod.get("bonus", {})
	var penalty: Dictionary = mod.get("penalty", {})

	# ボーナス適用
	if bonus.has("damage_mult"):
		stats["damage"] = int(stats["damage"] * bonus["damage_mult"])
	if bonus.has("cooldown_mult"):
		stats["cooldown"] *= bonus["cooldown_mult"]
	if bonus.has("range_mult"):
		stats["range"] = int(stats["range"] * bonus["range_mult"])
	if bonus.has("crit_chance"):
		stats["crit_chance"] = bonus.get("crit_chance", 0)
		stats["crit_mult"] = bonus.get("crit_mult", 2.0)
	if bonus.has("freeze_chance"):
		stats["freeze_chance"] = bonus["freeze_chance"]
		stats["freeze_duration"] = bonus.get("freeze_duration", 1.0)
	if bonus.has("splash_radius"):
		stats["splash_radius"] = bonus["splash_radius"]
		stats["splash_damage_pct"] = bonus.get("splash_damage_pct", 0.3)
	if bonus.has("life_on_hit"):
		stats["life_on_hit"] = bonus["life_on_hit"]
	if bonus.has("first_strike_instant"):
		stats["first_strike_instant"] = true
	if bonus.has("add_dot"):
		stats["add_dot"] = bonus["add_dot"]

	# ペナルティ適用
	if penalty.has("damage_mult"):
		stats["damage"] = int(stats["damage"] * penalty["damage_mult"])
	if penalty.has("cooldown_mult"):
		stats["cooldown"] *= penalty["cooldown_mult"]
	if penalty.has("range_mult"):
		stats["range"] = int(stats["range"] * penalty["range_mult"])
	if penalty.has("misfire_chance"):
		stats["misfire_chance"] = penalty["misfire_chance"]
	if penalty.has("self_damage_per_attack"):
		stats["self_damage_per_attack"] = penalty["self_damage_per_attack"]

	# Modのタグも追加
	for tag in mod.get("tags", []):
		if tag not in stats["tags"]:
			stats["tags"].append(tag)

# --- シナジー判定 ---

## タワー全体のモジュール構成からアクティブなシナジーを判定
func check_active_synergies(modules: Array) -> Array[Dictionary]:
	var active: Array[Dictionary] = []

	# 全モジュールのサポートIDとタグを集約
	var all_support_ids: Array[String] = []
	var all_tags: Array[String] = []

	for module in modules:
		for sup_id in module.support_ids:
			if sup_id not in all_support_ids:
				all_support_ids.append(sup_id)

		var stats := calculate_module_stats(module)
		for tag in stats.get("tags", []):
			if tag not in all_tags:
				all_tags.append(tag)

	# シナジー条件チェック
	for synergy in synergies:
		var condition: Dictionary = synergy.get("condition", {})
		var cond_type: String = condition.get("type", "")

		match cond_type:
			"supports_combo":
				var required: Array = condition.get("required_supports", [])
				var has_all := true
				for req in required:
					if req not in all_support_ids:
						has_all = false
						break
				if has_all:
					active.append(synergy)

			"tag_count":
				var required_tags: Array = condition.get("required_tags", [])
				var min_unique: int = condition.get("min_unique", 3)
				var count := 0
				for tag in required_tags:
					if tag in all_tags:
						count += 1
				if count >= min_unique:
					active.append(synergy)

	return active

# --- Mod ロール ---

## ランダムなprefixを1つ返す（重み付き）
func roll_prefix() -> Dictionary:
	return _weighted_pick(prefixes)

## ランダムなsuffixを1つ返す（重み付き）
func roll_suffix() -> Dictionary:
	return _weighted_pick(suffixes)

func _weighted_pick(pool: Array) -> Dictionary:
	if pool.is_empty():
		return {}
	var total_weight := 0
	for item in pool:
		total_weight += item.get("weight", 100)
	var roll := randi() % total_weight
	var cumulative := 0
	for item in pool:
		cumulative += item.get("weight", 100)
		if roll < cumulative:
			return item
	return pool[0]

# --- ランダムスキル/サポート選択 ---

func get_random_skill_ids(count: int, exclude: Array[String] = []) -> Array[String]:
	var available: Array[String] = []
	for id in skills.keys():
		if id not in exclude:
			available.append(id)
	available.shuffle()
	return available.slice(0, mini(count, available.size()))

func get_random_support_ids(count: int, exclude: Array[String] = []) -> Array[String]:
	var available: Array[String] = []
	for id in supports.keys():
		if id not in exclude:
			available.append(id)
	available.shuffle()
	return available.slice(0, mini(count, available.size()))
