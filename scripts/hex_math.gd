extends RefCounted
## Pointy-top axial hex math for the 9×7 board.

const Contract := preload("res://types/contract.gd")

const AXIAL_DIRS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(1, -1),
	Vector2i(0, -1),
	Vector2i(-1, 0),
	Vector2i(-1, 1),
	Vector2i(0, 1),
]

## LIVE src/hex.ts pickDecoyHex walk order (docs/contract neighbor table).
const DECOY_DIRS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
	Vector2i(1, -1),
	Vector2i(-1, 1),
]


static func axial_to_pixel(q: int, r: int, size: float) -> Vector2:
	var x := size * (sqrt(3.0) * float(q) + sqrt(3.0) / 2.0 * float(r))
	var y := size * (1.5 * float(r))
	return Vector2(x, y)


static func pixel_to_axial(pos: Vector2, size: float) -> Vector2i:
	var q := (sqrt(3.0) / 3.0 * pos.x - 1.0 / 3.0 * pos.y) / size
	var r := (2.0 / 3.0 * pos.y) / size
	return cube_round(q, r)


static func cube_round(fq: float, fr: float) -> Vector2i:
	var fs := -fq - fr
	var rq := roundi(fq)
	var rr := roundi(fr)
	var rs := roundi(fs)
	var dq := absf(float(rq) - fq)
	var dr := absf(float(rr) - fr)
	var ds := absf(float(rs) - fs)
	if dq > dr and dq > ds:
		rq = -rr - rs
	elif dr > ds:
		rr = -rq - rs
	return Vector2i(rq, rr)


static func distance(aq: int, ar: int, bq: int, br: int) -> int:
	return (absi(aq - bq) + absi(aq + ar - bq - br) + absi(ar - br)) / 2


static func neighbors(q: int, r: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dir in AXIAL_DIRS:
		var nq := q + dir.x
		var nr := r + dir.y
		if Contract.on_board(nq, nr):
			out.append(Vector2i(nq, nr))
	return out


static func sector(q: int, r: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if Contract.on_board(q, r):
		out.append(Vector2i(q, r))
	out.append_array(neighbors(q, r))
	return out


static func hex_corners(size: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var angle := deg_to_rad(60.0 * float(i) - 30.0)
		pts.append(Vector2(cos(angle), sin(angle)) * size)
	return pts


static func board_pixel_size(size: float) -> Vector2:
	var max_x := 0.0
	var max_y := 0.0
	for q in Contract.BOARD_Q:
		for r in Contract.BOARD_R:
			var p := axial_to_pixel(q, r, size)
			max_x = maxf(max_x, p.x)
			max_y = maxf(max_y, p.y)
	return Vector2(max_x + size * 2.0, max_y + size * 2.0)
