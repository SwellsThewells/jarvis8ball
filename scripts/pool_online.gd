class_name PoolOnline
extends Node

# Everything online: signing in with Discord, your coins and cues, friends and
# messages, and lobbies. It all lives in a Supabase project (see
# ONLINE_SETUP.md and supabase/schema.sql); this talks to it over HTTPS for
# requests and one WebSocket (PoolRealtime) for anything live.
#
# Signing in opens Discord in your browser. Supabase sends the browser back
# to a tiny web page this game serves on 127.0.0.1 for a moment, carrying a
# one-time code, and the game trades that code for a session (the PKCE flow:
# nothing secret ever has to be built into the game).
#
# The one instance is PoolOnline.inst, so menus and the game can all reach it.

signal auth_changed()                         # signed in or out
signal me_changed()                           # coins, cues, trophies, stats
signal friends_changed()
signal message_received(msg: Dictionary)      # someone sent you something
signal conversation_changed(user_id: String)
signal lobby_changed()                        # the lobby row, or who's in it
signal lobby_event(event: String, payload: Dictionary)
signal notice(text: String)                   # something worth a toast
signal avatar_loaded(url: String)

const CALLBACK_PORT := 47219
const CALLBACK_PATH := "/callback"
const SESSION_PATH := "user://online_session.cfg"
const CONFIG_NAME := "online.cfg"

static var inst: PoolOnline

var url := ""
var api_key := ""

var access_token := ""
var refresh_token := ""
var expires_at := 0.0
var user_id := ""
var me: Dictionary = {}                       # your profile row
var signing_in := false                       # waiting on the browser

var friends: Array = []                       # [{id, username, display_name, avatar_url, trophies, status, unread}]
var online := {}                              # user id -> {status, name}
var conversations := {}                       # user id -> [message rows], oldest first
var open_chat := ""                           # whose conversation is on screen (read as they arrive)

var lobby: Dictionary = {}                    # the lobby you're in, as public.lobby() returns it
var lobby_members := {}                       # user id -> presence meta, on the lobby channel

var rt: PoolRealtime
var _status := "menu"
var _tcp: TCPServer
var _verifier := ""
var _sign_in_until := 0.0
var _refresh_busy := false
var _avatars := {}                            # url -> Texture2D (or null while loading)
var _lobby_tick := 0.0
var _friends_tick := 0.0


func _init() -> void:
	inst = self


func _ready() -> void:
	_load_config()
	rt = PoolRealtime.new()
	rt.name = "Realtime"
	add_child(rt)
	rt.broadcast_received.connect(_on_broadcast)
	rt.presence_changed.connect(_on_presence)
	rt.db_changed.connect(_on_db)
	if configured():
		_resume_session()


func configured() -> bool:
	return url != "" and api_key != ""


func signed_in() -> bool:
	return user_id != "" and access_token != ""


func _load_config() -> void:
	# a file next to the exe wins, so a build can be pointed at another project
	# without rebuilding; otherwise the one in the project
	for path in [OS.get_executable_path().get_base_dir().path_join(CONFIG_NAME), "res://" + CONFIG_NAME]:
		var cfg := ConfigFile.new()
		if cfg.load(path) == OK:
			url = str(cfg.get_value("supabase", "url", "")).strip_edges().trim_suffix("/")
			api_key = str(cfg.get_value("supabase", "anon_key", "")).strip_edges()
			if configured():
				return


# ---------------------------------------------------------------------------
# Signing in
# ---------------------------------------------------------------------------

func sign_in_discord() -> void:
	if not configured():
		notice.emit("Online play isn't set up in this build yet. See ONLINE_SETUP.md.")
		return
	if signed_in() or signing_in:
		return
	_tcp = TCPServer.new()
	if _tcp.listen(CALLBACK_PORT, "127.0.0.1") != OK:
		_tcp = null
		notice.emit("Couldn't start sign-in (port %d is busy). Close other copies of the game and try again." % CALLBACK_PORT)
		return
	_verifier = _random_string(64)
	var challenge := Marshalls.raw_to_base64(_verifier.sha256_buffer()).replace("+", "-").replace("/", "_").trim_suffix("=").trim_suffix("=")
	var redirect := "http://127.0.0.1:%d%s" % [CALLBACK_PORT, CALLBACK_PATH]
	var auth_url := "%s/auth/v1/authorize?provider=discord&redirect_to=%s&code_challenge=%s&code_challenge_method=s256" % [
		url, redirect.uri_encode(), challenge]
	signing_in = true
	_sign_in_until = Time.get_ticks_msec() / 1000.0 + 180.0
	auth_changed.emit()
	OS.shell_open(auth_url)


