import Foundation

@main struct Tests {
    static func main() {
        let width = 100, height = 100
        func scene(_ points: [(Int, Int)], background: UInt8 = 10) -> [UInt8] {
            var data = [UInt8](repeating: background, count: width * height)
            for (cx, cy) in points { for y in cy..<cy+3 { for x in cx..<cx+3 { data[y * width + x] = 255 } } }
            return data
        }
        var tracker = TipTracker()
        let one = scene([(50, 50)])
        for _ in 0..<5 { precondition(tracker.process(one, width: width, height: height).0 == nil, "Unselected bright objects must not draw") }
        tracker.seed(x: 0.51, y: 0.51)
        precondition(tracker.process(one, width: width, height: height).0 == nil)
        precondition(tracker.process(one, width: width, height: height).0 == nil)
        let locked = tracker.process(one, width: width, height: height).0!
        precondition(abs(locked.x - 0.51) < 0.001 && locked.area == 9)
        precondition(tracker.process(scene([(53, 51), (5, 5)]), width: width, height: height).0!.x > 0.5, "Stay with the selected tip")
        precondition(tracker.process(scene([(5, 5)]), width: width, height: height).0 == nil, "Do not jump to a distant reflection")
        precondition(tracker.process(one, width: width, height: height).0 != nil, "Recover immediately from a brief gap")
        let dim = one.map { $0 == 255 ? UInt8(150) : $0 }
        var recovered = false
        for _ in 0..<6 { if tracker.process(dim, width: width, height: height).0 != nil { recovered = true } }
        precondition(recovered, "Follow a dimmer tip near the existing selection")
        for _ in 0..<8 { _ = tracker.process(scene([]), width: width, height: height) }
        precondition(!tracker.locked, "Long gaps release lock")
        precondition(tracker.process(one, width: width, height: height).0 == nil, "Reconfirm after a long gap")
        tracker.reset(); tracker.automaticAcquisition = true
        for _ in 0..<4 { precondition(tracker.process(scene([(10, 10), (60, 60)]), width: width, height: height).0 == nil, "Ambiguous candidates need selection") }
        tracker.seed(x: 0.51, y: 0.51)
        precondition(tracker.process([UInt8](repeating: 255, count: width * height), width: width, height: height).1 == 0, "Reject large bright regions")
        precondition(tracker.process(scene([(50, 50)], background: 240), width: width, height: height).0 == nil)
        precondition(tracker.process([], width: 0, height: 0).0 == nil)
        print("PASS: selection, brief-gap recovery, brightness adaptation, long-gap release, distractor rejection, glare, empty frames")
    }
}
