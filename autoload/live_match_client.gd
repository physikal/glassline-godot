extends Node
## HTTPS + SSE client for the locked Glassline Hono API.
## Same method names as MockMatchServer. Bearer = join token.

const Contract := preload("res://types/contract.gd")
const ActionResult := preload("res://types/action_result.gd")

signal match_event(player_id: String, event_name: String, snapshot: Dictionary)

const TIMEOUT_MSEC := 8000

var last_error: String = ""

var _sse: HTTPClient
var _sse_buf: String = ""
var _sse_event: String = ""
var _sse_match_id: String = ""
var _sse_token: String = ""
var _sse_host: String = ""
var _sse_port: int = 80
var _sse_tls: bool = false
var _connecting_sse: bool = false


func clear_all() -> void:
	stop_events()
	last_error = ""


func health() -> Dictionary:
	return _json("GET", "/health", null, "")


func create_match() -> Dictionary:
	var body: Dictionary = _json("POST", "/matches", {}, "")
	if body.has("error") and not body.has("matchId"):
		last_error = str(body.get("error", "create_failed"))
	return body


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
	var url := _split_base(ClientSession.api_base_url())
	_sse_host = str(url.get("host", "127.0.0.1"))
	_sse_port = int(url.get("port", 80))
	_sse_tls = bool(url.get("tls", false))
	_sse = HTTPClient.new()
	_sse_buf = ""
	_sse_event = ""
	_connecting_sse = true
	var tls: TLSOptions = TLSOptions.client() if _sse_tls else null
	var err := _sse.connect_to_host(_sse_host, _sse_port, tls)
	if err != OK:
		last_error = "sse_connect"
		_connecting_sse = false
		_sse = null


func stop_events() -> void:
	_connecting_sse = false
	if _sse != null:
		_sse.close()
	_sse = null
	_sse_buf = ""
	_sse_event = ""


func _process(_delta: float) -> void:
	if _sse == null:
		return
	_sse.poll()
	var st := _sse.get_status()
	if _connecting_sse:
		if st == HTTPClient.STATUS_RESOLVING or st == HTTPClient.STATUS_CONNECTING:
			return
		if st != HTTPClient.STATUS_CONNECTED:
			last_error = "sse_status_%d" % st
			stop_events()
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
			last_error = "sse_request"
			stop_events()
		return
	if st == HTTPClient.STATUS_BODY:
		var chunk := _sse.read_response_body_chunk()
		if chunk.size() > 0:
			_sse_buf += chunk.get_string_from_utf8()
			_drain_sse()
	elif st == HTTPClient.STATUS_CONNECTION_ERROR or st == HTTPClient.STATUS_DISCONNECTED:
		var mid := _sse_match_id
		var tok := _sse_token
		stop_events()
		if mid != "" and tok != "":
			start_events(mid, tok)


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