func cancel_sign_in() -> void:
	if _tcp != null:
		_tcp.stop()
	_tcp = null
	if signing_in:
		signing_in = false
		auth_changed.emit()


# Email and password: not offered in the game, but handy for testing against
# a local Supabase without a Discord app.
func sign_in_password(email: String, password: String) -> bool:
	var r := await _http(HTTPClient.METHOD_POST, "/auth/v1/token?grant_type=password",
		{"email": email, "password": password}, false)
	if not r.ok:
		notice.emit("Sign-in failed: %s" % r.error)
		return false
	await _take_session(r.data)
	return true


func sign_out() -> void:
	if not signed_in():
		return
	leave_lobby()
	_http(HTTPClient.METHOD_POST, "/auth/v1/logout", {})
	rt.close()
	access_token = ""
	refresh_token = ""
	user_id = ""
	me = {}
	friends = []
	online = {}
	conversations = {}
	_save_session()
	auth_changed.emit()
	me_changed.emit()
	friends_changed.emit()


func _poll_callback() -> void:
	if _tcp == null:
		return
	if Time.get_ticks_msec() / 1000.0 > _sign_in_until:
		cancel_sign_in()
		notice.emit("Sign-in timed out. Try again when you're ready.")
		return
	if not _tcp.is_connection_available():
		return
	var peer := _tcp.take_connection()
	var raw := ""
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 2000:
		peer.poll()
		var n := peer.get_available_bytes()
		if n > 0:
			raw += peer.get_utf8_string(n)
			if raw.contains("\r\n\r\n"):
				break
		else:
			OS.delay_msec(5)
	var line := raw.get_slice("\r\n", 0)       # GET /callback?code=... HTTP/1.1
	var target := line.get_slice(" ", 1)
	var query := target.get_slice("?", 1) if target.contains("?") else ""
	var params := {}
	for pair in query.split("&", false):
		params[pair.get_slice("=", 0)] = pair.get_slice("=", 1).uri_decode()
	if not target.begins_with(CALLBACK_PATH):
		_reply(peer, 404, "Not here.")
		return
	var code := str(params.get("code", ""))
	if code == "":
		var why := str(params.get("error_description", params.get("error", "no code came back")))
		_reply(peer, 400, "Sign-in didn't work: %s. You can close this tab and try again from the game." % why.replace("+", " "))
		cancel_sign_in()
		notice.emit("Discord sign-in didn't work: %s" % why.replace("+", " "))
		return
	_reply(peer, 200, "You're signed in. Head back to Jarvis 8 Pool.")
	_tcp.stop()
	_tcp = null
	var r := await _http(HTTPClient.METHOD_POST, "/auth/v1/token?grant_type=pkce",
		{"auth_code": code, "code_verifier": _verifier}, false)
	signing_in = false
	if not r.ok:
		auth_changed.emit()
		notice.emit("Discord sign-in didn't work: %s" % r.error)
		return
	await _take_session(r.data)
	if signed_in():
		notice.emit("Signed in as %s" % display_name())


func _reply(peer: StreamPeerTCP, code: int, text: String) -> void:
	var body := "<!doctype html><html><head><meta charset='utf-8'><title>Jarvis 8 Pool</title></head>" \
		+ "<body style='background:#0b0c0d;color:#f7f3ea;font:20px system-ui;display:grid;place-items:center;height:90vh'>" \
		+ "<div style='text-align:center'><div style='font-size:44px;font-weight:800;margin-bottom:12px'>Jarvis 8 Pool</div>" \
		+ text.xml_escape() + "</div></body></html>"
	var bytes := body.to_utf8_buffer()
	var head := "HTTP/1.1 %d OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [code, bytes.size()]
	peer.put_data(head.to_utf8_buffer())
	peer.put_data(bytes)
	peer.disconnect_from_host()


