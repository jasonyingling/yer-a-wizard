# Yer a Wizard

Native macOS magical drawing canvas. Raise a reflective wand to draw gold and ivory light on a pure black screen; glittering sparks follow the tip, and each part of the trail lingers then fades away over six seconds, oldest first. Camera processing stays local. Swift/AppKit/AVFoundation track the reflective wand tip. The Pumpkin Atelier and tracking tools remain accessible from the Developer menu.

## Run

Requires macOS 14+, Xcode command-line tools, and Homebrew libusb at `/opt/homebrew/lib/libusb-1.0.dylib` for the optional USB exposure control.

```sh
bash scripts/build.sh
open 'Yer a Wizard.app'
```

Keep the app inside this project: it uses the adjacent `scripts/inspect_usb.py` helper and `diagnostics` directory. Allow camera access when macOS asks. The app selects only an Arducam, never the iPhone camera.

## Magic canvas

The app opens full screen on black. After two seconds, a softly glowing **Raise your wand** prompt appears. Detection dissolves the letters into golden particles with a small outward burst that floats downward and fades. An ivory point appears immediately, so you can draw while the text disperses. The thicker luminous trail sheds a shower of sparks, and the point continues sparkling when held still. Reduce Motion keeps the text disintegration gentle without the outward or downward movement.

Each trail sample holds full brightness for 2.65 seconds, then fades over 3.35 seconds, for six seconds total, including while you keep drawing. The text explosion spreads outward and drifts downward for 2.3–3.4 seconds, holding its brightness briefly before fading. Lost tracking stops the stroke immediately. The prompt returns only after every trail and spark has faded and the drawing canvas has stayed black for two seconds. Reacquisition and large detection jumps start new strokes. A stalled camera clears the point automatically. Drawing also stops when the window loses focus. Trails are ephemeral and are not saved.

- **Esc** exits full screen. The green window button re-enters it.
- **Show webcam**, in the bottom-right corner, toggles a live camera preview. Click the bright wand tip in the preview to select it. The preview uses the existing camera session and mirrors the drawing direction. The button and preview do not affect the drawing canvas’s prompt countdown.
- **Developer → Open Developer Studio…** (**⌥⌘D**) opens camera calibration and manual tip selection if reflections prevent automatic acquisition.
- **Developer → Mouse Practice on Magic Canvas** (**⌥⌘M**) toggles click-and-drag practice.
- **⌘1** returns to the magic canvas; **⌘2** opens the Pumpkin Atelier.
- The system Reduce Motion setting softens the glitter and removes drifting sparks and text shimmer.

To practice without accessing the camera, quit any running instance and launch:

```sh
open 'Yer a Wizard.app' --args --offline
```

Add `--windowed` to start in a regular resizable window. Camera permission and connection details are available in Developer Studio if the wand cannot be acquired.

## The Pumpkin Atelier

Open **Developer → Open Pumpkin Atelier** (**⌘2**) to carve a 3D pumpkin. No tracking sliders, diagnostics, spell scores, or developer tabs appear in the game window.

1. Point the reflective wand tip toward the camera. Click its bright tip in the small webcam preview if automatic acquisition needs help.
2. Press **Start carving** (or **Space**). The bright cursor follows the wand over the curved pumpkin surface. Move the wand to trace eyes, a nose, and a mouth.
3. Close each loop to cut out its interior. Open paths leave narrow cuts. Pause carving with **Space** before repositioning between features. A brief rest completes a stroke; lost tracking and large jumps break the stroke instead of joining unrelated points.
4. **Undo** / **⌘Z** removes the latest stroke. **Light it up** reveals your carving as a warm jack-o’-lantern; **Back to carving** lets you continue.
5. **Save portrait** exports the 3D scene as PNG without the webcam or controls. **New pumpkin** backs up your previous carving before clearing it.

Enable **Mouse practice** to click and drag directly on the pumpkin without a wand; release to end each stroke. To launch without requesting camera access (quit an existing instance first):

