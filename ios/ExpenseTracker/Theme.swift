import SwiftUI
import UIKit

enum Theme {
    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? dark : light
        })
    }

    static let bgPrimary = dynamic(
        light: UIColor(red: 0.95, green: 0.96, blue: 0.98, alpha: 1),
        dark: UIColor(red: 0.04, green: 0.04, blue: 0.10, alpha: 1)
    )
    static let bgSecondary = dynamic(
        light: UIColor(red: 0.98, green: 0.98, blue: 1.0, alpha: 1),
        dark: UIColor(red: 0.08, green: 0.07, blue: 0.16, alpha: 1)
    )
    static let cardBg = dynamic(
        light: UIColor(red: 0.99, green: 0.99, blue: 1.0, alpha: 1),
        dark: UIColor(red: 0.11, green: 0.10, blue: 0.20, alpha: 1)
    )
    static let accentPrimary = Color(red: 0.49, green: 0.23, blue: 0.93)   // #7c3aed
    static let accentLight = dynamic(
        light: UIColor(red: 0.33, green: 0.20, blue: 0.76, alpha: 1),
        dark: UIColor(red: 0.65, green: 0.55, blue: 0.98, alpha: 1)
    )
    static let green = Color(red: 0.13, green: 0.77, blue: 0.37)           // #22c55e
    static let red = Color(red: 0.94, green: 0.27, blue: 0.27)             // #ef4444
    static let yellow = Color(red: 0.92, green: 0.70, blue: 0.03)          // #eab308
    static let blue = Color(red: 0.23, green: 0.51, blue: 0.96)            // #3b82f6
    static let textPrimary = dynamic(
        light: UIColor(red: 0.10, green: 0.11, blue: 0.16, alpha: 1),
        dark: .white
    )
    static let textSecondary = dynamic(
        light: UIColor(red: 0.29, green: 0.33, blue: 0.41, alpha: 1),
        dark: UIColor(white: 0.75, alpha: 1)
    )
    static let textMuted = dynamic(
        light: UIColor(red: 0.43, green: 0.47, blue: 0.55, alpha: 1),
        dark: UIColor(white: 0.55, alpha: 1)
    )
    static let border = dynamic(
        light: UIColor.black.withAlphaComponent(0.12),
        dark: UIColor.white.withAlphaComponent(0.08)
    )

    // MARK: - Shared Layout Metrics

    static func horizontalInset(compact: Bool) -> CGFloat {
        compact ? 10 : 14
    }

    static func cardInset(compact: Bool) -> CGFloat {
        compact ? 10 : 14
    }

    static let categoryColors: [String: Color] = [
        "Food & Dining": .orange,
        "Shopping": .pink,
        "Transport": .cyan,
        "Travel": .indigo,
        "Bills & Utilities": .yellow,
        "Entertainment": .purple,
        "Groceries": .green,
        "Health": .red,
        "Education": .teal,
        "Insurance": Color(red: 0.92, green: 0.50, blue: 0.03),
        "Investment": .blue,
        "EMI & Loans": Color(red: 0.94, green: 0.47, blue: 0.10),
        "Rent": Color(red: 0.85, green: 0.30, blue: 0.55),
        "Salary": Color(red: 0.13, green: 0.77, blue: 0.37),
        "Transfer": .gray,
        "ATM": Color(white: 0.55),
        "Subscription": .mint,
        "Cashback & Rewards": Color(red: 0.65, green: 0.88, blue: 0.18),
        "Refund": Color(red: 0.20, green: 0.78, blue: 0.62),
        "Tax": Color(red: 0.85, green: 0.60, blue: 0.10),
        "Credit Card Payment": Color(red: 0.23, green: 0.51, blue: 0.96),
        "Savings": Color(red: 0.10, green: 0.68, blue: 0.42),
        "Other": Color(white: 0.5),
    ]

    static func colorForCategory(_ cat: String) -> Color {
        categoryColors[cat] ?? accentLight
    }
}
