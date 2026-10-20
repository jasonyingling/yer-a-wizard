import Cocoa

struct MagicSample {
    let point: CGPoint
    let time: TimeInterval
    let stroke: Int
}

struct MagicSpark {
    let origin: CGPoint
    let velocity: CGVector
    let time: TimeInterval
    let lifetime: TimeInterval
    let size: CGFloat
    let phase: Double
}

struct PromptFragment {
    let origin: CGPoint
    let velocity: CGVector
    let time: TimeInterval
    let lifetime: TimeInterval
    let size: CGFloat
    let opacity: CGFloat
    let motion: CGFloat

    func position(at now: TimeInterval, in bounds: CGRect) -> CGPoint {
        let age = max(0, now - time)
        // A short outward impulse slows into a downward float.
        let burst = (1 - exp(-age * 2.6)) / 2.6
        return CGPoint(x: bounds.minX + origin.x * bounds.width + velocity.dx * burst * motion,
                       y: bounds.minY + origin.y * bounds.height + (velocity.dy * burst + 34 * age + 32 * age * age) * motion)
    }
}

// All times are monotonic seconds. Keeping age per sample makes long strokes
// disappear from their beginning while the user is still drawing their end.
struct MagicTrail {
    static let brightHold: TimeInterval = 2.65
    static let lifetime: TimeInterval = 6
    private(set) var samples: [MagicSample] = []
    private(set) var tip: CGPoint?
    private(set) var lastSeen: TimeInterval?
    private(set) var lostAt: TimeInterval?
    private var stroke = 0

    static func opacity(age: TimeInterval) -> CGFloat {
        let progress = min(1, max(0, (age - brightHold) / (lifetime - brightHold)))
        return CGFloat(1 - progress * progress * (3 - 2 * progress))
    }

    mutating func receive(_ point: CGPoint?, at now: TimeInterval) {
        guard let point, point.x.isFinite, point.y.isFinite,
              (0...1).contains(point.x), (0...1).contains(point.y) else {
            disconnect(at: now); return
        }
        if let lastSeen, now - lastSeen > 0.2 { disconnect(at: lastSeen + 0.2) }
        if let previous = tip, hypot(point.x - previous.x, point.y - previous.y) > 0.18 {
            disconnect(at: now)
        }
        let previous = tip
        let smoothed = previous.map { CGPoint(x: $0.x * 0.25 + point.x * 0.75, y: $0.y * 0.25 + point.y * 0.75) } ?? point
        if let previous, let lastSeen {
            let distance = hypot(smoothed.x - previous.x, smoothed.y - previous.y)
            let count = min(64, max(1, Int(ceil(distance / 0.003))))
            for index in 1...count {
                let t = Double(index) / Double(count)
                samples.append(MagicSample(point: CGPoint(x: previous.x + (smoothed.x - previous.x) * t,
                                                          y: previous.y + (smoothed.y - previous.y) * t),
                                           time: lastSeen + (now - lastSeen) * t, stroke: stroke))
            }
        } else {
            samples.append(MagicSample(point: smoothed, time: now, stroke: stroke))
        }
        tip = smoothed; lastSeen = now; lostAt = nil
        prune(at: now)
    }

    mutating func disconnect(at now: TimeInterval) {
        if tip != nil { stroke += 1; lostAt = now }
        tip = nil
    }

    mutating func advance(at now: TimeInterval, holdingMouse: Bool = false) {
        if !holdingMouse, tip != nil, let lastSeen, now - lastSeen > 0.2 {
            disconnect(at: lastSeen + 0.2)
        }
        prune(at: now)
    }

    private mutating func prune(at now: TimeInterval) {
        samples.removeAll { now - $0.time >= Self.lifetime }
        if samples.count > 4096 { samples.removeFirst(samples.count - 4096) }
    }

}

struct MagicPrompt {
    private var blackSince: TimeInterval?

    mutating func update(hasContent: Bool, at now: TimeInterval) -> Bool {
        if hasContent { blackSince = nil; return false }
        if blackSince == nil { blackSince = now }
        return now - blackSince! >= 2
    }
}

