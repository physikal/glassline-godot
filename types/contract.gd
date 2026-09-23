extends RefCounted
## Locked Glassline v0 constants. Live HTTPS must keep these shapes.

const BOARD_Q := 9
const BOARD_R := 7
const TURN_CAP := 16
const DEFAULT_EXPOSURE := 50
## Gear floor. Server owns operativeLevel → you.exposureFloor (50/40/30/20).
## Client displays the percent. It never maps a level to a lower %.
const EXPOSURE_FLOOR_START := 50
const EXPOSURE_FLOOR_LABEL := "Exposure %d%%"
const EXPOSURE_FLOOR_TIP := "Gear tightened — harder to spot"
const EXPOSURE_FLOOR_TIP_TITLE := "GEAR"
const EXPOSURE_FLOOR_SEEN_KEY := "exposureFloorTipSeen"
const EXPOSURE_FLOOR_PRIOR_KEY := "exposureFloorPrior"
const EXPOSURE_FLOOR_LATCH_KEY := "exposureFloorTipLatched"
const RECON_BASE := 0.35
const RECON_MOVED_BONUS := 0.25
const TERRAIN_SALT := "glassline-v0"

const STATUS_WAITING := "waiting"
const STATUS_READY := "ready"
const STATUS_ACTIVE := "active"
const STATUS_ENDED := "ended"

const PHASE_ACTION := "await_action"
const PHASE_END_TURN := "await_end_turn"

const SEAT_A := "a"
const SEAT_B := "b"

const TYPE_OPEN := "open"
const TYPE_BRUSH := "brush"
const TYPE_HARD := "hard"

const ACT_SELECT_HEX := "select_hex"
const ACT_START := "start"
const ACT_ATTACK := "attack"
const ACT_RECON := "recon"
const ACT_UAV := "uav"
const ACT_DECOY := "decoy"
const ACT_SMOKE := "smoke"
const ACT_END_TURN := "end_turn"
const ACT_FORFEIT := "forfeit"

const EVENT_SNAPSHOT := "snapshot"
const EVENT_YOUR_TURN := "your_turn"

const WIN_DRAW := "draw"

const ACT_REJECT := "reject"
const DEFAULT_API_BASE := "https://glassline-api.vercel.app"

const MODE_PVP := "pvp"
const MODE_SP_JOB := "sp_job"
## Practice hunt — full rules, server bot, Marks always Δ0. Not ranked / not a job.
const MODE_PRACTICE := "practice"
const MARKS_PRACTICE := 0

const END_KILL := "kill"
const END_STANDOFF := "standoff"
const END_LOSS := "loss"
const END_JOB := "job"
const END_JOB_FAIL := "job_fail"
const END_FORFEIT := "forfeit"
const END_DISCONNECT := "disconnect"

## Soft A4 — treat these snapshot/result tokens as forfeit chrome.
const FORFEIT_REASONS := ["forfeit", "disconnect", "disconnected", "ragequit"]

## Ability slot chrome (M5). Intent type stays `uav`.
const ABILITY_LABEL := "UAV"
const ABILITY_SLOT := "ABILITY"
## Ability SMOKE — once/match toy puff. Intent `{ type: "smoke" }`, no hex.
## Bind exact you.smokeAvailable and you.operativeLevel. Missing key → not available.
## smokeAvailable is only a charge once operativeLevel >= 5. HARD for exposure+spot is server-owned.
## No Attack +0.10. No IN COVER chip. No Marks buy. No IAP. Practice XP does not level.
const SMOKE_LABEL := "SMOKE"
const SMOKE_UNLOCK_LEVEL := 5
## Hideout wood plate. Server curve is operativeLevel = 1 + floor(xp / 100).
## Toward-next is xp % XP_PER_LEVEL. There is no xpToNext field.
## The plate never reads you.smokeAvailable — that charge stays on the match chip.
const XP_PER_LEVEL := 100
const XP_PLATE_TIP := "SMOKE · L5"
const SMOKE_TOAST := "Smoke — hex is Hard this turn"
const SMOKE_LOCKED_TOAST := "Reach operative L5"
const SMOKE_COPY := "Once a hunt. A toy puff — your hex counts as Hard this turn."
const SMOKE_SPENT_COPY := "Smoke is spent."
const SMOKE_ABSENT_COPY := "Smoke is not on this hunt."
const SMOKE_CHROME_AVAILABLE := "available"
const SMOKE_CHROME_LOCKED := "locked"
const SMOKE_CHROME_SPENT := "spent"
const SMOKE_CHROME_ABSENT := "absent"
## Ability #2 — toy doll decoy. Intent `{ type: "decoy" }`, no hex arg.
## Bind exact you.decoyAvailable and you.operativeLevel. Missing key → not available.
## decoyAvailable is only a charge once operativeLevel >= 3. Once unlocked: once/match,
## adjacent empty, miss+clear, no Marks. No IAP. Practice XP does not level.
const DECOY_LABEL := "DECOY"
const DECOY_SLOT := "TOY DOLL"
const DECOY_UNLOCK_LEVEL := 3
const DECOY_TIP := "DECOY · L3"
const DECOY_LOCKED_TOAST := "Reach operative L3"
## LIVE reject when the action is sent below L3. The charge stays unspent.
const DECOY_LOCKED_REASON := "reach operative L3"
const DECOY_COPY := "Plant a toy doll on a neighbor hex. Rivals see a soft blip. Once a hunt."
const DECOY_SPENT_COPY := "Decoy is spent."
const DECOY_ABSENT_COPY := "Decoy is not on this hunt."
const DECOY_CHROME_AVAILABLE := "available"
const DECOY_CHROME_LOCKED := "locked"
const DECOY_CHROME_SPENT := "spent"
const DECOY_CHROME_ABSENT := "absent"
## HIGH GROUND — attacker HARD only. Chip binds you.highGroundActive. Never invent.
const HIGH_GROUND_LABEL := "HIGH GROUND"
const HIGH_GROUND_SUB := "+10%"
const HIGH_GROUND_COPY := "HARD footing. Server +10% hit."
const HIGH_GROUND_MUTED_COPY := "Not on HARD. No hit bonus."
## LIVE occupy-hex base (Coder 4720879). HARD adds +0.10, one stack, clamp [0, 1].
const BASE_HIT_CHANCE := 0.90
const HIGH_GROUND_HIT := 0.10
## BRUSH cover — target cell BRUSH → −0.10 abs on the occupy roll. No chip this slice.
const BRUSH_COVER_HIT := 0.10
const COVER_APPLIED_COPY := "Brush cover"
const COVER_SKIPPED_COPY := "No cover"
const HIGH_GROUND_APPLIED_COPY := "High ground"
const HIGH_GROUND_SKIPPED_COPY := "No high ground"

