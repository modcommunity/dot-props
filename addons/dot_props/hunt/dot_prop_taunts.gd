class_name DotPropTaunts
extends RefCounted

## Taunts: the noises a hidden player makes, by choice or because they stood still too long.
##
## [b]A taunt is the hiding side's whole contract with the seeking side.[/b] A prop that never
## makes a sound can only be found by shooting everything, and a round decided by who shoots
## the most furniture is not a round. So a taunt is paid for when a player chooses it, and
## forced on one who has not moved for a while — the rule that stops somebody hiding in a
## corner for the whole round.
##
## [b]Standing still is measured against a radius, not a speed.[/b] A player who shuffles back
## and forth on one spot is standing still as far as finding them goes, and a speed test would
## call them moving. [method observe] keeps an anchor; leaving [member auto_radius] of it moves
## the anchor and starts the clock again.
##
## [b]Simulated seconds, passed in.[/b] Never a wall clock, for the reason every timer in this
## family gives: a wall clock lets a player who lags the server taunt on a different schedule
## from one who does not.
##
## [b]It plays nothing.[/b] A taunt here is an id, a length and the points it earned. Which file
## plays, where, and who hears it are the game's: the sound has to come from where the player
## is on every client, which is a replication question this addon does not own.

## Seconds a player may stand within [member auto_radius] before a taunt is forced. 0 is never.
var auto_after: float = 45.0

## Metres a player must move from where they settled for that to count as moving.
var auto_radius: float = 1.5

## The least time between two taunts, in seconds, on top of the length of the last one: a taunt
## cannot start while the last is still playing.
var cooldown: float = 2.0

## Points for a taunt the player chose.
var points_voluntary: int = 2

## Points for one forced on them. 0 by default: being found out for standing still is not
## something to be paid for, and a server that wants to pay for it says so.
var points_forced: int = 0

## Whether a taunt a player chose starts the standing-still clock again. On: a player who
## taunts is doing the thing the forced one exists to make them do.
var voluntary_resets_clock: bool = true

## id -> `{"id", "title", "seconds", "sound"}`.
var catalogue: Dictionary = {}

## The ids in the order they were added, for a menu and for a seeded pick.
var order: Array[StringName] = []

## key -> `{"anchor": Vector3, "since": float, "last": float, "length": float}`.
var _state: Dictionary = {}


## Adds a taunt. [param sound] is whatever the game plays it from: a path, an audio id.
func add(id: StringName, title: String, seconds: float, sound: String = "") -> void:
	if not catalogue.has(id):
		order.append(id)

	catalogue[id] = {"id": id, "title": title, "seconds": maxf(seconds, 0.1), "sound": sound}


## Adds every entry of a JSON-shaped list: `[{"id", "title", "seconds", "sound"}]`. Returns how
## many were added; an entry without an id is skipped.
func add_all(entries: Array) -> int:
	var added := 0

	for raw in entries:
		if not (raw is Dictionary):
			continue

		var entry := raw as Dictionary
		var id := StringName(str(entry.get("id", "")))

		if id == &"":
			continue

		add(id, str(entry.get("title", id)), float(entry.get("seconds", 1.0)), str(entry.get("sound", "")))
		added += 1

	return added


func has(id: StringName) -> bool:
	return catalogue.has(id)


func entry(id: StringName) -> Dictionary:
	return catalogue.get(id, {})


## Where [param key] is, at [param now]. Call it every tick for every hidden player.
func observe(key: StringName, position: Vector3, now: float) -> void:
	var s: Dictionary = _state.get(key, {})

	if s.is_empty():
		_state[key] = {"anchor": position, "since": now, "last": -INF, "length": 0.0}
		return

	if (s["anchor"] as Vector3).distance_to(position) > auto_radius:
		s["anchor"] = position
		s["since"] = now


## Seconds [param key] has stood still.
func still_for(key: StringName, now: float) -> float:
	var s: Dictionary = _state.get(key, {})
	return maxf(now - float(s.get("since", now)), 0.0)


## How full the meter is, 0 to 1: 1 is a taunt forced this tick. Always 0 with
## [member auto_after] at 0.
func meter(key: StringName, now: float) -> float:
	if auto_after <= 0.0:
		return 0.0

	return clampf(still_for(key, now) / auto_after, 0.0, 1.0)


## Whether a taunt is to be forced on [param key] now. Not while one is still playing.
func due(key: StringName, now: float) -> bool:
	return auto_after > 0.0 and meter(key, now) >= 1.0 and _quiet(key, now)


## Whether [param key] may taunt now, and why not.
func may_taunt(key: StringName, now: float) -> DotResult:
	if catalogue.is_empty():
		return DotResult.fail(DotError.CODE_STATE, "This server has no taunts.")

	if not _quiet(key, now):
		return DotResult.fail(DotError.CODE_RATE_LIMITED,
			"Wait %.1f s to taunt again." % ready_in(key, now))

	return DotResult.success(null)


## Seconds until [param key] may taunt again; 0 is now.
func ready_in(key: StringName, now: float) -> float:
	var s: Dictionary = _state.get(key, {})

	if s.is_empty():
		return 0.0

	return maxf(float(s["last"]) + float(s["length"]) + cooldown - now, 0.0)


## Records a taunt. [param id] empty picks one from [param seed_value]. Returns
## `{"id", "title", "seconds", "sound", "points", "forced"}`, or an empty dictionary when
## there is nothing to play.
func taunt(key: StringName, now: float, id: StringName = &"", forced: bool = false, seed_value: int = 0) -> Dictionary:
	if catalogue.is_empty():
		return {}

	if id == &"" or not catalogue.has(id):
		id = order[posmod(hash("%d:%s" % [seed_value, String(key)]) >> 7, order.size())]

	var e: Dictionary = catalogue[id]

	if not _state.has(key):
		_state[key] = {"anchor": Vector3.ZERO, "since": now, "last": -INF, "length": 0.0}

	var s: Dictionary = _state[key]
	s["last"] = now
	s["length"] = float(e["seconds"])

	if forced or voluntary_resets_clock:
		s["since"] = now

	var out := e.duplicate()
	out["points"] = points_forced if forced else points_voluntary
	out["forced"] = forced
	return out


func forget(key: StringName) -> void:
	_state.erase(key)


## Starts everybody's clock again: a new round.
func reset() -> void:
	_state.clear()


func _quiet(key: StringName, now: float) -> bool:
	return ready_in(key, now) <= 0.0


func describe() -> Dictionary:
	return {
		"taunts": order.size(),
		"auto": "after %.0f s within %.1f m" % [auto_after, auto_radius] if auto_after > 0.0 else "off",
		"cooldown": cooldown,
		"points": "%d chosen, %d forced" % [points_voluntary, points_forced],
		"tracked": _state.size(),
	}