final class MagicCameraPreview: NSView {
    var image: CGImage?
    var tip: Tip?
    var mirrored = true
    var message = "Waiting for the camera…"
    var onSeed: ((Double, Double) -> Void)?
    override var isFlipped: Bool { true }
    private var imageRect: CGRect {
        let aspect = image.map { CGFloat($0.width) / CGFloat($0.height) } ?? 4 / 3
        let width = min(bounds.width, bounds.height * aspect)
        return CGRect(x: (bounds.width - width) / 2, y: (bounds.height - width / aspect) / 2, width: width, height: width / aspect)
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        NSColor(calibratedWhite: 0.055, alpha: 1).setFill(); bounds.fill()
        if let image {
            let r = imageRect
            c.saveGState(); c.translateBy(x: mirrored ? r.maxX : r.minX, y: r.maxY)
            c.scaleBy(x: mirrored ? -1 : 1, y: -1)
            c.draw(image, in: CGRect(origin: .zero, size: r.size)); c.restoreGState()
            if let tip {
                let p = CGPoint(x: r.minX + (mirrored ? 1 - tip.x : tip.x) * r.width, y: r.minY + tip.y * r.height)
                c.setStrokeColor(NSColor.systemYellow.cgColor); c.setLineWidth(2)
                c.strokeEllipse(in: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14))
            }
        } else {
            let style = NSMutableParagraphStyle(); style.alignment = .center
            let text = NSAttributedString(string: message, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: style])
            let area = bounds.insetBy(dx: 20, dy: 16)
            let height = text.boundingRect(with: area.size, options: [.usesLineFragmentOrigin]).height
            text.draw(in: CGRect(x: area.minX, y: bounds.midY - height / 2, width: area.width, height: height))
        }
    }
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil), r = imageRect
        guard image != nil, r.contains(p) else { return }
        let x = (p.x - r.minX) / r.width
        onSeed?(mirrored ? 1 - x : x, (p.y - r.minY) / r.height)
    }
}

final class MagicCanvasView: NSView {
    private(set) var trail = MagicTrail()
    private(set) var sparks: [MagicSpark] = []
    private(set) var promptFragments: [PromptFragment] = []
    var mouseMode = false { didSet { stopInput() } }
    private var holdingMouse = false
    private var timer: Timer?
    private var lastTick = ProcessInfo.processInfo.systemUptime
    private var sparkCredit = 0.0
    private var prompt = MagicPrompt()
    private(set) var promptOpacity: CGFloat = 0
    private var promptFrom: CGFloat = 0
    private var promptTarget: CGFloat = 0
    private var promptChangedAt = ProcessInfo.processInfo.systemUptime
    private var promptTransitionDuration = 0.3
    private var reducedMotion = false
    let cameraPreview = MagicCameraPreview()
    let cameraButton = NSButton(title: "Show webcam", target: nil, action: nil)
    var cameraMessage = "Waiting for the camera…"
    private var lastCameraFrame: TimeInterval?
    private let gold = NSColor(calibratedRed: 1, green: 0.74, blue: 0.32, alpha: 1)
    private let ivory = NSColor(calibratedRed: 1, green: 0.96, blue: 0.80, alpha: 1)
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Magic drawing canvas")
        cameraButton.target = self; cameraButton.action = #selector(toggleCamera)
        cameraButton.bezelStyle = .rounded
        cameraButton.image = NSImage(systemSymbolName: "video", accessibilityDescription: nil)
        cameraButton.imagePosition = .imageLeading
        cameraButton.toolTip = "Show or hide the webcam. Click the bright wand tip in the preview to select it."
        addSubview(cameraButton)
        cameraPreview.isHidden = true; cameraPreview.wantsLayer = true
        cameraPreview.layer?.cornerRadius = 12; cameraPreview.layer?.masksToBounds = true
        cameraPreview.layer?.borderWidth = 1
        cameraPreview.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        cameraPreview.setAccessibilityElement(true); cameraPreview.setAccessibilityRole(.image)
        cameraPreview.setAccessibilityLabel("Webcam preview. Click the wand tip to select it.")
        addSubview(cameraPreview)
        _ = prompt.update(hasContent: false, at: ProcessInfo.processInfo.systemUptime)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        timer?.invalidate(); timer = nil
        guard window != nil else { return }
        lastTick = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
    deinit { timer?.invalidate() }

    override func layout() {
        super.layout()
        cameraButton.frame = CGRect(x: bounds.maxX - 156, y: bounds.maxY - 60, width: 140, height: 44)
        let width = min(280, max(1, bounds.width - 32))
        cameraPreview.frame = CGRect(x: bounds.maxX - width - 16, y: cameraButton.frame.minY - width * 0.75 - 10, width: width, height: width * 0.75)
    }

    @objc func toggleCamera() {
        cameraPreview.isHidden.toggle()
        cameraButton.title = cameraPreview.isHidden ? "Show webcam" : "Hide webcam"
        cameraButton.setAccessibilityValue(cameraPreview.isHidden ? "Hidden" : "Visible")
        cameraPreview.needsDisplay = true
        window?.makeFirstResponder(self)
    }

