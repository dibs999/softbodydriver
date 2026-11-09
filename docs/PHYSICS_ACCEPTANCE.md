# Vehicle physics: current iteration and acceptance gaps

## Highway rendering

The old render filter treated any movement over four metres between rendered
frames as a teleport. At 15 FPS, ordinary travel above 216 km/h therefore disabled
the body vibration filter. The threshold now includes expected travel from vehicle
velocity and frame duration. Explicit repair/reset still resets the filter.
The regression covers 0–324 km/h at 120, 30, 15 and 10 FPS, plus teleports.
This fixes that rendering discontinuity; it does not establish that every source
of suspension, tyre or camera vibration has been eliminated.

Rear toe-link anchors now have three breakable braces to the suspension subframe
pivots. Previously these anchors were attached only to the flexible body shell;
cornering could change rear toe substantially without any beam yielding. The
existing Concept GT landing, fast-turn and wall-impact regression verifies that
normal driving holds alignment while crash loads can still deform the suspension.

Further Concept GT handling diagnosis found that the rear toe-control arm reused
the front steering arm's short 0.14 m lever. Under lateral tyre loading it admitted
large rear steer with no yielded beam. Rear arms and their anchors now scale with
tyre radius (0.34 m on Concept GT); front steering geometry remains unchanged.
Four-second probes at 200 km/h with normalized steering ±0.017 reduced peak rear
toe from about 25 degrees to 0.53–0.55 degrees. At 100 km/h and ±0.07 input, peak
rear toe is still 4.2–4.9 degrees under higher sustained lateral load. This remains
a compliant soft-body suspension, not a rigid idealized axle. New regressions
sample throughout both left and right maneuvers instead of only their end state.

The Concept definition now uses explicit `engine.position: "mid"`. Its engine
nodes and mounts sit ahead of the rear axle, its fuel tank is moved forward to
avoid overlap, and the front radiator no longer has collision support beams
running through the cabin to a rear engine. Other cars default to front engines.

Bonnet mass is included before body mass distribution and suspension preload.
The minimum 2 kg shell-node mass is incorporated inside the mass/axle-load solve,
rather than clamped after it. Tests verify all seven authored curb masses and
the shell-node mass floor.

## Bonnet prototype

Procedural vehicles have an independent 18 kg, eight-node bonnet. Its structural
beams remain connected when the latch group breaks; the two rear mounts form a
separate hinge break group. Breaking all mounts releases a physical panel with
aerodynamic triangles and ground/other-vehicle collision. The visible bonnet is
bound to those nodes instead of to the main body. At speeds below 2 km/h,
`release_bonnet()` releases the latch once and extends two physical hydraulic
supports over 1.25 seconds. Their travel targets a 65-degree opening; gravity
preload and damping let the panel stay open for engine inspection. These are
breakable beams in the hinge group, so a detached panel has no invisible support
tether. No opening impulse or fixed mesh rotation is applied. Repair restores
the mounts and closed panel position and clears the hydraulic input.

The core inspection regression ramps the supports, checks a settled angle of
55–72 degrees, then verifies less than three degrees of drift over another
0.6 seconds with all eight hinge/support attachments intact. It also verifies
that repair closes the panel without manually resetting the actuator input.

The existing engine/detail model has its own bindings; it is not a texture behind
the bonnet. Imported external visual models do not automatically receive a
segmented bonnet and must be authored with compatible separate panels.
The native inspection action rejects those unsegmented imported models.

Kestrel Hatch additionally has independent front and rear lower bumper cages.
Each has its own skin, eight physical nodes and breakable clips. Front and rear
18 m/s wall-impact regressions verify release, a still-connected cage, and
restored mounts after repair. Their mass is allocated within the declared curb
mass instead of added on top.

### Released-panel contact

`SoftBody::addSelfCollisionPanel` now opts a named panel into contact against
explicit target groups after its latch/mount break groups release. The bonnet
targets body and engine surfaces; independent bumpers target the body. The old
closed hood collision skin is removed, and the engine has an outward-facing
collision box with aerodynamic drag disabled (its internal faces are shielded).

Only registered panel nodes and face-centroid samples are tested, rather than
all nodes against all triangles. Face samples distribute impulses to their real
nodes without adding mass; this catches a bonnet straddling a narrower engine
block with all corners outside it. Torn faces stop contributing samples. Live
joint neighbourhoods exclude connected body triangles to avoid fighting hinges.
Registration resolves topology once; broadphase uses swept panel/triangle bounds.
Plane-crossing tests catch fast motion through thin faces. Corrections and
inelastic friction impulses act on both the panel and contacted body nodes.

Nine contact regressions cover mount activation/repair, opt-in isolation, a
0.5 m-per-step thin-surface crossing, momentum conservation/energy dissipation,
both skins near a live hinge, broken targets, a narrow engine face under a broad
panel, and actual Kestrel bonnet drops onto its own roof and engine. The workload
guard adds 1,000 unrelated nodes and still visits one candidate pair. Roof-drop
work is also checked against the explicit sample × target-triangle budget.

### Still required before production acceptance

