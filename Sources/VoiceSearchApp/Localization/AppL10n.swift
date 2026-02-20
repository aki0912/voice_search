import Foundation

enum AppL10n {
    static func text(_ key: String) -> String {
        NSLocalizedString(
            key,
            tableName: nil,
            bundle: .module,
            value: key,
            comment: ""
        )
    }

    static func format(_ key: String, _ args: CVarArg...) -> String {
        format(key, arguments: args)
    }

    static func format(_ key: String, arguments: [CVarArg]) -> String {
        let format = text(key)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: Locale.current, arguments: arguments)
    }
}
