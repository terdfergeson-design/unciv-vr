# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

extends Node
## Talks to the Unciv bridge (bridge/ in the Unciv repo) over TCP, one JSON message per line.
## Usage:  var reply := await bridge.request("getState")
##         if reply.ok: use(reply.result) else: print(reply.error)

signal connected
signal disconnected
signal _response(message: Dictionary)

const RETRY_SECONDS := 1.0

var host := "127.0.0.1"
var port := 8765

var _peer := StreamPeerTCP.new()
var _buffer := PackedByteArray()
var pending := 0   # requests sent and still waiting for an answer (main's watchdog looks at this)
var _next_id := 1
var _is_connected := false
var _retry_timer := 0.0
var _wanted := false


func connect_to_bridge() -> void:
	_wanted = true
	_peer.disconnect_from_host()
	var err := _peer.connect_to_host(host, port)
	if err != OK:
		push_warning("Bridge connect_to_host failed: %s" % error_string(err))


func is_bridge_connected() -> bool:
	return _is_connected


## True while the TCP connection is up (polls the socket; usable when the scene tree is shutting down).
func is_connection_open() -> bool:
	return _peer.get_status() == StreamPeerTCP.STATUS_CONNECTED


## Polls the socket outside _process (e.g. while quitting).
func poll_now() -> void:
	_peer.poll()
	if _peer.get_status() == StreamPeerTCP.STATUS_CONNECTED and _peer.get_available_bytes() > 0:
		_peer.get_partial_data(_peer.get_available_bytes())   # discard; we only care that it closes


## Asks the bridge to exit, without waiting for the reply (used when quitting).
func send_shutdown() -> void:
	if not _is_connected:
		return
	var line := JSON.stringify({"id": 0, "method": "shutdown", "params": {}}) + "\n"
	_peer.put_data(line.to_utf8_buffer())
	_peer.poll()


## Sends a request and waits for its reply. Always returns {ok: bool, result | error}.
func request(method: String, params: Dictionary = {}) -> Dictionary:
	if not _is_connected:
		return {"ok": false, "error": "Not connected to the bridge"}
	var id := _next_id
	_next_id += 1
	var line := JSON.stringify({"id": id, "method": method, "params": params}) + "\n"
	var err := _peer.put_data(line.to_utf8_buffer())
	if err != OK:
		return {"ok": false, "error": "Send failed: %s" % error_string(err)}
	pending += 1
	while true:
		var message: Dictionary = await _response
		if message.get("id") != null and int(message["id"]) == id:
			pending -= 1
			return message
		if message.get("_disconnected", false):
			pending -= 1
			return {"ok": false, "error": "Bridge disconnected"}
	return {}  # unreachable


func _process(delta: float) -> void:
	if not _wanted:
		return
	_peer.poll()
	var status := _peer.get_status()
	match status:
		StreamPeerTCP.STATUS_CONNECTED:
			if not _is_connected:
				_is_connected = true
				_peer.set_no_delay(true)
				connected.emit()
			_read_available()
		StreamPeerTCP.STATUS_CONNECTING:
			pass
		_:  # STATUS_NONE or STATUS_ERROR: (re)connect after a short wait
			if _is_connected:
				_is_connected = false
				_buffer.clear()
				_response.emit({"_disconnected": true})
				disconnected.emit()
			_retry_timer += delta
			if _retry_timer >= RETRY_SECONDS:
				_retry_timer = 0.0
				_peer.disconnect_from_host()
				_peer.connect_to_host(host, port)


func _read_available() -> void:
	var available := _peer.get_available_bytes()
	if available <= 0:
		return
	var chunk: Array = _peer.get_partial_data(available)
	if chunk[0] != OK:
		return
	_buffer.append_array(chunk[1])
	while true:
		var newline := _buffer.find(10)
		if newline < 0:
			break
		var line := _buffer.slice(0, newline).get_string_from_utf8()
		_buffer = _buffer.slice(newline + 1)
		if line.strip_edges().is_empty():
			continue
		var parsed: Variant = JSON.parse_string(line)
		if parsed is Dictionary:
			_response.emit(parsed)
		else:
			push_warning("Bridge sent something that isn't JSON: %s" % line.left(200))
