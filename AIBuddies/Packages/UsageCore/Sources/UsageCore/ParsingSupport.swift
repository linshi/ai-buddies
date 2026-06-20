import Foundation

/// JSON / timestamp parsing helpers shared by the two parsers.
/// Ported from `usage_buddy.py` `parse_ts` and the inline JSON handling.
enum ParsingSupport {

    /// Parse one JSONL line into a dictionary, tolerating malformed lines (returns nil).
    static func jsonObject(_ line: Substring) -> [String: Any]? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// Coerce a JSON value to Int, tolerating NSNumber / String / nil.
    static func int(_ value: Any?) -> Int {
        switch value {
        case let n as Int: return n
        case let n as Double: return Int(n)
        case let n as NSNumber: return n.intValue
        case let s as String: return Int(s) ?? Int(Double(s) ?? 0)
        default: return 0
        }
    }

    /// Coerce a JSON value to Double?, tolerating NSNumber / String / nil.
    static func double(_ value: Any?) -> Double? {
        switch value {
        case let n as Double: return n
        case let n as Int: return Double(n)
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }

    private static let isoFormatters: [ISO8601DateFormatter] = {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return [withFraction, plain]
    }()

    /// Parse various timestamp shapes into a Date. Ported from `parse_ts`.
    /// Accepts ISO-8601 strings (with/without fractional seconds, "Z" or offset)
    /// and numeric epoch seconds/milliseconds.
    static func parseTimestamp(_ value: Any?) -> Date? {
        switch value {
        case let n as NSNumber:
            var v = n.doubleValue
            if v > 1e12 { v /= 1000.0 }   // milliseconds → seconds
            return Date(timeIntervalSince1970: v)
        case let s as String:
            let str = s.trimmingCharacters(in: .whitespaces)
            for f in isoFormatters {
                if let d = f.date(from: str) { return d }
            }
            // Fallback: epoch in a string.
            if let v = Double(str) {
                return Date(timeIntervalSince1970: v > 1e12 ? v / 1000.0 : v)
            }
            return nil
        default:
            return nil
        }
    }
}
