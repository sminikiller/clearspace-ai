import Foundation

/// Formattazione uniforme di dimensioni, date e durate.
enum Format {

    private static let italian = Locale(identifier: "it_IT")

    /// Unità decimali, come nelle Impostazioni di iOS: 1 MB = 1.000.000 byte.
    private static let byteUnits = ["KB", "MB", "GB", "TB"]

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

    /// "18,4 GB", con le convenzioni italiane qualunque sia la lingua del dispositivo
    /// (`ByteCountFormatter` seguirebbe quella del dispositivo e scriverebbe "18.4 GB").
    /// Per valori nulli o negativi restituisce "0 KB"; una dimensione non nulla non diventa mai "0 KB".
    static func bytes(_ value: Int64?) -> String {
        let safe = max(0, value ?? 0)
        if safe == 0 { return "0 KB" }
        var amount = Double(safe) / 1_000
        var unit = 0
        // 999,5 e oltre verrebbe arrotondato a 1000: meglio passare all'unità successiva.
        while amount >= 999.5 && unit < byteUnits.count - 1 {
            amount /= 1_000
            unit += 1
        }
        let digits: Int
        switch unit {
        case 0: digits = 0                      // 512 KB
        case 1: digits = 1                      // 2,8 MB
        case 2: digits = amount < 10 ? 2 : 1    // 1,25 GB · 46,3 GB
        default: digits = 2                     // 1,05 TB
        }
        if digits == 0 { amount = max(1, amount) }
        return "\(decimal(amount, maximumFractionDigits: digits)) \(byteUnits[unit])"
    }

    /// Numero con la virgola decimale e senza zeri finali: 2.80 → "2,8", 5.0 → "5".
    static func decimal(_ value: Double, maximumFractionDigits digits: Int) -> String {
        var text = String(format: "%.\(max(0, digits))f", locale: italian, value)
        if digits > 0 {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(",") { text.removeLast() }
        }
        return text
    }

    /// Come `bytes`, ma mostra "—" quando la dimensione non è nota.
    static func bytesOrUnknown(_ value: Int64?) -> String {
        guard let value else { return "—" }
        return bytes(value)
    }

    /// Per i valori in evidenza: "296,4 GB". Sotto 1 GB usa l'unità più adatta ("12,9 MB")
    /// invece di mostrare "0,0 GB".
    static func gigabytes(_ value: Int64) -> String {
        guard value >= AppConfiguration.Thresholds.gigabyte else { return bytes(value) }
        let gb = Double(value) / Double(AppConfiguration.Thresholds.gigabyte)
        return "\(decimal(gb, maximumFractionDigits: 1)) GB"
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
        return "\(width) × \(height) (\(decimal(megapixel, maximumFractionDigits: 1)) MP)"
    }
}