func _take_session(s: Dictionary) -> void:
	access_token = str(s.get("access_token", ""))
	refresh_token = str(s.get("refresh_token", refresh_token))
	expires_at = Time.get_unix_time_from_system() + float(s.get("expires_in", 3600))
	var u: Dictionary = s.get("user", {})
	var new_id := str(u.get("id", user_id))
	var fresh := new_id != user_id
	user_id = new_id
	_save_session()
	if not fresh:
		rt.set_token(access_token)
		return
	await refresh_me()
	rt.open(url, api_key, access_token)
	rt.join("user:" + user_id, user_id, [
		{"event": "INSERT", "schema": "public", "table": "messages", "filter": "recipient=eq." + user_id},
		{"event": "*", "schema": "public", "table": "friendships", "filter": "addressee=eq." + user_id},
		{"event": "*", "schema": "public", "table": "friendships", "filter": "requester=eq." + user_id},
	])
	rt.join("online", user_id)
	_track_status()
	await refresh_friends()
	auth_changed.emit()


func _resume_session() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SESSION_PATH) != OK:
		return
	refresh_token = str(cfg.get_value("session", "refresh_token", ""))
	if refresh_token == "":
		return
	await _refresh()


func _refresh() -> void:
	if _refresh_busy or refresh_token == "":
		return
	_refresh_busy = true
	var r := await _http(HTTPClient.METHOD_POST, "/auth/v1/token?grant_type=refresh_token",
		{"refresh_token": refresh_token}, false)
	_refresh_busy = false
	if r.ok:
		await _take_session(r.data)
	elif r.code >= 400 and r.code < 500:
		# the session is gone for good (signed out elsewhere, or expired)
		refresh_token = ""
		_save_session()


func _save_session() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("session", "refresh_token", refresh_token)
	cfg.save(SESSION_PATH)


func display_name() -> String:
	return str(me.get("display_name", me.get("username", "Player")))


# ---------------------------------------------------------------------------
# HTTP
# ---------------------------------------------------------------------------

# One request. Returns {ok, code, data, error}.
func _http(method: int, path: String, body: Variant = null, as_user := true) -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = 20.0
	add_child(req)
	var headers := PackedStringArray(["apikey: " + api_key, "Content-Type: application/json", "Accept: application/json"])
	if as_user and access_token != "":
		headers.append("Authorization: Bearer " + access_token)
	var data := JSON.stringify(body) if body != null else ""
	var err := req.request(url + path, headers, method, data)
	if err != OK:
		req.queue_free()
		return {"ok": false, "code": 0, "data": null, "error": "couldn't reach the server"}
	var res: Array = await req.request_completed
	req.queue_free()
	var code: int = res[1]
	var text: String = (res[3] as PackedByteArray).get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text) if text != "" else null
	if res[0] != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "code": 0, "data": null, "error": "couldn't reach the server"}
	if code >= 200 and code < 300:
		return {"ok": true, "code": code, "data": parsed, "error": ""}
	var msg := "error %d" % code
	if typeof(parsed) == TYPE_DICTIONARY:
		for k in ["message", "msg", "error_description", "error"]:
			if parsed.has(k) and str(parsed[k]) != "":
				msg = str(parsed[k])
				break
	return {"ok": false, "code": code, "data": parsed, "error": msg}


# Call one of the functions in supabase/schema.sql.
func call_fn(fn: String, args: Dictionary = {}) -> Dictionary:
	if not signed_in():
		return {"ok": false, "code": 401, "data": null, "error": "not signed in"}
	var r := await _http(HTTPClient.METHOD_POST, "/rest/v1/rpc/" + fn, args)
	if r.code == 401 and refresh_token != "":
		await _refresh()
		r = await _http(HTTPClient.METHOD_POST, "/rest/v1/rpc/" + fn, args)
	return r


func _process(delta: float) -> void:
	_poll_callback()
	if not signed_in():
		return
	if expires_at - Time.get_unix_time_from_system() < 120.0:
		_refresh()
	# keep the lobby fresh (and on the public list) while you're in it
	if not lobby.is_empty():
		_lobby_tick += delta
		if _lobby_tick >= 20.0:
			_lobby_tick = 0.0
			refresh_lobby()
	# unfriending doesn't come through live, so look again now and then
	_friends_tick += delta
	if _friends_tick >= 45.0:
		_friends_tick = 0.0
		refresh_friends()


