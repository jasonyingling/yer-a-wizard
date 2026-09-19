# Yer a Wizard

Native macOS prototype for drawing with a reflective wand tip and an Arducam B0590 USB camera. Camera processing stays local. Swift/AppKit/AVFoundation capture video; a compact bright-blob tracker follows a selected tip and renders glowing strokes.

## Run

Requires macOS 14+, Xcode command-line tools, and Homebrew libusb at `/opt/homebrew/lib/libusb-1.0.dylib` for the optional USB exposure control.

```sh
bash scripts/build.sh
open 'Yer a Wizard.app'
```

Keep the app inside this project: it uses the adjacent `scripts/inspect_usb.py` helper and `diagnostics` directory. Allow camera access when macOS asks. The app selects only an Arducam, never the iPhone camera.

1. Point the reflective tip toward the lens. It needs illumination near the camera to return a bright reflection.
2. Click the tip in the preview to select it. The tracker requires three consecutive detections. “Find tip” can acquire a single isolated bright candidate automatically; reflections can also be candidates.
3. Start with brightness threshold **170** and maximum component area **600**. After selecting the tip, detection uses a lower local threshold that adapts to its measured brightness. Area is measured in the image downsampled by two in each dimension. Threshold and area preferences persist across launches.
4. Lower exposure to suppress the room background once the tip is illuminated. The exposure slider uses standard UVC requests and displays read-back values. Restore auto exposure returns the camera's advertised automatic default.
5. Pause drawing to reposition, clear the canvas, or hide the camera preview. Save PNG exports the drawing without the camera image.

The app saves one initial camera frame locally to `diagnostics/initial-frame.png`. “Save diagnostic frame” updates `diagnostics/latest-frame.png`. The free-drawing canvas autosaves to `diagnostics/canvas-autosave.json` and restores on launch; clearing creates a backup. Last spell paths and tracking measurements are also saved under `diagnostics`. These files are ignored by Git.

## Spellbook and Debug

The **Spells** tab puts Lumos, Nox, and Wingardium Leviosa on the left, with a shared camera/drawing stage on the right. The shapes follow the supplied wand-movement reference:

- **Lumos:** an upward peak → turns on a warm light that stays on.
- **Nox:** an arch with an inward curl → extinguishes that light.
- **Wingardium Leviosa:** a U-shaped sweep and downward finish → floats a feather for four seconds.

In **Spells**, point the wand toward the camera and draw anywhere on the stage. A single isolated bright tip is acquired automatically. The glowing trail appears immediately. Pause for **1.2 seconds** to recognize and cast; the next movement starts a fresh attempt. All three spell shapes are considered, regardless of the selected card. There is no guide to trace and no Begin/Cast click. Small tip jitter is ignored when deciding whether movement has stopped. Internal tracking gaps are still rejected; losing the tip at the end can finish a gesture. Multiple bright reflections may require selecting the tip in Debug. Uncheck **Show camera feed** to keep the glowing drawing, guide, and effects on a dark background; camera tracking continues.

**Debug** contains the existing threshold, area, exposure, tracking diagnostics, mirror, free-drawing, export, and legacy Kindle/Ward/Spark exercises. Both tabs share the same capture session and drawing stage. Free drawing is separate from spell attempts and is saved locally.

For hardware-free testing, check **Practice with mouse**, drag the shape anywhere, and pause. Mouse practice uses the same automatic gesture completion and shape recognizer. Manual Begin/Cast controls and dotted guides remain in **Debug**. To launch without requesting camera access at all (quit any running instance first):

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
swiftc -O -module-cache-path .build/module-cache Sources/Tracker.swift scripts/test_tracker.swift -o .build/test-tracker
.build/test-tracker
swiftc -O -module-cache-path .build/module-cache Sources/Spells.swift scripts/test_spells.swift -o .build/test-spells
.build/test-spells
```

USB diagnostics may require running outside an agent sandbox to see USB devices. The helper uses only GET requests unless explicitly invoked with `--exposure-ms` or `--auto-exposure`. It does not write vendor registers or firmware.

Known limitations: bright-object tracking is not semantic wand recognition; glare can be mistaken for the tip. Selection and temporal gating reduce this but cannot replace proper IR illumination. A software night-mode override and physical-wand accuracy over varied distances and movement speeds are not yet verified. Tracking loss breaks the stroke instead of connecting across gaps.
