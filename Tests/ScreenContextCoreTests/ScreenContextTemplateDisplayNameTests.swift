import XCTest
@testable import ScreenContextCore

final class ScreenContextTemplateDisplayNameTests: XCTestCase {
    func testDisplayNameUsesFallbackForEmptyAndWhitespaceOnlyNames() {
        let emptyTemplate = ScreenContextTemplate(name: "", body: "")
        let whitespaceTemplate = ScreenContextTemplate(name: " \n\t", body: "")

        XCTAssertEqual(emptyTemplate.displayName(fallback: "Untitled"), "Untitled")
        XCTAssertEqual(whitespaceTemplate.displayName(fallback: "Untitled"), "Untitled")
    }

    func testDisplayNameTrimsVisibleNames() {
        let template = ScreenContextTemplate(name: "  Demo  ", body: "")

        XCTAssertEqual(template.displayName(fallback: "Untitled"), "Demo")
    }
}
