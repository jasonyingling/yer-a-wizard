import Foundation
import ImageIO
import CoreGraphics

@main struct FrameCheck {
    static func main() {
        guard CommandLine.arguments.count > 1,
              let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("Pass a camera PNG") }
        let w = image.width / 2, h = image.height / 2
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        rgba.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            // CGImage rows are copied in their native order.
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        let gray: [UInt8] = (0..<w*h).map { i in
            let r = Int(rgba[i*4]) * 77, g = Int(rgba[i*4+1]) * 150, b = Int(rgba[i*4+2]) * 29
            return UInt8((r + g + b) >> 8)
        }
        let sorted = gray.sorted()
        print("Frame \(image.width)x\(image.height); median \(sorted[sorted.count/2]); p99 \(sorted[sorted.count*99/100]); peak \(sorted.last!)")
        for threshold in [190, 170, 150] {
            for maximum in [109, 200, 600] {
                var tracker = TipTracker()
                tracker.settings.threshold = threshold; tracker.settings.maximumArea = maximum
                tracker.seed(x: 0.667, y: 0.656)
                var result: (Tip?, Int) = (nil, 0)
                for _ in 0..<3 { result = tracker.process(gray, width: w, height: h) }
                print("Threshold \(threshold), max area \(maximum): \(result)")
            }
        }
    }
}
