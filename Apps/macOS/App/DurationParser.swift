import Foundation

/// What someone types into the countdown field (feedback round 2): "45" is minutes; "45:30" and "1:05:00" are
/// minutes:seconds and hours:minutes:seconds; "90m", "1h", "1h30", "1h 30m", "1.5h" and "30s" use units.
enum DurationParser {
    static func seconds(from text: String) -> TimeInterval? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false).map { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard (2...3).contains(parts.count), parts.allSatisfy({ ($0 ?? -1) >= 0 }) else { return nil }
            let values = parts.map { $0! }
            let total = parts.count == 2 ? values[0] * 60 + values[1] : values[0] * 3600 + values[1] * 60 + values[2]
            return total > 0 ? TimeInterval(total) : nil
        }
        if let minutes = Double(trimmed) {
            return minutes > 0 ? minutes * 60 : nil
        }
        // Unit form. A bare number after a unit takes the next smaller unit: "1h30" is 1 h 30 min.
        let scanner = Scanner(string: trimmed)
        scanner.charactersToBeSkipped = .whitespaces
        var total: Double = 0
        var lastUnit: Character? = nil
        while !scanner.isAtEnd {
            guard let value = scanner.scanDouble(), value >= 0 else { return nil }
            if let unit = scanner.scanCharacter() {
                switch unit {
                case "h": total += value * 3600
                case "m": total += value * 60
                case "s": total += value
                default: return nil
                }
                lastUnit = unit
            } else {
                switch lastUnit {
                case "h": total += value * 60
                case "m": total += value
                default: return nil
                }
                lastUnit = nil
            }
        }
        return total > 0 ? total : nil
    }
}
