import Cocoa
import AVFoundation
import CoreImage

let root = Bundle.main.bundleURL.deletingLastPathComponent()
let diagnosticDirectory = root.appendingPathComponent("diagnostics")
try? FileManager.default.createDirectory(at: diagnosticDirectory, withIntermediateDirectories: true)

final class DrawingView: NSView {
    var mouseMode = false
    var lastMouseTip: Tip?
    var onMouseTip: ((Tip) -> Void)?
    var lightOn = false
    var camera: CGImage?
    var tip: Tip?
    var mirrored = true
    var showCamera = true
    var drawing = true
    var strokes: [[CGPoint]] = []
    var current: [CGPoint] = []
    var onSeed: ((Double, Double) -> Void)?
    var gapFrames = 0
    var spell: Spell?
    var gameStrokes: [[CGPoint]] = []
    var gameCurrent: [CGPoint] = []
    var gameRecording = false
    var effectUntil = Date.distantPast
    var guideVisible = true
    override var isFlipped: Bool { true }
    var imageRect: CGRect {
        let aspect = camera.map { Double($0.width) / Double($0.height) } ?? 4.0 / 3.0
        let w = max(1, min(bounds.width - 32, (bounds.height - 32) * aspect))
        let h = w / aspect
        return CGRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h)
    }
    func finishStroke() {
        if !current.isEmpty { strokes.append(current) }
        current = []
        if !gameCurrent.isEmpty { gameStrokes.append(gameCurrent) }
        gameCurrent = []
    }
    func update(_ next: Tip?) {
        tip = next
        if let next {
            let point = CGPoint(x: mirrored ? 1 - next.x : next.x, y: next.y)
            if gapFrames > 6 { finishStroke() }
            let previous = spell != nil ? gameCurrent.last : current.last
            if let previous, gapFrames > 0, hypot(previous.x - point.x, previous.y - point.y) > 0.12 { finishStroke() }
            let smoothed = previous.map { CGPoint(x: $0.x * 0.25 + point.x * 0.75, y: $0.y * 0.25 + point.y * 0.75) } ?? point
            let moved = previous.map { hypot($0.x - smoothed.x, $0.y - smoothed.y) > 0.0008 } ?? true
            if spell != nil { if gameRecording && moved { gameCurrent.append(smoothed) } }
            else if drawing && moved { current.append(smoothed) }
            gapFrames = 0
        } else {
            gapFrames += 1
            if gapFrames == 7 { finishStroke() }
        }
        needsDisplay = true
    }
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil), r = imageRect
        guard r.contains(p) else { return }
        let x = (p.x - r.minX) / r.width
        finishStroke()
        if mouseMode { lastMouseTip = nil; mouseDragged(with: event) }
        else { onSeed?(mirrored ? 1 - x : x, (p.y - r.minY) / r.height) }
    }
    override func mouseDragged(with event: NSEvent) {
        guard mouseMode else { return }
        let p = convert(event.locationInWindow, from: nil), r = imageRect
        guard r.contains(p) else { finishStroke(); return }
        let x = (p.x - r.minX) / r.width
        let next = Tip(x: mirrored ? 1 - x : x, y: (p.y - r.minY) / r.height, area: 10, peak: 255, contrast: 255)
        if let previous = lastMouseTip {
            let count = max(1, Int(ceil(hypot(next.x - previous.x, next.y - previous.y) / 0.008)))
            for i in 1...count {
                let t = Double(i) / Double(count)
                let sample = Tip(x: previous.x + (next.x - previous.x) * t, y: previous.y + (next.y - previous.y) * t, area: 10, peak: 255, contrast: 255)
                onMouseTip?(sample); update(sample)
            }
        } else { onMouseTip?(next); update(next) }
        lastMouseTip = next
    }
    override func mouseUp(with event: NSEvent) { if mouseMode { mouseDragged(with: event); finishStroke(); lastMouseTip = nil } }
    func render(in context: CGContext, rect: CGRect, includeCamera: Bool, overlays: Bool = true) {
        context.setFillColor(NSColor(calibratedRed: 0.025, green: 0.035, blue: 0.075, alpha: 1).cgColor)
        context.fill(rect)
        if includeCamera, let camera {
            context.saveGState()
            context.translateBy(x: mirrored ? rect.maxX : rect.minX, y: rect.maxY)
            context.scaleBy(x: mirrored ? -1 : 1, y: -1)
            context.setAlpha(0.65)
            context.draw(camera, in: CGRect(origin: .zero, size: rect.size))
            context.restoreGState()
        }
        if lightOn && overlays {
            context.setFillColor(NSColor.systemYellow.withAlphaComponent(0.12).cgColor); context.fill(rect)
        }
        func point(_ p: CGPoint) -> CGPoint { CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height) }
        if let spell, guideVisible, overlays {
            let size = min(rect.width, rect.height) * 0.64
            let origin = CGPoint(x: rect.midX - size / 2, y: rect.midY - size / 2)
            let path = CGMutablePath()
            for (i, p) in spell.points.enumerated() {
                let q = CGPoint(x: origin.x + p.x * size, y: origin.y + p.y * size)
                if i == 0 { path.move(to: q) } else { path.addLine(to: q) }
            }
            context.saveGState(); context.setStrokeColor(NSColor.white.withAlphaComponent(0.35).cgColor)
            context.setLineWidth(3); context.setLineDash(phase: 0, lengths: [7, 8]); context.addPath(path); context.strokePath(); context.restoreGState()
            if let first = spell.points.first {
                context.setFillColor(NSColor.systemGreen.cgColor)
                context.fillEllipse(in: CGRect(x: origin.x + first.x * size - 6, y: origin.y + first.y * size - 6, width: 12, height: 12))
            }
        }
        let visibleStrokes = spell != nil ? gameStrokes + [gameCurrent] : strokes + [current]
        for stroke in visibleStrokes where !stroke.isEmpty {
            let path = CGMutablePath(); path.move(to: point(stroke[0]))
            if stroke.count == 1 {
                let p = point(stroke[0]); path.addLine(to: CGPoint(x: p.x + 0.1, y: p.y))
            } else { for p in stroke.dropFirst() { path.addLine(to: point(p)) } }
            context.saveGState()
            context.setLineCap(.round); context.setLineJoin(.round)
            context.setShadow(offset: .zero, blur: 12, color: NSColor.systemCyan.cgColor)
            context.setStrokeColor(NSColor.systemCyan.withAlphaComponent(0.4).cgColor)
            context.setLineWidth(8); context.addPath(path); context.strokePath()
            context.setStrokeColor(NSColor(calibratedRed: 0.8, green: 1, blue: 1, alpha: 1).cgColor)
            context.setLineWidth(2.5); context.addPath(path); context.strokePath()
            context.restoreGState()
        }
        if overlays, let tip {
            let p = point(CGPoint(x: mirrored ? 1 - tip.x : tip.x, y: tip.y))
            context.setStrokeColor(NSColor.systemYellow.cgColor); context.setLineWidth(2)
            context.strokeEllipse(in: CGRect(x: p.x - 14, y: p.y - 14, width: 28, height: 28))
        }
        if overlays, let spell { drawMagic(context, rect: rect, spell: spell) }
    }
    func drawMagic(_ c: CGContext, rect: CGRect, spell: Spell) {
        let active = Date() < effectUntil
        let t = Date.timeIntervalSinceReferenceDate
        let center = CGPoint(x: rect.maxX - 65, y: rect.minY + 65)
        let color: NSColor = active ? [.systemOrange, .systemCyan, .systemPurple, .systemYellow, .systemIndigo, .systemMint][spell.rawValue] : .gray
        c.saveGState(); c.setStrokeColor(color.cgColor); c.setFillColor(color.withAlphaComponent(active ? 0.6 : 0.12).cgColor); c.setLineWidth(3)
        if active { c.setShadow(offset: .zero, blur: 25, color: color.cgColor) }
        switch spell {
        case .lumos, .nox:
            if lightOn { c.setShadow(offset: .zero, blur: 45, color: NSColor.systemYellow.cgColor); c.setFillColor(NSColor.systemYellow.cgColor) }
            c.fillEllipse(in: CGRect(x: center.x - 15, y: center.y - 15, width: 30, height: 30))
            c.strokeEllipse(in: CGRect(x: center.x - 22, y: center.y - 22, width: 44, height: 44))
        case .leviosa:
            let y = center.y + (active ? -25 + sin(t * 3) * 10 : 25)
            c.move(to: CGPoint(x: center.x - 20, y: y + 20)); c.addLine(to: CGPoint(x: center.x + 18, y: y - 20)); c.strokePath()
            for i in 0..<7 {
                let d = Double(i) * 5
                c.move(to: CGPoint(x: center.x - 18 + d, y: y + 18 - d))
                c.addQuadCurve(to: CGPoint(x: center.x - 12 + d, y: y - 8 - d), control: CGPoint(x: center.x - 34 + d, y: y - 8 - d)); c.strokePath()
            }
        case .kindle:
            c.stroke(CGRect(x: center.x - 19, y: center.y - 25, width: 38, height: 50))
            if active {
                let radius = 10 + sin(t * 12) * 2
                c.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - 15, width: radius * 2, height: 30))
            }
        case .ward:
            let p = CGMutablePath(); p.move(to: CGPoint(x: center.x - 26, y: center.y - 23)); p.addLine(to: CGPoint(x: center.x + 26, y: center.y - 23)); p.addQuadCurve(to: CGPoint(x: center.x, y: center.y + 30), control: CGPoint(x: center.x + 26, y: center.y + 15)); p.addQuadCurve(to: CGPoint(x: center.x - 26, y: center.y - 23), control: CGPoint(x: center.x - 26, y: center.y + 15)); c.addPath(p); c.drawPath(using: .fillStroke)
        case .spark:
            if !active {
                let p = CGMutablePath(); p.move(to: CGPoint(x: center.x, y: center.y - 30)); p.addLine(to: CGPoint(x: center.x + 22, y: center.y)); p.addLine(to: CGPoint(x: center.x, y: center.y + 30)); p.addLine(to: CGPoint(x: center.x - 22, y: center.y)); p.closeSubpath(); c.addPath(p); c.drawPath(using: .fillStroke)
            }
        }
        if active {
            let progress = (4 - effectUntil.timeIntervalSinceNow) / 4
            for i in 0..<24 {
                let angle = Double(i) / 24 * .pi * 2 + t * 0.3
                let radius = 30 + progress * (spell == .spark ? 130 : 60)
                let p = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
                c.fillEllipse(in: CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4))
            }
        }
        c.restoreGState()
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        NSColor(calibratedWhite: 0.04, alpha: 1).setFill(); bounds.fill()
        render(in: context, rect: imageRect, includeCamera: showCamera)
    }
}

