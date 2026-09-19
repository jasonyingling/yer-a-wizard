import Foundation
@main struct GestureTests {
    static func main() {
        var capture = GestureCapture()
        let points = SpellRecognizer.resample(Spell.lumos.points, count: 80)
        for (i, point) in points.enumerated() { _ = capture.observe(point, at: Double(i) * 0.03) }
        precondition(capture.finishIfIdle(at: 3) == nil)
        for i in 0..<20 { _ = capture.observe(CGPoint(x: points.last!.x + 0.002, y: points.last!.y), at: 2.4 + Double(i) * 0.06) }
        let first = capture.finishIfIdle(at: 3.7)!
        precondition(SpellRecognizer.match(first.points, spell: .lumos, coverage: 1, longestGap: first.gap).accepted)
        precondition(capture.finishIfIdle(at: 5) == nil, "Never cast twice for one gesture")
        _ = capture.observe(points.last!, at: 5)
        precondition(capture.points.isEmpty, "Resting tip must not start another gesture")
        for (i, point) in points.reversed().enumerated() { _ = capture.observe(point, at: 6 + Double(i) * 0.03) }
        _ = capture.observe(nil, at: 8.4)
        let second = capture.finishIfIdle(at: 9.7)!
        precondition(second.gap == 0, "Trailing tip loss should finish the gesture")
        precondition(SpellRecognizer.match(second.points, spell: .lumos, coverage: 1, longestGap: second.gap).accepted)
        let shifted = points.map { CGPoint(x: $0.x * 0.6 + 0.4, y: $0.y * 0.6 + 0.3) }
        for (i, point) in shifted.enumerated() { _ = capture.observe(point, at: 10 + Double(i) * 0.003) }
        let relocated = capture.finishIfIdle(at: 11.5)!
        precondition(SpellRecognizer.match(relocated.points, spell: .lumos, coverage: 1, longestGap: relocated.gap).accepted, "Previous endpoint must not contaminate the next shape")
        _ = capture.observe(CGPoint(x: 0.2, y: 0.2), at: 12)
        _ = capture.observe(nil, at: 12.1)
        _ = capture.observe(CGPoint(x: 0.4, y: 0.4), at: 13)
        precondition(capture.longestGap > 0.7, "Internal tracking interruption must remain visible")
        print("PASS: pause detection, jitter tolerance, repeated casting, no duplicate cast, trailing loss, internal gap")
    }
}