## Mock hideout stub until Coder's ledger / GET wallet exists.
const MOCK_WALLET_STUB := 24

## Marks sinks — hideout cosmetics. LIVE catalog lock (Coder 2026-09-19 / 2026-09-20).
## GET /shop item.id + POST /shop/buy itemId. Sink 1 ★50 · sink 2 ★100 · sink 3 ★150.
const SHOP_STUB_ITEM_ID := "skin_hideout_stub"
const SHOP_STUB_ITEM_NAME := "GHILLIE RECOLOR"
const SHOP_STUB_KIND := "skin"
const SHOP_STUB_PRICE := 50
const SHOP_BANDANA_ITEM_ID := "skin_bandana_stub"
const SHOP_BANDANA_ITEM_NAME := "BANDANA RECOLOR"
const SHOP_BANDANA_KIND := "skin"
const SHOP_BANDANA_PRICE := 100
const SHOP_POSTER_ITEM_ID := "decor_poster_stub"
const SHOP_POSTER_ITEM_NAME := "HIDEOUT POSTER"
const SHOP_POSTER_KIND := "decor"
const SHOP_POSTER_PRICE := 150
const SHOP_ERR_INSUFFICIENT := "insufficient_marks"
const SHOP_ERR_INVALID_BODY := "invalid_buy_body"
const SHOP_ERR_ALREADY_OWNED := "already_owned"
const SHOP_ERR_UNKNOWN_ITEM := "unknown_item"
const SHOP_ERR_UNAVAILABLE := "shop_unavailable"
const SHOP_ERR_NOT_OWNED := "not_owned"
## Hideout row copy — owned chrome is visual only. Equip is a separate suit toggle.
const SHOP_OWNED_COPY := "OWNED  ·  visual only"
const SHOP_EQUIP_COPY := "Tap to wear  ·  visual only"
const SHOP_EQUIPPED_COPY := "Wearing this  ·  visual only"
const SHOP_INSUFFICIENT_COPY := "Not enough Marks."

## Gun SKUs — same /shop spine as skins / poster. Chrome only, zero combat.
## Fieldbolt owned-by-default. Railframe ★125 · Crescent ★200 Marks sinks.
const GUN_FIELDBOLT := "gun_fieldbolt"
const GUN_RAILFRAME := "gun_railframe"
const GUN_CRESCENT := "gun_crescent"
const GUN_FIELDBOLT_NAME := "FIELDBOLT"
const GUN_RAILFRAME_NAME := "RAILFRAME"
const GUN_CRESCENT_NAME := "CRESCENT"
const GUN_KIND := "gun"
const GUN_SLOT := "gun"
const GUN_FIELDBOLT_PRICE := 0
const GUN_RAILFRAME_PRICE := 125
const GUN_CRESCENT_PRICE := 200
const GUN_STARTER_COPY := "STARTER"
const GUN_VISUAL_COPY := "visual only"

## Gun parts — same /shop spine. Soft feel only (wobble / shot window).
## Never hit% · spot% · exposure floor · HIGH GROUND · BRUSH · Marks earn.
## One equipped id per slot. T2 replaces T1 in that slot. Null id = bare.
const PART_OPTIC := "gun_part_optic"
const PART_STOCK := "gun_part_stock"
const PART_BARREL := "gun_part_barrel"
const PART_OPTIC_T2 := "gun_part_optic_t2"
const PART_STOCK_T2 := "gun_part_stock_t2"
const PART_BARREL_T2 := "gun_part_barrel_t2"
const PART_OPTIC_NAME := "OPTIC"
const PART_STOCK_NAME := "STOCK"
const PART_BARREL_NAME := "BARREL"
const PART_OPTIC_T2_NAME := "OPTIC T2"
const PART_STOCK_T2_NAME := "STOCK T2"
const PART_BARREL_T2_NAME := "BARREL T2"
const PART_KIND := "gun-part"
const PART_SLOT_OPTIC := "optic"
const PART_SLOT_STOCK := "stock"
const PART_SLOT_BARREL := "barrel"
const PART_OPTIC_PRICE := 75
const PART_STOCK_PRICE := 100
const PART_BARREL_PRICE := 125
const PART_OPTIC_T2_PRICE := 150
const PART_STOCK_T2_PRICE := 175
const PART_BARREL_T2_PRICE := 200
## Mock snapshot table matching LIVE. Attack chrome reads you.* only.
## T1 b5ba339: optic 1.4, stock 0.8, barrel 0.9, stack 0.75.
## T2 2608bd6: optic 1.55, stock 0.75, barrel 0.85, stack still 0.75.
const SHOT_WINDOW_BASE_SEC := 1.2
const SHOT_WINDOW_OPTIC_SEC := 1.4
const SHOT_WINDOW_OPTIC_T2_SEC := 1.55
const WOBBLE_SCALE_BASE := 1.0
const WOBBLE_STOCK_SCALE := 0.80
const WOBBLE_BARREL_SCALE := 0.90
const WOBBLE_STOCK_T2_SCALE := 0.75
const WOBBLE_BARREL_T2_SCALE := 0.85
const WOBBLE_STACK_FLOOR := 0.75
const PART_TOAST_WINDOW := "Shot window looser"
const PART_TOAST_WOBBLE := "Wobble quieter"
## Buy-feel wood toast. Same hold as other clearing hideout toasts.
const PART_TOAST_HOLD_SEC := 2.4
const PART_OWNED_COPY := "OWNED"
const PART_EQUIPPED_COPY := "Wearing this"

## Locked GD earn table (2026-09-23). Display + mock only; LIVE ledger is Coder.
## Practice stays 0. SP max win (T3) stays under the PvP kill.
const MARKS_PVP_WIN := 32
const MARKS_PVP_LOSS := 4
const MARKS_STANDOFF := 10
const MARKS_JOB_T1 := 12
const MARKS_JOB_T2 := 18
const MARKS_JOB_T3 := 24
const MARKS_JOB_FAIL_T1 := 2
const MARKS_JOB_FAIL_T2 := 3
const MARKS_JOB_FAIL_T3 := 3
const MARKS_FORFEIT_WIN := 15
const MARKS_FORFEIT_LOSS := 0
const FORFEIT_GRACE_SEC := 30

