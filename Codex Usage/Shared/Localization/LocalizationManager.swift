import Foundation

extension String {
    /// Returns a localized string for the current app language.
    var localized: String {
        NSLocalizedString(self, comment: "")
    }

    /// Returns a localized format string with variadic arguments.
    func localized(with args: CVarArg...) -> String {
        String(format: NSLocalizedString(self, comment: ""), arguments: args)
    }

    /// Returns a localized string with an explicit comment.
    func localized(comment: String) -> String {
        NSLocalizedString(self, comment: comment)
    }
}