# ---------------------------------------------------------------------------
# You: coins, cues, stats
# ---------------------------------------------------------------------------

func refresh_me() -> void:
	var r := await call_fn("me")
	if r.ok and typeof(r.data) == TYPE_DICTIONARY:
		me = r.data
		me_changed.emit()


func coins() -> int:
	return int(me.get("coins", 0))


func owned_cues() -> Array:
	var out: Array = me.get("owned_cues", ["house"])
	return out


# Buys a cue. Returns "" when it worked, or why not.
func buy_cue(id: String) -> String:
	var r := await call_fn("buy_cue", {"p_cue": id})
	if not r.ok:
		return r.error
	if typeof(r.data) == TYPE_DICTIONARY:
		me = r.data
		me_changed.emit()
	return ""


func redeem_code(code: String) -> String:
	var r := await call_fn("redeem_code", {"p_code": code})
	if not r.ok:
		return ""
	await refresh_me()
	return str(r.data) if r.data != null else ""


# Pays for a drink. False when you can't afford it.
func spend(amount: int) -> bool:
	var r := await call_fn("spend_coins", {"p_amount": amount})
	if r.ok:
		me["coins"] = int(r.data)
		me_changed.emit()
	else:
		await refresh_me()
	return r.ok


func bot_reward(won: bool) -> void:
	var r := await call_fn("bot_reward", {"p_won": won})
	if r.ok:
		me["coins"] = int(r.data)
		me_changed.emit()


func save_stats(stats: Dictionary) -> void:
	var r := await call_fn("save_stats", {"p_stats": stats})
	if r.ok and typeof(r.data) == TYPE_DICTIONARY:
		me["stats"] = r.data


# ---------------------------------------------------------------------------
# Avatars
# ---------------------------------------------------------------------------

# The picture at `u`, or null until it has loaded (avatar_loaded says when).
func avatar(u: String) -> Texture2D:
	if not u.begins_with("http"):
		return null
	if _avatars.has(u):
		return _avatars[u]
	_avatars[u] = null
	_load_avatar(u)
	return null


func _load_avatar(u: String) -> void:
	var req := HTTPRequest.new()
	add_child(req)
	# ask Discord for a small PNG, whatever the avatar is
	var fetch := u
	if fetch.contains("cdn.discordapp.com"):
		fetch = fetch.get_slice("?", 0).get_basename() + ".png?size=128"
	if req.request(fetch) != OK:
		req.queue_free()
		return
	var res: Array = await req.request_completed
	req.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		return
	var bytes: PackedByteArray = res[3]
	var img := Image.new()
	var ok := img.load_png_from_buffer(bytes) == OK
	if not ok:
		ok = img.load_jpg_from_buffer(bytes) == OK
	if not ok:
		ok = img.load_webp_from_buffer(bytes) == OK
	if not ok:
		return
	img.generate_mipmaps()
	_avatars[u] = ImageTexture.create_from_image(img)
	avatar_loaded.emit(u)


# ---------------------------------------------------------------------------
# Friends and messages
# ---------------------------------------------------------------------------

func refresh_friends() -> void:
	var r := await call_fn("friends")
	if r.ok and typeof(r.data) == TYPE_ARRAY:
		friends = r.data
		friends_changed.emit()


func friend(id: String) -> Dictionary:
	for f in friends:
		if str(f.id) == id:
			return f
	return {}


func unread_total() -> int:
	var n := 0
	for f in friends:
		n += int(f.get("unread", 0))
	return n


func incoming_requests() -> int:
	var n := 0
	for f in friends:
		if str(f.status) == "incoming":
			n += 1
	return n


func find_players(q: String) -> Array:
	var r := await call_fn("find_players", {"p_query": q})
	return r.data if r.ok and typeof(r.data) == TYPE_ARRAY else []


func add_friend(id: String) -> String:
	var r := await call_fn("send_friend_request", {"p_user": id})
	await refresh_friends()
	return str(r.data) if r.ok else r.error


func answer_request(id: String, accept: bool) -> void:
	await call_fn("respond_friend_request", {"p_user": id, "p_accept": accept})
	await refresh_friends()


func remove_friend(id: String) -> void:
	await call_fn("remove_friend", {"p_user": id})
	conversations.erase(id)
	await refresh_friends()