## Rematch — same two seats, new matchId + terrain salt. Marks already final.
const REMATCH_NONE := "none"
const REMATCH_PENDING := "pending"
const REMATCH_WAITING := "waiting"
const REMATCH_ACCEPTED_A := "accepted_a"
const REMATCH_ACCEPTED_B := "accepted_b"
const REMATCH_READY := "ready"
const REMATCH_DECLINED := "declined"
const REMATCH_EXPIRED := "expired"
const REMATCH_TIMEOUT_SEC := 30
const REMATCH_TIMEOUT_MS := 30000
const REMATCH_ERR_UNAVAILABLE := "rematch_unavailable"
const REMATCH_ERR_NOT_ENDED := "match_not_ended"
const REMATCH_ERR_NOT_PVP := "rematch_not_pvp"
const REMATCH_PLAY_COPY := "PLAY AGAIN"
const REMATCH_DECLINE_COPY := "DECLINE"
const REMATCH_SETTLED_COPY := "Marks already settled."
const REMATCH_HINT_COPY := "Play again for a fresh drop. Wallet stays put."
## Forfeit body. +15 / 0 already landed — do not say the wallet stayed put.
const FORFEIT_HINT_COPY := "Play again for a fresh drop. Wallet already settled."
const REMATCH_WAIT_COPY := "Waiting on your rival…"
const REMATCH_TIMER_COPY := "Answer in %ds"

## Private lobby invite — short code, seated PvP, no public queue / ranked.
const LOBBY_CODE_LEN := 6
const LOBBY_CODE_ALPHABET := "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
const LOBBY_TTL_SEC := 600
const LOBBY_TTL_MS := 600000
const LOBBY_WAITING := "waiting"
const LOBBY_READY := "ready"
const LOBBY_CANCELLED := "cancelled"
const LOBBY_EXPIRED := "expired"
const LOBBY_ERR_UNAVAILABLE := "lobby_unavailable"
const LOBBY_ERR_BAD_CODE := "invalid_lobby_code"
const LOBBY_ERR_NOT_FOUND := "lobby_not_found"
const LOBBY_ERR_EXPIRED := "lobby_expired"
const LOBBY_ERR_CANCELLED := "lobby_cancelled"
const LOBBY_ERR_FULL := "lobby_full"
const LOBBY_ERR_SELF := "already_in_lobby"
const LOBBY_ERR_INVALID := "invalid_lobby_code"
const LOBBY_ERR_INVALID_BODY := "invalid_join_body"
const LOBBY_ERR_STARTED := "lobby_already_started"
const LOBBY_ERR_FORBIDDEN := "not_member"
const LOBBY_KICKER := "WARTABLE"
const LOBBY_HEADING := "PRIVATE HUNT"
const LOBBY_BLURB := "Invite a rival with a short code. Same hunt. No queue."
const LOBBY_CREATE_COPY := "CREATE LOBBY"
const LOBBY_JOIN_COPY := "JOIN"
const LOBBY_WAIT_COPY := "Waiting on your rival…"
const LOBBY_CODE_HINT := "Share this code."
const LOBBY_REJECT_COPY := "That code is expired or wrong."
const LOBBY_CANCEL_COPY := "CANCEL"
const LOBBY_BACK_COPY := "BACK"
const LOBBY_COPY_CODE := "COPY"
const LOBBY_SHARE_CODE := "SHARE"
const LOBBY_PASTE_CODE := "PASTE"
## Short cozy note. The %s is the existing 6-char code — no link, no new code.
const LOBBY_SHARE_BLURB := "Hunt with me — code %s"
const LOBBY_UNAVAILABLE_COPY := "LIVE invite not ready"
const LOBBY_COPIED_COPY := "Code copied."
const LOBBY_PASTED_COPY := "Pasted."
const LOBBY_HIDEOUT_COPY := "Back at the hideout."

## Quick Match — 1-tap hideout queue. No bot fill / MMR / ranked.
const QUEUE_TTL_SEC := 60
const QUEUE_TTL_MS := 60000
const QUEUE_IDLE := "idle"
const QUEUE_QUEUED := "queued"
const QUEUE_MATCHED := "matched"
const QUEUE_EXPIRED := "expired"
const QUEUE_TIMEOUT := "timeout"
const QUEUE_ERR_UNAVAILABLE := "queue_unavailable"
const QUEUE_ERR_MATCHED := "queue_already_matched"
const QUEUE_ERR_IN_MATCH := "already_in_match"
const QUEUE_ERR_IN_LOBBY := "in_lobby"
const QUEUE_ERR_FORBIDDEN := "not_in_queue"
const QUEUE_KICKER := "WARTABLE"
const QUEUE_HEADING := "FINDING A RIVAL…"
const QUEUE_BLURB := "Scouting the hideouts. Same hunt when they sit."
const QUEUE_WAIT_COPY := "Finding a rival…"
const QUEUE_CANCEL_COPY := "CANCEL"
const QUEUE_CTA := "QUICK MATCH"
const QUEUE_HIDEOUT_COPY := "Back at the hideout."
const QUEUE_TIMEOUT_COPY := "No rival yet. Back at the hideout."
const QUEUE_UNAVAILABLE_COPY := "LIVE queue not ready"

## Practice hunt — cozy hideout CTA. Same rules, toy spy, no Marks, not a queue.
const PRACTICE_CTA := "PRACTICE"
const PRACTICE_KICKER := "HIDEOUT"
const PRACTICE_HEADING := "QUIET HUNT"
const PRACTICE_BLURB := "Same hunt — terrain, optic, decoy, exposure. A toy spy sits across the table."
const PRACTICE_NO_MARKS := "No Marks. Win, lose, or leave — your wallet stays put (Δ0)."
const PRACTICE_START := "START PRACTICE"
const PRACTICE_BACK := "NOT NOW"
const PRACTICE_UNAVAILABLE_COPY := "LIVE practice not ready"
const PRACTICE_RIVAL := "TOY SPY"
const PRACTICE_CHIP := "PRACTICE  ·  TOY SPY  ·  NO MARKS"
const PRACTICE_SETTLED_COPY := "No Marks  ·  0"
const PRACTICE_REMATCH_HINT := "Another practice drop. Still no Marks."
const PRACTICE_WAIT_COPY := "Toy spy is shuffling the board…"
const PRACTICE_ABANDON_TIP := "Leave the table. No Marks."
const PRACTICE_CLEAR := "PRACTICE CLEAR"
const PRACTICE_OVER := "PRACTICE OVER"
const PRACTICE_LEFT := "LEFT THE TABLE"
const PRACTICE_SPY_LEFT := "TOY SPY LEFT"

## Match journal — last 10 ended hunts. Server ledger only. No local history.
const JOURNAL_LIMIT := 10
const JOURNAL_ERR_UNAVAILABLE := "journal_unavailable"
const JOURNAL_ERR_MISSING := "missing_bearer"
const JOURNAL_KICKER := "HIDEOUT"
const JOURNAL_HEADING := "HUNT JOURNAL"
const JOURNAL_BLURB := "The last few hunts, from the ledger."
const JOURNAL_EMPTY := "No hunts yet."
const JOURNAL_EMPTY_SUB := "The table is quiet. Take a hunt when you want."
const JOURNAL_CTA := "JOURNAL"
const JOURNAL_CLOSE := "BACK"
const JOURNAL_REMATCH := "REMATCH"
const JOURNAL_PRACTICE_AGAIN := "PRACTICE AGAIN"
const JOURNAL_TAG_PRACTICE := "PRACTICE"
const JOURNAL_TAG_QUICK := "QUICK"
const JOURNAL_TAG_JOB := "JOB"
const JOURNAL_RESULT_WIN := "WIN"
const JOURNAL_RESULT_LOSS := "LOSS"
const JOURNAL_RESULT_FORFEIT := "FORFEIT"
const JOURNAL_RESULT_DRAW := "DRAW"
const JOURNAL_WAIT_COPY := "Waiting on your rival…"
const JOURNAL_CLOSED_COPY := "That rematch closed."

