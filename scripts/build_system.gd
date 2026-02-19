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
var chips: Dictionary = {}        # id -> chip data
var presets: Dictionary = {}      # id -> preset data
var art_config: Dictionary = {}   # Design Lock設定

# 装備中のBehavior Chips（カテゴリ -> chip_id）
# Mirror War: デフォルトは手動。AutoはDropで"勝ち取る"
var equipped_chips: Dictionary = {
	"move": "manual",
	"attack": "manual_aim",  # 移動方向に発射。AutoAimチップで自動照準に
	"skill": "auto_cast",
}

func _ready() -> void:
	_load_data()
	_apply_saved_chips()

## Chip Vault: セーブデータから解放済みチップを適用
func _apply_saved_chips() -> void:
	var save_mgr := get_node_or_null("/root/SaveManager")
	if save_mgr == null:
		return
	var saved: Dictionary = save_mgr.get_unlocked_chips()
	var applied: Array[String] = []
	for category in saved.keys():
		var chip_id: String = saved[category]
		# チップが実際に存在するか確認してから適用
		if chips.has(chip_id) or chip_id in ["manual", "manual_aim", "auto_cast"]:
			equipped_chips[category] = chip_id
			if chip_id != "manual" and chip_id != "manual_aim" and chip_id != "auto_cast":
				applied.append("%s=%s" % [category, chip_id])
	if applied.size() > 0:
		print("Chip Vault loaded: ", ", ".join(applied))
	else:
		print("Chip Vault: no saved unlocks (fresh start)")

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

	var art_raw: Variant = _load_json_raw("res://art_config.json")
	if art_raw:
		art_config = art_raw

	var chip_data: Variant = _load_json_raw("res://data/behavior_chips.json")
	if chip_data:
		for chip in chip_data.get("chips", []):
			if chip.has("id"):
				chips[chip["id"]] = chip
		for preset in chip_data.get("presets", []):
			if preset.has("id"):
				presets[preset["id"]] = preset

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
		# Summon/Meteor用フィールド（該当スキルのみ非ゼロ）
		"summon_duration": skill_data.get("summon_duration", 0.0),
		"summon_attack_cd": skill_data.get("summon_attack_cd", 0.0),
		"meteor_delay": skill_data.get("meteor_delay", 0.0),
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
		# v0.4 新Mod用デフォルト値
		"lightning_chain_chance": 0.0,
		"lightning_chain_range": 0.0,
		"lightning_chain_dmg_pct": 0.0,
		"hp_on_kill": 0,
		"bonus_pierce": 0,
		"speed_mult": 1.0,
		"on_kill_explode_radius": 0.0,
		"on_kill_explode_dmg_pct": 0.0,
		"max_hp_mult": 1.0,
		"berserker_threshold": 0.0,
		"berserker_dmg_mult": 1.0,
		"split_count": 0,
		"split_dmg_pct": 0.0,
		"gravity_pull": 0.0,
		"drop_rate_mult": 1.0,
		"life_steal_pct": 0.0,
		"on_hit_explode_radius": 0.0,
		"on_hit_explode_dmg_pct": 0.0,
		"homing_strength": 0.0,
		"projectile_size_mult": 1.0,
		"echo_chance": 0.0,
		"on_hit_slow": 0.0,
		"on_hit_slow_duration": 0.0,
		"thorns_pct": 0.0,
		"thorns_radius": 0.0,
		"upgrade_on_kill_chance": 0.0,
		"crit_freeze_duration": 0.0,
		"ghost_chance": 0.0,
	}

	# bugfix: skills.jsonのon_hitディクトをフラットstatキーに変換
	# Why: on_hitは"slow"/"dot_damage"等のネスト構造で書かれているが、
	# _create_projectile()はon_hit_slow/add_dot等のフラットキーしか読まない。
	# この変換がないとice_shardのスロー・poison_novaのDoTが一切機能しない。
	var skill_on_hit: Dictionary = skill_data.get("on_hit", {})
	if skill_on_hit.has("slow"):
		stats["on_hit_slow"] = skill_on_hit["slow"]
		stats["on_hit_slow_duration"] = skill_on_hit.get("slow_duration", 1.0)
	if skill_on_hit.has("dot_damage"):
		stats["add_dot"] = {
			"damage": skill_on_hit["dot_damage"],
			"duration": skill_on_hit.get("dot_duration", 3.0),
			"element": skill_on_hit.get("element", "poison")
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
	# v0.4 新bonus key
	if bonus.has("lightning_chain_chance"):
		stats["lightning_chain_chance"] = bonus["lightning_chain_chance"]
		stats["lightning_chain_range"] = bonus.get("lightning_chain_range", 60.0)
		stats["lightning_chain_dmg_pct"] = bonus.get("lightning_chain_dmg_pct", 0.5)
	if bonus.has("hp_on_kill"):
		stats["hp_on_kill"] = bonus["hp_on_kill"]
	if bonus.has("bonus_pierce"):
		stats["bonus_pierce"] = bonus["bonus_pierce"]
	if bonus.has("on_kill_explode_radius"):
		stats["on_kill_explode_radius"] = bonus["on_kill_explode_radius"]
		stats["on_kill_explode_dmg_pct"] = bonus.get("on_kill_explode_dmg_pct", 0.3)
	if bonus.has("berserker_threshold"):
		stats["berserker_threshold"] = bonus["berserker_threshold"]
		stats["berserker_dmg_mult"] = bonus.get("berserker_dmg_mult", 1.8)
	if bonus.has("split_count"):
		stats["split_count"] = bonus["split_count"]
		stats["split_dmg_pct"] = bonus.get("split_dmg_pct", 0.5)
	if bonus.has("gravity_pull"):
		stats["gravity_pull"] = bonus["gravity_pull"]
	if bonus.has("drop_rate_mult"):
		stats["drop_rate_mult"] = bonus["drop_rate_mult"]
	if bonus.has("life_steal_pct"):
		stats["life_steal_pct"] = bonus["life_steal_pct"]
	if bonus.has("on_hit_explode_radius"):
		stats["on_hit_explode_radius"] = bonus["on_hit_explode_radius"]
		stats["on_hit_explode_dmg_pct"] = bonus.get("on_hit_explode_dmg_pct", 0.4)
	if bonus.has("homing_strength"):
		stats["homing_strength"] = bonus["homing_strength"]
	if bonus.has("projectile_size_mult"):
		stats["projectile_size_mult"] = bonus["projectile_size_mult"]
	if bonus.has("echo_chance"):
		stats["echo_chance"] = bonus["echo_chance"]
	if bonus.has("on_hit_slow"):
		stats["on_hit_slow"] = bonus["on_hit_slow"]
		stats["on_hit_slow_duration"] = bonus.get("on_hit_slow_duration", 2.0)
	if bonus.has("thorns_pct"):
		stats["thorns_pct"] = bonus["thorns_pct"]
		stats["thorns_radius"] = bonus.get("thorns_radius", 80.0)
	if bonus.has("upgrade_on_kill_chance"):
		stats["upgrade_on_kill_chance"] = bonus["upgrade_on_kill_chance"]
	if bonus.has("crit_freeze_duration"):
		stats["crit_freeze_duration"] = bonus["crit_freeze_duration"]
	if bonus.has("ghost_chance"):
		stats["ghost_chance"] = bonus["ghost_chance"]

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
	if penalty.has("speed_mult"):
		stats["speed_mult"] *= penalty["speed_mult"]
	if penalty.has("max_hp_mult"):
		stats["max_hp_mult"] *= penalty["max_hp_mult"]

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

	# 全モジュールのスキルIDとprefixを集約
	var all_skill_ids: Array[String] = []
	var all_prefix_ids: Array[String] = []
	for module in modules:
		if module.skill_id not in all_skill_ids:
			all_skill_ids.append(module.skill_id)
		if not module.prefix.is_empty():
			var pid: String = module.prefix.get("id", "")
			if pid != "" and pid not in all_prefix_ids:
				all_prefix_ids.append(pid)

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

			"skill_support_combo":
				var req_skill: String = condition.get("required_skill", "")
				var req_sups: Array = condition.get("required_supports", [])
				if req_skill in all_skill_ids:
					var has_sups := true
					for s in req_sups:
						if s not in all_support_ids:
							has_sups = false
							break
					if has_sups:
						active.append(synergy)

			"prefix_variety":
				var min_prefixes: int = condition.get("min_unique_prefixes", 3)
				if all_prefix_ids.size() >= min_prefixes:
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

# --- Behavior Chips ---

func get_chip(chip_id: String) -> Dictionary:
	return chips.get(chip_id, {})

func get_equipped_chip(category: String) -> Dictionary:
	var chip_id: String = equipped_chips.get(category, "")
	return get_chip(chip_id)

func equip_chip(category: String, chip_id: String) -> void:
	equipped_chips[category] = chip_id

func get_chips_by_category(category: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for chip in chips.values():
		if chip.get("category", "") == category:
			result.append(chip)
	return result

## プリセットを適用: 3チップ + 初期スキルを一括設定
func apply_preset(preset_id: String) -> String:
	var preset: Dictionary = presets.get(preset_id, {})
	if preset.is_empty():
		return ""
	equipped_chips["move"] = preset.get("move", "kite")
	equipped_chips["attack"] = preset.get("attack", "aim_nearest")
	equipped_chips["skill"] = preset.get("skill", "auto_cast")
	return preset.get("starting_skill", "fireball")

func get_all_presets() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for p in presets.values():
		result.append(p)
	return result
