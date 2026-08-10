# Postmortem: the 1-3 frame split-screen flash (Godot 4.4 Camera2D + physics interpolation)

**Status:** fixed in r19 (`9eb8a74`) and r20 (`3cd3f3c`), on top of the r18 split system (`091b8c8`).
**Affected code:** `Scripts/Autoload/coop_manager.gd` (`build_split_2p`, `update_split_cameras`).
**Engine:** Godot 4.4.x, project-wide physics interpolation ON, `canvas_items` stretch at 480x270.

This document is a full reproduction guide: how the bug looked, how it was captured and
measured, why the engine behaves this way (with source line references), what shipped, what
was deliberately rejected, and how the fix was verified. A reader with no prior context
should be able to redo every step.

---

## 1. Symptom

2-player dynamic split-screen (SMBX/TheXTech-style rules, r18): the shared camera follows
both players until one crosses the 75%/25% screen line, then the view cuts into two panes,
each following its own player.

At the instant the screen split, **one pane showed the wrong view for 1-3 frames** — it
looked like "the opposite side of the split repeated" — then snapped to the correct view.
It reproduced on the initial split, on every orientation flip (L/R to T/B), and on every
teardown/rebuild cycle (e.g. Yoshi swallowing the other player merges the screen; spitting
re-splits it).

User-visible as a flash at every cut. Worse than cosmetic: for 1-3 frames a pane shows a
player who is not that pane's owner, at the exact moment the player is trying to track a
cut — a real risk of misreading player position.

## 2. Capture method

Windows 10, Intel QuickSync, no installs beyond ffmpeg. `ddagrab` (Desktop Duplication)
captures the screen on the GPU; `hwmap` hands the frames to QuickSync for zero-copy H.264
encode, so the recording does not perturb the game's frame timing:

```
ffmpeg -init_hw_device d3d11va -filter_complex "ddagrab=framerate=60,hwmap=derive_device=qsv,format=qsv" -t 30 -c:v h264_qsv -global_quality 23 out.mp4
```

Note: 60 fps was requested; the delivered capture ran at ~51 fps effective (ddagrab
delivers on desktop-update cadence). This matters when converting "bad captured frames"
to game frames below.

Find the cut timestamps with scene-change detection (a split cut changes half the screen
at once, which trips the scene score):

```
ffmpeg -i out.mp4 -vf "select='gt(scene,0.2)',showinfo" -f null -
```

`showinfo` prints `pts_time` for each detected cut. Then extract a short frame burst
around each cut, preserving original timing:

```
ffmpeg -ss <t> -i out.mp4 -t 0.3 -fps_mode passthrough frames_%03d.png
```

Three cuts were recorded and analyzed, labeled by their capture timestamps: **t388**,
**t780** (both left/right splits), and **t1285** (top/bottom). The extracted frame
sequences were kept as `t388_001.png` ... `t388_014.png`, `t780_001..017`,
`t1285_001..017` (analysis workspace, not committed to the repo; the measurement script
lived alongside them as `analyze.py`).

## 3. Forensics: measuring what the wrong pane actually shows

