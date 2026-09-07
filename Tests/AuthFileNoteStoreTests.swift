import XCTest
@testable import CLIProxyGUI

final class AuthFileNoteStoreTests: XCTestCase {
    func testNotesPersistAndAreIsolatedByNodeAndFilename() {
        let first = UUID()
        let second = UUID()
        defer {
            AuthFileNoteStore.remove(for: first)
            AuthFileNoteStore.remove(for: second)
        }
        AuthFileNoteStore.setNote("  工作账号\n", for: first, filename: "auth.json")
        AuthFileNoteStore.setNote("个人账号", for: second, filename: "auth.json")
        AuthFileNoteStore.setNote("备用", for: first, filename: "other.json")
        XCTAssertEqual(AuthFileNoteStore.notes(for: first)["auth.json"], "工作账号")
        XCTAssertEqual(AuthFileNoteStore.notes(for: second)["auth.json"], "个人账号")
        AuthFileNoteStore.setNote("更新", for: first, filename: "auth.json")
        XCTAssertEqual(AuthFileNoteStore.notes(for: first)["auth.json"], "更新")
        AuthFileNoteStore.setNote(" \n", for: first, filename: "auth.json")
        XCTAssertNil(AuthFileNoteStore.notes(for: first)["auth.json"])
        XCTAssertEqual(AuthFileNoteStore.notes(for: first)["other.json"], "备用")
        AuthFileNoteStore.remove(for: first)
        XCTAssertTrue(AuthFileNoteStore.notes(for: first).isEmpty)
        XCTAssertEqual(AuthFileNoteStore.notes(for: second)["auth.json"], "个人账号")
    }
}
