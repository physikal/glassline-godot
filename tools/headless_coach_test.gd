extends SceneTree
## Small first-hunt coach smoke: chips when unseen, gone after dismiss, ConfigFile persists.
## Run: godot --headless --path . -s res://tools/headless_coach_test.gd

const Contract := preload("res://types/contract.gd")
const CoachScript := preload("res://scenes/match/first_hunt_coach.gd")


func _init() -> void:
	var code := _run()
	quit(code)


func _run() -> int:
	var failed: PackedStringArray = []
	CoachScript.reset_store_for_test()
	_expect(failed, not CoachScript.is_seen(), "unseen when flag clear")

	var coach = CoachScript.new()
	coach.present(false, true)
	_expect(failed, coach.is_showing(), "chips appear when flag clear + live PvP")
	var titles: PackedStringArray = coach.visible_titles()
	_expect(failed, titles.has("ATTACK") and titles.has("RECON") and titles.has("DOLL") and titles.has("DECOY"), "Attack Recon Doll Decoy")
	_expect(failed, coach.passthrough_ok(), "no modal lock")
	_expect(failed, Contract.RECON_BASE == 0.35 and Contract.MARKS_PVP_WIN == 32, "no combat delta")

	coach.dismiss()
	_expect(failed, not coach.is_showing(), "chips gone after dismiss")
	_expect(failed, CoachScript.is_seen(), "coachSeen true")

	var cfg := ConfigFile.new()
	_expect(failed, cfg.load(CoachScript.store_path) == OK, "ConfigFile saved")
	_expect(failed, bool(cfg.get_value(Contract.COACH_SECTION, Contract.COACH_SEEN_KEY, false)), "coachSeen persisted")

	var again = CoachScript.new()
	again.present(false, true)
	_expect(failed, not again.is_showing(), "does not return after dismiss")

	CoachScript.clear_seen()
	var job = CoachScript.new()
	job.present(true, true)
	_expect(failed, not job.is_showing(), "SP job skips")

	coach.free()
	again.free()
	job.free()
	CoachScript.restore_store()

	if failed.is_empty():
		print("HEADLESS_COACH_OK")
		return 0
	for line in failed:
		push_error(line)
		print("FAIL: ", line)
	return 1


func _expect(failed: PackedStringArray, cond: bool, label: String) -> void:
	if not cond:
		failed.append(label)
