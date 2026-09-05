import Foundation
import XCTest
@testable import ScreenContextCore

final class RecordingContextDeepLinkBuilderTests: XCTestCase {
    private let builder = RecordingContextDeepLinkBuilder()

    func testCodexDeepLinkStructureAndPromptRoundTrip() throws {
        let prompt = roundTripPrompt
        let url = try builder.url(for: .codex, prompt: prompt)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.scheme, "codex")
        XCTAssertEqual(components.host, "threads")
        XCTAssertEqual(components.path, "/new")
        XCTAssertEqual(components.queryItems, [URLQueryItem(name: "prompt", value: prompt)])
    }

    func testClaudeDeepLinkStructureAndPromptRoundTrip() throws {
        let prompt = roundTripPrompt
        let url = try builder.url(for: .claude, prompt: prompt)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.scheme, "claude")
        XCTAssertEqual(components.host, "claude.ai")
        XCTAssertEqual(components.path, "/new")
        XCTAssertEqual(components.queryItems, [URLQueryItem(name: "q", value: prompt)])
    }

    func testClaudeAcceptsMaximumPromptLength() throws {
        let prompt = String(repeating: "é", count: RecordingContextDeepLinkBuilder.claudeMaximumPromptLength)
        let url = try builder.url(for: .claude, prompt: prompt)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.queryItems?.first?.value, prompt)
    }

    func testClaudeRejectsOversizedPromptWithoutProducingPartialLink() {
        let prompt = String(repeating: "x", count: RecordingContextDeepLinkBuilder.claudeMaximumPromptLength + 1)

        XCTAssertThrowsError(try builder.url(for: .claude, prompt: prompt)) { error in
            XCTAssertEqual(
                error as? RecordingContextPromptLengthError,
                RecordingContextPromptLengthError(
                    destination: .claude,
                    maximumCharacterCount: RecordingContextDeepLinkBuilder.claudeMaximumPromptLength,
                    actualCharacterCount: prompt.count
                )
            )
        }
    }

    func testCodexDoesNotImposeClaudePromptLimit() throws {
        let prompt = String(repeating: "x", count: RecordingContextDeepLinkBuilder.claudeMaximumPromptLength + 1)
        let url = try builder.url(for: .codex, prompt: prompt)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.queryItems?.first?.value, prompt)
    }

    private var roundTripPrompt: String {
        """
        Review this recording context 🚀
        Spaces, question? ampersand& hash#
        [frame](/Users/marcus/My Recordings/frame #1.png)
        """
    }
}