    func updateCamera(_ image: CGImage?, tip: Tip?, mirrored: Bool) {
        cameraPreview.image = image; cameraPreview.tip = tip; cameraPreview.mirrored = mirrored
        lastCameraFrame = ProcessInfo.processInfo.systemUptime
        if !cameraPreview.isHidden { cameraPreview.needsDisplay = true }
    }

    func receive(_ tip: Tip?, mirrored: Bool, at now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard !mouseMode else { return }
        observe(tip.map { CGPoint(x: mirrored ? 1 - $0.x : $0.x, y: $0.y) }, at: now)
    }

    private func observe(_ point: CGPoint?, at now: TimeInterval) {
        let previous = trail.tip
        let previousStroke = trail.samples.last?.stroke
        trail.receive(point, at: now)
        if trail.tip != nil, promptTarget == 1, promptOpacity > 0.01 {
            dissolvePrompt(at: now)
        }
        if trail.tip != nil { _ = prompt.update(hasContent: true, at: now) }
        if let previous, let current = trail.tip, previousStroke == trail.samples.last?.stroke {
            let distance = hypot((current.x - previous.x) * bounds.width, (current.y - previous.y) * bounds.height)
            let count = min(72, Int(distance / (reducedMotion ? 16 : 3)))
            if count > 0 {
                for i in 1...count {
                    let t = Double(i) / Double(count)
                    emit(at: CGPoint(x: previous.x + (current.x - previous.x) * t,
                                     y: previous.y + (current.y - previous.y) * t), time: now)
                }
            }
        }
        needsDisplay = true
    }

    func stopInput() {
        holdingMouse = false
        trail.disconnect(at: ProcessInfo.processInfo.systemUptime)
        sparkCredit = 0
    }

    private func tick() {
        advanceAnimation(at: ProcessInfo.processInfo.systemUptime, acceptsInput: window?.isKeyWindow == true)
    }

    func advanceAnimation(at now: TimeInterval, acceptsInput: Bool) {
        let dt = min(0.05, max(0, now - lastTick)); lastTick = now
        reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !acceptsInput { stopInput() }
        // A stationary held mouse acts like a stream of stationary camera samples.
        if holdingMouse, let point = trail.tip { trail.receive(point, at: now) }
        trail.advance(at: now, holdingMouse: holdingMouse)
        sparks.removeAll { now - $0.time >= $0.lifetime }
        promptFragments.removeAll { now - $0.time >= $0.lifetime }
        if let point = trail.tip {
            sparkCredit += dt * (reducedMotion ? 12 : 65)
            while sparkCredit >= 1 { emit(at: point, time: now); sparkCredit -= 1 }
        } else { sparkCredit = 0 }
        // The two-second pause starts only after the last stroke AND spark expire.
        let hasContent = trail.tip != nil || !trail.samples.isEmpty || !sparks.isEmpty || !promptFragments.isEmpty
        let target: CGFloat = prompt.update(hasContent: hasContent, at: now) ? 1 : 0
        if target != promptTarget {
            promptFrom = promptOpacity; promptTarget = target; promptChangedAt = now
            promptTransitionDuration = 0.3
            setAccessibilityLabel(target == 1 ? "Raise your wand" : "Wand detected. Drawing golden sparks.")
        }
        let progress = min(1, max(0, (now - promptChangedAt) / promptTransitionDuration))
        promptOpacity = promptFrom + (promptTarget - promptFrom) * CGFloat(1 - pow(1 - progress, 3))
        if lastCameraFrame.map({ now - $0 > 2 }) ?? true {
            cameraPreview.image = nil; cameraPreview.tip = nil
            cameraPreview.message = CommandLine.arguments.contains("--offline") ? "Webcam is off in offline practice.\nReopen the app normally to use it." : cameraMessage
            if !cameraPreview.isHidden { cameraPreview.needsDisplay = true }
        }
        if window?.isVisible == true, window?.isMiniaturized != true { needsDisplay = true }
    }

