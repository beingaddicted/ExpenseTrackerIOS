import SwiftUI

enum Theme {
    // Match PWA dark palette
    static let bgPrimary = Color(red: 0.04, green: 0.04, blue: 0.10)       // #0a0a1a
    static let bgSecondary = Color(red: 0.08, green: 0.07, blue: 0.16)     // #141225
    static let cardBg = Color(red: 0.11, green: 0.10, blue: 0.20)          // #1c1a33
    static let accentPrimary = Color(red: 0.49, green: 0.23, blue: 0.93)   // #7c3aed
    static let accentLight = Color(red: 0.65, green: 0.55, blue: 0.98)     // #a78bfa
    static let green = Color(red: 0.13, green: 0.77, blue: 0.37)           // #22c55e
    static let red = Color(red: 0.94, green: 0.27, blue: 0.27)             // #ef4444
    static let yellow = Color(red: 0.92, green: 0.70, blue: 0.03)          // #eab308
    static let blue = Color(red: 0.23, green: 0.51, blue: 0.96)            // #3b82f6
    static let textPrimary = Color.white
    static let textSecondary = Color(white: 0.65)
    static let textMuted = Color(white: 0.45)
    static let border = Color.white.opacity(0.08)

    static let categoryColors: [String: Color] = [
        "Food": .orange,
        "Shopping": .pink,
        "Transport": .cyan,
        "Travel": .indigo,
        "Bills": .yellow,
        "Entertainment": .purple,
        "Groceries": .green,
        "Health": .red,
        "Investment": .blue,
        "Transfer": .gray,
        "Salary": Color(red: 0.13, green: 0.77, blue: 0.37),
        "Other": Color(white: 0.5),
    ]

    static func colorForCategory(_ cat: String) -> Color {
        categoryColors[cat] ?? accentLight
    }
}
