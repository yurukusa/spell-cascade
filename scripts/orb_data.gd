extends Node

## OrbData - オーブとシナジーの定義（データ駆動）。
## Autoloadシングルトン。全てのオーブ効果・シナジー条件をここに集約。

# オーブの基本タイプ
enum OrbType {
	FIRE,
	ICE,
	LIGHTNING,
	POISON,
	ARCANE,
	HOLY
}

# オーブ情報
class OrbInfo:
	var type: int
	var name: String
	var description: String
	var color: Color  # プレースホルダ色（design.md後に差し替え）
	var effect: Dictionary  # 効果パラメータ

	func _init(t: int, n: String, d: String, c: Color, e: Dictionary) -> void:
		type = t
		name = n
		description = d
		color = c
		effect = e

# シナジー情報
class SynergyInfo:
	var name: String
	var description: String
	var required_orbs: Array[int]
	var bonus: Dictionary  # ボーナスパラメータ

	func _init(n: String, d: String, req: Array[int], b: Dictionary) -> void:
		name = n
		description = d
		required_orbs = req
		bonus = b

# --- データ定義 ---

var orb_catalog: Dictionary = {}
var synergy_catalog: Array[SynergyInfo] = []

func _ready() -> void:
	_init_orbs()
	_init_synergies()

func _init_orbs() -> void:
	orb_catalog = {
		OrbType.FIRE: OrbInfo.new(
			OrbType.FIRE, "Fire Orb", "Attack speed +15%",
			Color(1.0, 0.3, 0.1),
			{"attack_speed_mult": 1.15}
		),
		OrbType.ICE: OrbInfo.new(
			OrbType.ICE, "Ice Orb", "Enemies slowed 20%",
			Color(0.3, 0.7, 1.0),
			{"enemy_slow": 0.8}
		),
		OrbType.LIGHTNING: OrbInfo.new(
			OrbType.LIGHTNING, "Lightning Orb", "Chain to 2 nearby enemies",
			Color(1.0, 1.0, 0.3),
			{"chain_count": 2}
		),
		OrbType.POISON: OrbInfo.new(
			OrbType.POISON, "Poison Orb", "DoT 5 dmg/sec for 3s",
			Color(0.3, 0.9, 0.2),
			{"dot_damage": 5.0, "dot_duration": 3.0}
		),
		OrbType.ARCANE: OrbInfo.new(
			OrbType.ARCANE, "Arcane Orb", "Damage +25%",
			Color(0.7, 0.3, 1.0),
			{"damage_mult": 1.25}
		),
		OrbType.HOLY: OrbInfo.new(
			OrbType.HOLY, "Holy Orb", "HP regen 2/sec",
			Color(1.0, 0.95, 0.6),
			{"hp_regen": 2.0}
		),
	}

func _init_synergies() -> void:
	synergy_catalog = [
		SynergyInfo.new(
			"Meltdown", "Fire+Ice: Explosions on kill",
			[OrbType.FIRE, OrbType.ICE],
			{"explosion_on_kill": true, "explosion_radius": 80.0, "explosion_damage": 20.0}
		),
		SynergyInfo.new(
			"Tempest", "Lightning+Ice: Freeze chance 15%",
			[OrbType.LIGHTNING, OrbType.ICE],
			{"freeze_chance": 0.15, "freeze_duration": 1.5}
		),
		SynergyInfo.new(
			"Plague Storm", "Poison+Fire: Poison spreads on death",
			[OrbType.POISON, OrbType.FIRE],
			{"poison_spread_on_death": true, "spread_radius": 100.0}
		),
	]

func get_orb(type: int) -> OrbInfo:
	return orb_catalog.get(type)

func get_random_orbs(count: int, exclude: Array[int] = []) -> Array[int]:
	var available: Array[int] = []
	for t in orb_catalog.keys():
		if t not in exclude:
			available.append(t)
	available.shuffle()
	return available.slice(0, mini(count, available.size()))

func check_synergies(owned_orbs: Array[int]) -> Array[SynergyInfo]:
	var active: Array[SynergyInfo] = []
	for synergy in synergy_catalog:
		var has_all := true
		for req in synergy.required_orbs:
			if req not in owned_orbs:
				has_all = false
				break
		if has_all:
			active.append(synergy)
	return active
