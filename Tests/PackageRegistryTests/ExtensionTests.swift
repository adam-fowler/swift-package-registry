import Testing

@testable import PackageRegistry

struct StdLibExtensionTests {
    @Test
    func testHexDigest() {
        let a = [UInt8]([1, 45, 2, 255, 127])
        #expect(a.hexDigest() == "012d02ff7f")
    }
}
