import Foundation

enum ServicesL10n {
    static func text(_ key: String) -> String {
        L10nResolver.text(key)
    }

    static func format(_ key: String, _ args: CVarArg...) -> String {
        format(key, arguments: args)
    }

    static func format(_ key: String, arguments: [CVarArg]) -> String {
        L10nResolver.format(key, arguments: arguments)
    }
}
