extension StringProtocol {
    func dropPrefix(_ prefix: String) -> Self.SubSequence {
        if hasPrefix(prefix) {
            return self.dropFirst(prefix.count)
        } else {
            return self[...]
        }
    }

    func dropSuffix(_ suffix: String) -> Self.SubSequence {
        if hasSuffix(suffix) {
            return self.dropLast(suffix.count)
        } else {
            return self[...]
        }
    }

    func addPrefix(_ prefix: String) -> String {
        if hasPrefix(prefix) {
            return String(self)
        } else {
            return prefix + self
        }
    }

    func addSuffix(_ suffix: String) -> String {
        if hasSuffix(suffix) {
            return String(self)
        } else {
            return self + suffix
        }
    }
}
