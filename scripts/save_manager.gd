extends Node

## SaveManager - Chip Vault永続化。
## user://spell_cascade_save.json にチップ解放状態を保存。
## JSON壊れ→丸ごと初期化（クラッシュよりマシ）。

const SAVE_PATH := "user://spell_cascade_save.json"
const SAVE_VERSION := 1

var _data: Dictionary = {}

func _ready() -> void:
	_load()

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		_data = _default_data()
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		_data = _default_data()
		return
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK or not json.data is Dictionary:
		push_warning("SaveManager: corrupt save, resetting")
		_data = _default_data()
		_save()
		return
	_data = json.data
	if _data.get("version", 0) != SAVE_VERSION:
		push_warning("SaveManager: version mismatch, resetting")
		_data = _default_data()
		_save()

func _save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: cannot write to %s" % SAVE_PATH)
		return
	file.store_string(JSON.stringify(_data, "\t"))
	file.close()

func _default_data() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"unlocked_chips": {
			"move": "manual",
			"attack": "manual_aim",
			"skill": "auto_cast",
		},
	}

## チップ解放: カテゴリ内でより上位のチップに更新
func unlock_chip(category: String, chip_id: String) -> bool:
	var current: String = _data["unlocked_chips"].get(category, "")
	if current == chip_id:
		return false  # 既に解放済み
	# 上位チップへの更新のみ許可（マニュアル→自動は常にアップグレード）
	if _is_upgrade(category, current, chip_id):
		_data["unlocked_chips"][category] = chip_id
		_save()
		return true
	return false

## 解放済みチップを取得
func get_unlocked_chips() -> Dictionary:
	return _data.get("unlocked_chips", _default_data()["unlocked_chips"]).duplicate()

## チップが手動でないか（何か解放されているか）
func has_any_unlock() -> bool:
	var chips: Dictionary = get_unlocked_chips()
	return chips.get("move", "manual") != "manual" or chips.get("attack", "manual_aim") != "manual_aim"

func _is_upgrade(category: String, current: String, new_id: String) -> bool:
	# 手動からの変更は常にアップグレード
	match category:
		"move":
			if current == "manual":
				return true
			# kite < orbit < greedy の優先度
			var order := ["manual", "kite", "orbit", "greedy"]
			return order.find(new_id) > order.find(current)
		"attack":
			if current == "manual_aim":
				return true
			var order := ["manual_aim", "aim_nearest", "aim_highest_hp", "aim_cluster"]
			return order.find(new_id) > order.find(current)
		"skill":
			# auto_castがデフォ。on_kill/panicは横並びなので常に更新
			if current == "auto_cast" and new_id != "auto_cast":
				return true
			return current != new_id
	return false
