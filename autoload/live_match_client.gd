extends Node
## HTTPS + SSE client for the locked Glassline Hono API.
## Same method names as MockMatchServer.
## Bearer = durable POST /players token on create / join / jobs / shop.
## Match actions / snapshot / heartbeat / SSE still use the per-match join token.

const Contract := preload("res://types/contract.gd")
const ActionResult := preload("res://types/action_result.gd")

signal match_event(player_id: String, event_name: String, snapshot: Dictionary)

const TIMEOUT_MSEC := 20000
const POLL_SEC := 1.0

var last_error: String = ""
var realtime_mode: String = "" ## "sse" | "poll" | ""
## Set when GET /matches/:id poll fails. Cleared on a good snapshot. Grace UI only.
var poll_failed_since_msec: int = -1

var _sse: HTTPClient
var _sse_buf: String = ""
var _sse_event: String = ""
var _sse_match_id: String = ""
var _sse_token: String = ""
var _sse_host: String = ""
var _sse_port: int = 80
var _sse_tls: bool = false
var _connecting_sse: bool = false
var _poll: bool = false
var _poll_accum: float = 0.0
var _last_fp: String = ""


func clear_all() -> void:
	stop_events()
	last_error = ""
	poll_failed_since_msec = -1


func health() -> Dictionary:
	return _json("GET", "/health", null, "")


func create_player() -> Dictionary:
	## POST /players → { playerId, token, marks }. Caller must keep `token`.
	var body: Dictionary = _json("POST", "/players", {}, "")
	if body.has("error") and not body.has("token"):
		last_error = str(body.get("error", "player_create_failed"))
	return body


func auth_dev(token: String = "") -> Dictionary:
	var bearer := token if token != "" else ClientSession.player_bearer()
	if bearer == "":
		return {}
	return _json("POST", "/auth/dev", {"token": bearer}, "")


func ensure_player(force_new: bool = false) -> Dictionary:
	## Mint once, reuse the same Bearer on matches / jobs / shop.
	if not force_new:
		ClientSession.load_player()
	if not force_new and ClientSession.player_bearer() != "":
		var auth: Dictionary = auth_dev(ClientSession.player_bearer())
		if auth.has("playerId") and str(auth.get("error", "")) == "":
			ClientSession.bind_player({
				"playerId": auth.get("playerId", ""),
				"token": ClientSession.player_bearer(),
				"marks": auth.get("marks", ClientSession.marks),
			})
			return auth
	var created: Dictionary = create_player()
	if created.has("token"):
		ClientSession.bind_player(created)
		if not force_new:
			ClientSession.persist_player()
	return created


func create_match(opts: Dictionary = {}) -> Dictionary:
	## Bearer player token binds seat A to that playerId (no fresh mint at 0).
	var payload: Dictionary = opts.duplicate(true)
	var body: Dictionary = _json("POST", "/matches", payload, ClientSession.player_bearer())
	if body.has("error") and not body.has("matchId"):
		last_error = str(body.get("error", "create_failed"))
	return body


func wallet() -> Dictionary:
	## Prefer GET /shop/me (marks + equippedSkinId). Fall back to POST /auth/dev.
	if ClientSession.player_bearer() != "":
		var me: Dictionary = get_shop_me()
		if str(me.get("error", "")) == "" and (me.has("you") or me.has("marks")):
			return me
		var auth: Dictionary = auth_dev()
		if auth.has("marks"):
			return {
				"marks": int(auth.get("marks")),
				"playerId": str(auth.get("playerId", "")),
			}
	return {}


func get_shop() -> Dictionary:
	## LIVE GET /shop → { items: [{ id, name, price, kind }] }. Public catalog.
	var raw: Dictionary = _raw("GET", "/shop", null, ClientSession.player_bearer())
	return _shop_from_raw(raw)


