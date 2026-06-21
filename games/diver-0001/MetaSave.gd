extends RefCounted
class_name MetaSave
# Persistence for the run-meta layer: banked score, purchased upgrade levels,
# and dive number. Static + preload-able (a headless --script run does NOT
# instantiate autoloads, so this must never be an autoload global). Reached via
# const MetaSaveRef := preload("res://MetaSave.gd").

const PATH: String = "user://save.json"

static func write(banked: int, upgrades: Dictionary, dive_num: int, commission_zone: int = 1, commissions_done: int = 0) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"banked": banked,
		"upgrades": upgrades,
		"dive_num": dive_num,
		"commission_zone": commission_zone,
		"commissions_done": commissions_done,
	}))
	f.close()

static func read() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return {}
	var txt: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if parsed is Dictionary:
		return parsed
	return {}

static func clear() -> void:
	if FileAccess.file_exists(PATH):
		var dir := DirAccess.open("user://")
		if dir != null:
			dir.remove("save.json")
