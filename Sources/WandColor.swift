import Cocoa

struct WandColor: Equatable {
    let hex: String
    static let gold = WandColor(hex: "#FFBD52")!

    init?(hex: String) {
        let value = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard value.count == 7, value.first == "#",
              value.dropFirst().allSatisfy({ "0123456789ABCDEF".contains($0) }) else { return nil }
        self.hex = value
    }

    init(color: NSColor) {
        let rgb = color.usingColorSpace(.sRGB) ?? .white
        hex = String(format: "#%02X%02X%02X", Int((rgb.redComponent * 255).rounded()),
                     Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
    }

    var glow: NSColor {
        let value = UInt32(hex.dropFirst(), radix: 16)!
        return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                       green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
    }
    var core: NSColor { glow.blended(withFraction: 0.68, of: .white) ?? .white }
}

// Only completed calls to this narrowly scoped tool can change the canvas.
struct WandColorCommand {
    let callID: String
    let color: WandColor

    init?(item: [String: Any]) {
        guard item["type"] as? String == "function_call", item["name"] as? String == "set_wand_color",
              let id = item["call_id"] as? String, !id.isEmpty,
              let arguments = item["arguments"] as? String, arguments.utf8.count <= 512,
              let data = arguments.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == ["hex"], let hex = object["hex"] as? String,
              let color = WandColor(hex: hex) else { return nil }
        callID = id; self.color = color
    }
}