func get_shop_me() -> Dictionary:
	## LIVE GET /shop/me + Bearer → { you: { marks, equippedSkinId }, owned }.
	var bearer := ClientSession.player_bearer()
	if bearer == "":
		return {"ok": false, "error": "missing_bearer"}
	var raw: Dictionary = _raw("GET", "/shop/me", null, bearer)
	return _shop_from_raw(raw, false, false, true)


func buy_shop(item_id: String, client_buy_id: String = "") -> Dictionary:
	## LIVE POST /shop/buy { itemId, clientBuyId } + Bearer **player** token.
	## 200 { ok, you.marks, purchaseId, item } — idempotent on clientBuyId.
	## 402 { error, code: insufficient_marks, you.marks }. Never local marks -=.
	if client_buy_id == "":
		client_buy_id = Contract.new_client_buy_id()
	var payload := {"itemId": item_id, "clientBuyId": client_buy_id}
	var bearer := ClientSession.player_bearer()
	if bearer == "":
		bearer = ClientSession.join_token
	var raw: Dictionary = _raw("POST", "/shop/buy", payload, bearer)
	return _shop_from_raw(raw, true)


func equip_cosmetic(item_id: String) -> Dictionary:
	## LIVE POST /shop/equip { itemId } | { itemId: null } + Bearer **player** token.
	## 200 { ok, you: { marks, equippedSkinId }, item? }. 403 not_owned. Marks untouched.
	var payload: Dictionary = {}
	if item_id == "":
		payload["itemId"] = null
	else:
		payload["itemId"] = item_id
	var bearer := ClientSession.player_bearer()
	if bearer == "":
		bearer = ClientSession.join_token
	var raw: Dictionary = _raw("POST", "/shop/equip", payload, bearer)
	return _shop_from_raw(raw, false, true)


func _shop_unavailable(body: Dictionary) -> bool:
	var err := str(body.get("error", ""))
	return err in [Contract.SHOP_ERR_UNAVAILABLE, "http_404", "bad_json"] or int(body.get("status", 0)) == 404


func _shop_from_raw(raw: Dictionary, is_buy: bool = false, is_equip: bool = false, is_me: bool = false) -> Dictionary:
	var status := int(raw.get("status", 0))
	var js: Variant = raw.get("json", {})
	if not (js is Dictionary):
		if status == 404 and (not is_buy or is_equip):
			return {
				"ok": false,
				"error": Contract.SHOP_ERR_UNAVAILABLE,
				"status": 404,
				"snapshot": {},
				"liveEquipMissing": is_equip,
			}
		var fallback := str(raw.get("error", "bad_json"))
		return {"ok": false, "error": fallback, "status": status, "snapshot": {}}
	var body: Dictionary = js
	var code := str(body.get("code", body.get("error", "")))
	if status == 404 and is_equip:
		body["error"] = Contract.SHOP_ERR_UNAVAILABLE if code == "" else code
		body["ok"] = false
		body["liveEquipMissing"] = true
	elif status == 404 and not is_buy and code == "":
		return {
			"ok": false,
			"error": Contract.SHOP_ERR_UNAVAILABLE,
			"status": 404,
			"snapshot": {},
		}
	if status == 402 or code == Contract.SHOP_ERR_INSUFFICIENT:
		body["error"] = Contract.SHOP_ERR_INSUFFICIENT
		body["ok"] = false
	elif status == 404 and is_buy and not is_equip:
		body["error"] = Contract.SHOP_ERR_UNKNOWN_ITEM if code == "" else code
		body["ok"] = false
	elif status == 400 and is_buy:
		body["error"] = Contract.SHOP_ERR_INVALID_BODY if code == "" else code
		body["ok"] = false
	elif status == 400 and is_equip:
		body["error"] = code if code != "" else "invalid_equip_body"
		body["ok"] = false
	elif status == 403 and is_equip:
		body["error"] = Contract.SHOP_ERR_NOT_OWNED if code == "" else code
		body["ok"] = false
	elif status >= 400 and not body.has("error"):
		var result: Variant = body.get("result", {})
		if result is Dictionary and str(result.get("reason", "")) != "":
			body["error"] = str(result.get("reason"))
		else:
			body["error"] = "http_%s" % str(status)
	if is_buy or is_equip or is_me:
		if body.has("ok"):
			body["ok"] = bool(body.get("ok"))
		elif is_me:
			body["ok"] = status >= 200 and status < 300 and str(body.get("error", "")) == ""
		else:
			body["ok"] = status >= 200 and status < 300 and str(body.get("error", "")) == ""
		if not body.has("snapshot"):
			if body.has("you") or body.has("marks") or body.has("owned") or body.has("item") \
					or body.has("equipped") or body.has("equippedSkinId"):
				body["snapshot"] = body.duplicate(true)
	body["status"] = status
	return body