## Soft A4 gaps — abandon CTA + grace countdown. Duration stays 30s.
const ABANDON_COPY := "ABANDON"
const ABANDON_ERR_UNAVAILABLE := "abandon_unavailable"
## Disconnect grace — not a turn clock. Rival drop vs local poll HOLD.
const GRACE_RIVAL_COPY := "Waiting on rival…  %s"
const GRACE_HOLD_COPY := "Reconnect  %s"

## First-hunt coach — client-only tip chips. No API / Marks / combat.
const COACH_STORE := "user://glassline_coach.cfg"
const COACH_SECTION := "coach"
const COACH_SEEN_KEY := "coachSeen"
const COACH_KICKER := "FIRST HUNT"
const COACH_GOT_IT := "GOT IT"
const COACH_ATTACK := "Peek the optic —\ntap a hex."
const COACH_RECON := "Scout a hex —\nno shot fired."
const COACH_DOLL := "They peek —\nthe doll lights up."
const COACH_DECOY := "Once a hunt —\ndrop a fake blip."

## Terrain coach — one-shot HIGH GROUND + BRUSH. Same store, separate flag.
const COACH_TERRAIN_SEEN_KEY := "coachTerrainSeen"
const COACH_TERRAIN_HIGH := "high"
const COACH_TERRAIN_BRUSH := "brush"
const COACH_TERRAIN_KICKER := "TERRAIN"
const COACH_TERRAIN_HIGH_TITLE := "HIGH GROUND"
const COACH_TERRAIN_BRUSH_TITLE := "BRUSH"
const COACH_TERRAIN_HIGH_COPY := "Hard hex lights the chip.\nYou shoot better from up there."
const COACH_TERRAIN_BRUSH_COPY := "Leafy cover softens\nshots at you."

## Hideout gear strip — local mute + coach reset. Not an Options app.
const GEAR_KICKER := "GEAR"
const GEAR_MUTE_LIVE := "LIVE"
const GEAR_MUTE_MUTED := "MUTED"
const GEAR_RESET := "RESET TIPS"
const GEAR_CONFIRM_COPY := "Tips will show again."
const GEAR_CONFIRM_YES := "RESET"
const GEAR_CONFIRM_NO := "CANCEL"


static func exposure_floor_or_start(value: Variant, present: bool) -> int:
	## Missing, 0, or any percent outside 50/40/30/20 → start floor.
	## Never invents a lower step from operativeLevel.
	if not present or value == null:
		return EXPOSURE_FLOOR_START
	if value is bool or value is Dictionary or value is Array:
		return EXPOSURE_FLOOR_START
	if value is String and str(value).strip_edges() == "":
		return EXPOSURE_FLOOR_START
	var n := int(round(float(value)))
	if n == 50 or n == 40 or n == 30 or n == 20:
		return n
	return EXPOSURE_FLOOR_START


static func xp_for_level_start(level: int) -> int:
	## XP at the start of a server level. Mock L5 harness uses this so the bar is 0.
	return maxi(0, int(level) - 1) * XP_PER_LEVEL


static func xp_progress(xp: int) -> int:
	## Toward next. No server field. 100 lands on 0 of the next level.
	return maxi(0, int(xp)) % XP_PER_LEVEL


static func xp_remaining(xp: int) -> int:
	return XP_PER_LEVEL - xp_progress(xp)


static func operative_level_from_xp(xp: int) -> int:
	## Documented server curve. The hideout label prefers you.operativeLevel.
	## SMOKE does not call this.
	return 1 + int(floor(float(maxi(0, int(xp))) / float(XP_PER_LEVEL)))


static func operative_card_from_payload(bag: Dictionary) -> Dictionary:
	## Exact xp and operativeLevel. you, then the bag, then player, then snapshot.
	## Missing, junk, negative xp, or level < 1 stay absent. Never invents a 0.
	## Snake-case aliases and smokeAvailable are not read.
	var xp_hit := _find_operative_number(bag, "xp")
	var lv_hit := _find_operative_number(bag, "operativeLevel")
	var xp_ok := bool(xp_hit.get("present", false)) and int(xp_hit.get("value", -1)) >= 0
	var lv_ok := bool(lv_hit.get("present", false)) and int(lv_hit.get("value", 0)) >= 1
	return {
		"xp_present": xp_ok,
		"xp": int(xp_hit.get("value", 0)) if xp_ok else 0,
		"level_present": lv_ok,
		"level": int(lv_hit.get("value", 0)) if lv_ok else 0,
	}


static func _find_operative_number(bag: Dictionary, key: String) -> Dictionary:
	var sources: Array = []
	var you_bag: Variant = bag.get("you", null)
	if you_bag is Dictionary:
		sources.append(you_bag)
	sources.append(bag)
	var player_bag: Variant = bag.get("player", null)
	if player_bag is Dictionary:
		sources.append(player_bag)
	var snap: Variant = bag.get("snapshot", null)
	if snap is Dictionary:
		var snap_you: Variant = snap.get("you", null)
		if snap_you is Dictionary:
			sources.append(snap_you)
		sources.append(snap)
	for source in sources:
		var dict: Dictionary = source
		if not dict.has(key):
			continue
		var n: Variant = _as_operative_int(dict.get(key))
		if n == null:
			return {"present": false, "value": -1}
		return {"present": true, "value": int(n)}
	return {"present": false, "value": -1}


static func _as_operative_int(value: Variant) -> Variant:
	## JSON numbers only. Strings, bools, and null are not a level or an XP total.
	if value == null or value is bool or value is String:
		return null
	if value is Dictionary or value is Array:
		return null
	if value is int or value is float:
		return int(floor(float(value)))
	return null


static func exposure_floor_named(bag: Dictionary) -> bool:
	## Exact exposureFloor on you, the bag, player, or snapshot. Absent is not 50.
	if bag.has("exposureFloor"):
		return true
	var you_bag: Variant = bag.get("you", null)
	if you_bag is Dictionary and (you_bag as Dictionary).has("exposureFloor"):
		return true
	var player_bag: Variant = bag.get("player", null)
	if player_bag is Dictionary and (player_bag as Dictionary).has("exposureFloor"):
		return true
	var snap: Variant = bag.get("snapshot", null)
	if snap is Dictionary:
		if (snap as Dictionary).has("exposureFloor"):
			return true
		var snap_you: Variant = snap.get("you", null)
		if snap_you is Dictionary and (snap_you as Dictionary).has("exposureFloor"):
			return true
	return false


