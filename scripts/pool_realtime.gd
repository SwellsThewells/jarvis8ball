class_name PoolRealtime
extends Node

# One WebSocket to Supabase Realtime, speaking its Phoenix channel protocol:
# join a topic, send and receive broadcasts on it, say you're there
# (presence), and hear about new rows in the database (postgres changes).
# It keeps the socket alive with a heartbeat, and if the connection drops it
# reconnects and rejoins every channel it was in.

signal broadcast_received(topic: String, event: String, payload: Dictionary)
signal presence_changed(topic: String, state: Dictionary)
signal db_changed(topic: String, data: Dictionary)
signal channel_joined(topic: String)
signal connection_changed(up: bool)

const HEARTBEAT := 25.0
# Supabase counts every message against a per-second allowance for the whole
# project, and closes a channel that goes over. Each channel keeps well under
# it: anything that must arrive waits its turn, anything that can be skipped
# (where someone is standing) is dropped instead.
const SEND_RATE := 12.0             # messages a second, per channel
const SEND_BURST := 12.0

var endpoint := ""          # wss://<project>.supabase.co/realtime/v1/websocket
var api_key := ""
var access_token := ""

var _ws: WebSocketPeer
var _up := false
var _want := false
var _retry_in := 0.0
var _backoff := 1.0
var _hb := 0.0
var _ref := 0
# topic -> {config, join_ref, joined, track (meta or null), presence {key: [metas]},
#          queue [[event, payload]], tokens, rejoin_at}
var _channels := {}


func open(url: String, key: String, token: String) -> void:
	endpoint = url.replace("https://", "wss://").replace("http://", "ws://").trim_suffix("/") \
		+ "/realtime/v1/websocket?apikey=%s&vsn=1.0.0" % key.uri_encode()
	api_key = key
	access_token = token
	_want = true
	_connect()


func close() -> void:
	_want = false
	_channels.clear()
	if _ws != null:
		_ws.close()
	_ws = null
	if _up:
		_up = false
		connection_changed.emit(false)


func is_up() -> bool:
	return _up


func set_token(token: String) -> void:
	access_token = token
	for topic in _channels:
		if _channels[topic].joined:
			_send(topic, "access_token", {"access_token": token}, _channels[topic].join_ref)


# Join a channel. postgres: a list of {event, schema, table, filter} to be
# told about; presence_key: who you are on this channel (usually your id).
func join(topic: String, presence_key := "", postgres: Array = []) -> void:
	var full := _full(topic)
	if _channels.has(full):
		return
	_channels[full] = {
		"config": {
			"broadcast": {"self": false, "ack": false},
			"presence": {"key": presence_key},
			"postgres_changes": postgres,
			"private": false,
		},
		"join_ref": "",
		"joined": false,
		"track": null,
		"presence": {},
		"queue": [],
		"tokens": SEND_BURST,
		"rejoin_at": 0,
	}
	if _up:
		_join(full)


func leave(topic: String) -> void:
	var full := _full(topic)
	if not _channels.has(full):
		return
	if _up and _channels[full].joined:
		_send(full, "phx_leave", {}, _channels[full].join_ref)
	_channels.erase(full)


func in_channel(topic: String) -> bool:
	var full := _full(topic)
	return _channels.has(full) and _channels[full].joined


# Broadcast to everyone else on the channel. `reliable` messages wait (in
# order) through a dropped connection or a busy moment; the others are just
# skipped if they can't go now.
func send(topic: String, event: String, payload: Dictionary, reliable := true) -> void:
	var full := _full(topic)
	if not _channels.has(full):
		return
	var ch: Dictionary = _channels[full]
	if reliable:
		(ch.queue as Array).append([event, payload])
		_flush(full)
	elif _up and ch.joined and (ch.queue as Array).is_empty() and float(ch.tokens) >= 1.0:
		ch.tokens = float(ch.tokens) - 1.0
		_send(full, "broadcast", {"type": "broadcast", "event": event, "payload": payload}, ch.join_ref)


func _flush(full: String) -> void:
	var ch: Dictionary = _channels[full]
	var q: Array = ch.queue
	while _up and ch.joined and not q.is_empty() and float(ch.tokens) >= 1.0:
		ch.tokens = float(ch.tokens) - 1.0
		var m: Array = q.pop_front()
		_send(full, "broadcast", {"type": "broadcast", "event": m[0], "payload": m[1]}, ch.join_ref)


# What you want others on this channel to see about you. Sent again after
# any reconnect.
func track(topic: String, meta: Dictionary) -> void:
	var full := _full(topic)
	if not _channels.has(full):
		return
	_channels[full].track = meta
	if _up and _channels[full].joined:
		_send(full, "presence", {"type": "presence", "event": "track", "payload": meta}, _channels[full].join_ref)


func presence(topic: String) -> Dictionary:
	var full := _full(topic)
	return _channels[full].presence if _channels.has(full) else {}


# ---------------------------------------------------------------------------

func _full(topic: String) -> String:
	return topic if topic.begins_with("realtime:") else "realtime:" + topic