func create_job(tier: int = 1, client_job_id: String = "") -> Dictionary:
	## LIVE POST /jobs { tier: 1|2|3, clientJobId? }. Zod currently keeps `tier` only.
	## Credit is match/job end — this call does not grant Marks.
	var payload := {"tier": clampi(tier, 1, 3)}
	if client_job_id != "":
		payload["clientJobId"] = client_job_id
	var body: Dictionary = _json("POST", "/jobs", payload, ClientSession.player_bearer())
	if body.has("error") and not body.has("matchId"):
		last_error = str(body.get("error", "job_create_failed"))
	return body


func get_job(job_id: String) -> Dictionary:
	var token := ClientSession.join_token
	var body: Dictionary = _json("GET", "/jobs/%s" % job_id, null, token)
	if body.has("error") and not body.has("jobId"):
		last_error = str(body.get("error", "job_get_failed"))
	return body


func heartbeat() -> Dictionary:
	if ClientSession.match_id == "" or ClientSession.join_token == "":
		return {}
	return _json("POST", "/matches/%s/heartbeat" % ClientSession.match_id, {}, ClientSession.join_token)


func join(match_id: String, token: String) -> Dictionary:
	## Body token is the join token. Bearer player token binds an empty seat.
	## Dummy seat B must not reuse player A's token (409 same player both seats).
	var bearer := _join_bearer(token)
	var body: Dictionary = _json("POST", "/matches/%s/join" % match_id, {"token": token}, bearer)
	if body.has("playerId") and body.has("snapshot"):
		return body
	if body.has("error"):
		return body
	return {"error": str(body.get("error", "join_failed"))}


func _join_bearer(join_token: String) -> String:
	if join_token != "" and join_token == ClientSession.dummy_token:
		return join_token
	if ClientSession.player_bearer() != "":
		return ClientSession.player_bearer()
	return join_token


func get_snapshot(match_id: String, player_id: String) -> Dictionary:
	var token := ClientSession.token_for(player_id)
	var body: Dictionary = _json("GET", "/matches/%s" % match_id, null, token)
	if body.has("matchId"):
		return body
	var snap: Variant = body.get("snapshot", {})
	if snap is Dictionary and snap.has("matchId"):
		return snap
	return {}


func abandon(match_id: String, token: String = "") -> Dictionary:
	## LIVE POST /matches/:id/abandon + join Bearer. Same forfeit path as timeout.
	if match_id == "":
		match_id = ClientSession.match_id
	var bearer := token
	if bearer == "":
		bearer = ClientSession.join_token
	if bearer == "":
		bearer = ClientSession.player_bearer()
	## LIVE contract: no body. Same forfeit path as timeout.
	var raw: Dictionary = _raw("POST", "/matches/%s/abandon" % match_id, null, bearer)
	return _abandon_from_raw(raw, match_id, bearer)


