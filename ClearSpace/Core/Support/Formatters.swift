import Foundation

/// Formattazione uniforme di dimensioni, date e durate.
enum Format {

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return formatter
    }()

    private static let mediumDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let monthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }()

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    /// "18,4 GB". Per valori nulli o negativi restituisce "0 KB".
    static func bytes(_ value: Int64?) -> String {
        let safe = max(0, value ?? 0)
        if safe == 0 { return "0 KB" }
        return byteFormatter.string(fromByteCount: safe)
    }

    /// Come `bytes`, ma mostra "—" quando la dimensione non è nota.
    static func bytesOrUnknown(_ value: Int64?) -> String {
        guard let value else { return "—" }
        return bytes(value)
    }

    static func gigabytes(_ value: Int64) -> String {
        let gb = Double(value) / Double(AppConfiguration.Thresholds.gigabyte)
        return String(format: "%.1f GB", locale: Locale(identifier: "it_IT"), gb)
    }

    static func date(_ date: Date?) -> String {
        guard let date else { return "Data sconosciuta" }
        return mediumDateFormatter.string(from: date)
    }

    static func dateTime(_ date: Date?) -> String {
        guard let date else { return "Data sconosciuta" }
        return dateTimeFormatter.string(from: date)
    }

    static func monthYear(_ date: Date) -> String {
        monthYearFormatter.string(from: date).capitalized
    }

    /// "1:23" oppure "1:02:03".
    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    static func count(_ value: Int) -> String {
        numberFormatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// Singolare o plurale italiano: `plural(1, "elemento", "elementi")` → "1 elemento".
    static func plural(_ value: Int, _ singular: String, _ plural: String) -> String {
        "\(count(value)) \(value == 1 ? singular : plural)"
    }

    static func percent(_ fraction: Double) -> String {
        let clamped = min(max(fraction, 0), 1)
        return "\(Int((clamped * 100).rounded()))%"
    }

    static func megapixels(width: Int, height: Int) -> String {
        guard width > 0, height > 0 else { return "—" }
        let megapixel = Double(width * height) / 1_000_000
        return "\(width) × \(height) (\(String(format: "%.1f", megapixel)) MP)"
    }
}
