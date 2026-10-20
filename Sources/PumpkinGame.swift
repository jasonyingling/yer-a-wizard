import Cocoa
import SceneKit

// UV-space cuts stay attached to the mesh, independently of window size.
struct PumpkinCuts: Codable {
    var strokes: [[CGPoint]] = []
    static func isClosed(_ stroke: [CGPoint]) -> Bool {
        guard stroke.count >= 8, let first = stroke.first, let last = stroke.last else { return false }
        let width = (stroke.map(\.x).max() ?? 0) - (stroke.map(\.x).min() ?? 0)
        let height = (stroke.map(\.y).max() ?? 0) - (stroke.map(\.y).min() ?? 0)
        return width > 0.012 && height > 0.02 && hypot(first.x - last.x, first.y - last.y) < 0.018
    }
}

final class CarvingSceneView: SCNView {
    var onPointer: ((CGPoint?) -> Void)?
    override func mouseDown(with event: NSEvent) { onPointer?(convert(event.locationInWindow, from: nil)) }
    override func mouseDragged(with event: NSEvent) { onPointer?(convert(event.locationInWindow, from: nil)) }
    override func mouseUp(with event: NSEvent) { onPointer?(nil) }
}

final class CameraReferenceView: NSView {
    var image: CGImage? { didSet { needsDisplay = true } }
    var tip: Tip? { didSet { needsDisplay = true } }
    var mirrored = true
    var onSeed: ((Double, Double) -> Void)?
    override var isFlipped: Bool { true }
    var imageRect: CGRect {
        let aspect = image.map { CGFloat($0.width) / CGFloat($0.height) } ?? 4 / 3
        let width = min(bounds.width, bounds.height * aspect)
        return CGRect(x: (bounds.width - width) / 2, y: (bounds.height - width / aspect) / 2, width: width, height: width / aspect)
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        NSColor(calibratedWhite: 0.08, alpha: 1).setFill(); bounds.fill()
        if let image {
            let r = imageRect
            c.saveGState(); c.translateBy(x: mirrored ? r.maxX : r.minX, y: r.maxY); c.scaleBy(x: mirrored ? -1 : 1, y: -1)
            c.draw(image, in: CGRect(origin: .zero, size: r.size)); c.restoreGState()
            if let tip {
                let p = CGPoint(x: r.minX + (mirrored ? 1 - tip.x : tip.x) * r.width, y: r.minY + tip.y * r.height)
                c.setStrokeColor(NSColor.systemYellow.cgColor); c.setLineWidth(2)
                c.strokeEllipse(in: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12))
            }
        } else {
            let text = "Camera reference\nMouse practice is ready"
            (text as NSString).draw(in: bounds.insetBy(dx: 15, dy: 36), withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor])
        }
    }
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil), r = imageRect
        guard image != nil, r.contains(p) else { return }
        let x = (p.x - r.minX) / r.width
        onSeed?(mirrored ? 1 - x : x, (p.y - r.minY) / r.height)
    }
}

final class PumpkinGameController: NSViewController {
    let stage = CarvingSceneView()
    let preview = CameraReferenceView()
    let scene = SCNScene()
    let pumpkin = SCNNode()
    let core = SCNNode()
    let cursor = SCNNode(geometry: SCNSphere(radius: 0.025))
    let skin = SCNMaterial()
    let hint = NSTextField(labelWithString: "A face only you could imagine.")
    let cameraStatus = NSTextField(wrappingLabelWithString: "Connecting your wand…")
    let countLabel = NSTextField(labelWithString: "YOUR PUMPKIN · A BLANK CANVAS")
    var carveButton: NSButton!
    var undoButton: NSButton!
    var lightButton: NSButton!
    var mouseButton: NSButton!
    var cuts = PumpkinCuts()
    var current: [CGPoint] = []
    var carving = false
    var lit = false
    var mouseMode = CommandLine.arguments.contains("--offline")
    var lastMovement = Date.distantPast
    var lastInput = Date.distantPast
    var timer: Timer?
    var trail = SCNNode()
    let saveURL: URL
    let amber = NSColor(calibratedRed: 1, green: 0.66, blue: 0.29, alpha: 1)

