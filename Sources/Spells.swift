import Foundation

enum Spell: Int, CaseIterable {
    case kindle, ward, spark, lumos, nox, leviosa
    var title: String { ["Kindle", "Ward", "Spark", "Lumos", "Nox", "Wingardium Leviosa"][rawValue] }
    var instruction: String { ["Draw one circle to light the lantern.", "Draw one triangle to raise a shield.", "Draw a lightning bolt to shatter the crystal.", "Sweep up to a peak, then down to bring light.", "Sweep an arch, then curl inward to extinguish the light.", "Sweep down and up, then pull straight down to lift the feather."][rawValue] }
    var success: String { ["Lantern lit!", "Shield raised!", "Crystal shattered!", "Lumos! Let there be light.", "Nox! Light extinguished.", "Wingardium Leviosa! Feather lifted."][rawValue] }
    var closed: Bool { self == .kindle || self == .ward }
    var points: [CGPoint] {
        switch self {
        case .lumos: return [CGPoint(x: 0.15, y: 0.9), CGPoint(x: 0.5, y: 0.1), CGPoint(x: 0.85, y: 0.9)]
        case .nox: return Self.curve(CGPoint(x: 0.08, y: 0.8), CGPoint(x: 0.3, y: 0.06), CGPoint(x: 0.65, y: 0.05), CGPoint(x: 0.9, y: 0.3)) + Self.curve(CGPoint(x: 0.9, y: 0.3), CGPoint(x: 0.25, y: 0.25), CGPoint(x: 0.4, y: 0.95), CGPoint(x: 0.98, y: 0.75)).dropFirst()
        case .leviosa: return Self.curve(CGPoint(x: 0.08, y: 0.1), CGPoint(x: 0.13, y: 0.95), CGPoint(x: 0.85, y: 0.95), CGPoint(x: 0.92, y: 0.1)) + [CGPoint(x: 0.92, y: 0.95)]
        case .kindle: return (0...64).map { n in let a = Double(n) / 64 * .pi * 2 - .pi / 2; return CGPoint(x: cos(a) * 0.42 + 0.5, y: sin(a) * 0.42 + 0.5) }
        case .ward: return [CGPoint(x: 0.5, y: 0.05), CGPoint(x: 0.95, y: 0.9), CGPoint(x: 0.05, y: 0.9), CGPoint(x: 0.5, y: 0.05)]
        case .spark: return [CGPoint(x: 0.65, y: 0.05), CGPoint(x: 0.22, y: 0.52), CGPoint(x: 0.78, y: 0.48), CGPoint(x: 0.35, y: 0.95)]
        }
    }
    static func curve(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> [CGPoint] {
        (0...32).map { i in
            let t = Double(i) / 32, u = 1 - t
            return CGPoint(x: u*u*u*a.x + 3*u*u*t*b.x + 3*u*t*t*c.x + t*t*t*d.x,
                           y: u*u*u*a.y + 3*u*u*t*b.y + 3*u*t*t*c.y + t*t*t*d.y)
        }
    }
}

struct SpellMatch {
    var score: Double
    var accepted: Bool
    var feedback: String
}

enum SpellRecognizer {
    static func distance(_ a: CGPoint, _ b: CGPoint) -> Double { hypot(a.x - b.x, a.y - b.y) }
    static func resample(_ input: [CGPoint], count: Int = 64) -> [CGPoint] {
        guard input.count >= 2 else { return [] }
        var cumulative = [0.0]
        for i in 1..<input.count { cumulative.append(cumulative.last! + distance(input[i - 1], input[i])) }
        guard let total = cumulative.last, total > 0.0001 else { return [] }
        var result: [CGPoint] = [], segment = 1
        for n in 0..<count {
            let target = total * Double(n) / Double(count - 1)
            while segment < input.count - 1 && cumulative[segment] < target { segment += 1 }
            let length = cumulative[segment] - cumulative[segment - 1]
            let t = length > 0 ? (target - cumulative[segment - 1]) / length : 0
            let a = input[segment - 1], b = input[segment]
            result.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
        }
        return result
    }
    static func normalize(_ input: [CGPoint]) -> [CGPoint] {
        guard let minX = input.map(\.x).min(), let maxX = input.map(\.x).max(), let minY = input.map(\.y).min(), let maxY = input.map(\.y).max() else { return [] }
        let scale = max(maxX - minX, maxY - minY)
        guard scale > 0.0001 else { return [] }
        return input.map { CGPoint(x: ($0.x - (minX + maxX) / 2) / scale, y: ($0.y - (minY + maxY) / 2) / scale) }
    }
    static func match(_ input: [CGPoint], spell: Spell, coverage: Double, longestGap: Double) -> SpellMatch {
        guard coverage >= 0.55, longestGap <= 0.7 else { return SpellMatch(score: 0, accepted: false, feedback: "Tracking interrupted. Keep the tip facing the lens and try again.") }
        let clean = input.reduce(into: [CGPoint]()) { out, point in if out.last.map({ distance($0, point) > 0.003 }) ?? true { out.append(point) } }
        guard clean.count >= 8 else { return SpellMatch(score: 0, accepted: false, feedback: "Draw a complete pattern before casting.") }
        let minX = clean.map(\.x).min()!, maxX = clean.map(\.x).max()!, minY = clean.map(\.y).min()!, maxY = clean.map(\.y).max()!
        guard max(maxX - minX, maxY - minY) >= 0.12 else { return SpellMatch(score: 0, accepted: false, feedback: "Make the pattern bigger.") }
        let path = normalize(resample(clean))
        let template = normalize(resample(spell.points))
        guard path.count == 64, template.count == 64 else { return SpellMatch(score: 0, accepted: false, feedback: "Try a complete pattern.") }
        var best = Double.infinity
        for reverse in [false, true] {
            let candidate = reverse ? Array(path.reversed()) : path
            for shift in 0..<(spell.closed ? 64 : 1) {
                let error = (0..<64).reduce(0.0) { $0 + distance(candidate[($1 + shift) % 64], template[$1]) } / 64
                best = min(best, error)
            }
        }
        let closure = distance(clean.first!, clean.last!) / max(maxX - minX, maxY - minY)
        let score = max(0, min(1, 1 - best / 0.55))
        let accepted = score >= 0.76 && (!spell.closed || closure < 0.35)
        return SpellMatch(score: score, accepted: accepted, feedback: accepted ? spell.success : (spell.closed && closure >= 0.35 ? "Close the shape by returning to its start." : "Follow the guide: \(spell.instruction)"))
    }
}

/// Ends gestures on stillness or loss of the tip, without counting a trailing
/// disappearance as an interruption inside the shape. Times are injectable.
struct GestureCapture {
    var points: [CGPoint] = []
    var anchor: CGPoint?
    var lastMovement = 0.0
    var missingSince: Double?
    var longestGap = 0.0
    let pause = 1.2

    mutating func observe(_ point: CGPoint?, at time: Double) -> Bool {
        guard let point else {
            if !points.isEmpty && missingSince == nil { missingSince = time }
            return false
        }
        if let missingSince, !points.isEmpty { longestGap = max(longestGap, time - missingSince) }
        missingSince = nil
        guard anchor.map({ SpellRecognizer.distance($0, point) >= 0.012 }) ?? true else { return false }
        let started = points.isEmpty
        points.append(point); anchor = point; lastMovement = time
        return started
    }
    mutating func finishIfIdle(at time: Double) -> (points: [CGPoint], gap: Double)? {
        guard !points.isEmpty, time - lastMovement >= pause else { return nil }
        let result = (points, longestGap)
        points = []; missingSince = nil; longestGap = 0
        return result
    }
}