static func exposure_floor_from_payload(bag: Dictionary) -> int:
	## Read you.exposureFloor / top-level exposureFloor / player.exposureFloor.
	## operativeLevel, skins, guns, and poster chrome are ignored.
	## A missing field does not invent 50 — callers keep the last server floor.
	if bag.has("exposureFloor"):
		return exposure_floor_or_start(bag.get("exposureFloor"), true)
	var you_bag: Variant = bag.get("you", null)
	if you_bag is Dictionary and (you_bag as Dictionary).has("exposureFloor"):
		return exposure_floor_or_start((you_bag as Dictionary).get("exposureFloor"), true)
	var player_bag: Variant = bag.get("player", null)
	if player_bag is Dictionary and (player_bag as Dictionary).has("exposureFloor"):
		return exposure_floor_or_start((player_bag as Dictionary).get("exposureFloor"), true)
	var snap: Variant = bag.get("snapshot", null)
	if snap is Dictionary:
		if (snap as Dictionary).has("exposureFloor"):
			return exposure_floor_or_start((snap as Dictionary).get("exposureFloor"), true)
		var snap_you: Variant = snap.get("you", null)
		if snap_you is Dictionary and (snap_you as Dictionary).has("exposureFloor"):
			return exposure_floor_or_start((snap_you as Dictionary).get("exposureFloor"), true)
	return EXPOSURE_FLOOR_START


static func clamp_exposure_intent(floor: int, intent: float) -> float:
	## Next end_turn exposurePct band. Minimum is the server floor. Never 0.
	var band := float(exposure_floor_or_start(floor, true))
	return clampf(intent, band, 100.0)


static func snap_next_exposure(floor: int, current: float, baseline: float, player_raised: bool) -> Dictionary:
	## NEXT label/slider baseline is the same server floor as the doll.
	## On open / snapshot apply: below the floor, still on the untouched
	## baseline, or stuck at the stale default 50 while the floor is lower
	## → snap to the floor. A player raise stays inside the band.
	## Never writes exposureFloor.
	var band := float(exposure_floor_or_start(floor, true))
	var shown_now := float(current)
	var stale_default := (
		not player_raised
		and int(round(shown_now)) == EXPOSURE_FLOOR_START
		and int(band) < EXPOSURE_FLOOR_START
	)
	var on_baseline := not player_raised and is_equal_approx(shown_now, float(baseline))
	var follows := stale_default or on_baseline or shown_now < band
	var shown := band if follows else clampf(shown_now, band, 100.0)
	return {
		"value": shown,
		"min": band,
		"baseline": shown if follows else float(baseline),
		"player_raised": false if follows else player_raised,
	}


static func format_grace_clock(sec: float) -> String:
	var n := maxi(0, ceili(sec))
	return "%d:%02d" % [int(n / 60), n % 60]


static func format_marks_delta(n: int) -> String:
	## One plate chip for every Marks Δ: `0`, `+N`, or `−N` (U+2212).
	## Never glue a prefix (`Δ+25`, `0+25`, `+0`) and never an ASCII hyphen.
	if n > 0:
		return "+%d" % n
	if n < 0:
		return "−%d" % absi(n)
	return "0"


const JOB_NAME_T1 := "Rooftop Rookie"
const JOB_NAME_T2 := "Warehouse Watch"
const JOB_NAME_T3 := "Night Contract"
const JOB_TIERS := [1, 2, 3]


static func job_name(tier: int) -> String:
	match tier:
		2:
			return JOB_NAME_T2
		3:
			return JOB_NAME_T3
		_:
			return JOB_NAME_T1


static func job_tier_delta(tier: int) -> int:
	match tier:
		2:
			return MARKS_JOB_T2
		3:
			return MARKS_JOB_T3
		_:
			return MARKS_JOB_T1


static func job_tier_fail_delta(tier: int) -> int:
	## Per-tier job loss. Unknown tier stays T1. Display + mock only.
	match tier:
		2:
			return MARKS_JOB_FAIL_T2
		3:
			return MARKS_JOB_FAIL_T3
		_:
			return MARKS_JOB_FAIL_T1


static func job_row_label(tier: int) -> String:
	## Hideout ladder copy: tier + name. Payout is a separate ★ chip.
	return "T%d  %s" % [clampi(tier, 1, 3), job_name(tier)]


static func job_bot_hex(tier: int) -> Dictionary:
	## LIVE src/bot.ts SP_BOT_HEX. Secret until UAV / kill.
	match clampi(tier, 1, 3):
		2:
			return hex_dict(7, 5)
		3:
			return hex_dict(8, 5)
		_:
			return hex_dict(8, 6)

static func on_board(q: int, r: int) -> bool:
	return q >= 0 and q < BOARD_Q and r >= 0 and r < BOARD_R


static func hex_dict(q: int, r: int) -> Dictionary:
	return {"q": q, "r": r}


static func hex_key(hex: Variant) -> String:
	if hex == null or not (hex is Dictionary):
		return ""
	return "%d,%d" % [int(hex.get("q", -1)), int(hex.get("r", -1))]


static func same_hex(a: Variant, b: Variant) -> bool:
	if a == null or b == null:
		return false
	if not (a is Dictionary) or not (b is Dictionary):
		return false
	return int(a.get("q", -99)) == int(b.get("q", -98)) and int(a.get("r", -99)) == int(b.get("r", -98))


static func other_seat(seat: String) -> String:
	return SEAT_B if seat == SEAT_A else SEAT_A


## LIVE POST /matches → { matchId, joinToken, seat: "a" }. Never both seats.
## Mock still also returns joinTokens for the local dummy loop.
static func create_join_token(created: Dictionary) -> String:
	var tok := str(created.get("joinToken", ""))
	if tok != "":
		return tok
	var tokens: Variant = created.get("joinTokens", {})
	if tokens is Dictionary:
		return str(tokens.get(SEAT_A, tokens.get("a", "")))
	return ""


static func create_seat(created: Dictionary) -> String:
	var seat := str(created.get("seat", ""))
	return seat if seat != "" else SEAT_A


static func create_dummy_token(created: Dictionary) -> String:
	## Mock / editor only. LIVE create never ships seat B.
	var tokens: Variant = created.get("joinTokens", {})
	if tokens is Dictionary:
		return str(tokens.get(SEAT_B, tokens.get("b", "")))
	return ""


## Toy-spy attack stingers. Names stay cozy — not gunshot / killstreak.
const CUE_MISS := "glass_click"
const CUE_HIT := "glass_ping"
const CUE_HIGH := "high_chime"
const CUE_BRUSH := "brush_hush"


