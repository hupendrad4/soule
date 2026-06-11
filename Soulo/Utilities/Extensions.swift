import Foundation
import SwiftUI

// MARK: - Date Extensions

extension Date {
    var relative: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    var entryDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }

    var entryTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: self)
    }

    var dayOfWeek: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: self)
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }

    var isYesterday: Bool {
        Calendar.current.isDateInYesterday(self)
    }

    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    func daysSince(_ other: Date) -> Int {
        Calendar.current.dateComponents([.day], from: other, to: self).day ?? 0
    }

    var hourValue: Int {
        Calendar.current.component(.hour, from: self)
    }
}

// MARK: - Color Extensions

extension Color {
    static let accentVoice = Color(red: 0.4, green: 0.6, blue: 1.0)
    static let accentWarm = Color(red: 1.0, green: 0.6, blue: 0.4)
    static let surfacePrimary = Color(.systemBackground)
    static let surfaceSecondary = Color(.secondarySystemBackground)
    static let textPrimary = Color(.label)
    static let textSecondary = Color(.secondaryLabel)
    static let positive = Color.green
    static let negative = Color.red
    static let warning = Color.orange
    static let calm = Color(red: 0.5, green: 0.8, blue: 0.7)

    static let sentimentColors: [Color] = [
        .red, .orange, .yellow, Color(red: 0.6, green: 0.8, blue: 0.4), .green
    ]
}

// MARK: - View Extensions

extension View {
    func cardStyle() -> some View {
        self
            .padding()
            .background(Color.surfaceSecondary)
            .cornerRadius(14)
    }

    func insetGroupedStyle() -> some View {
        self
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(Color.surfaceSecondary)
            .cornerRadius(12)
    }
}

// MARK: - String Extensions

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    var wordCount: Int {
        split(separator: " ").filter { !$0.isEmpty }.count
    }

    var isEmptyOrWhitespace: Bool {
        trimmed.isEmpty
    }

    func containsAny(of phrases: [String]) -> Bool {
        let lower = lowercased()
        return phrases.contains { lower.contains($0.lowercased()) }
    }

    func similarity(to other: String) -> Double {
        let words1 = Set(lowercased().split(separator: " ").map(String.init))
        let words2 = Set(other.lowercased().split(separator: " ").map(String.init))
        let intersection = words1.intersection(words2)
        let union = words1.union(words2)
        guard !union.isEmpty else { return 0 }
        return Double(intersection.count) / Double(union.count)
    }
}

// MARK: - Double Extensions

extension Double {
    var formattedMinutes: String {
        let minutes = Int(self) / 60
        let seconds = Int(self) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var percentage: String {
        "\(Int(self * 100))%"
    }

    func rounded(to places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}

// MARK: - Int Extensions

extension Int {
    var ordinal: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }

    func nonZero(default defaultValue: Int) -> Int {
        self == 0 ? defaultValue : self
    }
}

extension Bool {
    static func defaultValue(_ key: String, default defaultVal: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? defaultVal
    }
}

// MARK: - UIImage Extensions

extension UIImage {
    func aspectFit(to size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: size).fit(self.size))
        }
    }
}

extension CGRect {
    func fit(_ aspect: CGSize) -> CGRect {
        let scale = min(width / aspect.width, height / aspect.height)
        let w = aspect.width * scale
        let h = aspect.height * scale
        return CGRect(x: (width - w) / 2, y: (height - h) / 2, width: w, height: h)
    }
}
