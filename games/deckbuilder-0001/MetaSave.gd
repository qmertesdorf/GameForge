extends RefCounted

const SAVE_PATH := "user://save.json"

func load_state() -> Dictionary:
	var defaults := {"unlocked_cards": [], "ascension": 0, "best": ""}
	if not FileAccess.file_exists(SAVE_PATH):
		return defaults
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return defaults
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return defaults
	var d: Dictionary = parsed
	# fill any missing keys
	for k in defaults:
		if not d.has(k):
			d[k] = defaults[k]
	return d

func save_state(state: Dictionary) -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(state))
	f.close()