static func shop_stub_item() -> Dictionary:
	return _shop_item(SHOP_STUB_ITEM_ID, SHOP_STUB_ITEM_NAME, SHOP_STUB_KIND, SHOP_STUB_PRICE)


static func shop_bandana_item() -> Dictionary:
	return _shop_item(SHOP_BANDANA_ITEM_ID, SHOP_BANDANA_ITEM_NAME, SHOP_BANDANA_KIND, SHOP_BANDANA_PRICE)


static func shop_poster_item() -> Dictionary:
	return _shop_item(SHOP_POSTER_ITEM_ID, SHOP_POSTER_ITEM_NAME, SHOP_POSTER_KIND, SHOP_POSTER_PRICE)


static func shop_gun_fieldbolt_item() -> Dictionary:
	return _shop_item(GUN_FIELDBOLT, GUN_FIELDBOLT_NAME, GUN_KIND, GUN_FIELDBOLT_PRICE)


static func shop_gun_railframe_item() -> Dictionary:
	return _shop_item(GUN_RAILFRAME, GUN_RAILFRAME_NAME, GUN_KIND, GUN_RAILFRAME_PRICE)


static func shop_gun_crescent_item() -> Dictionary:
	return _shop_item(GUN_CRESCENT, GUN_CRESCENT_NAME, GUN_KIND, GUN_CRESCENT_PRICE)


static func shop_part_optic_item() -> Dictionary:
	return _shop_item(PART_OPTIC, PART_OPTIC_NAME, PART_KIND, PART_OPTIC_PRICE, 1)


static func shop_part_stock_item() -> Dictionary:
	return _shop_item(PART_STOCK, PART_STOCK_NAME, PART_KIND, PART_STOCK_PRICE, 1)


static func shop_part_barrel_item() -> Dictionary:
	return _shop_item(PART_BARREL, PART_BARREL_NAME, PART_KIND, PART_BARREL_PRICE, 1)


static func shop_part_optic_t2_item() -> Dictionary:
	return _shop_item(PART_OPTIC_T2, PART_OPTIC_T2_NAME, PART_KIND, PART_OPTIC_T2_PRICE, 2)


static func shop_part_stock_t2_item() -> Dictionary:
	return _shop_item(PART_STOCK_T2, PART_STOCK_T2_NAME, PART_KIND, PART_STOCK_T2_PRICE, 2)


static func shop_part_barrel_t2_item() -> Dictionary:
	return _shop_item(PART_BARREL_T2, PART_BARREL_T2_NAME, PART_KIND, PART_BARREL_T2_PRICE, 2)


static func _shop_item(item_id: String, item_name: String, kind: String, price: int, tier: int = 0) -> Dictionary:
	var item := {
		"id": item_id,
		"itemId": item_id,
		"name": item_name,
		"kind": kind,
		"price": price,
		"priceMarks": price,
		"cosmetic": true,
		"combat": false,
	}
	if tier > 0:
		item["tier"] = tier
	return item


static func shop_catalog_items() -> Array:
	## Mock + LIVE-lag fallback. Prefer LIVE items when Coder lists guns.
	return [
		shop_stub_item(),
		shop_bandana_item(),
		shop_poster_item(),
		shop_gun_fieldbolt_item(),
		shop_gun_railframe_item(),
		shop_gun_crescent_item(),
		shop_part_optic_item(),
		shop_part_optic_t2_item(),
		shop_part_stock_item(),
		shop_part_stock_t2_item(),
		shop_part_barrel_item(),
		shop_part_barrel_t2_item(),
	]


static func shop_item_by_id(item_id: String) -> Dictionary:
	var resolved := _canonical_shop_id(item_id)
	for entry in shop_catalog_items():
		if str(entry.get("id", "")) == resolved:
			return entry
	return {}


static func shop_item_price(item_id: String) -> int:
	var item := shop_item_by_id(item_id)
	if item.is_empty():
		return 0
	return int(item.get("price", 0))


static func _canonical_shop_id(item_id: String) -> String:
	if item_id in ["ghillie_recolor", ""]:
		return SHOP_STUB_ITEM_ID
	if item_id == "bandana_recolor":
		return SHOP_BANDANA_ITEM_ID
	if item_id in ["hideout_poster", "poster_stub"]:
		return SHOP_POSTER_ITEM_ID
	var gun := canonical_gun_id(item_id)
	if gun != "":
		return gun
	var part := canonical_part_id(item_id)
	if part != "":
		return part
	return item_id


static func is_suit_chrome(item_id: String) -> bool:
	## Ghillie / bandana swap the operative plate. Poster is wall decor, not a suit.
	if item_id == "":
		return false
	var resolved := _canonical_shop_id(item_id)
	return resolved == SHOP_STUB_ITEM_ID or resolved == SHOP_BANDANA_ITEM_ID


static func is_decor_chrome(item_id: String) -> bool:
	if item_id == "":
		return false
	return _canonical_shop_id(item_id) == SHOP_POSTER_ITEM_ID


static func gun_family_ids() -> Array:
	return [GUN_FIELDBOLT, GUN_RAILFRAME, GUN_CRESCENT]


static func is_gun_chrome(item_id: String) -> bool:
	return canonical_gun_id(item_id) != ""


static func canonical_gun_id(item_id: String) -> String:
	## Catalog + rack ids. kind: gun. Never a skin / decor slot.
	match str(item_id):
		GUN_FIELDBOLT, "fieldbolt", "starter_bolt", "bolt_classic":
			return GUN_FIELDBOLT
		GUN_RAILFRAME, "railframe", "chassis_bolt":
			return GUN_RAILFRAME
		GUN_CRESCENT, "crescent", "long_cutout":
			return GUN_CRESCENT
		_:
			return ""


static func part_ids() -> Array:
	## Slot then tier, so T2 sits under its T1 on the same PARTS plate.
	return [
		PART_OPTIC, PART_OPTIC_T2,
		PART_STOCK, PART_STOCK_T2,
		PART_BARREL, PART_BARREL_T2,
	]


static func is_part_chrome(item_id: String) -> bool:
	return canonical_part_id(item_id) != ""


static func is_part_slot(slot: String) -> bool:
	return slot in [PART_SLOT_OPTIC, PART_SLOT_STOCK, PART_SLOT_BARREL]


