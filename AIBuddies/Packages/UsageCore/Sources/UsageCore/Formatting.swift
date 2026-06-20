import Foundation

/// Display formatting helpers. Ported from `usage_buddy.py` `fmt_usd` / `human_duration`.
public enum Formatting {

    private static let usd: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US_POSIX")
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.groupingSeparator = ","
        f.usesGroupingSeparator = true
        return f
    }()

    public static func usd(_ x: Double) -> String {
        "$" + (usd.string(from: NSNumber(value: x)) ?? String(format: "%.2f", x))
    }

    /// Human duration in Chinese, e.g. "1小时5分", "12分", "现在", "?".
    public static func humanDuration(_ seconds: Double?) -> String {
        guard let seconds else { return "?" }
        let s = Int(seconds)
        if s <= 0 { return "现在" }
        let h = s / 3600
        let m = (s % 3600) / 60
        if h > 0 { return "\(h)小时\(m)分" }
        return "\(m)分"
    }
}