func _abandon_from_raw(raw: Dictionary, match_id: String, token: String) -> Dictionary:
	var http_status := int(raw.get("status", 0))
	var js: Variant = raw.get("json", {})
	if not (js is Dictionary):
		js = {}
	var body: Dictionary = js
	if http_status == 404:
		return {
			"ok": false,
			"error": Contract.ABANDON_ERR_UNAVAILABLE,
			"status": 404,
			"snapshot": {},
		}
	## Coder: already ended is 409 match_already_ended. Treat as idempotent OK.
	if http_status == 409 and str(body.get("code", "")) == "match_already_ended":
		var replay_ended: Dictionary = _json("GET", "/matches/%s" % match_id, null, token)
		if replay_ended.has("matchId"):
			return {
				"ok": true,
				"alreadyEnded": true,
				"status": http_status,
				"code": body.get("code", ""),
				"snapshot": replay_ended,
			}
	if http_status >= 400:
		var snap: Variant = body.get("snapshot", {})
		if snap is Dictionary and str(snap.get("status", "")) == Contract.STATUS_ENDED:
			body["ok"] = true
			body["alreadyEnded"] = true
			body["status"] = http_status
			return body
		if str(body.get("error", "")) == "":
			body["error"] = "http_%s" % str(http_status)
		body["ok"] = false
		body["status"] = http_status
		return body
	body["ok"] = true
	body["status"] = http_status
	if not body.has("snapshot") or not (body.get("snapshot") is Dictionary) \
			or not body.get("snapshot").has("matchId"):
		if body.has("matchId"):
			body["snapshot"] = body.duplicate(true)
		else:
			var replay: Dictionary = _json("GET", "/matches/%s" % match_id, null, token)
			if replay.has("matchId"):
				body["snapshot"] = replay
	if str(body.get("snapshot", {}).get("status", "")) == Contract.STATUS_ENDED:
		body["alreadyEnded"] = bool(body.get("alreadyEnded", true))
	return body


func rematch(match_id: String, accept: bool, token: String = "") -> Dictionary:
	## LIVE POST /matches/:id/rematch { accept }.
	## Bearer prefers the seat join token (Coder), then durable player token.
	var bearer := token
	if bearer == "":
		bearer = ClientSession.join_token
	if bearer == "":
		bearer = ClientSession.player_bearer()
	var raw: Dictionary = _raw("POST", "/matches/%s/rematch" % match_id, {"accept": accept}, bearer)
	return _rematch_from_raw(raw)


func _rematch_from_raw(raw: Dictionary) -> Dictionary:
	var http_status := int(raw.get("status", 0))
	var js: Variant = raw.get("json", {})
	if not (js is Dictionary):
		js = {}
	var body: Dictionary = js
	if http_status == 404:
		return {
			"ok": false,
			"error": Contract.REMATCH_ERR_UNAVAILABLE,
			"status": 404,
			"rematch": {},
			"snapshot": {},
		}
	if http_status >= 400:
		if str(body.get("error", "")) == "":
			var result: Variant = body.get("result", {})
			if result is Dictionary and str(result.get("reason", "")) != "":
				body["error"] = str(result.get("reason"))
			else:
				body["error"] = "http_%s" % str(http_status)
		body["ok"] = false
		body["httpStatus"] = http_status
		return body
	## LIVE: waiting | ready { matchId, joinToken, snapshot? } | declined | expired
	## Snapshot on ready is optional — bind_new_match GETs the new match. Replay after ready for joinToken.
	var rem_st := str(body.get("status", ""))
	var snap: Variant = body.get("snapshot", {})
	if not body.has("rematch"):
		if snap is Dictionary and snap.has("rematch"):
			body["rematch"] = snap.get("rematch")
		else:
			var rem := {
				"status": rem_st if rem_st != "" else Contract.REMATCH_WAITING,
				"youAccepted": bool(body.get("youAccepted", rem_st == Contract.REMATCH_READY)),
				"opponentAccepted": bool(body.get("opponentAccepted", rem_st == Contract.REMATCH_READY)),
			}
			if str(body.get("expiresAt", "")) != "":
				rem["expiresAt"] = body.get("expiresAt")
			var new_id := str(body.get("matchId", body.get("newMatchId", "")))
			if rem_st == Contract.REMATCH_READY and new_id != "":
				rem["newMatchId"] = new_id
				rem["matchId"] = new_id
			body["rematch"] = rem
	if rem_st == Contract.REMATCH_READY:
		var mid := str(body.get("matchId", body.get("newMatchId", "")))
		if mid != "":
			body["newMatchId"] = mid
			body["matchId"] = mid
	if not body.has("ok"):
		body["ok"] = http_status >= 200 and http_status < 300
	body["httpStatus"] = http_status
	return body