static func canonical_part_id(item_id: String) -> String:
	## LIVE ids gun_part_*. kind gun-part. T2 does not collapse into T1.
	## Never a skin, decor, or gun slot.
	match str(item_id):
		PART_OPTIC_T2, "part_optic_t2", "optic_t2":
			return PART_OPTIC_T2
		PART_STOCK_T2, "part_stock_t2", "stock_t2":
			return PART_STOCK_T2
		PART_BARREL_T2, "part_barrel_t2", "barrel_t2":
			return PART_BARREL_T2
		PART_OPTIC, "part_optic", "optic", "toy_optic", "glass_optic":
			return PART_OPTIC
		PART_STOCK, "part_stock", "stock", "toy_stock", "shoulder_stock":
			return PART_STOCK
		PART_BARREL, "part_barrel", "barrel", "toy_barrel":
			return PART_BARREL
		_:
			return ""


static func part_slot(item_id: String) -> String:
	match canonical_part_id(item_id):
		PART_OPTIC, PART_OPTIC_T2:
			return PART_SLOT_OPTIC
		PART_STOCK, PART_STOCK_T2:
			return PART_SLOT_STOCK
		PART_BARREL, PART_BARREL_T2:
			return PART_SLOT_BARREL
		_:
			return ""


static func part_name(item_id: String) -> String:
	match canonical_part_id(item_id):
		PART_STOCK_T2:
			return PART_STOCK_T2_NAME
		PART_BARREL_T2:
			return PART_BARREL_T2_NAME
		PART_OPTIC_T2:
			return PART_OPTIC_T2_NAME
		PART_STOCK:
			return PART_STOCK_NAME
		PART_BARREL:
			return PART_BARREL_NAME
		PART_OPTIC:
			return PART_OPTIC_NAME
		_:
			return ""


static func part_glyph(item_id: String) -> String:
	## Toy-spy icon kind for Chrome.make_icon. Not a mil-sim part plate.
	match part_slot(item_id):
		PART_SLOT_STOCK:
			return "part_stock"
		PART_SLOT_BARREL:
			return "part_barrel"
		PART_SLOT_OPTIC:
			return "part_optic"
		_:
			return "star"


static func part_buy_toast(item_id: String) -> String:
	## Soft feel line. Practice hunts stay silent on Marks — this is hideout buy only.
	if part_slot(item_id) == PART_SLOT_OPTIC:
		return PART_TOAST_WINDOW
	if part_slot(item_id) in [PART_SLOT_STOCK, PART_SLOT_BARREL]:
		return PART_TOAST_WOBBLE
	return ""


static func part_row_status(owned: bool, can_buy: bool, equipped: bool) -> String:
	## Wear copy only. Insufficient Marks is one shared wood toast, not a line per chip.
	## No hit / spot / exposure copy. Feel lives on the clearing buy toast.
	if owned:
		return PART_EQUIPPED_COPY if equipped else PART_OWNED_COPY
	if not can_buy:
		return ""
	return ""


static func _part_feel_id(value: Variant, t1_when_true: String) -> String:
	## Bool true is the T1 id (older call sites). A string is that equipped id.
	if value is bool:
		return t1_when_true if value else ""
	if value == null:
		return ""
	return canonical_part_id(str(value))


static func local_wobble_scale(stock_on: Variant = false, barrel_on: Variant = false) -> float:
	## Mock snapshot table, matching LIVE. Attack chrome does not call this.
	## Any stock plus any barrel floors at 0.75. T2 stock alone is already 0.75.
	var stock_id := _part_feel_id(stock_on, PART_STOCK)
	var barrel_id := _part_feel_id(barrel_on, PART_BARREL)
	if stock_id != "" and barrel_id != "":
		return WOBBLE_STACK_FLOOR
	if stock_id == PART_STOCK_T2:
		return WOBBLE_STOCK_T2_SCALE
	if stock_id == PART_STOCK:
		return WOBBLE_STOCK_SCALE
	if barrel_id == PART_BARREL_T2:
		return WOBBLE_BARREL_T2_SCALE
	if barrel_id == PART_BARREL:
		return WOBBLE_BARREL_SCALE
	return WOBBLE_SCALE_BASE


static func local_shot_window_sec(optic_on: Variant = false) -> float:
	## Mock snapshot table, matching LIVE. Attack chrome does not call this.
	var optic_id := _part_feel_id(optic_on, PART_OPTIC)
	if optic_id == PART_OPTIC_T2:
		return SHOT_WINDOW_OPTIC_T2_SEC
	if optic_id == PART_OPTIC:
		return SHOT_WINDOW_OPTIC_SEC
	return SHOT_WINDOW_BASE_SEC


static func feel_number(value: Variant) -> bool:
	if value == null:
		return false
	if value is int or value is float:
		return true
	if value is String and str(value).is_valid_float():
		return true
	return false


static func resolve_wobble_scale(present: bool, value: Variant) -> float:
	## C2: you.wobbleScale only. Missing / null stays the bare 1. Equipped ids do not author it.
	if present and feel_number(value):
		return float(value)
	return WOBBLE_SCALE_BASE


static func resolve_shot_window_sec(present: bool, value: Variant) -> float:
	## C2: you.shotWindowSec only. Missing / null stays 1.2. Equipped ids do not author it.
	if present and feel_number(value):
		return float(value)
	return SHOT_WINDOW_BASE_SEC


static func gun_family_name(item_id: String) -> String:
	match canonical_gun_id(item_id):
		GUN_RAILFRAME:
			return GUN_RAILFRAME_NAME
		GUN_CRESCENT:
			return GUN_CRESCENT_NAME
		GUN_FIELDBOLT:
			return GUN_FIELDBOLT_NAME
		_:
			return ""


static func shop_catalog_stub(
	marks: int = 0,
	owned: Array = [],
	equipped: String = "",
	equipped_decor: String = "",
	equipped_gun: String = GUN_FIELDBOLT,
	equipped_optic: String = "",
	equipped_stock: String = "",
	equipped_barrel: String = ""
) -> Dictionary:
	var owned_ids: Array = owned.duplicate()
	if not owned_ids.has(GUN_FIELDBOLT):
		owned_ids.append(GUN_FIELDBOLT)
	var skin: Variant = equipped if equipped != "" else null
	var decor: Variant = equipped_decor if equipped_decor != "" else null
	var gun_id := canonical_gun_id(equipped_gun)
	var gun: Variant = gun_id if gun_id != "" else null
	var optic_id := canonical_part_id(equipped_optic)
	var stock_id := canonical_part_id(equipped_stock)
	var barrel_id := canonical_part_id(equipped_barrel)
	var optic: Variant = optic_id if optic_id != "" else null
	var stock: Variant = stock_id if stock_id != "" else null
	var barrel: Variant = barrel_id if barrel_id != "" else null
	var owned_gun_ids: Array = []
	var owned_part_ids: Array = []
	for item_id in owned_ids:
		var gid := canonical_gun_id(str(item_id))
		if gid != "" and not owned_gun_ids.has(gid):
			owned_gun_ids.append(gid)
		var pid := canonical_part_id(str(item_id))
		if pid != "" and not owned_part_ids.has(pid):
			owned_part_ids.append(pid)
	if not owned_gun_ids.has(GUN_FIELDBOLT):
		owned_gun_ids.append(GUN_FIELDBOLT)
	var wobble := local_wobble_scale(stock_id, barrel_id)
	var window_sec := local_shot_window_sec(optic_id)
	return {
		"items": shop_catalog_items(),
		"you": {
			"marks": marks,
			"owned": owned_ids,
			"ownedGuns": owned_gun_ids,
			"ownedParts": owned_part_ids,
			"equipped": skin,
			"equippedSkinId": skin,
			"equippedDecorId": decor,
			"equippedGunId": gun,
			"equippedOpticId": optic,
			"equippedStockId": stock,
			"equippedBarrelId": barrel,
			"wobbleScale": wobble,
			"shotWindowSec": window_sec,
		},
		"owned": owned_ids,
		"ownedGuns": owned_gun_ids,
		"ownedParts": owned_part_ids,
		"equipped": skin,
		"equippedSkinId": skin,
		"equippedDecorId": decor,
		"equippedGunId": gun,
		"equippedOpticId": optic,
		"equippedStockId": stock,
		"equippedBarrelId": barrel,
		"wobbleScale": wobble,
		"shotWindowSec": window_sec,
		"marks": marks,
	}


