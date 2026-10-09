import Foundation

enum LocalUsageTrendFormatter {
    static func weeklyLabel(_ date: Date, language: AppLanguage, calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        let index = calendar.component(.weekday, from: date) - 1
        let labels = language == .zhHans
            ? ["周天", "周一", "周二", "周三", "周四", "周五", "周六"]
            : ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return labels[min(6, max(0, index))]
    }

    static func diagnosticTime(_ date: Date?, language: AppLanguage) -> String {
        guard let date else { return language == .zhHans ? "无" : "n/a" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == .zhHans ? "zh_CN" : "en_US_POSIX")
        formatter.dateFormat = language == .zhHans ? "MM-dd HH:mm" : "MMM d HH:mm"
        return formatter.string(from: date)
    }
}
