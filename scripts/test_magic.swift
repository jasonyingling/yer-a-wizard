import Cocoa

@main struct MagicTests {
    static func main() throws {
        var trail = MagicTrail()
        var prompt = MagicPrompt()
        precondition(!prompt.update(hasContent: false, at: 0))
        precondition(!prompt.update(hasContent: false, at: 1.99))
        precondition(prompt.update(hasContent: false, at: 2), "Startup waits two black seconds")
        precondition(!prompt.update(hasContent: true, at: 3), "Drawing hides the prompt")
        precondition(!prompt.update(hasContent: true, at: 8), "Remaining sparks or strokes prevent the countdown")
        precondition(!prompt.update(hasContent: false, at: 9))
        precondition(!prompt.update(hasContent: false, at: 10.99))
        precondition(prompt.update(hasContent: false, at: 11), "Prompt waits until all content clears, then two seconds")
        precondition(!prompt.update(hasContent: true, at: 11.1))
        precondition(!prompt.update(hasContent: false, at: 11.2))
        precondition(!prompt.update(hasContent: true, at: 12), "Reacquisition resets the black interval")
        precondition(!prompt.update(hasContent: false, at: 12.1))
        precondition(!prompt.update(hasContent: false, at: 13.9))
        precondition(prompt.update(hasContent: false, at: 14.2))
        trail.receive(CGPoint(x: 0.1, y: 0.4), at: 0)
        precondition(trail.tip != nil)
        for frame in 1...150 {
            trail.receive(CGPoint(x: 0.1 + Double(frame) * 0.004, y: 0.4), at: Double(frame) / 30)
        }
        precondition(trail.samples.first!.time == 0, "Marks remain on screen for six seconds")
        var agingTrail = trail
        agingTrail.advance(at: 6.1, holdingMouse: true)
        precondition(agingTrail.samples.first!.time > 0.1, "Oldest marks expire independently")
        precondition(trail.samples.last!.time == 5)
        precondition(MagicTrail.opacity(age: 3) < MagicTrail.opacity(age: 1), "Oldest marks fade first")
        precondition(MagicTrail.opacity(age: 2.65) == 1, "Trail holds full brightness two seconds longer")
        precondition(MagicTrail.opacity(age: 4) > 0 && MagicTrail.opacity(age: 6) == 0)
        let stroke = trail.samples.last!.stroke
        trail.receive(nil, at: 5.01)
        precondition(trail.tip == nil && !trail.samples.isEmpty)
        trail.receive(CGPoint(x: 0.71, y: 0.4), at: 5.55)
        precondition(trail.samples.last!.stroke != stroke, "Reacquisition never bridges a tracking gap")
        let resumed = trail.samples.last!.stroke
        trail.receive(CGPoint(x: 0.1, y: 0.8), at: 5.58)
        precondition(trail.samples.last!.stroke != resumed, "Large jumps start new strokes")
        trail.advance(at: 5.8)
        precondition(trail.tip == nil, "Camera stalls clear the cursor without a nil callback")
        trail.advance(at: 12)
        precondition(trail.samples.isEmpty, "Fading continues without camera input")
        trail.receive(CGPoint(x: 0.5, y: 0.5), at: 13)
        let beforeStall = trail.samples.last!.stroke
        trail.receive(CGPoint(x: 0.51, y: 0.5), at: 14)
        precondition(trail.samples.last!.stroke != beforeStall, "Delayed callbacks cannot bridge a stall")
        trail.receive(CGPoint(x: CGFloat.nan, y: 0), at: 14.1)
        precondition(trail.tip == nil)
        for frame in 0..<36000 {
            let t = Double(frame) / 60 + 20
            trail.receive(CGPoint(x: 0.5 + sin(t) * 0.3, y: 0.5 + cos(t) * 0.3), at: t)
        }
        precondition(trail.samples.count < 4096, "Ten minutes of drawing keeps bounded storage")

        _ = NSApplication.shared
        let view = MagicCanvasView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800))
        view.layoutSubtreeIfNeeded()
        precondition(view.promptOpacity == 0, "Launch starts black")
        precondition(view.cameraPreview.isHidden)
        view.setWandColor(WandColor(hex: "#FF69B4")!, persist: false)
        precondition(view.wandColor.hex == "#FF69B4")
        view.updateVoice(enabled: true, automatic: false, listening: false, status: "Click Listen to speak")
        precondition(!view.listenButton.isHidden && !view.voiceStatus.isHidden)
        view.updateVoice(enabled: false, automatic: true, listening: false, status: "Voice is off")
        precondition(view.listenButton.isHidden && view.voiceStatus.isHidden)
        view.toggleCamera()
        precondition(!view.cameraPreview.isHidden && view.cameraButton.title == "Hide webcam")
        view.toggleCamera()
        precondition(view.cameraPreview.isHidden && view.cameraButton.title == "Show webcam")
        let directory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/tmp")
        func snapshot(_ name: String, of target: MagicCanvasView? = nil) throws {
            let target = target ?? view
            let bitmap = target.bitmapImageRepForCachingDisplay(in: target.bounds)!
            target.cacheDisplay(in: target.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name))
            precondition(bitmap.colorAt(x: 10, y: 10)!.usingColorSpace(.deviceRGB)!.redComponent == 0, "Canvas is pure black")
        }
        try snapshot("magic-idle.png")
        let now = ProcessInfo.processInfo.systemUptime
        var acquisitions = 0
        view.onWandPresence = { detected, _ in if detected { acquisitions += 1 } }
        let burstView = MagicCanvasView(frame: view.frame)
        burstView.layoutSubtreeIfNeeded()
        burstView.advanceAnimation(at: now + 3, acceptsInput: true)
        burstView.advanceAnimation(at: now + 3.31, acceptsInput: true)
        precondition(burstView.promptOpacity == 1)
        try snapshot("magic-prompt-before.png", of: burstView)
        let detectedAt = now + 3.32
        let detectedTip = Tip(x: 0.2, y: 0.2, area: 10, peak: 255, contrast: 255)
        burstView.receive(detectedTip, mirrored: false, at: detectedAt)
        let fragmentCount = burstView.promptFragments.count
        precondition(fragmentCount > 200 && fragmentCount <= 1800, "Text dissolves into bounded letter-shaped particles")
        precondition(burstView.trail.tip != nil, "Drawing begins immediately during the prompt burst")
        burstView.receive(nil, mirrored: false, at: detectedAt + 0.01)
        burstView.receive(detectedTip, mirrored: false, at: detectedAt + 0.02)
        precondition(burstView.promptFragments.count == fragmentCount && burstView.promptFragments.allSatisfy { $0.time == detectedAt }, "Brief tracking gaps never duplicate the burst")
        burstView.advanceAnimation(at: detectedAt + 0.06, acceptsInput: true)
        try snapshot("magic-prompt-breaking.png", of: burstView)
        burstView.advanceAnimation(at: detectedAt + 0.45, acceptsInput: true)
        precondition(burstView.promptOpacity == 0 && !burstView.promptFragments.isEmpty)
        try snapshot("magic-prompt-burst.png", of: burstView)
        let movingFragments = burstView.promptFragments.filter { $0.motion > 0 }
        if !movingFragments.isEmpty {
            let averageDrop = movingFragments.reduce(CGFloat(0)) { result, fragment in
                result + fragment.position(at: detectedAt + 1, in: burstView.bounds).y - fragment.origin.y * burstView.bounds.height
            } / CGFloat(movingFragments.count)
            precondition(averageDrop > 35, "The explosion floats downward")
        }
        burstView.advanceAnimation(at: detectedAt + 1, acceptsInput: true)
        try snapshot("magic-prompt-falling.png", of: burstView)
        burstView.advanceAnimation(at: detectedAt + 2.2, acceptsInput: true)
        if !movingFragments.isEmpty {
            precondition(!burstView.promptFragments.isEmpty, "Text fragments linger beyond two seconds")
            let fragment = movingFragments[0]
            precondition(fragment.position(at: detectedAt + 2.2, in: burstView.bounds).y - fragment.origin.y * burstView.bounds.height > 200, "Particles float farther down")
        }
        try snapshot("magic-prompt-lingering.png", of: burstView)
        burstView.advanceAnimation(at: detectedAt + 3.5, acceptsInput: true)
        precondition(burstView.promptFragments.isEmpty, "Dissolve particles expire")
        burstView.advanceAnimation(at: detectedAt + 6.1, acceptsInput: true)
        burstView.advanceAnimation(at: detectedAt + 8.09, acceptsInput: true)
        precondition(burstView.promptOpacity == 0, "The black pause still follows all effects")
        burstView.advanceAnimation(at: detectedAt + 8.11, acceptsInput: true)
        burstView.advanceAnimation(at: detectedAt + 8.42, acceptsInput: true)
        burstView.receive(detectedTip, mirrored: false, at: detectedAt + 8.43)
        precondition(!burstView.promptFragments.isEmpty && burstView.promptFragments.allSatisfy { $0.time == detectedAt + 8.43 }, "A returning prompt can dissolve again")
        for frame in 0...100 {
            let angle = Double(frame) / 100 * .pi * 2.5
            view.receive(Tip(x: 0.5 + cos(angle) * 0.23, y: 0.5 + sin(angle) * 0.25,
                             area: 10, peak: 255, contrast: 255), mirrored: false, at: now - 3.3 + Double(frame) * 0.033)
        }
        precondition(view.sparks.count > 0 && view.sparks.count <= 1200)
        precondition(acquisitions > 0, "Wand raises are reported immediately, without waiting for animation ticks")
        try snapshot("magic-trail.png")
        precondition(view.wandColor.glow.redComponent > view.wandColor.glow.greenComponent, "Picker color reaches the renderer")
        view.setFrameSize(NSSize(width: 600, height: 400))
        view.layoutSubtreeIfNeeded()
        view.toggleCamera()
        try snapshot("magic-resized.png")
        precondition(view.bounds.contains(view.cameraPreview.frame), "Preview fits in a resized canvas")
        view.setFrameSize(NSSize(width: 480, height: 320)); view.layoutSubtreeIfNeeded()
        precondition(view.voiceSettingsButton.frame.maxX < view.cameraButton.frame.minX, "Controls fit the minimum window width")
        print("PASS: letter-shaped prompt burst, immediate drawing, downward drift, no duplicate burst, particle expiry, repeat detection, two-second black pause, oldest-first expiry, tracking gaps, bounded storage, webcam toggle, rendering and resizing")
    }
}