static func merge_live_shop_catalog(live: Dictionary) -> Dictionary:
	## Prefer LIVE names/prices when Coder lists a SKU. Append any missing
	## mock row so ARMORY still shows skins / poster / guns / parts.
	## LIVE lists gun_part_* — those rows buy on the shop spine.
	var out: Dictionary = live.duplicate(true)
	var items: Variant = out.get("items", [])
	if not (items is Array):
		items = []
	var ids: Array = []
	var merged: Array = []
	for entry in items:
		if not (entry is Dictionary):
			continue
		merged.append(entry)
		var iid := _canonical_shop_id(str(entry.get("id", entry.get("itemId", ""))))
		if iid != "" and not ids.has(iid):
			ids.append(iid)
	for stub in shop_catalog_items():
		var sid := str(stub.get("id", ""))
		if sid != "" and not ids.has(sid):
			merged.append(stub.duplicate(true))
	out["items"] = merged
	return out


static func new_client_job_id() -> String:
	## UUID v4 for POST /jobs clientJobId. New id on every START click.
	return new_client_buy_id()


static func normalize_lobby_code(raw: String) -> String:
	## Uppercase, strip spaces / dashes. Ambiguous 0O1I stay so join can reject.
	var out := ""
	for i in raw.length():
		var ch := raw.substr(i, 1).to_upper()
		if ch == " " or ch == "-" or ch == "_":
			continue
		out += ch
	return out


static func is_lobby_code(code: String) -> bool:
	var norm := normalize_lobby_code(code)
	if norm.length() != LOBBY_CODE_LEN:
		return false
	for i in norm.length():
		if LOBBY_CODE_ALPHABET.find(norm.substr(i, 1)) < 0:
			return false
	return true


static func is_match_snapshot(snap: Dictionary, match_id: String = "") -> bool:
	## Join handoff is a match snap. GET /lobbies/:id keeps a lobby snap + top-level matchId.
	if snap.is_empty():
		return false
	if str(snap.get("kind", "")) == "lobby":
		return false
	var mid := str(snap.get("matchId", ""))
	if match_id != "" and mid != "" and mid != match_id:
		return false
	if mid == "" and match_id == "":
		return false
	return snap.has("terrain") or snap.has("turnIndex") or snap.has("phase") \
			or snap.has("whoseTurn") \
			or str(snap.get("kind", "")) in [MODE_PVP, MODE_SP_JOB, MODE_PRACTICE, "job"]


static func practice_envelope_ok(body: Dictionary) -> bool:
	## Seat A + one joinToken. A leaked seat-B token, or a named non-practice mode, is not a hunt.
	## LIVE practice create echoes `mode: "practice"` (API 0d30bd7). PvP create still omits mode.
	if body.is_empty():
		return false
	if str(body.get("matchId", "")) == "" or create_join_token(body) == "":
		return false
	if body.has("joinTokens"):
		return false
	var seat := str(body.get("seat", ""))
	if seat != "" and seat != SEAT_A:
		return false
	var named := str(body.get("mode", body.get("kind", "")))
	if named != "" and named != MODE_PRACTICE:
		return false
	return true


static func practice_snapshot_ok(snap: Dictionary) -> bool:
	## Fail closed unless the caller snapshot is practice and the rival is the server bot.
	## A PvP snap, a missing flag, or kind/mode disagreement is not a practice hunt.
	if snap.is_empty():
		return false
	var kind := str(snap.get("kind", ""))
	var mode_name := str(snap.get("mode", snap.get("matchMode", "")))
	if kind != "" and mode_name != "" and kind != mode_name:
		return false
	var named := kind if kind != "" else mode_name
	if named != MODE_PRACTICE:
		return false
	var enemy: Variant = snap.get("enemy", {})
	if not (enemy is Dictionary):
		return false
	if not enemy.has("isBot") and not enemy.has("bot"):
		return false
	return bool(enemy.get("isBot", enemy.get("bot", false)))


static func practice_create_ok(body: Dictionary) -> bool:
	## Echoed `mode: "practice"` is enough. A body that omits mode still needs the snapshot.
	## PvP create does not echo mode.
	if not practice_envelope_ok(body):
		return false
	var named := str(body.get("mode", body.get("kind", "")))
	if named == MODE_PRACTICE:
		return true
	var posted: Variant = body.get("snapshot", {})
	if posted is Dictionary and practice_snapshot_ok(posted):
		return true
	return false


static func lobby_code_display(code: String) -> String:
	var norm := normalize_lobby_code(code)
	if norm.length() == LOBBY_CODE_LEN:
		return "%s %s" % [norm.substr(0, 3), norm.substr(3, 3)]
	return norm


static func new_lobby_code(rng: RandomNumberGenerator = null) -> String:
	var gen: RandomNumberGenerator = rng
	if gen == null:
		gen = RandomNumberGenerator.new()
		gen.randomize()
	var out := ""
	for _i in LOBBY_CODE_LEN:
		out += LOBBY_CODE_ALPHABET.substr(gen.randi_range(0, LOBBY_CODE_ALPHABET.length() - 1), 1)
	return out


static func new_client_buy_id() -> String:
	## UUID v4 for POST /shop/buy clientBuyId. New id on every Buy click.
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var bytes := PackedByteArray()
	bytes.resize(16)
	for i in 16:
		bytes[i] = rng.randi_range(0, 255)
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	var hex := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [
		hex.substr(0, 8),
		hex.substr(8, 4),
		hex.substr(12, 4),
		hex.substr(16, 4),
		hex.substr(20, 12),
	]
