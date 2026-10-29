class_name DotPropBridge
extends Node3D

## A plank bridge that sags under load and collapses under speed or weight. The caller reports
## mass and speed ([method report]) and calls [method step] each tick; strain must stay above
## [member rating] for [member hold] seconds, so one bump is not enough.

signal sagged(depth: float)
signal collapsed
signal restored

enum State { INTACT, COLLAPSED }

## Strain this deck takes before it fails. 1.0 is a mid-weight truck at about 11 m/s.
@export var rating: float = 1.8
## Most the deck drops under a load just under failing, metres.
@export var sag_max: float = 0.35
## Seconds over the rating before it goes.
@export var hold: float = 0.3
## Seconds until a collapsed deck is back.
@export var restore_after: float = 25.0

var state: State = State.INTACT
var sag: float = 0.0
## A mirror of a deck simulated elsewhere: [method step] only draws, [method apply_remote] says
## what the authority reports. Nothing here decides a collapse or a rebuild.
var remote: bool = false
var _remote_sag: float = 0.0

var _deck: AnimatableBody3D = null
var _rest := Transform3D.IDENTITY
var _peak: float = 0.0
var _over: float = 0.0
var _down: float = 0.0
var _fall: float = 0.0


## Strain of [param mass] kilograms at [param speed] m/s: heavier loads count for more, with
## diminishing returns past [param soft_mass], and speed counts squared against [param ref_speed].
static func strain(mass: float, speed: float, soft_mass: float = 8000.0, ref_speed: float = 7.0) -> float:
	var s := speed / ref_speed
	return mass / (mass + soft_mass) * (1.0 + s * s)


## Lays the deck from [param from] to [param to] (road surface points), [param width] across.
## It is built along the chord, so it suits a straight stretch.
func build(from: Vector3, to: Vector3, width: float, material: Material, layers: int = 1) -> void:
	var span := from.distance_to(to)
	_deck = AnimatableBody3D.new()
	_deck.name = "Deck"
	_deck.collision_layer = layers
	_deck.sync_to_physics = false
	add_child(_deck)
	var thick := 0.4
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, thick, span)
	collider.shape = shape
	_deck.add_child(collider)
	var planks := maxi(int(span / 0.9), 3)
	var plank_len := span / float(planks)
	for i in planks:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(width, thick, plank_len * 0.92)
		mesh.mesh = box
		mesh.material_override = material
		mesh.position = Vector3(0.0, 0.0, -span * 0.5 + plank_len * (float(i) + 0.5))
		_deck.add_child(mesh)
	var middle := (from + to) * 0.5
	var basis := Basis.looking_at((to - from).normalized(), Vector3.UP)
	_rest = Transform3D(basis, middle - basis.y * thick * 0.5)
	global_transform = Transform3D.IDENTITY
	_deck.global_transform = _rest


## Says how much strain something on the deck puts on it this tick; the largest counts.
func report(value: float) -> void:
	_peak = maxf(_peak, value)


## Once a tick: moves the sag toward what was reported and applies the failure rule.
func step(delta: float) -> void:
	if _deck == null:
		return
	if remote:
		_step_remote(delta)
		return
	if state == State.COLLAPSED:
		_down += delta
		_fall += delta
		var drop := minf(_fall * _fall * 4.0, 12.0)
		_deck.global_transform = Transform3D(_rest.basis.rotated(_rest.basis.z, minf(_fall * 0.4, 0.6)), _rest.origin - Vector3(0.0, drop, 0.0))
		if _down >= restore_after:
			_stand()
		_peak = 0.0
		return
	var target := clampf(_peak / rating, 0.0, 1.0) * sag_max
	var before := sag
	sag = move_toward(sag, target, delta * 0.6)
	if absf(sag - before) > 0.0 and absf(sag - target) < 0.001 and sag > 0.05:
		sagged.emit(sag)
	_deck.global_transform = Transform3D(_rest.basis, _rest.origin - Vector3(0.0, sag, 0.0))
	_over = _over + delta if _peak > rating else 0.0
	_peak = 0.0
	if _over >= hold:
		_collapse()


## Mirror side: the authority says the deck is down or standing and how far it has sagged.
## Turns [member remote] on, so the first report is the last time this deck decides anything.
func apply_remote(down: bool, sag_depth: float) -> void:
	remote = true
	_remote_sag = clampf(sag_depth, 0.0, sag_max)
	if down and state == State.INTACT:
		_collapse()
	elif not down and state == State.COLLAPSED:
		_stand()


func _step_remote(delta: float) -> void:
	if state == State.COLLAPSED:
		_fall += delta
		var drop := minf(_fall * _fall * 4.0, 12.0)
		_deck.global_transform = Transform3D(_rest.basis.rotated(_rest.basis.z, minf(_fall * 0.4, 0.6)), _rest.origin - Vector3(0.0, drop, 0.0))
		return
	sag = move_toward(sag, _remote_sag, delta * 0.6)
	_deck.global_transform = Transform3D(_rest.basis, _rest.origin - Vector3(0.0, sag, 0.0))


## Brings the deck down now.
func _collapse() -> void:
	state = State.COLLAPSED
	_down = 0.0
	_fall = 0.0
	_deck.get_child(0).set_deferred("disabled", true)
	collapsed.emit()


func _stand() -> void:
	state = State.INTACT
	sag = 0.0
	_over = 0.0
	_deck.get_child(0).set_deferred("disabled", false)
	_deck.global_transform = _rest
	restored.emit()


## Whether it can be driven on.
func is_standing() -> bool:
	return state == State.INTACT
