import Cocoa
import SceneKit

@main struct PumpkinTests {
    static func main() throws {
        _ = NSApplication.shared
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pumpkin-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let game = PumpkinGameController(saveURL: url)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 820), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = game
        game.view.layoutSubtreeIfNeeded()
        let geometry = PumpkinGameController.geometry()
        precondition(geometry.sources(for: .vertex).first!.vectorCount == 81 * 161)
        precondition(geometry.sources(for: .texcoord).first!.vectorCount == 81 * 161)
        precondition(geometry.elements.first!.primitiveCount == 80 * 160 * 2)
        let loop = (0...40).map { i in
            let angle = Double(i) / 40 * .pi * 2
            return CGPoint(x: 0.25 + cos(angle) * 0.025, y: 0.45 + sin(angle) * 0.05)
        }
        precondition(PumpkinCuts.isClosed(loop))
        precondition(!PumpkinCuts.isClosed(Array(loop.prefix(20))))
        precondition(!PumpkinCuts.isClosed(Array(repeating: CGPoint(x: 0.25, y: 0.45), count: 30)))
        game.current = loop; game.finishStroke()
        precondition(game.cuts.strokes.count == 1)
        let image = game.skin.transparent.contents as! CGImage
        let rep = NSBitmapImageRep(cgImage: image)
        precondition(rep.colorAt(x: 256, y: 461)!.alphaComponent < 0.1, "Closed loops must remove the inside of the mask at the matching UV coordinate")
        precondition(rep.colorAt(x: 500, y: 461)!.alphaComponent > 0.9, "Uncarved skin must stay opaque")
        let restored = PumpkinGameController(saveURL: url)
        precondition(restored.cuts.strokes == game.cuts.strokes, "Carvings must survive reload")
        game.toggleLight(); precondition(game.lit && !game.carving)
        game.toggleLight(); precondition(!game.lit)
        game.undo(); precondition(game.cuts.strokes.isEmpty)
        // A large jump must finish the old stroke, never bridge it to the next sample.
        game.current = [CGPoint(x: 0.1, y: 0.2), CGPoint(x: 0.11, y: 0.21)]
        game.trace(CGPoint(x: 0.25, y: 0.5), at: SCNVector3(0, 0, 1), drawing: true)
        precondition(game.cuts.strokes.count == 1 && game.current.count == 1)
        game.receive(nil, image: nil, mirrored: true, message: "Lost tip", active: true)
        precondition(game.current.isEmpty && game.cursor.isHidden)
        print("PASS: mesh topology, closed cutouts, opaque skin, persistence, lantern, undo, jump rejection, tracking loss")
    }
}