func apply_action(match_id: String, player_id: String, action: Dictionary) -> ActionResult:
	var token := ClientSession.token_for(player_id)
	# Live contract: no `start` — both select_hex auto-activates. Treat as reconnect no-op.
	if str(action.get("type", "")) == Contract.ACT_START:
		var snap: Dictionary = get_snapshot(match_id, player_id)
		if str(snap.get("status", "")) == Contract.STATUS_ACTIVE:
			return ActionResult.ok_result(snap)
	var raw: Dictionary = _raw("POST", "/matches/%s/actions" % match_id, action, token)
	var parsed: ActionResult = ActionResult.from_http(int(raw.get("status", 0)), raw.get("json", {}))
	if parsed.ok and player_id == ClientSession.player_id:
		var ev := parsed.event
		if ev == "":
			ev = Contract.EVENT_SNAPSHOT
		match_event.emit(player_id, ev, parsed.snapshot)
	return parsed


func start_events(match_id: String, token: String) -> void:
	stop_events()
	_sse_match_id = match_id
	_sse_token = token
	_last_fp = ""
	var url := _split_base(ClientSession.api_base_url())
	_sse_host = str(url.get("host", "glassline-api.vercel.app"))
	_sse_port = int(url.get("port", 443 if bool(url.get("tls", true)) else 80))
	_sse_tls = bool(url.get("tls", false))
	_sse = HTTPClient.new()
	_sse_buf = ""
	_sse_event = ""
	_connecting_sse = true
	realtime_mode = "sse"
	var tls: TLSOptions = TLSOptions.client() if _sse_tls else null
	var err := _sse.connect_to_host(_sse_host, _sse_port, tls)
	if err != OK:
		last_error = "sse_connect"
		_connecting_sse = false
		_sse = null
		_start_poll("sse_connect")


func stop_events() -> void:
	_connecting_sse = false
	_poll = false
	_poll_accum = 0.0
	realtime_mode = ""
	if _sse != null:
		_sse.close()
	_sse = null
	_sse_buf = ""
	_sse_event = ""


func _process(delta: float) -> void:
	if _poll:
		_poll_accum += delta
		if _poll_accum >= POLL_SEC:
			_poll_accum = 0.0
			_poll_once()
		return
	if _sse == null:
		return
	_sse.poll()
	var st := _sse.get_status()
	if _connecting_sse:
		if st == HTTPClient.STATUS_RESOLVING or st == HTTPClient.STATUS_CONNECTING:
			return
		if st != HTTPClient.STATUS_CONNECTED:
			_start_poll("sse_status_%d" % st)
			return
		var path := "/matches/%s/events" % _sse_match_id
		var headers := PackedStringArray([
			"Accept: text/event-stream",
			"Cache-Control: no-cache",
			"Authorization: Bearer %s" % _sse_token,
		])
		var err := _sse.request(HTTPClient.METHOD_GET, path, headers)
		_connecting_sse = false
		if err != OK:
			_start_poll("sse_request")
		return
	if st == HTTPClient.STATUS_BODY:
		var chunk := _sse.read_response_body_chunk()
		if chunk.size() > 0:
			_sse_buf += chunk.get_string_from_utf8()
			_drain_sse()
	elif st == HTTPClient.STATUS_CONNECTION_ERROR or st == HTTPClient.STATUS_DISCONNECTED:
		# Vercel/serverless often closes the stream after a tick — poll instead of reconnect storm.
		_start_poll("sse_closed")


