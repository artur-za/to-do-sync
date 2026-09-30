import Foundation

public struct ParsedTitle: Sendable {
    public var title: String
    public var date: Date?
    public var reminder: Date?
    public var listID: UUID?
}

public enum TitleParser {
    /// Local deterministic parsing. No requests or task text leave the Mac.
    public static func parse(_ input: String, lists: [TaskList], now: Date = Date(), calendar: Calendar = .current) -> ParsedTitle {
        var result = ParsedTitle(title: input)
        var text = input
        for list in lists.sorted(by: { $0.name.count > $1.name.count }) where !list.name.isEmpty {
            let pattern = "(?i)(?<![\\p{L}\\p{N}_])#" + NSRegularExpression.escapedPattern(for: list.name) + "(?![\\p{L}\\p{N}_])"
            if let range = text.range(of: pattern, options: .regularExpression) {
                result.listID = list.id; text.removeSubrange(range); break
            }
        }
        let keywords = [("tomorrow|завтра|明天", 1), ("today|сегодня|今天", 0)]
        for (keyword, offset) in keywords {
            if let range = text.range(of: "(?i)(?<![\\p{L}])(?:\(keyword))(?![\\p{L}])", options: .regularExpression) {
                result.date = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))
                text.removeSubrange(range); break
            }
        }
        let pattern = "(?i)(?<![\\p{L}\\p{N}])(?:(?:at|в)\\s+)?(\\d{1,2})(?::(\\d{2}))?\\s*(am|pm)(?![\\p{L}])|(?<![\\p{L}\\p{N}])(?:(?:at|в)\\s+)?(\\d{1,2}):(\\d{2})(?!\\d)"
        if let regex = try? NSRegularExpression(pattern: pattern), let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            let ns = text as NSString
            func capture(_ n: Int) -> String? { m.range(at: n).location == NSNotFound ? nil : ns.substring(with: m.range(at: n)) }
            var hour = Int(capture(1) ?? capture(4) ?? "") ?? -1
            let minute = Int(capture(2) ?? capture(5) ?? "0") ?? -1
            let suffix = capture(3)?.lowercased()
            let valid = (suffix == nil ? (0...23).contains(hour) : (1...12).contains(hour)) && (0...59).contains(minute)
            if valid {
                if suffix != nil { hour = hour % 12 + (suffix == "pm" ? 12 : 0) }
                let day = result.date ?? calendar.startOfDay(for: now)
                result.date = day; result.reminder = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
                if let range = Range(m.range, in: text) { text.removeSubrange(range) }
            }
        }
        result.title = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        if result.title.isEmpty { result.title = input }
        return result
    }
}
