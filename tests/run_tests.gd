extends SceneTree

const TestBoardModel = preload("res://tests/test_board_model.gd")
const TestExplosion = preload("res://tests/test_explosion.gd")
const TestTurnResolver = preload("res://tests/test_turn_resolver.gd")
const TestAvatarRules = preload("res://tests/test_avatar_rules.gd")
const TestGenerator = preload("res://tests/test_generator.gd")
const TestFixtureWalkthrough = preload("res://tests/test_fixture_walkthrough.gd")

var total = 0
var failed = 0
var failures = []


func _initialize():
	var tests = [
		TestBoardModel.new(),
		TestExplosion.new(),
		TestTurnResolver.new(),
		TestAvatarRules.new(),
		TestGenerator.new(),
		TestFixtureWalkthrough.new(),
	]
	for test in tests:
		test.run(self)

	if failed == 0:
		print("TEST SUMMARY: %d passed, 0 failed" % total)
		quit(0)
	else:
		print("TEST SUMMARY: %d passed, %d failed" % [total - failed, failed])
		for failure in failures:
			print("FAIL: " + failure)
		quit(1)


func check(condition, message):
	total += 1
	if not condition:
		failed += 1
		failures.append(message)


func equal(actual, expected, message):
	check(actual == expected, "%s | expected=%s actual=%s" % [message, str(expected), str(actual)])


func not_equal(actual, expected, message):
	check(actual != expected, "%s | unexpected=%s" % [message, str(expected)])
