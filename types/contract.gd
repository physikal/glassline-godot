extends RefCounted
## Locked Glassline v0 constants. Live HTTPS must keep these shapes.

const BOARD_Q := 9
const BOARD_R := 7
const TURN_CAP := 16
const DEFAULT_EXPOSURE := 50
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
const ACT_END_TURN := "end_turn"

const EVENT_SNAPSHOT := "snapshot"
const EVENT_YOUR_TURN := "your_turn"

const WIN_DRAW := "draw"

const ACT_REJECT := "reject"
const DEFAULT_API_BASE := "https://glassline-api.vercel.app"

const MODE_PVP := "pvp"
const MODE_SP_JOB := "sp_job"

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

## Mock hideout stub until Coder's ledger / GET wallet exists.
const MOCK_WALLET_STUB := 24

## Assumed stub table (GD one-pager TBD). Mock display grants only.
const MARKS_PVP_WIN := 1
const MARKS_PVP_LOSS := 0
const MARKS_STANDOFF := 0
const MARKS_JOB_WIN := 1
const MARKS_JOB_FAIL := 0
const MARKS_FORFEIT_WIN := 1
const MARKS_FORFEIT_LOSS := 0

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
