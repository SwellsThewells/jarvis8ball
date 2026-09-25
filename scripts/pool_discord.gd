class_name PoolDiscord
extends Node

# Discord Rich Presence, spoken straight down the pipe the Discord app opens
# on this machine (\\?\pipe\discord-ipc-N), so there is no plugin or library
# to install. Each message is a little-endian opcode, a length, and a JSON
# body. Everything runs on its own thread: if Discord is closed, slow, or
# quits halfway through a game, the game never notices.
#
# Setting it up (once): make an application at
# https://discord.com/developers/applications named "Jarvis 8 Pool", and under
# Rich Presence > Art Assets upload the J ball image with the name "logo".
# Then give the game its Application ID, either in APP_ID below or, with no
# rebuild, in a text file called discord_app_id.txt next to the exe (or in
# the project folder when running from the editor). With no ID anywhere this
# does nothing at all, and Discord just shows the bare process it detected.

const APP_ID := "1553148912616087602"
const ID_FILE := "discord_app_id.txt"
const LOGO_ASSET := "logo"
# Discord allows five updates every twenty seconds; this stays well inside it.
const MIN_GAP_MS := 4200
const RETRY_MS := 15000

const OP_HANDSHAKE := 0
const OP_FRAME := 1
const OP_CLOSE := 2
const OP_PING := 3
const OP_PONG := 4

var app_id := APP_ID
var _thread: Thread
var _mutex := Mutex.new()
var _want: Dictionary = {}
var _quit := false


func _ready() -> void:
	if app_id == "":
		app_id = _id_from_file()
	if app_id == "" or OS.get_name() != "Windows":
		print("Discord Rich Presence off: no Application ID (see pool_discord.gd)")
		return
	print("Discord Rich Presence on, app ", app_id)
	_thread = Thread.new()
	_thread.start(_worker)


# The ID from discord_app_id.txt, looked for beside the exe, then in the
# project folder. Anything that isn't digits is ignored, so a pasted line
# with spaces or a label on it still works.
func _id_from_file() -> String:
	var dirs := [OS.get_executable_path().get_base_dir()]
	if OS.has_feature("editor") or not OS.has_feature("template"):
		dirs.append(ProjectSettings.globalize_path("res://"))
	for d in dirs:
		var path: String = str(d).path_join(ID_FILE)
		if not FileAccess.file_exists(path):
			continue
		var digits := ""
		for ch in FileAccess.get_file_as_string(path):
			if ch >= "0" and ch <= "9":
				digits += ch
		if digits.length() >= 15:
			return digits
	return ""


# What your friends see under your name. `details` is the first line, `state`
# the second; `since` (unix seconds) shows as time elapsed.
func set_presence(details: String, state := "", since := 0) -> void:
	if _thread == null:
		return
	var act := {
		"details": details,
		"assets": {"large_image": LOGO_ASSET, "large_text": "Jarvis 8 Pool"},
	}
	if state != "":
		act["state"] = state
	if since > 0:
		act["timestamps"] = {"start": since}
	_mutex.lock()
	_want = act
	_mutex.unlock()


func _exit_tree() -> void:
	if _thread == null:
		return
	_mutex.lock()
	_quit = true
	_mutex.unlock()
	_thread.wait_to_finish()
	_thread = null


# ---------------------------------------------------------------------------
# Worker thread
# ---------------------------------------------------------------------------

func _quitting() -> bool:
	_mutex.lock()
	var q := _quit
	_mutex.unlock()
	return q


func _worker() -> void:
	var pipe: FileAccess = null
	var sent := ""
	var sent_at := -MIN_GAP_MS
	var retry_at := 0
	while not _quitting():
		var now := Time.get_ticks_msec()
		if pipe == null:
			if now >= retry_at:
				pipe = _connect()
				sent = ""
				if pipe == null:
					retry_at = now + RETRY_MS
			OS.delay_msec(200)
			continue
		_mutex.lock()
		var want := _want.duplicate(true)
		_mutex.unlock()
		var body := JSON.stringify(want)
		if not want.is_empty() and body != sent and now - sent_at >= MIN_GAP_MS:
			var cmd := {"cmd": "SET_ACTIVITY", "nonce": str(now),
				"args": {"pid": OS.get_process_id(), "activity": want}}
			if not _send(pipe, OP_FRAME, cmd) or not _receive(pipe):
				pipe = null
				retry_at = now + RETRY_MS
				continue
			sent = body
			sent_at = now
		OS.delay_msec(200)
	if pipe != null:
		# leave nothing behind on your profile once the game is closed
		_send(pipe, OP_FRAME, {"cmd": "SET_ACTIVITY", "nonce": "bye",
			"args": {"pid": OS.get_process_id()}})
		_receive(pipe)
		pipe.close()


# Discord listens on the first free of ten pipes.
func _connect() -> FileAccess:
	for i in 10:
		var f := FileAccess.open("\\\\?\\pipe\\discord-ipc-%d" % i, FileAccess.READ_WRITE)
		if f == null:
			continue
		f.big_endian = false
		if _send(f, OP_HANDSHAKE, {"v": 1, "client_id": app_id}) and _receive(f):
			return f
		f.close()
	return null


func _send(f: FileAccess, op: int, payload: Dictionary) -> bool:
	var data := JSON.stringify(payload).to_utf8_buffer()
	f.store_32(op)
	f.store_32(data.size())
	f.store_buffer(data)
	f.flush()
	return f.get_error() == OK


# Reads one reply. A close from Discord, or a broken pipe, ends the
# connection; a ping is answered.
func _receive(f: FileAccess) -> bool:
	var op := f.get_32()
	var n := f.get_32()
	if f.get_error() != OK or n > 1 << 20:
		return false
	var data := f.get_buffer(n) if n > 0 else PackedByteArray()
	if f.get_error() != OK:
		return false
	if op == OP_CLOSE:
		push_warning("Discord closed the Rich Presence connection: " + data.get_string_from_utf8())
		return false
	if op == OP_PING:
		var reply = JSON.parse_string(data.get_string_from_utf8())
		return _send(f, OP_PONG, reply if reply is Dictionary else {})
	return true
