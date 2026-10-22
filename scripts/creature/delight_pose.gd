class_name DelightPose
extends RefCounted
## Active F1 delight poses (ACTIVE_WISHES §5 "Friend's reaction"; GDD §14.4 D15: mapped onto the
## existing celebrate + behaviour motion, no new rig poses). Pure: the Mossling asks for the motion
## of a wishes.json granted_pose at a moment of the pose and applies it to its own springs.
##
##   hop      two small in-place hops (Art Bible §5.7 play hop 0.12 bu, a little higher)
##   sway     a happy side-to-side lean (the pet wiggle, louder), easing out
##   spin     a quick look left, right and back with one small hop
##   snuggle  a soft squash with a gentle sway (the pet release, without a press)
##
## Every pose also gets happy eyes, a heart bouquet and sparkles from the Mossling.

const HOP := &"hop"
const SWAY := &"sway"
const SPIN := &"spin"
const SNUGGLE := &"snuggle"
## wishes.json granted_pose (and FE-T's sip_tea) -> motion.
const MOTION := {&"delight_hop": HOP, &"delight_splash": HOP, &"delight_paw_water": SNUGGLE,
	&"delight_sway": SWAY, &"delight_gaze": SWAY, &"delight_sit_by": SWAY, &"delight_spin": SPIN,
	&"delight_snuggle": SNUGGLE, &"delight_sip": SNUGGLE, &"sip_tea": SNUGGLE, &"delight_nap": SNUGGLE,
	&"delight_nibble": SNUGGLE, &"ride_boat": SWAY}
## Shapes: hop height (body units), hops per pose, sway amplitude (deg) and rate (Hz), the spin's
## three looks (-1 left .. +1 right), the snuggle squash.
const HOP_BU := 0.16
const HOPS := 2
const SPIN_HOP_K := 0.6
const SWAY_DEG := 5.0
const SWAY_HZ := 1.4
const SNUG_SWAY_K := 0.5
const SPIN_LOOKS: Array[float] = [-0.8, 0.8, 0.0]
const SNUG_SQUASH := 0.9
const HEARTS := 3
const SPARKLES := 6


## The motion of [param pose] (an unknown pose snuggles: every wish has a soft answer).
static func motion_of(pose: StringName) -> StringName:
	var m: StringName = MOTION.get(pose, SNUGGLE)
	return m


## Body lift in body units at progress [param u] (0..1) of the pose.
static func lift_bu(motion: StringName, u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	match motion:
		HOP:
			var hu := fposmod(u * HOPS, 1.0)
			return 4.0 * HOP_BU * hu * (1.0 - hu) * (1.0 - u * 0.3)
		SPIN:
			return 4.0 * HOP_BU * SPIN_HOP_K * u * (1.0 - u)
	return 0.0


## Lean offset (rad) at [param t] s, progress [param u].
static func wiggle(motion: StringName, t: float, u: float) -> float:
	if motion != SWAY and motion != SNUGGLE:
		return 0.0
	var amp := deg_to_rad(SWAY_DEG) * (SNUG_SWAY_K if motion == SNUGGLE else 1.0)
	return amp * sin(TAU * SWAY_HZ * t) * (1.0 - clampf(u, 0.0, 1.0))


## The spin's look step at progress [param u] (0, 1, 2), -1 for other motions.
static func spin_step(motion: StringName, u: float) -> int:
	if motion != SPIN:
		return -1
	return mini(int(clampf(u, 0.0, 1.0) * float(SPIN_LOOKS.size())), SPIN_LOOKS.size() - 1)