    init(saveURL: URL) {
        self.saveURL = saveURL
        super.init(nibName: nil, bundle: nil)
        if let data = try? Data(contentsOf: saveURL), let saved = try? JSONDecoder().decode(PumpkinCuts.self, from: data) { cuts = saved }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func text(_ value: String, size: CGFloat, color: NSColor = .white) -> NSTextField {
        let field = NSTextField(labelWithString: value); field.font = .systemFont(ofSize: size); field.textColor = color; return field
    }
    func button(_ title: String, symbol: String, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded; b.controlSize = .large
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil); b.imagePosition = .imageLeading
        b.heightAnchor.constraint(equalToConstant: 38).isActive = true
        return b
    }
    override func loadView() {
        view = NSView(); view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(calibratedRed: 0.045, green: 0.055, blue: 0.052, alpha: 1).cgColor
        stage.scene = scene; stage.backgroundColor = .clear; stage.antialiasingMode = .multisampling4X
        stage.preferredFramesPerSecond = 30; stage.autoenablesDefaultLighting = false
        stage.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stage)
        NSLayoutConstraint.activate([stage.leadingAnchor.constraint(equalTo: view.leadingAnchor), stage.trailingAnchor.constraint(equalTo: view.trailingAnchor), stage.topAnchor.constraint(equalTo: view.topAnchor), stage.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
        buildScene()

        let title = NSStackView(views: [text("YER A WIZARD  /  AUTUMN COLLECTION", size: 10, color: amber), text("The Pumpkin Atelier", size: 32), text("A little mischief. A little magic. Something entirely yours.", size: 12, color: .secondaryLabelColor)])
        title.orientation = .vertical; title.alignment = .centerX; title.spacing = 8
        title.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(title)
        NSLayoutConstraint.activate([title.centerXAnchor.constraint(equalTo: view.centerXAnchor, constant: 60), title.topAnchor.constraint(equalTo: view.topAnchor, constant: 27)])

        preview.wantsLayer = true; preview.layer?.cornerRadius = 12; preview.layer?.masksToBounds = true
        preview.widthAnchor.constraint(equalToConstant: 176).isActive = true; preview.heightAnchor.constraint(equalToConstant: 112).isActive = true
        cameraStatus.font = .systemFont(ofSize: 11); cameraStatus.textColor = .secondaryLabelColor
        cameraStatus.preferredMaxLayoutWidth = 176
        let cameraCard = NSStackView(views: [preview, cameraStatus]); cameraCard.orientation = .vertical; cameraCard.alignment = .leading; cameraCard.spacing = 9
        cameraCard.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(cameraCard)
        NSLayoutConstraint.activate([cameraCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24), cameraCard.topAnchor.constraint(equalTo: view.topAnchor, constant: 24), cameraCard.widthAnchor.constraint(equalToConstant: 176)])

        carveButton = button("Start carving", symbol: "wand.and.stars", action: #selector(toggleCarving)); carveButton.contentTintColor = amber; carveButton.keyEquivalent = " "
        undoButton = button("Undo", symbol: "arrow.uturn.backward", action: #selector(undo)); undoButton.keyEquivalent = "z"; undoButton.keyEquivalentModifierMask = .command
        lightButton = button("Light it up", symbol: "flame", action: #selector(toggleLight))
        let fresh = button("New pumpkin", symbol: "arrow.clockwise", action: #selector(newPumpkin))
        let save = button("Save portrait", symbol: "square.and.arrow.down", action: #selector(savePortrait))
        let controls = NSStackView(views: [carveButton, undoButton, lightButton, fresh, save]); controls.spacing = 10
        hint.font = .systemFont(ofSize: 13); hint.textColor = .secondaryLabelColor
        countLabel.font = .systemFont(ofSize: 10, weight: .medium); countLabel.textColor = amber
        let instructions = text("Trace a loop for each eye and a smile. Close the loop to cut it out.", size: 13, color: .secondaryLabelColor)
        let footer = NSStackView(views: [countLabel, instructions, controls, hint]); footer.orientation = .vertical; footer.alignment = .centerX; footer.spacing = 14
        footer.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(footer)
        NSLayoutConstraint.activate([footer.centerXAnchor.constraint(equalTo: view.centerXAnchor), footer.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -28)])
        mouseButton = NSButton(checkboxWithTitle: "Mouse practice", target: self, action: #selector(toggleMouse)); mouseButton.state = mouseMode ? .on : .off
        mouseButton.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(mouseButton)
        NSLayoutConstraint.activate([mouseButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24), mouseButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 26)])
        stage.onPointer = { [weak self] point in
            guard let self, self.mouseMode else { return }
            if let point { self.sample(point, drawing: !self.lit) } else { self.finishStroke(); self.cursor.isHidden = true }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if Date().timeIntervalSince(self.lastMovement) > 0.8 { self.finishStroke() }
            if Date().timeIntervalSince(self.lastInput) > 0.4 { self.cursor.isHidden = true; self.finishStroke() }
        }
        updateMask(); updateControls()
        if mouseMode { cameraStatus.stringValue = "Mouse practice · drag on the pumpkin" }
    }

    // A ribbed, flattened sphere with explicit UVs; no downloaded model or assets.
    static func geometry(scale: Float = 1) -> SCNGeometry {
        let rows = 80, columns = 160
        var vertices: [SCNVector3] = [], uv: [CGPoint] = [], indices: [Int32] = []
        for row in 0...rows {
            let v = Double(row) / Double(rows), phi = v * .pi
            for column in 0...columns {
                let u = Double(column) / Double(columns), theta = u * .pi * 2
                let rib = 1 + 0.075 * cos(theta * 10)
                let radius = sin(phi) * rib
                vertices.append(SCNVector3(Float(radius * cos(theta)) * scale, Float(cos(phi) * 0.83 - 0.08 * pow(abs(cos(phi)), 8) * cos(phi)) * scale, Float(radius * sin(theta)) * scale))
                uv.append(CGPoint(x: u, y: v))
                if row < rows && column < columns {
                    let a = Int32(row * (columns + 1) + column), b = a + Int32(columns + 1)
                    indices += [a, a + 1, b, a + 1, b + 1, b]
                }
            }
        }
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(textureCoordinates: uv)], elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        // Smooth normals derived from local mesh neighbors, including periodic seam.
        var normals: [SCNVector3] = []
        for row in 0...rows { for column in 0...columns {
            let left = vertices[row * (columns + 1) + (column + columns - 1) % columns]
            let right = vertices[row * (columns + 1) + (column + 1) % columns]
            let above = vertices[max(0, row - 1) * (columns + 1) + column]
            let below = vertices[min(rows, row + 1) * (columns + 1) + column]
            let a = SCNVector3(right.x - left.x, right.y - left.y, right.z - left.z)
            let b = SCNVector3(below.x - above.x, below.y - above.y, below.z - above.z)
            var n = SCNVector3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
            let length = sqrt(n.x * n.x + n.y * n.y + n.z * n.z)
            if length > 0.00001 { n = SCNVector3(n.x / length, n.y / length, n.z / length) }
            else { n = SCNVector3(0, row == 0 ? 1 : -1, 0) }
            normals.append(n)
        } }
        return SCNGeometry(sources: g.sources + [SCNGeometrySource(normals: normals)], elements: g.elements)
    }
    func buildScene() {
        let camera = SCNNode(); camera.camera = SCNCamera(); camera.camera?.usesOrthographicProjection = true; camera.camera?.orthographicScale = 1.85
        camera.position = SCNVector3(0, 0.3, 6); camera.look(at: SCNVector3(0, 0.08, 0)); scene.rootNode.addChildNode(camera); stage.pointOfView = camera
        func light(_ kind: SCNLight.LightType, _ color: NSColor, _ intensity: CGFloat, _ position: SCNVector3) {
            let node = SCNNode(); node.light = SCNLight(); node.light?.type = kind; node.light?.color = color; node.light?.intensity = intensity
            node.position = position; node.look(at: SCNVector3Zero); scene.rootNode.addChildNode(node)
        }
        light(.ambient, NSColor(calibratedRed: 0.65, green: 0.72, blue: 0.8, alpha: 1), 420, SCNVector3Zero)
        light(.omni, NSColor(calibratedRed: 1, green: 0.8, blue: 0.55, alpha: 1), 650, SCNVector3(-3, 4, 4))
        light(.omni, NSColor(calibratedRed: 0.5, green: 0.7, blue: 0.62, alpha: 1), 380, SCNVector3(3, 2, -2))
        pumpkin.geometry = Self.geometry(); pumpkin.name = "pumpkin"
        skin.diffuse.contents = NSColor(calibratedRed: 0.83, green: 0.25, blue: 0.035, alpha: 1)
        skin.lightingModel = .blinn; skin.shininess = 0.22
        skin.specular.contents = NSColor(calibratedWhite: 0.12, alpha: 1)
        skin.transparencyMode = .aOne; skin.isDoubleSided = true
        pumpkin.geometry?.materials = [skin]; scene.rootNode.addChildNode(pumpkin)
        core.geometry = Self.geometry(scale: 0.91)
        let inside = SCNMaterial(); inside.diffuse.contents = NSColor(calibratedRed: 0.11, green: 0.038, blue: 0.01, alpha: 1); inside.lightingModel = .constant
        core.geometry?.materials = [inside]; scene.rootNode.addChildNode(core)
        let stem = SCNNode(geometry: SCNCylinder(radius: 0.095, height: 0.32)); stem.position = SCNVector3(0.025, 0.87, 0); stem.eulerAngles.z = -0.22
        stem.geometry?.firstMaterial?.diffuse.contents = NSColor(calibratedRed: 0.21, green: 0.25, blue: 0.095, alpha: 1); scene.rootNode.addChildNode(stem)
        let collar = SCNNode(geometry: SCNTorus(ringRadius: 0.12, pipeRadius: 0.035)); collar.position.y = 0.74; collar.geometry?.firstMaterial?.diffuse.contents = NSColor(calibratedRed: 0.28, green: 0.27, blue: 0.075, alpha: 1); scene.rootNode.addChildNode(collar)
        let pedestal = SCNNode(geometry: SCNCylinder(radius: 1.27, height: 0.12)); pedestal.position.y = -0.85
        pedestal.geometry?.firstMaterial?.diffuse.contents = NSColor(calibratedRed: 0.13, green: 0.16, blue: 0.14, alpha: 1); scene.rootNode.addChildNode(pedestal)
        cursor.geometry?.firstMaterial?.diffuse.contents = NSColor.white; cursor.geometry?.firstMaterial?.emission.contents = amber
        cursor.isHidden = true; scene.rootNode.addChildNode(cursor); scene.rootNode.addChildNode(trail)
    }
    func receive(_ tip: Tip?, image: CGImage?, mirrored: Bool, message: String, active: Bool) {
        preview.image = image; preview.tip = tip; preview.mirrored = mirrored
        if !mouseMode { cameraStatus.stringValue = message }
        guard !mouseMode, active else { finishStroke(); cursor.isHidden = true; return }
        guard let tip else { finishStroke(); cursor.isHidden = true; return }
        // Camera coordinates are top-down; SceneKit view coordinates are bottom-up.
        let point = CGPoint(x: (mirrored ? 1 - tip.x : tip.x) * stage.bounds.width, y: (1 - tip.y) * stage.bounds.height)
        sample(point, drawing: carving && !lit)
    }
    func sample(_ point: CGPoint, drawing: Bool) {
        lastInput = Date()
        let hits = stage.hitTest(point, options: [.rootNode: pumpkin, .backFaceCulling: false, .ignoreHiddenNodes: false])
        guard let hit = hits.first(where: { $0.node === pumpkin }) else { finishStroke(); cursor.isHidden = true; return }
        let p = hit.worldCoordinates, n = hit.worldNormal
        trace(hit.textureCoordinates(withMappingChannel: 0), at: SCNVector3(p.x + n.x * 0.025, p.y + n.y * 0.025, p.z + n.z * 0.025), drawing: drawing)
    }
    func trace(_ uv: CGPoint, at position: SCNVector3, drawing: Bool) {
        cursor.isHidden = false; cursor.position = position
        guard drawing else { return }
        if let previous = current.last {
            let distance = hypot(uv.x - previous.x, uv.y - previous.y)
            if distance > 0.085 { finishStroke() } // Never cut across a tracking jump.
            else if distance < 0.0015 { return }
        }
        lastMovement = Date(); current.append(uv)
        let dot = SCNNode(geometry: SCNSphere(radius: 0.012)); dot.position = cursor.position
        dot.geometry?.firstMaterial = cursor.geometry?.firstMaterial; trail.addChildNode(dot)
        if trail.childNodes.count > 160 { trail.childNodes.first?.removeFromParentNode() }
        updateMask(); updateControls()
    }
    func finishStroke() {
        guard !current.isEmpty else { return }
        if current.count > 1 { cuts.strokes.append(current) }
        current = []; trail.childNodes.forEach { $0.removeFromParentNode() }
        updateMask(); updateControls(); persist()
    }
    func updateMask() {
        let size = 1024
        guard let c = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        c.setFillColor(NSColor.white.cgColor); c.fill(CGRect(x: 0, y: 0, width: size, height: size))
        c.setBlendMode(.clear); c.setLineWidth(5); c.setLineCap(.round); c.setLineJoin(.round)
        for stroke in cuts.strokes + [current] where stroke.count > 1 {
            c.beginPath()
            for (i, p) in stroke.enumerated() {
                let q = CGPoint(x: p.x * Double(size), y: (1 - p.y) * Double(size))
                if i == 0 { c.move(to: q) } else { c.addLine(to: q) }
            }
            if PumpkinCuts.isClosed(stroke) { c.closePath(); c.drawPath(using: .fillStroke) } else { c.strokePath() }
        }
        skin.transparent.contents = c.makeImage()
    }
    func updateControls() {
        undoButton?.isEnabled = !cuts.strokes.isEmpty || !current.isEmpty
        carveButton?.title = mouseMode ? "Mouse carving" : (carving ? "Pause carving" : "Start carving")
        carveButton?.isEnabled = !lit && !mouseMode
        lightButton?.title = lit ? "Back to carving" : "Light it up"
        let count = cuts.strokes.filter { PumpkinCuts.isClosed($0) }.count
        countLabel.stringValue = count == 0 ? "YOUR PUMPKIN · MAKE YOUR FIRST MARK" : "YOUR PUMPKIN · \(count) MAGICAL CUTOUT\(count == 1 ? "" : "S")"
        hint.stringValue = lit ? "Your very own jack-o’-lantern. Happy haunting." : (mouseMode ? "Click and drag to carve · release to lift your wand · ⌘Z to undo" : (carving ? "Carving is on · pause to reposition · Space to lift your wand" : "Point your wand, then press Start carving · Space to pause"))
    }
    @objc func toggleCarving() { finishStroke(); carving.toggle(); updateControls() }
    @objc func toggleMouse() { finishStroke(); mouseMode = mouseButton.state == .on; carving = false; cursor.isHidden = true; cameraStatus.stringValue = mouseMode ? "Mouse practice · drag on the pumpkin" : "Point your wand at the camera"; updateControls() }
    @objc func undo() {
        if !current.isEmpty { current = []; trail.childNodes.forEach { $0.removeFromParentNode() } }
        else if !cuts.strokes.isEmpty { cuts.strokes.removeLast() }
        updateMask(); updateControls(); persist()
    }
    @objc func toggleLight() {
        finishStroke(); lit.toggle(); carving = false
        core.geometry?.firstMaterial?.diffuse.contents = lit ? amber : NSColor(calibratedRed: 0.11, green: 0.038, blue: 0.01, alpha: 1)
        core.geometry?.firstMaterial?.emission.contents = lit ? amber : NSColor.black
        updateControls()
    }
    @objc func newPumpkin() {
        finishStroke()
        guard let window = view.window else { return }
        let alert = NSAlert(); alert.messageText = "Start a fresh pumpkin?"; alert.informativeText = "Your current pumpkin will be backed up locally. Save a portrait first if you’d like to keep a picture."
        alert.addButton(withTitle: "New pumpkin"); alert.addButton(withTitle: "Keep carving")
        alert.beginSheetModal(for: window) { [weak self] result in
            guard let self, result == .alertFirstButtonReturn else { return }
            if !self.cuts.strokes.isEmpty {
                let backup = self.saveURL.deletingLastPathComponent().appendingPathComponent("pumpkin-\(Int(Date().timeIntervalSince1970)).json")
                do { try JSONEncoder().encode(self.cuts).write(to: backup, options: .atomic) }
                catch { self.hint.stringValue = "Couldn’t back up your pumpkin. Your carving is still here."; return }
            }
            self.cuts = PumpkinCuts(); self.carving = false
            if self.lit { self.toggleLight() }
            self.updateMask(); self.updateControls(); self.persist()
        }
    }
    func persist() {
        do { try JSONEncoder().encode(cuts).write(to: saveURL, options: .atomic) }
        catch { hint.stringValue = "Couldn’t save your carving. Keep this window open and save a portrait." }
    }
    @objc func savePortrait() {
        finishStroke(); guard let window = view.window else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]; panel.nameFieldStringValue = "my-jack-o-lantern.png"
        cursor.isHidden = true
        let portrait = stage.snapshot()
        panel.beginSheetModal(for: window) { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            do {
                guard let data = portrait.tiffRepresentation, let rep = NSBitmapImageRep(data: data), let png = rep.representation(using: .png, properties: [:]) else { return }
                try png.write(to: url); self?.hint.stringValue = "Portrait saved. A little autumn magic to keep."
            } catch { self?.hint.stringValue = "Couldn’t save the portrait: \(error.localizedDescription)" }
        }
    }
}
