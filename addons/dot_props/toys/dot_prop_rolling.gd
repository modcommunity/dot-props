class_name DotPropRolling
extends RefCounted

## The harm a loose toy does by moving: a barrel that rolls into somebody. Server only; a game asks [method scan]
## each tick with the people it cares about and applies the damage through its own combat.
##
## A toy that is merely nudged does nothing: the speed must pass [member min_speed], and the damage grows with the
## speed over it and the toy's mass, up to [member max_damage]. One person is hurt at most once per
## [member cooldown] by any one toy, so a barrel sliding along somebody's legs is one hit, not sixty.

## Slowest a body may be going to hurt, m/s. A barrel pushed along by a walking survivor never reaches it.
var min_speed: float = 3.0
## Damage per m/s over [member min_speed], per 10 kg of the toy.
var damage_per_speed: float = 4.0
var max_damage: float = 60.0
## Seconds before the same toy may hurt the same person again.
var cooldown: float = 0.8
## The kinds that hurt; a beach ball rolling at speed does not.
var kinds: Array[StringName] = [&"barrel", &"crate", &"tyre"]

var _now: float = 0.0
var _last: Dictionary = {}


## Hits for this tick. [param victims]: [code]{id, position, radius, height}[/code] (feet, metres). Returns
## [code]{victim, damage, toy, direction}[/code] for each person a fast toy touches. [param delta] advances the cooldown clock.
func scan(box: DotPropToyBox, victims: Array, delta: float) -> Array[Dictionary]:
	_now += delta
	var out: Array[Dictionary] = []
	if box == null or victims.is_empty():
		return out
	for toy: DotPropToy in box.toys:
		if not is_instance_valid(toy) or toy.body == null or not toy.body.is_inside_tree() or not kinds.has(toy.kind):
			continue
		var speed := toy.body.linear_velocity.length()
		if speed < min_speed:
			continue
		var at := toy.body.global_position
		var reach := toy.radius() + 0.1
		for v: Variant in victims:
			var victim: Dictionary = v
			var feet: Vector3 = victim["position"]
			var flat := Vector2(at.x - feet.x, at.z - feet.z).length()
			if flat > reach + float(victim.get("radius", 0.35)):
				continue
			if at.y < feet.y - reach or at.y > feet.y + float(victim.get("height", 1.8)) + reach:
				continue
			var key := "%d:%s" % [toy.index, str(victim["id"])]
			if _now - float(_last.get(key, -INF)) < cooldown:
				continue
			_last[key] = _now
			out.append({"victim": victim["id"], "toy": toy, "direction": toy.body.linear_velocity.normalized(),
					"damage": damage_for(speed, toy.body.mass)})
	return out


## The damage of a toy of [param mass] kg going [param speed] m/s: nothing under [member min_speed].
func damage_for(speed: float, mass: float) -> float:
	if speed < min_speed:
		return 0.0
	return minf((speed - min_speed + 1.0) * damage_per_speed * maxf(mass, 1.0) / 10.0, max_damage)


## Forgets cooldowns (a map restart).
func reset() -> void:
	_last.clear()
	_now = 0.0