func load_conversation(id: String) -> void:
	var r := await call_fn("conversation", {"p_with": id, "p_limit": 80})
	if r.ok and typeof(r.data) == TYPE_ARRAY:
		conversations[id] = r.data
	await mark_read(id)
	conversation_changed.emit(id)


func mark_read(id: String) -> void:
	var f := friend(id)
	if not f.is_empty() and int(f.get("unread", 0)) > 0:
		f["unread"] = 0
		friends_changed.emit()
	await call_fn("mark_read", {"p_from": id})


func send_message(to: String, body: String, kind := "text", lobby_id := "") -> String:
	var args := {"p_to": to, "p_body": body, "p_kind": kind}
	if lobby_id != "":
		args["p_lobby"] = lobby_id
	var r := await call_fn("send_message", args)
	if not r.ok:
		return r.error
	_append_message(to, r.data)
	return ""


func invite(to: String) -> String:
	if lobby.is_empty():
		return "You're not in a lobby"
	return await send_message(to, "Come play at %s (code %s)" % [str(lobby.get("name", "my table")), str(lobby.get("code", ""))],
		"invite", str(lobby.id))


func _append_message(other: String, m: Variant) -> void:
	if typeof(m) != TYPE_DICTIONARY:
		return
	if not conversations.has(other):
		conversations[other] = []
	for existing in conversations[other]:
		if int(existing.id) == int(m.id):
			return
	(conversations[other] as Array).append(m)
	conversation_changed.emit(other)


func is_online(id: String) -> bool:
	return online.has(id)


func status_of(id: String) -> String:
	return str((online.get(id, {}) as Dictionary).get("status", "offline"))


# What your friends see next to your name: in the menu, in a lobby, playing.
func set_status(s: String) -> void:
	_status = s
	_track_status()


func _track_status() -> void:
	if signed_in():
		rt.track("online", {"status": _status, "name": display_name()})


# ---------------------------------------------------------------------------
# Lobbies
# ---------------------------------------------------------------------------

func lobby_topic() -> String:
	return "lobby:" + str(lobby.get("id", ""))


func is_host() -> bool:
	return not lobby.is_empty() and str(lobby.get("host", "")) == user_id


# The other player in your lobby, or {}.
func opponent() -> Dictionary:
	if lobby.is_empty():
		return {}
	var p: Variant = lobby.get("guest_player") if is_host() else lobby.get("host_player")
	return p if typeof(p) == TYPE_DICTIONARY else {}


func public_lobbies() -> Array:
	var r := await call_fn("public_lobbies")
	return r.data if r.ok and typeof(r.data) == TYPE_ARRAY else []


func create_lobby(lobby_name: String, is_public: bool, rules: Dictionary) -> String:
	var r := await call_fn("create_lobby", {"p_name": lobby_name, "p_public": is_public, "p_rules": rules})
	if not r.ok:
		return r.error
	_enter_lobby(r.data)
	return ""


func update_lobby(lobby_name: String, is_public: bool, rules: Dictionary) -> String:
	if not is_host():
		return "Only the host can change the table"
	var r := await call_fn("update_lobby", {"p_id": lobby.id, "p_name": lobby_name, "p_public": is_public, "p_rules": rules})
	if not r.ok:
		return r.error
	lobby = r.data
	lobby_send("lobby", {})
	lobby_changed.emit()
	return ""


func join_lobby(id: String) -> String:
	var r := await call_fn("join_lobby", {"p_id": id})
	if not r.ok:
		return r.error
	_enter_lobby(r.data)
	return ""


func join_code(code: String) -> String:
	var r := await call_fn("join_lobby_code", {"p_code": code})
	if not r.ok:
		return r.error
	_enter_lobby(r.data)
	return ""


func leave_lobby() -> void:
	if lobby.is_empty():
		return
	var id := str(lobby.id)
	lobby_send("left", {})
	rt.leave(lobby_topic())
	lobby = {}
	lobby_members = {}
	set_status("menu")
	lobby_changed.emit()
	await call_fn("leave_lobby", {"p_id": id})


func refresh_lobby() -> void:
	if lobby.is_empty():
		return
	var r := await call_fn("lobby", {"p_id": lobby.id})
	if not r.ok or lobby.is_empty():
		return
	if typeof(r.data) != TYPE_DICTIONARY or str(r.data.get("status", "")) == "closed":
		_lobby_closed()
		return
	lobby = r.data
	lobby_changed.emit()