func _start_poll(reason: String) -> void:
	last_error = reason
	_connecting_sse = false
	if _sse != null:
		_sse.close()
	_sse = null
	_sse_buf = ""
	_sse_event = ""
	if _sse_match_id == "" or _sse_token == "":
		_poll = false
		realtime_mode = ""
		return
	_poll = true
	_poll_accum = 0.0
	realtime_mode = "poll"
	_poll_once()


func _poll_once() -> void:
	if _sse_match_id == "" or _sse_token == "":
		return
	var raw: Dictionary = _raw("GET", "/matches/%s" % _sse_match_id, null, _sse_token)
	var js: Variant = raw.get("json", {})
	if not (js is Dictionary) or not js.has("matchId"):
		if poll_failed_since_msec < 0:
			poll_failed_since_msec = Time.get_ticks_msec()
		return
	poll_failed_since_msec = -1
	var snap: Dictionary = js
	heartbeat()
	var rem: Variant = snap.get("rematch", {})
	var rem_st := ""
	var rem_new := ""
	if rem is Dictionary:
		rem_st = str(rem.get("status", ""))
		rem_new = str(rem.get("newMatchId", ""))
	var fp := "%s|%s|%s|%s|%s|%s|%s" % [
		str(snap.get("status", "")),
		str(snap.get("phase", "")),
		str(snap.get("whoseTurn", "")),
		str(snap.get("turnIndex", "")),
		str(snap.get("endReason", "")),
		rem_st,
		rem_new,
	]
	var last: Variant = snap.get("lastAction", {})
	if last is Dictionary:
		fp += "|%s|%s" % [str(last.get("type", "")), str(last.get("decoyCleared", ""))]
	var you_live: Variant = snap.get("you", {})
	if you_live is Dictionary:
		fp += "|d:%s|%s|%s" % [
			str(you_live.get("decoyAvailable", "")),
			str(you_live.get("decoyRemaining", "")),
			Contract.hex_key(you_live.get("decoyHex", null)),
		]
	var enemy_live: Variant = snap.get("enemy", {})
	if enemy_live is Dictionary:
		fp += "|s:%s" % Contract.hex_key(enemy_live.get("decoySoftHex", null))
	if fp == _last_fp:
		return
	_last_fp = fp
	var ev := Contract.EVENT_SNAPSHOT
	if str(snap.get("status", "")) == Contract.STATUS_ACTIVE \
			and str(snap.get("phase", "")) == Contract.PHASE_ACTION \
			and str(snap.get("whoseTurn", "")) == ClientSession.seat:
		ev = Contract.EVENT_YOUR_TURN
	var pid := ClientSession.player_id
	if pid != "":
		match_event.emit(pid, ev, snap)


func _drain_sse() -> void:
	while true:
		var nl := _sse_buf.find("\n")
		if nl < 0:
			return
		var line := _sse_buf.substr(0, nl).strip_edges()
		_sse_buf = _sse_buf.substr(nl + 1)
		if line == "":
			_sse_event = ""
			continue
		if line.begins_with("event:"):
			_sse_event = line.substr(6).strip_edges()
		elif line.begins_with("data:"):
			var payload := line.substr(5).strip_edges()
			_emit_sse_data(payload)


func _emit_sse_data(payload: String) -> void:
	var parsed: Variant = JSON.parse_string(payload)
	if not (parsed is Dictionary):
		return
	var body: Dictionary = parsed
	var ev := _sse_event
	if ev == "":
		ev = str(body.get("event", Contract.EVENT_SNAPSHOT))
	var snap: Variant = body.get("snapshot", body)
	if not (snap is Dictionary) or not snap.has("matchId"):
		return
	var pid := ClientSession.player_id
	if pid == "":
		return
	_last_fp = "%s|%s|%s|%s" % [
		str(snap.get("status", "")),
		str(snap.get("phase", "")),
		str(snap.get("whoseTurn", "")),
		str(snap.get("turnIndex", "")),
	]
	match_event.emit(pid, ev, snap)