```sh
open 'Yer a Wizard.app' --args --offline
```

Completed cuts autosave to `diagnostics/pumpkin-autosave.json` and restore on launch. New-pumpkin backups use `diagnostics/pumpkin-<timestamp>.json`. Cuts are stored in mesh UV coordinates, so resizing the window preserves their location. The renderer uses a procedural ribbed mesh, an alpha cutout mask, and an inner lantern surface. It has a fixed front-facing view for carving a face; it does not export a boolean-cut 3D model.

Carving pauses when the game loses focus. A missing camera or denied permission leaves mouse practice available. Physical wand accuracy still needs live hardware testing; bright reflections can be mistaken for the tip.

## Separate developer mode

Open **Developer → Open Developer Studio…** (**⌥⌘D**) for the existing tracking lab and legacy spell experiments. **⌘1** returns to the magic canvas. The developer studio is a separate window and receives drawing/spell input only when it is the active window. All windows share one camera session, but their drawings and saved state are separate.

The **Debug** tab retains threshold, maximum area, exposure, mirroring, acquisition, diagnostics, and free drawing. Start with threshold **170** and maximum area **600**; settings persist. USB exposure read-back and restoring automatic exposure remain available here. These technical controls are not part of the game UI.

The app saves one initial camera frame locally to `diagnostics/initial-frame.png`. “Save diagnostic frame” updates `diagnostics/latest-frame.png`. Developer free drawing autosaves to `diagnostics/canvas-autosave.json`; clearing creates a backup. These local files are ignored by Git.

## Legacy spell experiments (developer studio)

The **Spells** tab puts Lumos, Nox, and Wingardium Leviosa on the left, with a shared camera/drawing stage on the right. The shapes follow the supplied wand-movement reference:

- **Lumos:** an upward peak → turns on a warm light that stays on.
- **Nox:** an arch with an inward curl → extinguishes that light.
- **Wingardium Leviosa:** a U-shaped sweep and downward finish → floats a feather for four seconds.

In **Spells**, point the wand toward the camera and draw anywhere on the stage. A single isolated bright tip is acquired automatically. The glowing trail appears immediately. Pause for **1.2 seconds** to recognize and cast; the next movement starts a fresh attempt. All three spell shapes are considered, regardless of the selected card. There is no guide to trace and no Begin/Cast click. Small tip jitter is ignored when deciding whether movement has stopped. Internal tracking gaps are still rejected; losing the tip at the end can finish a gesture. Multiple bright reflections may require selecting the tip in Debug. Uncheck **Show camera feed** to keep the glowing drawing, guide, and effects on a dark background; camera tracking continues.

**Debug** contains the existing threshold, area, exposure, tracking diagnostics, mirror, free-drawing, export, and legacy Kindle/Ward/Spark exercises. Both developer tabs share the same capture session and drawing stage. Free drawing is separate from spell attempts and is saved locally.

For hardware-free testing in the developer studio, check **Practice with mouse**, drag the shape anywhere, and pause. Mouse practice uses the same automatic gesture completion and shape recognizer. Manual Begin/Cast controls and dotted guides remain in **Debug**. To launch without requesting camera access at all (quit any running instance first):

```sh
open 'Yer a Wizard.app' --args --offline
```

Successful casts award XP and a streak bonus; each 300 XP gains a level. The selected spell stays selected for another attempt. Recognition tolerates position, uniform scale, reversed drawing direction, and small jitter. Closed legacy shapes permit different starting points. Poor tracking, small/incomplete drawings, wrong shapes, and scribbles are rejected. Mouse tests validate the interaction and recognition, while physical wand tracking still needs a live check.

## Tracking improvements and lighting check

At 1 ms exposure, the diagnostic frame's median brightness was **25/255**, its 99th percentile **100**, and its tip peak **197**. The earlier threshold of 190 left little brightness margin. The room was visible but was not broadly overexposed in that frame. Wand angle, distance, blur, and a restrictive area limit can also cause loss.