- General mesh self-collision: this is bounded, sampled panel-to-surface contact,
  not continuous edge/edge collision or collision between every flexible surface.
  Contacts follow authored collision triangles; narrow geometry between samples,
  extreme triangle folding, and very large deformations still need dedicated
  coverage. Imported models need matching physical panel topology.
- A reversible physical bonnet closure and relatching mechanism. Current
  inspection supports hold the released bonnet open; repair closes and relatches
  it. Manual closing is not yet implemented.
- Independently segmented rear doors, boot lid and lights, plus doors and bumpers
  on the other vehicle definitions, each with their own collision skin, mounts,
  mass allocation and repair behavior. Kestrel's front doors and lower bumpers
  are the current verified examples.
- High-speed soak tests across all cars and terrain, including low render rates,
  crashes with loose panels and multiple vehicles. Unit coverage of mount
  topology and free panel motion is not a substitute for those scenarios.

After the support damping and repair changes, the complete core CTest suite
passes, and all seven native `cartest --quick` vehicle benches pass settling,
acceleration, braking and cornering checks. The focused bonnet, bumper and
self-contact selection passes 14 cases and 29,393 assertions. These are bounded
regressions rather than full vehicle certification.

## Reversible front-door mechanisms

The reference Kestrel now opts into two physical front doors. Each assembly has
eight collision-cage corners and two vertical hinge points, with a total mass
of 30 kg allocated before the existing curb-mass and axle-load solve. The
110 mm deep cage carries its own painted panel, window, interior trim, handle
and mirror. The body collision aperture follows the door boundaries, with
clearance at its sill and roof so the frame can close without catching an
overlapping fixed skin. Collision geometry remains a coarse cage, not the full
rendered mesh.

Manual opening reversibly disables the latch beams; it does not break them or
increment structural damage. Core-owned hydraulic channels 2 and 3 ramp over
1.5 seconds toward a 68-degree opening. Hinges and the assisted check strap share
a break group, allowing a crash to detach the complete door without leaving an
actuator tether. Panel self-contact activates for a disengaged latch as well as
for broken mounts, and disengaged beams no longer act as live joint exclusions.

Closing returns the physical actuator toward its authored rest length. The
latch can engage only when every attachment remains intact, striker distances
are within 15 mm of their original lengths, and relative speed is below 0.15 m/s.
Damaged attachments cannot be healed by an opening or closing command. Repair
explicitly restores geometry, latch state and actuator input together.

Regressions verify the exact curb-mass budget and front weight distribution,
opening both doors to 58–78 degrees after four seconds, closing below three
degrees and relatching after five seconds, and zero broken or plastically
deformed beams throughout normal operation. Separate tests cover motion and
misalignment rejection, 18 m/s lateral wall impacts that detach each door,
refusal to relatch crashed assemblies, repair, exclusive door-node skinning,
and removal of duplicate fixed exterior panels. These cover stationary assisted
operation and bounded crash fixtures; manual obstruction/pinch response,
certified hinge loads and extensive uneven-terrain use remain unvalidated.

## Concept GT review: driving and packaging

A second investigation separated imported-mesh appearance from vehicle dynamics.
The imported and procedural versions follow the same physical trajectory in the
10-second import regression. Rendering artifacts are therefore tested separately.

The original rear toe-control lever was the same 0.14 m lever used for front
steering. Under lateral load this geometry admitted excessive elastic rear steer.
A longer, wheel-size-scaled rear lever reduces peak rear toe in the measured
200 km/h, ±0.017-input maneuver from about 25 degrees to below 0.6 degrees.
The harder 100 km/h, ±0.07-input maneuver still shows approximately 4–5 degrees
of loaded compliance. Temporal tests cover both directions, finite state,
beam integrity and body motion. This is a specific stability improvement, not
validation of every road condition or realistic tire dynamics.

`engine.position` now distinguishes front and mid-engine layouts. Concept GT's
engine and breakable mounts are behind the cabin, with the tank moved ahead of
the engine. The front radiator no longer has structural braces running through
the cabin to the rear engine. Other cars keep the default front layout.

Gameplay steering assistance now uses speed and wheelbase to bound requested
steering by a nominal 1.1 g bicycle-model demand. It limits input, not physical
forces: the vehicle can still slide, understeer, crash or roll. Assistance can be
disabled in the main/pause menu, and driving preferences persist. The gameplay
regression accelerates the Concept above 100 km/h, exercises left/right/release,
checks direct control with assistance disabled, and stops with the brakes.

## Imported-model appearance

The renderer now preserves and transforms imported tangent frames during dynamic
vertex uploads. Concept's authored occlusion texture uses UV2; its explicit
`aoOnUV2` option corrects material sampling on duplicated materials without
mutating the shared imported source. An unrelated procedural chassis overlay was
removed from this model because it produced floating front bumper geometry.
Tests inspect normals, tangents, AO channels, wheel dimensions and unchanged
physical trajectories. These fixes do not add missing engine-bay mesh parts,
segmented doors or a physically detachable hood to the imported model.

The compatibility-renderer smoke check also exposed opaque black billboards at
normal exhaust opacity. An explicit soft-edge particle shader now preserves tint
and lifetime alpha. Production emission rates, wheel-slip and damage logic remain
unchanged; controlled before/after renders and the driving capture verify the
visual correction. This renderer check does not establish performance on a GPU.