func _json(method: String, path: String, body: Variant, token: String) -> Dictionary:
	var raw: Dictionary = _raw(method, path, body, token)
	var js: Variant = raw.get("json", {})
	if js is Dictionary:
		if int(raw.get("status", 0)) >= 400 and not js.has("error"):
			js["error"] = "http_%s" % str(raw.get("status", 0))
		return js
	return {"error": str(raw.get("error", "bad_json"))}


func _raw(method: String, path: String, body: Variant, token: String) -> Dictionary:
	var base := _split_base(ClientSession.api_base_url())
	var client := HTTPClient.new()
	var tls: TLSOptions = TLSOptions.client() if bool(base.get("tls", false)) else null
	var err := client.connect_to_host(str(base["host"]), int(base["port"]), tls)
	if err != OK:
		last_error = "connect"
		return {"status": 0, "json": {"error": "connect"}, "error": "connect"}
	var started := Time.get_ticks_msec()
	while client.get_status() == HTTPClient.STATUS_RESOLVING or client.get_status() == HTTPClient.STATUS_CONNECTING:
		client.poll()
		if Time.get_ticks_msec() - started > TIMEOUT_MSEC:
			client.close()
			last_error = "timeout"
			return {"status": 0, "json": {"error": "timeout"}, "error": "timeout"}
		OS.delay_msec(5)
	if client.get_status() != HTTPClient.STATUS_CONNECTED:
		last_error = "not_connected"
		client.close()
		return {"status": 0, "json": {"error": "not_connected"}, "error": "not_connected"}
	var headers := PackedStringArray(["Accept: application/json", "Content-Type: application/json"])
	if token != "":
		headers.append("Authorization: Bearer %s" % token)
	var payload := ""
	if body != null:
		payload = JSON.stringify(body)
	var verb := HTTPClient.METHOD_GET
	match method:
		"POST":
			verb = HTTPClient.METHOD_POST
		"PUT":
			verb = HTTPClient.METHOD_PUT
	err = client.request(verb, path, headers, payload)
	if err != OK:
		client.close()
		last_error = "request"
		return {"status": 0, "json": {"error": "request"}, "error": "request"}
	while client.get_status() == HTTPClient.STATUS_REQUESTING:
		client.poll()
		if Time.get_ticks_msec() - started > TIMEOUT_MSEC:
			client.close()
			last_error = "timeout"
			return {"status": 0, "json": {"error": "timeout"}, "error": "timeout"}
		OS.delay_msec(5)
	var code := client.get_response_code()
	var chunks := PackedByteArray()
	while client.get_status() == HTTPClient.STATUS_BODY:
		client.poll()
		var piece := client.read_response_body_chunk()
		if piece.size() > 0:
			chunks.append_array(piece)
		else:
			OS.delay_msec(5)
		if Time.get_ticks_msec() - started > TIMEOUT_MSEC:
			break
	client.close()
	var text := chunks.get_string_from_utf8()
	var js: Variant = {}
	if text != "":
		js = JSON.parse_string(text)
	if not (js is Dictionary):
		js = {}
	return {"status": code, "json": js}


func _split_base(url: String) -> Dictionary:
	var tls := url.begins_with("https://")
	var rest := url
	if rest.begins_with("https://"):
		rest = rest.substr(8)
	elif rest.begins_with("http://"):
		rest = rest.substr(7)
	var hostport := rest
	var slash := rest.find("/")
	if slash >= 0:
		hostport = rest.substr(0, slash)
	var host := hostport
	var port := 443 if tls else 80
	var colon := hostport.rfind(":")
	if colon > 0:
		host = hostport.substr(0, colon)
		port = int(hostport.substr(colon + 1))
	return {"host": host, "port": port, "tls": tls}
