import Foundation
import Observation

/// Starred on-demand shows, persisted to UserDefaults and observed by the
/// sidebar, the browse list and the show view.
@Observable
@MainActor
public final class Favorites {
    public static let shared = Favorites()

    private static let key = "kvf.favorites"

    public private(set) var shows: [Show] = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let stored = try? JSONDecoder().decode([Show].self, from: data) {
            shows = stored
        }
    }

    public func contains(_ show: Show) -> Bool { shows.contains(show) }

    public func toggle(_ show: Show) {
        if let index = shows.firstIndex(of: show) {
            shows.remove(at: index)
        } else {
            shows.append(show)
        }
        UserDefaults.standard.set(try? JSONEncoder().encode(shows), forKey: Self.key)
    }
}

// MARK: - Faroese dates

// Hand-rolled: the guide needs Faroese weekday/month names and we don't want to
// depend on the "fo" locale being present in whatever macOS the user runs.
private let weekdays = [
    "sunnudagur", "mánadagur", "týsdagur", "mikudagur", "hósdagur", "fríggjadagur", "laturdagur",
]
private let months = [
    "januar", "februar", "mars", "apríl", "mai", "juni",
    "juli", "august", "september", "oktober", "november", "desember",
]

private let isoFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
}()

/// "YYYY-MM-DD" for today.
public func todayDateString() -> String { isoFormatter.string(from: Date()) }

public func addDays(_ days: Int, to dateString: String) -> String {
    guard let date = isoFormatter.date(from: dateString),
          let moved = Calendar.current.date(byAdding: .day, value: days, to: date)
    else { return dateString }
    return isoFormatter.string(from: moved)
}

/// "mánadagur 18. august" — the guide's day header.
public func formatGuideDate(_ dateString: String) -> String {
    guard let date = isoFormatter.date(from: dateString) else { return dateString }
    let parts = Calendar.current.dateComponents([.weekday, .day, .month], from: date)
    guard let weekday = parts.weekday, let day = parts.day, let month = parts.month else { return dateString }
    return "\(weekdays[weekday - 1]) \(day). \(months[month - 1])"
}

/// "1:02:03" / "4:07" — episode durations.
public func formatDuration(_ seconds: Int) -> String {
    guard seconds > 0 else { return "" }
    let (hours, minutes, secs) = (seconds / 3600, (seconds % 3600) / 60, seconds % 60)
    return hours > 0
        ? String(format: "%d:%02d:%02d", hours, minutes, secs)
        : String(format: "%d:%02d", minutes, secs)
}
