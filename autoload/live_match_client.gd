extends Node
## HTTPS + SSE client for the locked Glassline Hono API.
## Same method names as MockMatchServer. Bearer = join token.

const Contract := preload("res://types/contract.gd")
const ActionResult := preload("res://types/action_result.gd")

signal match_event(player_id: String, event_name: String, snapshot: Dictionary)

const TIMEOUT_MSEC := 20000
const POLL_SEC := 1.0

var last_error: String = ""
var realtime_mode: String = "" ## "sse" | "poll" | ""

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


func health() -> Dictionary:
	return _json("GET", "/health", null, "")


func create_match(opts: Dictionary = {}) -> Dictionary:
	## Live POST /matches currently ignores body. Forward mode/job flags for Coder.
	var payload: Dictionary = opts.duplicate(true)
	var body: Dictionary = _json("POST", "/matches", payload, "")
	if body.has("error") and not body.has("matchId"):
		last_error = str(body.get("error", "create_failed"))
	return body


func wallet() -> Dictionary:
	## No dedicated LIVE wallet route. Hideout binds `you.marks`.
	return {}


func create_job(tier: int = 1) -> Dictionary:
	var body: Dictionary = _json("POST", "/jobs", {"tier": clampi(tier, 1, 3)}, "")
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
	var body: Dictionary = _json("POST", "/matches/%s/join" % match_id, {"token": token}, token)
	if body.has("playerId") and body.has("snapshot"):
		return body
	if body.has("error"):
		return body
	return {"error": str(body.get("error", "join_failed"))}


func get_snapshot(match_id: String, player_id: String) -> Dictionary:
	var token := ClientSession.token_for(player_id)
	var body: Dictionary = _json("GET", "/matches/%s" % match_id, null, token)
	if body.has("matchId"):
		return body
	var snap: Variant = body.get("snapshot", {})
	if snap is Dictionary and snap.has("matchId"):
		return snap
	return {}


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
		return
	var snap: Dictionary = js
	heartbeat()
	var fp := "%s|%s|%s|%s|%s" % [
		str(snap.get("status", "")),
		str(snap.get("phase", "")),
		str(snap.get("whoseTurn", "")),
		str(snap.get("turnIndex", "")),
		str(snap.get("endReason", "")),
	]
	var last: Variant = snap.get("lastAction", {})
	if last is Dictionary:
		fp += "|%s" % str(last.get("type", ""))
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