    private func promptText(color: NSColor, shadow: NSShadow? = nil) -> NSAttributedString {
        let size = min(64, max(24, bounds.width * 0.048))
        let font = NSFont(name: "Baskerville", size: size) ?? NSFont(name: "Palatino", size: size) ?? NSFont.systemFont(ofSize: size)
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .kern: size * 0.055]
        if let shadow { attributes[.shadow] = shadow }
        return NSAttributedString(string: "Raise your wand", attributes: attributes)
    }

    private func dissolvePrompt(at now: TimeInterval) {
        // Sample the actual letter shapes, so the words themselves disintegrate.
        // No particles are emitted from the spaces between letters or words.
        let text = promptText(color: .white)
        let size = text.size()
        guard bounds.width > 0, bounds.height > 0, size.width > 0, size.height > 0 else { return }
        let mask = NSImage(size: size, flipped: true) { _ in
            text.draw(at: .zero); return true
        }
        if let image = mask.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let bitmap = NSBitmapImageRep(cgImage: image)
            let scaleX = size.width / CGFloat(bitmap.pixelsWide)
            let scaleY = size.height / CGFloat(bitmap.pixelsHigh)
            let spacing: CGFloat = reducedMotion ? 3 : 2
            let stepX = max(1, Int(spacing / scaleX)), stepY = max(1, Int(spacing / scaleY))
            let left = bounds.midX - size.width / 2, top = bounds.midY - size.height / 2
            promptFragments.removeAll(keepingCapacity: true)
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: stepY) {
                for x in stride(from: 0, to: bitmap.pixelsWide, by: stepX) {
                    guard promptFragments.count < 1800,
                          let color = bitmap.colorAt(x: x, y: y), color.alphaComponent > 0.2 else { continue }
                    let px = CGFloat(x) * scaleX, py = CGFloat(y) * scaleY
                    promptFragments.append(PromptFragment(
                        origin: CGPoint(x: (left + px - bounds.minX) / bounds.width, y: (top + py - bounds.minY) / bounds.height),
                        velocity: CGVector(dx: (px / size.width - 0.5) * 145 + CGFloat.random(in: -95...95),
                                           dy: CGFloat.random(in: -35...85)),
                        time: now, lifetime: reducedMotion ? 0.8 : Double.random(in: 2.3...3.4),
                        size: CGFloat.random(in: 1.2...2.6), opacity: promptOpacity * color.alphaComponent,
                        motion: reducedMotion ? 0 : 1))
                }
            }
        }
        promptFrom = promptOpacity; promptTarget = 0; promptChangedAt = now
        promptTransitionDuration = 0.18
        setAccessibilityLabel("Wand detected. Drawing golden sparks.")
    }

    private func emit(at point: CGPoint, time: TimeInterval) {
        guard sparks.count < 1200 else { return }
        let angle = Double.random(in: 0..<(2 * .pi))
        let speed = reducedMotion ? 0 : Double.random(in: 14...65)
        sparks.append(MagicSpark(origin: point,
                                 velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed - 18),
                                 time: time, lifetime: Double.random(in: 0.65...1.8),
                                 size: CGFloat.random(in: 0.8...2.2), phase: Double.random(in: 0...6.28)))
    }

    private func screenPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: bounds.minX + point.x * bounds.width, y: bounds.minY + point.y * bounds.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let now = lastTick
        NSColor.black.setFill(); bounds.fill()
        context.setLineCap(.round); context.setLineJoin(.round)
        // Batch by age so glow rendering stays bounded during continuous drawing.
        let paths = (0..<32).map { _ in CGMutablePath() }
        for (index, sample) in trail.samples.enumerated() {
            let alpha = MagicTrail.opacity(age: now - sample.time)
            guard alpha > 0 else { continue }
            let bucket = min(31, Int(alpha * 31))
            let point = screenPoint(sample.point)
            if index > 0, trail.samples[index - 1].stroke == sample.stroke {
                paths[bucket].move(to: screenPoint(trail.samples[index - 1].point))
                paths[bucket].addLine(to: point)
            } else {
                paths[bucket].move(to: point); paths[bucket].addLine(to: CGPoint(x: point.x + 0.1, y: point.y))
            }
        }
        context.saveGState()
        context.setBlendMode(.plusLighter)
        for (index, path) in paths.enumerated() where !path.isEmpty {
            let alpha = CGFloat(index + 1) / 32
            context.setShadow(offset: .zero, blur: 16, color: gold.withAlphaComponent(alpha * 0.65).cgColor)
            context.setStrokeColor(gold.withAlphaComponent(alpha * 0.24).cgColor)
            context.setLineWidth(10); context.addPath(path); context.strokePath()
            context.setShadow(offset: .zero, blur: 0, color: nil)
            context.setStrokeColor(ivory.withAlphaComponent(alpha * 0.95).cgColor)
            context.setLineWidth(3.4); context.addPath(path); context.strokePath()
        }
        for spark in sparks {
            let age = now - spark.time
            guard age >= 0, age < spark.lifetime else { continue }
            let origin = screenPoint(spark.origin)
            let drift = reducedMotion ? 0 : age
            let p = CGPoint(x: origin.x + spark.velocity.dx * drift,
                            y: origin.y + spark.velocity.dy * drift + 40 * drift * drift)
            let twinkle = reducedMotion ? 0.8 : 0.55 + 0.45 * pow(sin(age * 11 + spark.phase), 2)
            let alpha = CGFloat(pow(1 - age / spark.lifetime, 1.3) * twinkle)
            context.setFillColor(gold.withAlphaComponent(alpha * 0.15).cgColor)
            context.fillEllipse(in: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
            context.setFillColor(ivory.withAlphaComponent(alpha).cgColor)
            let r = spark.size
            context.fillEllipse(in: CGRect(x: p.x - r / 2, y: p.y - r / 2, width: r, height: r))
            if spark.size > 1.4 {
                context.setStrokeColor(gold.withAlphaComponent(alpha * 0.65).cgColor)
                context.setLineWidth(0.65)
                context.move(to: CGPoint(x: p.x - r * 2, y: p.y)); context.addLine(to: CGPoint(x: p.x + r * 2, y: p.y))
                context.move(to: CGPoint(x: p.x, y: p.y - r * 2)); context.addLine(to: CGPoint(x: p.x, y: p.y + r * 2))
                context.strokePath()
            }
        }
        for fragment in promptFragments {
            let age = now - fragment.time
            guard age >= 0, age < fragment.lifetime else { continue }
            let p = fragment.position(at: now, in: bounds)
            let reveal = min(1, age / 0.06)
            let hold = fragment.motion > 0 ? 0.45 : 0
            let fade = pow(1 - max(0, age - hold) / (fragment.lifetime - hold), 1.2)
            let alpha = fragment.opacity * reveal * fade
            let r = fragment.size
            context.setFillColor(gold.withAlphaComponent(alpha * 0.12).cgColor)
            context.fillEllipse(in: CGRect(x: p.x - r * 2, y: p.y - r * 2, width: r * 4, height: r * 4))
            context.setFillColor(ivory.withAlphaComponent(alpha).cgColor)
            context.fillEllipse(in: CGRect(x: p.x - r / 2, y: p.y - r / 2, width: r, height: r))
        }
        if let point = trail.tip {
            let p = screenPoint(point)
            let colors = [gold.withAlphaComponent(0.28).cgColor, gold.withAlphaComponent(0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                context.drawRadialGradient(gradient, startCenter: p, startRadius: 0, endCenter: p, endRadius: 23, options: [])
            }
            context.setShadow(offset: .zero, blur: 9, color: gold.cgColor)
            context.setFillColor(ivory.cgColor)
            context.fillEllipse(in: CGRect(x: p.x - 2.7, y: p.y - 2.7, width: 5.4, height: 5.4))
        }
        context.restoreGState()
        if promptOpacity > 0.001 {
            let shimmer = reducedMotion ? 1 : 0.92 + 0.08 * sin(now * 0.9)
            let shadow = NSShadow(); shadow.shadowColor = gold.withAlphaComponent(0.3 * promptOpacity)
            shadow.shadowBlurRadius = 18; shadow.shadowOffset = .zero
            let text = promptText(color: ivory.withAlphaComponent(promptOpacity * shimmer), shadow: shadow)
            let textSize = text.size()
            text.draw(at: CGPoint(x: bounds.midX - textSize.width / 2, y: bounds.midY - textSize.height / 2))
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard mouseMode else { return }
        stopInput(); window?.makeFirstResponder(self); holdingMouse = true; mouseDragged(with: event)
    }
    override func mouseDragged(with event: NSEvent) {
        guard mouseMode, holdingMouse else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point), bounds.width > 0, bounds.height > 0 else { stopInput(); return }
        let next = CGPoint(x: (point.x - bounds.minX) / bounds.width, y: (point.y - bounds.minY) / bounds.height)
        let now = ProcessInfo.processInfo.systemUptime
        // Mouse events may coalesce into a large jump; a held drag is known to
        // be continuous, unlike a distant camera detection after tracking loss.
        if let previous = trail.tip {
            let count = min(256, max(1, Int(ceil(hypot(next.x - previous.x, next.y - previous.y) / 0.008))))
            for index in 1...count {
                let t = Double(index) / Double(count)
                observe(CGPoint(x: previous.x + (next.x - previous.x) * t,
                                y: previous.y + (next.y - previous.y) * t), at: now)
            }
        } else { observe(next, at: now) }
    }
    override func mouseUp(with event: NSEvent) { if mouseMode { stopInput() } }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, window?.styleMask.contains(.fullScreen) == true { window?.toggleFullScreen(nil) }
        else { super.keyDown(with: event) }
    }
}