func _connect() -> void:
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 1 << 20
	_ws.outbound_buffer_size = 1 << 20
	var err := _ws.connect_to_url(endpoint)
	if err != OK:
		_retry_in = _backoff
		_backoff = minf(_backoff * 2.0, 20.0)


func _join(full: String) -> void:
	_ref += 1
	var jr := str(_ref)
	_channels[full].join_ref = jr
	_channels[full].joined = false
	_channels[full].presence = {}
	var payload: Dictionary = {"config": _channels[full].config}
	if access_token != "":
		payload["access_token"] = access_token
	_send(full, "phx_join", payload, jr, jr)


func _send(topic: String, event: String, payload: Dictionary, join_ref := "", ref := "") -> void:
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	if ref == "":
		_ref += 1
		ref = str(_ref)
	var msg := {"topic": topic, "event": event, "payload": payload, "ref": ref}
	if join_ref != "":
		msg["join_ref"] = join_ref
	_ws.send_text(JSON.stringify(msg))


var _last_ms := 0
var _wall_dt := 0.0


func _process(delta: float) -> void:
	# the send allowance runs on the real clock, whatever the frame rate
	var now_ms := Time.get_ticks_msec()
	_wall_dt = clampf((now_ms - _last_ms) / 1000.0, 0.0, 1.0) if _last_ms > 0 else 0.0
	_last_ms = now_ms
	if _ws == null:
		if _want:
			_retry_in -= delta
			if _retry_in <= 0.0:
				_connect()
		return
	_ws.poll()
	var st := _ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if not _up:
			_up = true
			_backoff = 1.0
			_hb = 0.0
			for full in _channels:
				_join(full)
			connection_changed.emit(true)
		_hb += delta
		if _hb >= HEARTBEAT:
			_hb = 0.0
			_send("phoenix", "heartbeat", {})
		var now := Time.get_ticks_msec()
		for full in _channels:
			var ch: Dictionary = _channels[full]
			ch.tokens = minf(SEND_BURST, float(ch.tokens) + SEND_RATE * _wall_dt)
			if not ch.joined and int(ch.rejoin_at) > 0 and now >= int(ch.rejoin_at):
				ch.rejoin_at = 0
				_join(full)
			if not (ch.queue as Array).is_empty():
				_flush(full)
		while _ws.get_available_packet_count() > 0:
			var txt := _ws.get_packet().get_string_from_utf8()
			var msg: Variant = JSON.parse_string(txt)
			if typeof(msg) == TYPE_DICTIONARY:
				_handle(msg)
	elif st == WebSocketPeer.STATE_CLOSED:
		_ws = null
		for full in _channels:
			_channels[full].joined = false
		if _up:
			_up = false
			connection_changed.emit(false)
		if _want:
			_retry_in = _backoff
			_backoff = minf(_backoff * 2.0, 20.0)


func _handle(msg: Dictionary) -> void:
	var topic := str(msg.get("topic", ""))
	var event := str(msg.get("event", ""))
	var payload: Dictionary = msg.get("payload", {}) if typeof(msg.get("payload")) == TYPE_DICTIONARY else {}
	if not _channels.has(topic):
		return
	var ch: Dictionary = _channels[topic]
	match event:
		"phx_reply":
			if str(msg.get("ref", "")) == ch.join_ref and not ch.joined:
				if str(payload.get("status", "")) == "ok":
					ch.joined = true
					if ch.track != null:
						_send(topic, "presence", {"type": "presence", "event": "track", "payload": ch.track}, ch.join_ref)
					_flush(topic)
					channel_joined.emit(topic.trim_prefix("realtime:"))
				else:
					push_warning("Realtime join failed for %s: %s" % [topic, JSON.stringify(payload)])
		"phx_error", "phx_close":
			# only the channel as we last joined it counts; a close for an
			# older join is the server tidying up
			var jr: Variant = msg.get("join_ref")
			var owner := str(jr) if jr != null else str(msg.get("ref", ""))
			if owner != ch.join_ref:
				return
			ch.joined = false
			if _up and _want:
				# the server dropped us from this channel: back in shortly
				ch.rejoin_at = Time.get_ticks_msec() + 1500
		"broadcast":
			var inner: Variant = payload.get("payload", {})
			broadcast_received.emit(topic.trim_prefix("realtime:"), str(payload.get("event", "")),
				inner if typeof(inner) == TYPE_DICTIONARY else {})
		"presence_state":
			ch.presence = {}
			for key in payload:
				ch.presence[key] = (payload[key] as Dictionary).get("metas", [])
			presence_changed.emit(topic.trim_prefix("realtime:"), ch.presence)
		"presence_diff":
			var joins: Dictionary = payload.get("joins", {})
			var leaves: Dictionary = payload.get("leaves", {})
			for key in leaves:
				ch.presence.erase(key)
			for key in joins:
				ch.presence[key] = (joins[key] as Dictionary).get("metas", [])
			presence_changed.emit(topic.trim_prefix("realtime:"), ch.presence)
		"postgres_changes":
			var data: Variant = payload.get("data", {})
			if typeof(data) == TYPE_DICTIONARY:
				db_changed.emit(topic.trim_prefix("realtime:"), data)