The tracker now adapts brightness only near the selected target, scores candidates using predicted position and area consistency, tolerates six missed frames before releasing its lock, and keeps the selection for up to 90 missed frames for reacquisition. It never emits predicted points as measured detections. The drawing view can join short gaps only when the reacquired point is nearby; longer gaps break the stroke. Recent lock percentage, background brightness, candidate count, and local threshold are displayed in the sidebar.

These changes pass synthetic regressions and recover the tip in a saved real camera frame. Sustained physical-wand accuracy during varied movement still requires live testing; the diagnostics expose that limitation rather than assuming every bright object is the wand.

## Night mode investigation

The attached device is USB `0c45:0590`, named `Arducam B0590 1080P Day/Night`. Its descriptors include a camera terminal (unit 1), processing unit (unit 2), and vendor extension units 3 and 4. The standard exposure controls respond to reads and writes on this Mac. No verified IR-cut or IR LED software switch has been identified.

[Arducam's B0590 product page](https://www.arducam.com/arducam-true-day-night-vision-usb2-uvc-camera-with-metal-housing.html) describes automatic day/night switching and 850 nm illumination. Its published UVC controls do not list a manual IR-cut override. Controls documented for Arducam USB camera shields or Raspberry Pi modules must not be assumed to apply to this UVC model.

On September 5, 2026, the user reported successfully enabling night mode after identifying the small dark/green window immediately below the lens (6 o'clock position) as the likely ambient-light sensor. The live image became grayscale and the previously dark wand tip became bright. Cover only that window with opaque tape; leave the main lens and eight surrounding IR LEDs unobstructed. This is the working physical approach; a software override remains unverified.

### Working wand calibration

Verified in the live app on September 5, 2026:

- Capture: 1920×1080, approximately 29 processed frames per second.
- Manual exposure: **1.0 ms**, confirmed by USB read-back.
- Brightness threshold: **190**.
- Maximum tip component area: **200** (in the downsampled analysis image).
- Mirror movement: on.
- Click the reflective tip in the preview to acquire it, then keep the tip facing the lens while moving.

The app showed a stable lock on the resting tip and visible loop/line trails during movement. This establishes basic physical-wand drawing, not a measured accuracy or distance guarantee. The values above document the first successful test; the improved tracker defaults to 170/600 and now persists threshold/area preferences. USB exposure can persist on the device until changed or disconnected.

## Diagnostics and tests

```sh
python3 scripts/inspect_usb.py
swiftc -O -module-cache-path .build/module-cache Sources/Tracker.swift Sources/MagicCanvas.swift scripts/test_magic.swift -o .build/test-magic -framework Cocoa
.build/test-magic /tmp
swiftc -O -module-cache-path .build/module-cache Sources/Tracker.swift scripts/test_tracker.swift -o .build/test-tracker
.build/test-tracker
swiftc -O -module-cache-path .build/module-cache Sources/Spells.swift scripts/test_spells.swift -o .build/test-spells
.build/test-spells
swiftc -O -module-cache-path .build/module-cache Sources/Spells.swift scripts/test_gestures.swift -o .build/test-gestures
.build/test-gestures
swiftc -O -module-cache-path .build/module-cache Sources/Tracker.swift Sources/PumpkinGame.swift scripts/test_pumpkin.swift -o .build/test-pumpkin -framework Cocoa -framework SceneKit
.build/test-pumpkin
```

USB diagnostics may require running outside an agent sandbox to see USB devices. The helper uses only GET requests unless explicitly invoked with `--exposure-ms` or `--auto-exposure`. It does not write vendor registers or firmware.

Known limitations: bright-object tracking is not semantic wand recognition; glare can be mistaken for the tip. Selection and temporal gating reduce this but cannot replace proper IR illumination. A software night-mode override and physical-wand accuracy over varied distances and movement speeds are not yet verified. Tracking loss breaks the stroke instead of connecting across gaps.
