extends SceneTree

# ============================================================
# selftest.gd — headless logic assertions for creature-0001
# Run: godot --headless --path games/creature-0001/ --script res://selftest.gd
# Expects: SELFTEST OK on stdout, exit 0.
# ============================================================

func _init() -> void:
	var game: Node2D = load("res://Main.tscn").instantiate()
	get_root().add_child(game)
	# _ready() is deferred after add_child — call init path directly.
	game._start_game()

	var failures: Array[String] = []

	# ----------------------------------------------------------
	# Test 1: collecting a seed at spirit's position scores + streaks
	# ----------------------------------------------------------
	var score_before: int = game.score
	var streak_before: int = game.streak
	# Place a seed exactly at the spirit's position
	game.seed_positions.append(game.spirit_pos)
	game.seed_phases.append(0.0)
	game._check_collisions()
	if game.score <= score_before:
		failures.append("seed collection did not increment score (before=%d after=%d)" % [score_before, game.score])
	if game.streak <= streak_before:
		failures.append("seed collection did not increment streak (before=%d after=%d)" % [streak_before, game.streak])

	# ----------------------------------------------------------
	# Test 2: full streak applies multiplier
	# ----------------------------------------------------------
	# Reset and collect enough seeds to hit the multiplier threshold
	game._start_game()
	var needed: int = game.STREAK_FOR_MULT + 1  # enough to push multiplier to 2
	for i in range(needed):
		game.seed_positions.append(game.spirit_pos)
		game.seed_phases.append(0.0)
		game._check_collisions()
	if game.multiplier < 2:
		failures.append("full streak did not raise multiplier (streak=%d mult=%d needed_seeds=%d)" % [game.streak, game.multiplier, needed])
	# Score should be higher than base_per_seed * needed because later ones had x2
	var expected_min: int = game.SCORE_PER_SEED * needed  # at least 1x for all
	if game.score < expected_min:
		failures.append("score after streak lower than expected (score=%d min=%d)" % [game.score, expected_min])

	# ----------------------------------------------------------
	# Test 3: hazard overlapping spirit triggers game-over
	# ----------------------------------------------------------
	game._start_game()
	# Clear all seeds so no accidental collection interferes
	game.seed_positions.clear()
	game.seed_phases.clear()
	# Place a hazard on top of spirit
	game.hazards.clear()
	game.hazards.append({
		"pos": game.spirit_pos,
		"vel": Vector2.ZERO,
		"drift_angle": 0.0,
		"wobble": 0.0
	})
	game._check_collisions()
	if game.alive:
		failures.append("hazard overlap did not trigger game-over")

	# ----------------------------------------------------------
	# Test 4: restart resets score/streak/state
	# ----------------------------------------------------------
	game.score = 9999
	game.streak = 88
	game.multiplier = 5
	game._start_game()
	if game.score != 0:
		failures.append("restart did not reset score (got %d)" % game.score)
	if game.streak != 0:
		failures.append("restart did not reset streak (got %d)" % game.streak)
	if game.multiplier != 1:
		failures.append("restart did not reset multiplier (got %d)" % game.multiplier)
	if not game.alive:
		failures.append("restart left game not alive")

	# ----------------------------------------------------------
	# Report
	# ----------------------------------------------------------
	if failures.size() == 0:
		print("SELFTEST OK")
		quit(0)
	else:
		for f in failures:
			print("SELFTEST FAIL: " + f)
		quit(1)
