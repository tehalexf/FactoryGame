## A 2D point or vector in fixed-point metres, on the Map's horizontal plane.
##
## Not `Vector2`, because its components are floats and floats are banned inside
## the Simulation. Not `Vector2i` either, which looks tempting but stores 32-bit
## components — a fixed-point value with 16 fractional bits exhausts 32 bits at
## about 32,768 metres, so positions would silently overflow.
##
## Horizontal only: `x` and `z` name the Map's ground plane, matching Godot's
## convention that y is up. DESIGN.md fixes Milestone 1 as flat building, which is
## what keeps Belt logic and the Enemy flowfield two-dimensional.
class_name FixedVec2
extends RefCounted

var x: int = 0
var z: int = 0


func _init(initial_x: int = 0, initial_z: int = 0) -> void:
	x = initial_x
	z = initial_z


static func zero() -> FixedVec2:
	return FixedVec2.new(0, 0)


func duplicate_vec() -> FixedVec2:
	return FixedVec2.new(x, z)


func plus(other: FixedVec2) -> FixedVec2:
	return FixedVec2.new(x + other.x, z + other.z)


## This vector scaled by a fixed-point factor.
func scaled(factor: int) -> FixedVec2:
	return FixedVec2.new(Fixed.mul(x, factor), Fixed.mul(z, factor))


func equals(other: FixedVec2) -> bool:
	if other == null:
		return false
	return x == other.x and z == other.z


func _to_string() -> String:
	return "(%d, %d)" % [x, z]
