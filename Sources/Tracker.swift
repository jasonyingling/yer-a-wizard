import Foundation

struct Tip: Codable {
    var x: Double
    var y: Double
    var area: Int
    var peak: Int
    var contrast: Double
}

struct TrackerSettings {
    var threshold = 170
    var minimumArea = 2
    var maximumArea = 600
    var minimumContrast = 25.0
}

/// Compact bright components, local contrast rejection, and temporal continuity.
/// Coordinates are normalized with the origin at the upper left of the image.
struct TipTracker {
    var settings = TrackerSettings()
    var anchor: Tip?
    var misses = 0
    var hits = 0
    var locked = false
    var automaticAcquisition = false
    var velocityX = 0.0
    var velocityY = 0.0
    var message = "Click the bright wand tip"
    var backgroundLevel = 0
    var brightPercent = 0.0
    var localThreshold = 170

    mutating func seed(x: Double, y: Double) {
        anchor = Tip(x: x, y: y, area: 0, peak: 0, contrast: 0)
        misses = 0
        hits = 0
        locked = false
        automaticAcquisition = false
        velocityX = 0; velocityY = 0
    }

    mutating func reset() { anchor = nil; misses = 0; hits = 0; locked = false; automaticAcquisition = false; velocityX = 0; velocityY = 0; message = "Click the bright wand tip" }

    mutating func process(_ gray: [UInt8], width: Int, height: Int) -> (Tip?, Int) {
        guard width > 0, height > 0, gray.count == width * height else { reset(); return (nil, 0) }
        var visited = [Bool](repeating: false, count: gray.count)
        var candidates: [Tip] = []
        let previous = anchor
        let radius = min(0.22, 0.10 + Double(misses) * 0.004)
        let px = (previous?.x ?? 0) + velocityX * Double(min(misses + 1, 4))
        let py = (previous?.y ?? 0) + velocityY * Double(min(misses + 1, 4))
        localThreshold = previous.map { $0.peak > 0 ? max(85, min(settings.threshold, Int(Double($0.peak) * (0.68 - Double(min(misses, 5)) * 0.04)))) : max(85, settings.threshold - 35) } ?? settings.threshold
        var thresholds = [Int](repeating: settings.threshold, count: gray.count)
        if previous != nil {
            let left = max(0, Int((px - radius) * Double(width))), right = min(width - 1, Int((px + radius) * Double(width)))
            let top = max(0, Int((py - radius) * Double(height))), bottom = min(height - 1, Int((py + radius) * Double(height)))
            if left <= right && top <= bottom {
                for y in top...bottom { for x in left...right { thresholds[y * width + x] = localThreshold } }
            }
        }
        var total = 0, samples = 0, bright = 0, tooLarge = 0
        for i in stride(from: 0, to: gray.count, by: 16) { total += Int(gray[i]); samples += 1; if gray[i] >= 170 { bright += 1 } }
        backgroundLevel = total / max(1, samples)
        brightPercent = Double(bright) * 100 / Double(max(1, samples))
        for start in gray.indices where !visited[start] && Int(gray[start]) >= thresholds[start] {
            var queue = [start]
            visited[start] = true
            var head = 0, sumX = 0, sumY = 0, peak = 0
            var minX = width, maxX = 0, minY = height, maxY = 0
            while head < queue.count {
                let index = queue[head]; head += 1
                let x = index % width, y = index / width
                sumX += x; sumY += y; peak = max(peak, Int(gray[index]))
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
                for dy in -1...1 {
                    for dx in -1...1 where dx != 0 || dy != 0 {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                        let neighbor = ny * width + nx
                        if !visited[neighbor] && Int(gray[neighbor]) >= thresholds[neighbor] {
                            visited[neighbor] = true; queue.append(neighbor)
                        }
                    }
                }
            }
            let area = queue.count
            let maxArea = previous.map { max(settings.maximumArea, min(2400, $0.area * 4)) } ?? settings.maximumArea
            if area > maxArea { tooLarge += 1; continue }
            guard area >= settings.minimumArea else { continue }
            let bw = maxX - minX + 1, bh = maxY - minY + 1
            guard Double(max(bw, bh)) / Double(min(bw, bh)) < 6,
                  Double(area) / Double(bw * bh) > 0.25 else { continue }
            var surround = 0, count = 0
            for y in max(0, minY - 4)...min(height - 1, maxY + 4) {
                for x in max(0, minX - 4)...min(width - 1, maxX + 4) {
                    if x < minX || x > maxX || y < minY || y > maxY {
                        surround += Int(gray[y * width + x]); count += 1
                    }
                }
            }
            let contrast = Double(peak) - Double(surround) / Double(max(1, count))
            guard contrast >= settings.minimumContrast else { continue }
            candidates.append(Tip(x: Double(sumX) / Double(area * width), y: Double(sumY) / Double(area * height), area: area, peak: peak, contrast: contrast))
        }
        let selected: Tip?
        if let previous {
            func cost(_ tip: Tip) -> Double {
                let sizePenalty = previous.area > 0 ? min(0.06, abs(log(Double(tip.area) / Double(previous.area))) * 0.018) : 0
                return hypot(tip.x - px, tip.y - py) + sizePenalty
            }
            selected = candidates.filter { hypot($0.x - px, $0.y - py) < radius }
                .min { cost($0) < cost($1) }
        } else {
            // Multiple bright objects require the user to select the wand tip.
            selected = automaticAcquisition && candidates.count == 1 ? candidates.first : nil
        }
        guard let tip = selected else {
            misses += 1
            if misses > 6 { hits = 0; locked = false; velocityX *= 0.5; velocityY *= 0.5 }
            if misses > 90 { anchor = nil }
            message = anchor != nil ? (misses <= 6 ? "Brief gap — holding selection" : "Tip lost — face the lens or click to reselect") : "Click the bright wand tip"
            if brightPercent > 8 { message += " · bright background" }
            else if tooLarge > 0 && candidates.isEmpty { message += " · bright blob too large" }
            return (nil, candidates.count)
        }
        if let previous, previous.area > 0 {
            velocityX = velocityX * 0.4 + (tip.x - previous.x) / Double(misses + 1) * 0.6
            velocityY = velocityY * 0.4 + (tip.y - previous.y) / Double(misses + 1) * 0.6
        }
        anchor = tip; misses = 0; hits += 1; locked = locked || hits >= 3
        if locked { automaticAcquisition = false }
        message = locked ? "Tip locked" : "Acquiring tip…"
        return (locked ? tip : nil, candidates.count)
    }
}
