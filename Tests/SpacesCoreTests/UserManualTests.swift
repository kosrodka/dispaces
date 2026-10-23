import XCTest
@testable import SpacesCore

final class UserManualTests: XCTestCase {
    func testMatchesTheDocsCopy() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let file = try String(contentsOf: root.appendingPathComponent("docs/08-user-manual.md"), encoding: .utf8)
        XCTAssertEqual(file.trimmingCharacters(in: .newlines), UserManual.markdown,
                       "docs/08-user-manual.md and UserManual.markdown must say the same")
    }

    func testBlocks() {
        let blocks = UserManual.blocks("# T\n\nIntro **bold** end\n\n## H\n- **Key:** text\n")
        XCTAssertEqual(blocks, [
            .title("T"),
            .paragraph([.init("Intro "), .init("bold", bold: true), .init(" end")]),
            .heading("H"),
            .bullet([.init("Key:", bold: true), .init(" text")]),
        ])
    }

    func testUnpairedBoldStaysPlain() {
        XCTAssertEqual(UserManual.spans("a **b"), [.init("a "), .init("**b")])
    }

    func testManualHasEverySection() {
        let headings = UserManual.blocks().compactMap { block -> String? in
            if case .heading(let text) = block { return text } else { return nil }
        }
        XCTAssertTrue(headings.contains("Keyboard and mouse shortcuts"))
        XCTAssertTrue(headings.contains("Manage displays and spaces"))
        XCTAssertEqual(UserManual.blocks().first, .title("Dispaces User Manual"))
    }
}
