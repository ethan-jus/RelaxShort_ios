import Foundation

// MARK: - RankingEntry (Task30 R4B-1)

struct RankingEntry: Identifiable, Sendable {
    let rankPosition: Int
    let metricType: String
    let metricValue: Int64
    let drama: DramaItem
    var id: String { "\(rankPosition):\(drama.id)" }
}

enum RankingMetricFormatter {
    static func string(from value: Int64) -> String {
        if value < 1_000 { return "\(value)" }
        else if value < 1_000_000 {
            let k = Double(value) / 1_000.0
            return String(format: k == floor(k) ? "%.0fK" : "%.1fK", k)
        } else {
            let m = Double(value) / 1_000_000.0
            return String(format: m == floor(m) ? "%.0fM" : "%.1fM", m)
        }
    }
}