Capture is 1920x1080 of a 480x270 logical viewport, so **4 screen px = 1 world px**. All
world coordinates below use "shared-view coords": (0,0) = top-left of the pre-split shared
view; the level floor sits at world y=270 (the camera's `limit_bottom`), the level's left
edge at world x=0 (`limit_left` region).

Method: template-match each pane's content against the last pre-split shared frame
(zero-mean cross-correlation for the offset, mean absolute difference in grey levels for
match quality), giving the wrong view's world-space rect. Inter-frame MAD on the wrong
pane distinguishes "frozen" from "tracking".

### Event table

| Event | Split type | Last shared frame | First split frame | Bad frames (captured) | Corrected frame | Wrong pane |
|---|---|---|---|---|---|---|
| t388  | LEFT/RIGHT | t388_005  | t388_006  | 006-007 = 2 (~39 ms, ~2.3 game frames @60) | t388_008  | RIGHT (Mario's cell) |
| t780  | LEFT/RIGHT | t780_004  | t780_005  | 005-007 = 3 (~59 ms, ~3.5 game frames)     | t780_008  | RIGHT (Mario's cell) |
| t1285 | TOP/BOTTOM | t1285_003 | t1285_004 | 004-005 = 2 (~39 ms, ~2.3 game frames)     | t1285_006 | TOP (Mario's cell) |

In all three events the wrong pane was **Mario's** — the pane of the player FAR from the
level's limit corner. Luigi's pane was pixel-perfect continuous with the pre-split shared
view from its very first frame (template MAD 0.15-0.34 grey levels, offset exactly (0,0)).

### What the wrong view is

**t1285 (the discriminating event** — top/bottom geometry separates the y candidates):

- Wrong top-pane content = shared-frame content at dx=0, **dy=+570 screen px** → wrong
  view rect spans world y 142.5..269.25, center y ≈ 205.9.
- The wrong rect's bottom edge (269.25) coincides with the level floor / `limit_bottom`
  (270) **within 1 world px**.
- It is **not** the midpoint/shared camera (center y=135.0 — off by 71 world px), **not**
  exactly Luigi's own camera view (off by 14 world px, explained by his cam's (0,-16)
  offset), and **not** world origin (that would show sky at the level's top-left).
- It is a **pane-sized camera pinned into the bottom-left camera-limit corner** — exactly
  what a Camera2D at a stale position clamps to. The correction snap at t1285_006 moved
  the view 150 world px (600 screen px) in one frame to the correct Mario view
  (center y ≈ 55.9).

**t388 / t780 (L/R, degenerate in y):** the wrong right pane shows the same limit-clamped
bottom-left view the left pane shows — content displaced 971 screen px vs. the 975 px pane
offset, i.e. the wrong rect sits at world x≈1 vs. the left pane's 0, **within 1 world px
of identical** ("the opposite side of the split repeated"). Correction snaps: +246.75
world px (t780; corrected cam center x 365.75 ≈ Mario at 369) and +242.75 world px (t388;
center 361.85 ≈ Mario at 362.5).

### Frozen, not tracking

Wrong-pane inter-frame MAD during the bad frames: t1285 004→005 = 0.22; t780 005→006 =
0.013, 006→007 = 0.014; t388 006→007 = 0.037 — versus **47-49** at the correction snap.
The wrong view is **frozen solid**. During t1285 Mario is moving upward; a
midpoint-tracking camera would have drifted. It did not. This is a camera parked against
its limits whose viewport transform is never being re-pushed — which points directly at
the engine mechanics below.

Also confirmed: no black frame, no tear (first split frame is fully composed with the
divider); the wrong pane is a **live world render** (it contains Luigi plus his "2" seat
label at a world offset), not a copy of the other pane's texture — ruling out container
layout / texture-sharing explanations.

## 4. Root cause: Godot 4.4 `scene/2d/camera_2d.cpp` mechanics

The pane cameras are created with the project's standard recipe: `process_callback =
PHYSICS`, `physics_interpolation_mode = ON` (required — without it the pane view smears
against the interpolated sprites). At the time of the bug, `build_split_2p` created each
camera at position (0,0) with only `limit_left = -64` and `limit_bottom = 64` set,
`add_child`-ed it into a fresh SubViewport, then `update_split_cameras` (same synchronous
call) set the remaining limits, snapped `global_position` to the seat's player, and called
`reset_physics_interpolation()`. Looks correct. Four engine facts make it render wrong
anyway (line references are Godot 4.4 branch, `scene/2d/camera_2d.cpp`):

**(a) The ENTER_TREE cascade pushes a canvas transform from the camera's ADD-TIME state**
(`camera_2d.cpp:342-357`). A fresh SubViewport has no current camera, so the lone Camera2D
`make_current()`s itself inside ENTER_TREE and `_update_scroll()` runs, calling
`viewport->set_canvas_transform(...)` computed from the camera as it existed at
`add_child` time: position (0,0), partial limits — i.e. a view clamped into the level's
bottom-left limit corner. (The in-source comment even notes an "extra manual reset" at the
end of ENTER_TREE because "the camera transform is not up to date until this point.")

**(b) With physics interpolation ON, setting position pushes nothing**
(`camera_2d.cpp:314-316`). The `NOTIFICATION_TRANSFORM_CHANGED` handler is guarded:
`_update_scroll()` runs only `if ((!position_smoothing_enabled &&
!is_physics_interpolated_and_enabled()) || _is_editing_in_editor())`. Interpolation ON
means the guard skips it — `cam.global_position = pos` updates the camera's state but the
SubViewport's canvas transform stays whatever (a) left there.

**(c) `reset_physics_interpolation()` reseeds but never pushes** (`camera_2d.cpp:299-303`).
The `NOTIFICATION_RESET_PHYSICS_INTERPOLATION` handler does `xform_curr =
get_camera_transform(); xform_prev = xform_curr;` and calls `_update_process_callback()` —
it contains no `_update_scroll()`. The interpolator now holds the correct transform; the
viewport still holds the stale one.

**(d) The first correct push can only arrive a frame late** (`camera_2d.cpp:288-290`).
With interpolation ON, `_update_process_callback()` does `set_process_internal(
is_current())`, and `NOTIFICATION_INTERNAL_PROCESS` → `_update_scroll()` runs every idle
frame — but a node added mid-`_process` (the split is built from `CoopManager._process`)
receives no INTERNAL_PROCESS until the **next** frame. So the SubViewport
(`UPDATE_ALWAYS`) renders at least one frame with the stale ENTER_TREE transform, and the
correction lands next frame (2-3 perceived frames after capture/compositor latency —
matching the table above exactly).

Known upstream: [godotengine/godot#101195](https://github.com/godotengine/godot/issues/101195)
("Camera2D stops scrolling when physics interpolation is enabled at runtime", suggested
workaround: `force_update_scroll()`), addressed by lawnjelly's
[PR #102652](https://github.com/godotengine/godot/pull/102652) (forward port of #101218) —
**not in 4.4.1**, which still carries the unfixed runtime-interpolation quirk. The fix
below is correct and idempotent both before and after that PR.

Why "the opposite side repeated": the r18 trigger geometry masks the bug on one side. The
split fires when the crossing player sits on the shared view's 75% line, which IS the new
pane's center — so near the level's limit corner, the crossing player's pane is
near-identical to the stale limit-clamped seed (exactly identical in L/R events via double
limit-clamping; within ~14 world px in the T/B event). Only the FAR player's pane differs
visibly from the stale seed, which is why it was always Mario's pane that flashed.

## 5. The fix: two independent layers, either sufficient, both shipped

### r19 (`9eb8a74`) — "kill the 1-3 frame split flash - force_update_scroll on fresh pane cams"

In `update_split_cameras`' fresh-snap branch, push the view synchronously, in this exact
order: **set position → `reset_physics_interpolation()` → `force_update_scroll()`**.

Why the order matters: `force_update_scroll()` is literally `_update_scroll()`, and with
interpolation ON, `_update_scroll()` pushes the `xform_prev` → `xform_curr` **blend**. That
blend equals the snapped transform only after the reset has set `prev == curr` from the
newly written position. Forcing before the reset pushes a blend contaminated by the stale
seed; forcing without the reset also lets the next physics tick smear the pane from its
spawn transform. `reset_physics_interpolation()` is synchronous in 4.4
(`Node::reset_physics_interpolation` propagates the notification immediately), so the
three-step sequence completes within the same `_process` call and the SubViewport renders
the correct view on the build frame.

Current code (`Scripts/Autoload/coop_manager.gd`, `update_split_cameras`):

```gdscript
		# Each pane tracks its OWN player on both axes (the SMBX shared-average
		# pinning made both halves bob with either player's jumps - nauseating,
		# per David). Rigid on the split axis, smoothed on the perpendicular
		# one so jumps don't bounce the whole view.
		var desired := target.global_position
		var pos := cam.global_position
		if split_fresh:
			pos = desired
		elif split_vertical:
			pos.x = desired.x
			pos.y = lerpf(pos.y, desired.y, minf(delta * 8.0, 1.0))
		else:
			pos.y = desired.y
			pos.x = lerpf(pos.x, desired.x, minf(delta * 8.0, 1.0))
		cam.global_position = pos
		if split_fresh:
			# first placement is a teleport, not motion - don't let the
			# interpolator smear the pane from its spawn transform
			cam.reset_physics_interpolation()
			# ...and PUSH the view now. With physics interpolation on, setting
			# position doesn't update the viewport (engine guard skips it) and
			# a camera born mid-frame gets no process tick until next frame -
			# without this the pane renders 1-3 frames pinned at the camera's
			# limit corner (David's split flash, confirmed frame-by-frame).
			# Order matters: position -> reset interpolation -> force scroll.
			cam.force_update_scroll()
```

### r20 (`3cd3f3c`) — "harden pane-cam seeding - full config before ENTER_TREE + null-target push guard"

Kill the stale seed at the source: configure the camera **fully before `add_child`** —
full limits from the level plus the seat player's position — so the ENTER_TREE push in
fact (a) already carries the correct view. Then every same-frame push (make_current, limit
setters) is harmless, and the fix survives engine reorderings and 4.4.1's
runtime-interpolation quirk. Do not call `make_current()` before `add_child` — it fails
outside the tree.

Current code (`Scripts/Autoload/coop_manager.gd`, `build_split_2p`):

```gdscript
		var cam := Camera2D.new()
		# SMBX rule: rigid center-lock, no smoothing, no deadzone.
		# Same interpolation recipe as the project's CoopCamera / player cams
		# (physics callback + interpolation ON) - without it the pane view
		# smears against the interpolated sprites while moving.
		cam.offset = Vector2(0, -16)
		cam.position_smoothing_enabled = false
		cam.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
		cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
		cam.limit_left = -64
		cam.limit_bottom = 64
		# configure FULLY before entering the tree: the engine pushes a canvas
		# transform from the camera's add-time state (ENTER_TREE cascade), so
		# limits and position must already be correct or the pane's first
		# frame renders the stale seed (the split flash's root)
		cam.limit_right = GameManager.current_level.camera_left_end_position
		cam.limit_top = GameManager.current_level.camera_top_end_position + 16
		var seat_i: int = split_seats[i]
		var seed_target: Node2D = null
		if alive_players.has(seat_i) and is_instance_valid(alive_players[seat_i]):
			seed_target = alive_players[seat_i]
		elif active_players.has(seat_i) and is_instance_valid(active_players[seat_i]):
			seed_target = active_players[seat_i]
		if seed_target != null:
			cam.global_position = seed_target.global_position
		sv.add_child(cam)
		svc.add_child(sv)
		split_grid.add_child(svc)
		cam.make_current()
		split_cameras.append(cam)
```

(`GameManager.current_level` is guaranteed valid here — `compute_split_layout` already
gated on it before returning a layout.)

r20 also hardens the theoretically-unreachable null-target path in
`update_split_cameras`, so a fresh camera is never left un-pushed:

```gdscript
		if target == null:
			if split_fresh:
				# even with no target, never leave the fresh cam un-pushed
				cam.reset_physics_interpolation()
				cam.force_update_scroll()
			continue
```

## 6. What NOT to do

**The hidden warm-up-frame reveal was considered and adversarially rejected.** The idea:
build the panes hidden, `await RenderingServer.frame_post_draw`, then show them — the
wrong frame renders invisibly. Rejected because:

- It **breaks the 75%-line seamless-cut geometry**. The r18 trigger fires at the exact
  moment the crossing player's position makes the cut seamless (the 75% line is the new
  pane's center — nobody teleports across the screen). Delaying the reveal by even one
  frame moves the players off that alignment and reintroduces the visual jump the r18
  trigger was built to eliminate.
- **Awaiting inside `_process` creates teardown/rebuild reentrancy hazards.** The split is
  torn down and rebuilt on consecutive frames in normal play (Yoshi eat/spit near the
  split threshold replays teardown → rebuild every time; orientation flips do the same).
  Pending coroutines from a previous build can wake up holding freed pane nodes.

The deterministic same-frame fix (Section 5) needs neither.

**General rule** for any physics-interpolated Camera2D teleport in Godot 4.4 — not just
split-screen: **`position` → `reset_physics_interpolation()` → `force_update_scroll()`**,
in that order. Setting position alone does not reach the viewport; resetting alone does
not push; forcing before resetting pushes a stale blend.

## 7. Verification

Headless validation (the project's standard pipeline — no editor, no display):

```
godot --headless --path . --import
godot --headless --path . --quit-after 400
```

The `--import` pass catches script compile errors project-wide; the `--quit-after 400` run
boots all autoloads (including CoopManager) and runs ~400 frames as a runtime smoke test,
checked by exit code and error output.

The fix itself was confirmed against the re-recording expectation derived from Section 3:
using the same capture + scene-detect + frame-extraction procedure as Section 2, the
**first visible split frame shows the correct view in both panes** — the wrong-pane
template match against the pre-split frame (the dy=+570-style displaced match) no longer
exists in any post-fix cut, and the correction snap (the inter-frame MAD ~48 event) is
gone because there is nothing to correct.
