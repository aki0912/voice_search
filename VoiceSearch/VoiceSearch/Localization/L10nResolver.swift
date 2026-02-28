import Foundation

enum L10nResolver {
    static func text(_ key: String, bundle: Bundle = .main) -> String {
        NSLocalizedString(
            key,
            tableName: nil,
            bundle: bundle,
            value: key,
            comment: ""
        )
    }

    static func format(
        _ key: String,
        arguments: [CVarArg],
        bundle: Bundle = .main
    ) -> String {
        let format = text(key, bundle: bundle)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: Locale.current, arguments: arguments)
    }
}