func set_lobby_status(s: String) -> void:
	if not lobby.is_empty():
		call_fn("set_lobby_status", {"p_id": lobby.id, "p_status": s})


func start_match() -> Dictionary:
	var r := await call_fn("start_match", {"p_lobby": lobby.id})
	return r.data if r.ok and typeof(r.data) == TYPE_DICTIONARY else {"error": r.error}


func report_result(match_id: String, winner: String) -> Dictionary:
	var r := await call_fn("report_result", {"p_match": match_id, "p_winner": winner})
	var out: Dictionary = r.data if r.ok and typeof(r.data) == TYPE_DICTIONARY else {"error": r.error}
	await refresh_me()
	return out


# To the other player in your lobby. Everything is sent reliably except
# where you're standing, which is only worth sending if it can go now.
func lobby_send(event: String, payload: Dictionary) -> void:
	if not lobby.is_empty():
		rt.send(lobby_topic(), event, payload, event != "pose")


func _enter_lobby(data: Variant) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		return
	if not lobby.is_empty() and str(lobby.id) != str(data.id):
		rt.leave(lobby_topic())
	lobby = data
	lobby_members = {}
	_lobby_tick = 0.0
	rt.join(lobby_topic(), user_id)
	rt.track(lobby_topic(), {"name": display_name(), "ready": false})
	set_status("lobby")
	lobby_changed.emit()


func _lobby_closed() -> void:
	rt.leave(lobby_topic())
	lobby = {}
	lobby_members = {}
	set_status("menu")
	lobby_changed.emit()
	lobby_event.emit("closed", {})


# ---------------------------------------------------------------------------
# Live events
# ---------------------------------------------------------------------------

func _on_broadcast(topic: String, event: String, payload: Dictionary) -> void:
	if lobby.is_empty() or topic != lobby_topic():
		return
	match event:
		"lobby", "joined":
			await refresh_lobby()
		"left":
			await refresh_lobby()
		"closed":
			_lobby_closed()
			return
	lobby_event.emit(event, payload)


func _on_presence(topic: String, state: Dictionary) -> void:
	if topic == "online":
		online = {}
		for key in state:
			var metas: Array = state[key]
			if not metas.is_empty():
				online[key] = metas[metas.size() - 1]
		friends_changed.emit()
	elif not lobby.is_empty() and topic == lobby_topic():
		var had_other := _other_present()
		lobby_members = {}
		for key in state:
			var metas: Array = state[key]
			if not metas.is_empty():
				lobby_members[key] = metas[metas.size() - 1]
		var has_other := _other_present()
		if has_other and not had_other:
			refresh_lobby()
		lobby_event.emit("presence", {"other_here": has_other})
		lobby_changed.emit()


func _other_present() -> bool:
	for k in lobby_members:
		if str(k) != user_id:
			return true
	return false


func other_here() -> bool:
	return _other_present()


func other_ready() -> bool:
	for k in lobby_members:
		if str(k) != user_id:
			return bool((lobby_members[k] as Dictionary).get("ready", false))
	return false


func set_ready(on: bool) -> void:
	if not lobby.is_empty():
		rt.track(lobby_topic(), {"name": display_name(), "ready": on})


func _on_db(topic: String, data: Dictionary) -> void:
	if topic != "user:" + user_id:
		return
	var table := str(data.get("table", ""))
	if table == "messages":
		var m: Dictionary = data.get("record", {})
		var from := str(m.get("sender", ""))
		_append_message(from, m)
		if open_chat == from:
			mark_read(from)
		else:
			var f := friend(from)
			if not f.is_empty():
				f["unread"] = int(f.get("unread", 0)) + 1
				friends_changed.emit()
		message_received.emit(m)
	elif table == "friendships":
		var before := incoming_requests()
		await refresh_friends()
		if incoming_requests() > before:
			notice.emit("New friend request")


# ---------------------------------------------------------------------------

func _random_string(n: int) -> String:
	var chars := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
	var crypto := Crypto.new()
	var bytes := crypto.generate_random_bytes(n)
	var s := ""
	for b in bytes:
		s += chars[b % chars.length()]
	return s
