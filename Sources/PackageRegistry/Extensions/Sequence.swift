extension Sequence<UInt8> {
    /// return a hexEncoded string buffer from an array of bytes
    public func hexDigest() -> String {
        self.map { "0\(String($0, radix: 16))".suffix(2) }.joined()
    }
}
