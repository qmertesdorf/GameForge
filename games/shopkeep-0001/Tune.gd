extends RefCounted
class_name Tune
# GF_TUNE / GF_SEED override seam for balance search. UNSET → empty dict / the
# game's own default seed → IDENTICAL production behavior (zero runtime impact;
# players never set these). The balance.mjs harness sets GF_TUNE (a JSON object of
# parameter overrides) and GF_SEED (the world RNG seed) per candidate run.
# Static funcs only — headless `--script` has no autoloads (preload + static).

static var _cache: Dictionary = {}
static var _parsed: bool = false

static func dict() -> Dictionary:
	if not _parsed:
		_parsed = true
		var raw := OS.get_environment("GF_TUNE")
		if not raw.is_empty():
			var d = JSON.parse_string(raw)
			if d is Dictionary:
				_cache = d
	return _cache

static func num(key: String, default_value: float) -> float:
	var d := dict()
	return float(d.get(key, default_value))

static func int_of(key: String, default_value: int) -> int:
	var d := dict()
	return int(d.get(key, default_value))

static func seed_of(default_value: int) -> int:
	var raw := OS.get_environment("GF_SEED")
	return int(raw) if raw.is_valid_int() else default_value