final class FlippedDocument: NSView { override var isFlipped: Bool { true } }

final class App: NSObject, NSApplicationDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, NSTabViewDelegate {
    var window: NSWindow!
    let canvas = DrawingView()
    let status = NSTextField(wrappingLabelWithString: "Requesting camera access…")
    let details = NSTextField(wrappingLabelWithString: "")
    let thresholdLabel = NSTextField(labelWithString: "Brightness threshold · 170")
    let areaLabel = NSTextField(labelWithString: "Maximum tip area · 600")
    let quality = NSTextField(wrappingLabelWithString: "Waiting for tracking measurements")
    let spellTitle = NSTextField(labelWithString: "Spell practice")
    let spellHint = NSTextField(wrappingLabelWithString: "Select your wand tip, then begin a challenge.")
    let spellResult = NSTextField(wrappingLabelWithString: "Circle → lantern · Triangle → shield · Bolt → crystal")
    let spellProgress = NSTextField(labelWithString: "")
    let spellPicker = NSPopUpButton()
    var castButton: NSButton!
    var spellButtons: [NSButton] = []
    var previewButtons: [NSButton] = []
    let connectionLabel = NSTextField(wrappingLabelWithString: "Camera is connecting. You can also practice with a mouse.")
    var gameTimer: Timer?
    var handsFree = true
    var gesture = GestureCapture()
    var gamePhase = "idle"
    var gameStart = Date.distantPast
    var gamePoints: [CGPoint] = []
    var gameFrames = 0, gameHits = 0
    var gapStarted: Date?
    var longestGap = 0.0
    var xp = UserDefaults.standard.integer(forKey: "spellXP")
    var streak = 0
    var qualityHistory: [Bool] = []
    let session = AVCaptureSession()
    let captureQueue = DispatchQueue(label: "wand.capture")
    let controlQueue = DispatchQueue(label: "wand.session")
    let ciContext = CIContext()
    var tracker = TipTracker()
    var device: AVCaptureDevice?
    var frameCount = 0
    var start = Date()
    var exposureSlider: NSSlider!
    var exposureLabel = NSTextField(labelWithString: "Exposure · automatic")
    var lastFrameTime = Date()
    var watchdog: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let data = try? Data(contentsOf: diagnosticDirectory.appendingPathComponent("canvas-autosave.json")), let paths = try? JSONDecoder().decode([[CGPoint]].self, from: data) { canvas.strokes = paths }
        buildUI()
        gameTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.tickGame() }
        if CommandLine.arguments.contains("--offline") {
            canvas.mouseMode = true
            status.stringValue = "Offline mouse practice"
            connectionLabel.stringValue = "Mouse practice · draw anywhere, then pause."
            return
        }
        let auth = AVCaptureDevice.authorizationStatus(for: .video)
        if auth == .authorized { startCamera() }
        else if auth == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { allowed in
                DispatchQueue.main.async {
                    if allowed { self.startCamera() }
                    else { self.status.stringValue = "Camera access denied. Enable Yer a Wizard in System Settings → Privacy & Security → Camera, then relaunch." }
                }
            }
        } else { status.stringValue = "Camera access is disabled. Enable Yer a Wizard in System Settings → Privacy & Security → Camera, then relaunch." }
        watchdog = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, self.device != nil, Date().timeIntervalSince(self.lastFrameTime) > 4 else { return }
            if !self.canvas.mouseMode { self.canvas.update(nil) }
            self.status.stringValue = "No camera frames. Check the USB connection and close other camera apps."
        }
    }
    func label(_ text: String, size: CGFloat = 13) -> NSTextField {
        let view = NSTextField(wrappingLabelWithString: text)
        view.font = .systemFont(ofSize: size)
        return view
    }
    func buildUI() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 780), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Yer a Wizard — Wand Studio"
        window.isRestorable = false
        window.minSize = NSSize(width: 940, height: 620)
        window.appearance = NSAppearance(named: .darkAqua)
        let container = NSView(); window.contentView = container
        let sidebar = NSStackView(); sidebar.orientation = .vertical; sidebar.alignment = .leading; sidebar.spacing = 13
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        let document = FlippedDocument(); document.translatesAutoresizingMaskIntoConstraints = false
        let scroller = NSScrollView(); scroller.hasVerticalScroller = true; scroller.drawsBackground = false; scroller.documentView = document
        document.addSubview(sidebar)
        NSLayoutConstraint.activate([
            document.widthAnchor.constraint(equalTo: scroller.contentView.widthAnchor),
            sidebar.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: document.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -8),
            sidebar.widthAnchor.constraint(equalToConstant: 266)
        ])
        canvas.translatesAutoresizingMaskIntoConstraints = false; scroller.translatesAutoresizingMaskIntoConstraints = false
        let gamePanel = NSStackView(); gamePanel.orientation = .vertical; gamePanel.alignment = .leading; gamePanel.spacing = 9; gamePanel.translatesAutoresizingMaskIntoConstraints = false
        let tabs = NSTabView(); tabs.translatesAutoresizingMaskIntoConstraints = false
        let library = NSStackView(); library.orientation = .vertical; library.alignment = .leading; library.spacing = 18
        let libraryHost = NSView(); library.translatesAutoresizingMaskIntoConstraints = false; libraryHost.addSubview(library)
        NSLayoutConstraint.activate([library.leadingAnchor.constraint(equalTo: libraryHost.leadingAnchor, constant: 14), library.trailingAnchor.constraint(equalTo: libraryHost.trailingAnchor, constant: -14), library.topAnchor.constraint(equalTo: libraryHost.topAnchor, constant: 24)])
        let spellsTab = NSTabViewItem(identifier: "spells"); spellsTab.label = "Spells"; spellsTab.view = libraryHost
        let debugTab = NSTabViewItem(identifier: "debug"); debugTab.label = "Debug"; debugTab.view = scroller; scroller.translatesAutoresizingMaskIntoConstraints = true
        tabs.addTabViewItem(spellsTab); tabs.addTabViewItem(debugTab); tabs.delegate = self
        library.addArrangedSubview(label("YOUR SPELLBOOK", size: 12))
        library.addArrangedSubview(label("A little everyday magic.", size: 23))
        for spell in [Spell.lumos, .nox, .leviosa] {
            let button = NSButton(title: spell.title, target: self, action: #selector(selectSpell(_:)))
            button.tag = spell.rawValue; button.bezelStyle = .regularSquare; button.setButtonType(.toggle)
            button.imagePosition = .imageAbove; button.image = spellIcon(spell)
            button.font = .systemFont(ofSize: 16, weight: .medium)
            button.widthAnchor.constraint(equalToConstant: 238).isActive = true; button.heightAnchor.constraint(equalToConstant: 104).isActive = true
            spellButtons.append(button); library.addArrangedSubview(button)
        }
        connectionLabel.font = .systemFont(ofSize: 12); connectionLabel.textColor = .secondaryLabelColor
        library.addArrangedSubview(connectionLabel)
        let mouse = NSButton(checkboxWithTitle: "Practice with mouse", target: self, action: #selector(toggleMouse(_:)))
        mouse.state = CommandLine.arguments.contains("--offline") ? .on : .off; library.addArrangedSubview(mouse)
        container.addSubview(canvas); container.addSubview(tabs); container.addSubview(gamePanel)
        NSLayoutConstraint.activate([
            tabs.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            tabs.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            tabs.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            tabs.widthAnchor.constraint(equalToConstant: 290),
            canvas.leadingAnchor.constraint(equalTo: tabs.trailingAnchor, constant: 8),
            canvas.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            gamePanel.leadingAnchor.constraint(equalTo: canvas.leadingAnchor, constant: 22),
            gamePanel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -22),
            gamePanel.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            canvas.topAnchor.constraint(equalTo: gamePanel.bottomAnchor, constant: 12), canvas.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        spellTitle.font = .systemFont(ofSize: 23, weight: .bold)
        spellResult.textColor = .systemCyan
        for view in [spellTitle, spellProgress, spellHint, spellResult] { gamePanel.addArrangedSubview(view) }
        for spell in Spell.allCases { spellPicker.addItem(withTitle: spell.title) }
        spellPicker.target = self; spellPicker.action = #selector(changeSpell)
        castButton = NSButton(title: "Cast ↵", target: self, action: #selector(castSpell)); castButton.keyEquivalent = "\r"; castButton.isEnabled = false
        let begin = NSButton(title: "Begin spell", target: self, action: #selector(beginSpell))
        let free = NSButton(title: "Free draw", target: self, action: #selector(freeDraw))
        let mainPreview = NSButton(checkboxWithTitle: "Show camera feed", target: self, action: #selector(togglePreview(_:))); mainPreview.state = .on; previewButtons.append(mainPreview)
        let gameButtons = NSStackView(views: [mainPreview]); gameButtons.spacing = 10; gamePanel.addArrangedSubview(gameButtons)
        updateProgress()
        func add(_ view: NSView) { sidebar.addArrangedSubview(view); view.widthAnchor.constraint(equalToConstant: 266).isActive = true }
        add(spellPicker); add(NSStackView(views: [begin, castButton, free]))
        let title = label("Tracking lab", size: 28); title.font = .systemFont(ofSize: 28, weight: .bold); add(title)
        add(label("Draw with a little reflected light.", size: 14))
        status.textColor = .systemCyan; add(status)
        add(details)
        quality.textColor = .secondaryLabelColor; quality.font = .monospacedSystemFont(ofSize: 11, weight: .regular); add(quality)
        add(label("Click the bright tip to select it. Keep it facing the lens. Brief gaps are tolerated; brightness adapts near the selected tip."))
        tracker.settings.threshold = UserDefaults.standard.object(forKey: "threshold") as? Int ?? 170
        tracker.settings.maximumArea = UserDefaults.standard.object(forKey: "maximumArea") as? Int ?? 600
        thresholdLabel.stringValue = "Brightness threshold · \(tracker.settings.threshold)"
        areaLabel.stringValue = "Maximum tip area · \(tracker.settings.maximumArea)"
        add(thresholdLabel)
        add(NSSlider(value: Double(tracker.settings.threshold), minValue: 85, maxValue: 254, target: self, action: #selector(thresholdChanged(_:))))
        add(areaLabel)
        add(NSSlider(value: Double(tracker.settings.maximumArea), minValue: 5, maxValue: 2400, target: self, action: #selector(areaChanged(_:))))
        add(exposureLabel)
        exposureSlider = NSSlider(value: 5, minValue: 0.2, maxValue: 33, target: self, action: #selector(exposureChanged(_:)))
        exposureSlider.isEnabled = false; exposureSlider.isContinuous = false; add(exposureSlider)
        add(NSButton(title: "Restore auto exposure", target: self, action: #selector(autoExposure)))
        let draw = NSButton(checkboxWithTitle: "Draw while tip is tracked", target: self, action: #selector(toggleDrawing(_:))); draw.state = .on; add(draw)
        let preview = NSButton(checkboxWithTitle: "Show camera preview", target: self, action: #selector(togglePreview(_:))); preview.state = .on; previewButtons.append(preview); add(preview)
        let mirror = NSButton(checkboxWithTitle: "Mirror movement", target: self, action: #selector(toggleMirror(_:))); mirror.state = .on; add(mirror)
        let buttons = NSStackView(views: [NSButton(title: "Clear", target: self, action: #selector(clear)), NSButton(title: "Find tip", target: self, action: #selector(reset)), NSButton(title: "Save PNG", target: self, action: #selector(save))]); buttons.spacing = 8; add(buttons)
        add(NSButton(title: "Save diagnostic frame", target: self, action: #selector(snapshot)))
        add(label("Night mode: keep the light sensor below the lens covered. Start near 1 ms exposure; increase slightly if the tip is dim.", size: 12))
        canvas.onSeed = { [weak self] x, y in self?.captureQueue.async { self?.tracker.seed(x: x, y: y) } }
        canvas.onMouseTip = { [weak self] tip in self?.recordGame(tip) }
        spellPicker.selectItem(at: Spell.lumos.rawValue); changeSpell(); armHandsFree()
        let mainMenu = NSMenu(); let item = NSMenuItem(); mainMenu.addItem(item)
        let menu = NSMenu(); menu.addItem(withTitle: "Quit Yer a Wizard", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"); item.submenu = menu; NSApp.mainMenu = mainMenu
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func armHandsFree() {
        canvas.finishStroke(); canvas.spell = Spell(rawValue: spellPicker.indexOfSelectedItem) ?? .lumos
        canvas.guideVisible = false; canvas.gameRecording = true
        gesture = GestureCapture(); gamePhase = "idle"; castButton.isEnabled = false
        spellPicker.isEnabled = true; spellButtons.forEach { $0.isEnabled = true }
        spellResult.stringValue = "Draw anywhere · pause for a moment to cast automatically."
        canvas.needsDisplay = true
    }
    func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        autosave(); canvas.finishStroke(); canvas.gameRecording = false; gamePhase = "idle"
        handsFree = (tabViewItem?.identifier as? String) == "spells"
        gesture = GestureCapture(); castButton.isEnabled = false
        spellPicker.isEnabled = true; spellButtons.forEach { $0.isEnabled = true }
        if handsFree { armHandsFree() }
        else { canvas.guideVisible = true; spellResult.stringValue = "Manual development controls · Begin spell or Free draw." }
        canvas.needsDisplay = true
    }
    func spellIcon(_ spell: Spell) -> NSImage {
        NSImage(size: NSSize(width: 70, height: 50), flipped: true) { rect in
            let path = NSBezierPath(); path.lineWidth = 2.5; path.lineCapStyle = .round; path.lineJoinStyle = .round
            for (i, p) in spell.points.enumerated() {
                let q = CGPoint(x: 15 + p.x * 40, y: 5 + p.y * 40)
                if i == 0 { path.move(to: q) } else { path.line(to: q) }
            }
            NSColor.systemCyan.setStroke(); path.stroke(); return true
        }
    }
    @objc func selectSpell(_ button: NSButton) { spellPicker.selectItem(at: button.tag); changeSpell() }
    @objc func toggleMouse(_ button: NSButton) {
        autosave(); canvas.finishStroke(); canvas.gameRecording = false; gamePhase = "idle"
        castButton.isEnabled = false; spellPicker.isEnabled = true; spellButtons.forEach { $0.isEnabled = true }
        canvas.mouseMode = button.state == .on; canvas.tip = nil; canvas.lastMouseTip = nil
        connectionLabel.stringValue = canvas.mouseMode ? "Mouse practice · draw anywhere, then pause." : "Point the wand at the camera, then draw."
        spellResult.stringValue = "Begin a spell when ready."; canvas.needsDisplay = true
        if handsFree { armHandsFree() }
    }
    func startCamera() {
        controlQueue.async {
            let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: .video, position: .unspecified).devices
            let inventory = devices.map { d in
                ["name": d.localizedName, "id": d.uniqueID, "customExposure": d.isExposureModeSupported(.custom), "formats": d.formats.map { f -> String in
                    let dim = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
                    return "\(dim.width)x\(dim.height) \(f.videoSupportedFrameRateRanges.map { $0.maxFrameRate })"
                }] as [String: Any]
            }
            if let data = try? JSONSerialization.data(withJSONObject: inventory, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: diagnosticDirectory.appendingPathComponent("camera.json")) }
            guard let device = devices.first(where: { $0.localizedName.lowercased().contains("arducam") }) else {
                DispatchQueue.main.async { self.status.stringValue = "Arducam not found by macOS video capture. Check its connection, then relaunch." }; return
            }
            do {
                self.session.beginConfiguration()
                self.session.sessionPreset = .vga640x480
                let input = try AVCaptureDeviceInput(device: device)
                guard self.session.canAddInput(input) else { throw NSError(domain: "Camera input unavailable", code: 1) }
                self.session.addInput(input)
                if let format = device.formats.first(where: {
                    let dimensions = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
                    return dimensions.width == 640 && dimensions.height == 480
                }) {
                    try device.lockForConfiguration()
                    device.activeFormat = format
                    if let range = format.videoSupportedFrameRateRanges.first {
                        device.activeVideoMinFrameDuration = range.minFrameDuration
                        device.activeVideoMaxFrameDuration = range.minFrameDuration
                    }
                    device.unlockForConfiguration()
                }
                let output = AVCaptureVideoDataOutput()
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                output.alwaysDiscardsLateVideoFrames = true
                output.setSampleBufferDelegate(self, queue: self.captureQueue)
                guard self.session.canAddOutput(output) else { throw NSError(domain: "Camera output unavailable", code: 2) }
                self.session.addOutput(output)
                self.session.commitConfiguration()
                DispatchQueue.main.async {
                    self.device = device; self.lastFrameTime = Date()
                    self.details.stringValue = device.localizedName
                    self.exposureSlider.isEnabled = true
                    self.exposureLabel.stringValue = "Exposure · automatic (USB control)"
                    self.usbControl([])
                }
                self.session.startRunning()
            } catch {
                self.session.commitConfiguration()
                DispatchQueue.main.async { self.status.stringValue = "Camera error: \(error.localizedDescription)" }
            }
        }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { CVPixelBufferUnlockBaseAddress(buffer, .readOnly); return }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer), stride = CVPixelBufferGetBytesPerRow(buffer)
        let w = width / 2, h = height / 2
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var gray = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h { for x in 0..<w {
            let i = y * 2 * stride + x * 8
            let blue = Int(bytes[i]) * 29
            let green = Int(bytes[i + 1]) * 150
            let red = Int(bytes[i + 2]) * 77
            gray[y * w + x] = UInt8((blue + green + red) >> 8)
        } }
        CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
        if tracker.anchor == nil { tracker.automaticAcquisition = true }
        let (tip, candidates) = tracker.process(gray, width: w, height: h)
        let trackingMessage = tracker.message
        let background = tracker.backgroundLevel, adaptive = tracker.localThreshold, brightPercent = tracker.brightPercent
        let ci = CIImage(cvPixelBuffer: buffer)
        let image = ciContext.createCGImage(ci, from: ci.extent)
        frameCount += 1
        let shouldSave = frameCount == 30
        let shouldAutosave = frameCount % 90 == 0
        if frameCount == 1 { start = Date() }
        let fps = Double(frameCount) / max(1, Date().timeIntervalSince(start))
        DispatchQueue.main.async {
            self.lastFrameTime = Date()
            self.canvas.camera = image; if !self.canvas.mouseMode { self.recordGame(tip); self.canvas.update(tip) }; self.canvas.needsDisplay = true
            self.connectionLabel.stringValue = self.canvas.mouseMode ? "Mouse practice · draw anywhere, then pause." : (tip == nil ? "Point the wand at the camera, then draw." : "Wand connected · draw, then pause to cast")
            self.status.stringValue = trackingMessage
            self.qualityHistory.append(tip != nil); if self.qualityHistory.count > 90 { self.qualityHistory.removeFirst() }
            let percentage = self.qualityHistory.filter { $0 }.count * 100 / max(1, self.qualityHistory.count)
            self.quality.stringValue = "Recent lock \(percentage)% · candidates \(candidates)\nBackground \(background)/255 · bright \(String(format: "%.1f", brightPercent))%\nLocal threshold \(adaptive)"
            self.details.stringValue = "Arducam B0590 · \(width)×\(height)\n\(Int(fps)) fps" + (tip.map { " · tip \($0.area) px · contrast \(Int($0.contrast))" } ?? "")
            if shouldSave { self.writeFrame(image, name: "initial-frame.png") }
            if shouldAutosave {
                self.autosave()
                let measurement: [String: Any] = ["timestamp": Date().timeIntervalSince1970, "recentLockPercent": percentage, "backgroundMean": background, "brightPercent": brightPercent, "localThreshold": adaptive, "candidates": candidates, "message": trackingMessage, "peak": tip?.peak ?? 0, "area": tip?.area ?? 0, "fps": fps]
                if let data = try? JSONSerialization.data(withJSONObject: measurement, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: diagnosticDirectory.appendingPathComponent("tracking.json"), options: .atomic) }
            }
        }
    }
    func writeFrame(_ image: CGImage?, name: String) {
        guard let image else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: diagnosticDirectory.appendingPathComponent(name))
    }
    @objc func thresholdChanged(_ slider: NSSlider) {
        let value = slider.integerValue; thresholdLabel.stringValue = "Brightness threshold · \(value)"
        UserDefaults.standard.set(value, forKey: "threshold")
        canvas.finishStroke(); captureQueue.async { self.tracker.settings.threshold = value; self.tracker.reset() }
    }
    @objc func areaChanged(_ slider: NSSlider) {
        let value = slider.integerValue; areaLabel.stringValue = "Maximum tip area · \(value)"
        UserDefaults.standard.set(value, forKey: "maximumArea")
        canvas.finishStroke(); captureQueue.async { self.tracker.settings.maximumArea = value; self.tracker.reset() }
    }
    @objc func exposureChanged(_ slider: NSSlider) {
        usbControl(["--exposure-ms", String(slider.doubleValue)])
    }
    @objc func autoExposure() {
        usbControl(["--auto-exposure"])
    }
    func usbControl(_ arguments: [String]) {
        exposureSlider.isEnabled = false
        controlQueue.async {
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = [root.appendingPathComponent("scripts/inspect_usb.py").path] + arguments
            let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
                let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                DispatchQueue.main.async {
                    self.exposureSlider.isEnabled = true
                    let controls = json?["controls"] as? [String: [String: Any]]
                    let mode = (json?["mode_after"] as? Int) ?? (controls?["auto_exposure"]?["current"] as? Int)
                    let exposure = (json?["exposure_after"] as? Int) ?? (controls?["exposure"]?["current"] as? Int)
                    if process.terminationStatus == 0, let mode {
                        if let value = exposure, mode == 1 {
                            self.exposureLabel.stringValue = String(format: "Exposure · %.1f ms (verified)", Double(value) / 10)
                            self.exposureSlider.doubleValue = Double(value) / 10
                        } else { self.exposureLabel.stringValue = "Exposure · automatic (verified)" }
                    } else { self.exposureLabel.stringValue = "USB exposure control failed" }
                }
            } catch { DispatchQueue.main.async { self.exposureSlider.isEnabled = true; self.exposureLabel.stringValue = "USB control: \(error.localizedDescription)" } }
        }
    }
    @objc func toggleDrawing(_ button: NSButton) { canvas.finishStroke(); canvas.drawing = button.state == .on }
    @objc func togglePreview(_ button: NSButton) { canvas.showCamera = button.state == .on; for preview in previewButtons { preview.state = button.state }; canvas.needsDisplay = true }
    @objc func toggleMirror(_ button: NSButton) { canvas.finishStroke(); canvas.mirrored = button.state == .on; canvas.needsDisplay = true }
    @objc func clear() {
        autosave(backup: true)
        if canvas.spell != nil { canvas.gameStrokes = []; canvas.gameCurrent = []; gamePoints = []; gameHits = 0; gameFrames = 0 }
        else { canvas.strokes = []; canvas.current = [] }
        canvas.needsDisplay = true
    }
    @objc func reset() { canvas.finishStroke(); captureQueue.async { self.tracker.reset(); self.tracker.automaticAcquisition = true } }
    @objc func snapshot() { writeFrame(canvas.camera, name: "latest-frame.png"); status.stringValue = "Diagnostic frame saved in project/diagnostics" }
    @objc func save() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "wand-drawing.png"; panel.allowedContentTypes = [.png]
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url,
                  let context = CGContext(data: nil, width: 1280, height: 960, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.translateBy(x: 0, y: 960); context.scaleBy(x: 1, y: -1)
            self.canvas.render(in: context, rect: CGRect(x: 0, y: 0, width: 1280, height: 960), includeCamera: false, overlays: false)
            guard let image = context.makeImage() else { return }
            do { try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url) }
            catch { self.status.stringValue = "Save failed: \(error.localizedDescription)" }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { autosave() }
    func autosave(backup: Bool = false) {
        let paths = canvas.strokes + (canvas.current.isEmpty ? [] : [canvas.current])
        let name = backup ? "canvas-before-clear-\(Int(Date().timeIntervalSince1970)).json" : "canvas-autosave.json"
        if let data = try? JSONEncoder().encode(paths) { try? data.write(to: diagnosticDirectory.appendingPathComponent(name), options: .atomic) }
        if !canvas.gameStrokes.isEmpty || !canvas.gameCurrent.isEmpty {
            if let data = try? JSONEncoder().encode(canvas.gameStrokes + [canvas.gameCurrent]) { try? data.write(to: diagnosticDirectory.appendingPathComponent("last-spell.json"), options: .atomic) }
        }
    }
    func updateProgress() { spellProgress.stringValue = "Level \(xp / 300 + 1) apprentice · \(xp) XP · streak \(streak)" }
    @objc func changeSpell() {
        guard handsFree || (gamePhase != "recording" && gamePhase != "countdown") else { spellPicker.selectItem(at: canvas.spell?.rawValue ?? 0); return }
        autosave(); canvas.finishStroke()
        let spell = Spell(rawValue: spellPicker.indexOfSelectedItem)!
        canvas.spell = spell; canvas.gameStrokes = []; canvas.gameCurrent = []; canvas.guideVisible = true
        spellTitle.stringValue = spell.title; spellHint.stringValue = spell.instruction
        spellResult.stringValue = "Begin a spell, trace the guide, then cast."
        for button in spellButtons { button.state = button.tag == spell.rawValue ? .on : .off }
        canvas.needsDisplay = true
        if handsFree { armHandsFree() }
    }
    @objc func beginSpell() {
        guard gamePhase != "recording", gamePhase != "countdown" else { return }
        guard canvas.mouseMode || (canvas.tip != nil && Date().timeIntervalSince(lastFrameTime) < 4) else { spellResult.stringValue = "Select the bright wand tip first, then begin."; return }
        autosave(); canvas.finishStroke()
        let spell = Spell(rawValue: spellPicker.indexOfSelectedItem)!
        canvas.spell = spell; canvas.guideVisible = true; canvas.effectUntil = .distantPast
        canvas.gameStrokes = []; canvas.gameCurrent = []; canvas.gameRecording = false
        gamePoints = []; gameFrames = 0; gameHits = 0; longestGap = 0; gapStarted = nil
        gameStart = Date().addingTimeInterval(canvas.mouseMode ? 0 : 2); gamePhase = canvas.mouseMode ? "recording" : "countdown"; canvas.gameRecording = canvas.mouseMode
        spellTitle.stringValue = "\(spell.title) · spell challenge"
        spellHint.stringValue = spell.instruction + " Follow the dotted guide once."
        spellResult.stringValue = "Get ready…"; castButton.isEnabled = canvas.mouseMode; spellPicker.isEnabled = false; spellButtons.forEach { $0.isEnabled = false }
    }
    @objc func freeDraw() {
        autosave(); canvas.finishStroke(); canvas.gameRecording = false; canvas.spell = nil
        gamePhase = "idle"; castButton.isEnabled = false; spellPicker.isEnabled = true; spellButtons.forEach { $0.isEnabled = true }
        spellTitle.stringValue = "Spell practice"; spellResult.stringValue = "Free drawing — your earlier canvas is preserved."
    }
    func tickGame() {
        let now = Date()
        if handsFree {
            if let completed = gesture.finishIfIdle(at: now.timeIntervalSinceReferenceDate) {
                let points = completed.points
                // Ignore a resting tip and tiny adjustments rather than reporting failed spells.
                let width = (points.map(\.x).max() ?? 0) - (points.map(\.x).min() ?? 0)
                let height = (points.map(\.y).max() ?? 0) - (points.map(\.y).min() ?? 0)
                if max(width, height) >= 0.12 {
                    let ranked = [Spell.lumos, .nox, .leviosa].map { spell in
                        (spell, SpellRecognizer.match(points, spell: spell, coverage: 1, longestGap: completed.gap))
                    }.sorted { $0.1.score > $1.1.score }
                    let winner = ranked[0]
                    gamePoints = points; gameHits = 1; gameFrames = 1; longestGap = completed.gap; gapStarted = nil
                    if winner.1.accepted { canvas.spell = winner.0 }; gamePhase = "recording"
                    castSpell()
                    if !winner.1.accepted { spellResult.stringValue = "No spell recognized. Draw a shape, then pause to try again." }
                    else {
                        spellPicker.selectItem(at: winner.0.rawValue)
                        spellTitle.stringValue = winner.0.title
                        spellHint.stringValue = winner.0.instruction
                        for button in spellButtons { button.state = button.tag == winner.0.rawValue ? .on : .off }
                    }
                }
            }
            if now < canvas.effectUntil { canvas.needsDisplay = true }
            return
        }
        if gamePhase == "countdown" {
            let remaining = gameStart.timeIntervalSince(now)
            spellResult.stringValue = "Start in \(max(1, Int(ceil(remaining))))…"
            if remaining <= 0 { gamePhase = "recording"; canvas.gameRecording = true; castButton.isEnabled = true }
        } else if gamePhase == "recording" && !canvas.mouseMode {
            let remaining = 7 - now.timeIntervalSince(gameStart)
            spellResult.stringValue = "Draw now · \(max(0, Int(ceil(remaining))))s · press Cast when finished"
            if remaining <= 0 { castSpell() }
        }
        if gamePhase == "recording" && canvas.mouseMode { spellResult.stringValue = "Draw with the mouse · press Cast when finished" }
        if now < canvas.effectUntil || gamePhase == "countdown" { canvas.needsDisplay = true }
    }
    func recordGame(_ tip: Tip?) {
        if handsFree {
            let aspect = canvas.imageRect.width / max(1, canvas.imageRect.height)
            let point = tip.map { CGPoint(x: (canvas.mirrored ? 1 - $0.x : $0.x) * aspect, y: $0.y) }
            if gesture.observe(point, at: Date.timeIntervalSinceReferenceDate) {
                autosave(); canvas.finishStroke(); canvas.gameStrokes = []; canvas.gameCurrent = []
                canvas.gameRecording = true; canvas.guideVisible = false
                spellResult.stringValue = "Drawing… pause briefly to cast."
            }
            return
        }
        guard gamePhase == "recording" else { return }
        gameFrames += 1
        if let tip {
            gameHits += 1
            if let gapStarted { longestGap = max(longestGap, Date().timeIntervalSince(gapStarted)); self.gapStarted = nil }
            let aspect = canvas.imageRect.width / max(1, canvas.imageRect.height)
            let point = CGPoint(x: (canvas.mirrored ? 1 - tip.x : tip.x) * aspect, y: tip.y)
            if gamePoints.last.map({ SpellRecognizer.distance($0, point) > 0.003 }) ?? true { gamePoints.append(point) }
        } else if gapStarted == nil { gapStarted = Date() }
    }
    @objc func castSpell() {
        guard gamePhase == "recording", let spell = canvas.spell else { return }
        canvas.gameRecording = false; canvas.finishStroke(); gamePhase = "result"; castButton.isEnabled = false; spellPicker.isEnabled = true; spellButtons.forEach { $0.isEnabled = true }
        if let gapStarted { longestGap = max(longestGap, Date().timeIntervalSince(gapStarted)) }
        let result = SpellRecognizer.match(gamePoints, spell: spell, coverage: Double(gameHits) / Double(max(1, gameFrames)), longestGap: longestGap)
        spellResult.stringValue = "\(result.accepted ? "✦" : "Try again") \(result.feedback) · match \(Int(result.score * 100))%"
        if result.accepted {
            streak += 1; let reward = 100 + min(streak - 1, 5) * 10; xp += reward
            UserDefaults.standard.set(xp, forKey: "spellXP")
            canvas.guideVisible = false; canvas.effectUntil = Date().addingTimeInterval(4)
            spellResult.stringValue += " · +\(reward) XP"
            if spell == .lumos { canvas.lightOn = true }; if spell == .nox { canvas.lightOn = false }
        } else { streak = 0 }
        updateProgress(); canvas.needsDisplay = true; autosave()
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.run()
