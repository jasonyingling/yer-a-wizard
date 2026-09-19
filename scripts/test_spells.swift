import Foundation

@main struct SpellTests {
    static func main() {
        for spell in Spell.allCases {
            let points = SpellRecognizer.resample(spell.points, count: 100)
            let shifted = points.map { CGPoint(x: $0.x * 0.6 + 0.3, y: $0.y * 0.6 + 0.1) }
            let reversed = Array(shifted.reversed())
            for path in [points, shifted, reversed] {
                let match = SpellRecognizer.match(path, spell: spell, coverage: 0.95, longestGap: 0.1)
                precondition(match.accepted, "Valid \(spell.title) rejected: \(match)")
            }
            let jitter = shifted.enumerated().map { i, p in CGPoint(x: p.x + sin(Double(i) * 2) * 0.009, y: p.y + cos(Double(i) * 3) * 0.009) }
            precondition(SpellRecognizer.match(jitter, spell: spell, coverage: 0.8, longestGap: 0.2).accepted, "Small tracking jitter should be tolerated")
            for other in Spell.allCases where other != spell {
                let result = SpellRecognizer.match(SpellRecognizer.resample(other.points, count: 100), spell: spell, coverage: 1, longestGap: 0)
                print("\(other.title) as \(spell.title): \(Int(result.score * 100))% accepted=\(result.accepted)")
                precondition(!result.accepted, "Wrong spell accepted")
            }
            precondition(!SpellRecognizer.match(points, spell: spell, coverage: 0.3, longestGap: 1).accepted)
        }
        let line = (0..<100).map { CGPoint(x: Double($0)/100, y: 0.5) }
        let scribble = (0..<120).map { i in CGPoint(x: sin(Double(i)*1.7)*0.4 + 0.5, y: cos(Double(i)*2.3)*0.4 + 0.5) }
        for spell in Spell.allCases {
            precondition(!SpellRecognizer.match(line, spell: spell, coverage: 1, longestGap: 0).accepted)
            precondition(!SpellRecognizer.match(scribble, spell: spell, coverage: 1, longestGap: 0).accepted)
            precondition(!SpellRecognizer.match([], spell: spell, coverage: 1, longestGap: 0).accepted)
        }
        print("PASS: correct spells, position/scale/direction tolerance, jitter, wrong shapes, scribbles, incomplete input, poor tracking")
    }
}
