import Foundation
import XCTest
@testable import ScreenContextCore

@MainActor
final class AnalyticsTests: XCTestCase {
    func testConsentDefaultsOnAndPersistsAcrossControllers() {
        let defaults = makeDefaults()
        let firstClient = AnalyticsSpy()
        let first = AnalyticsConsentController(client: firstClient, defaults: defaults)

        XCTAssertTrue(first.isEnabled)
        XCTAssertEqual(firstClient.actions, ["opt_in"])

        first.setEnabled(false)
        XCTAssertFalse(first.isEnabled)
        XCTAssertEqual(firstClient.actions, ["opt_in", "opt_out"])

        let relaunchedClient = AnalyticsSpy()
        let relaunched = AnalyticsConsentController(client: relaunchedClient, defaults: defaults)
        XCTAssertFalse(relaunched.isEnabled)
        XCTAssertEqual(relaunchedClient.actions, ["opt_out"])
    }

    func testEnablingOptsInBeforeCapturingAnalyticsEnabled() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: AnalyticsConsentController.preferenceKey)
        let client = AnalyticsSpy()
        let controller = AnalyticsConsentController(client: client, defaults: defaults)

        controller.setEnabled(true)

        XCTAssertEqual(client.actions, ["opt_out", "opt_in", "capture:analytics_enabled"])
    }

    func testMissingAndPlaceholderTokensDisableProductionBootstrap() {
        XCTAssertNil(AnalyticsToken.normalized(nil))
        XCTAssertNil(AnalyticsToken.normalized("  "))
        XCTAssertNil(AnalyticsToken.normalized("$(POSTHOG_PROJECT_TOKEN)"))
        XCTAssertEqual(AnalyticsToken.normalized(" phc_test "), "phc_test")
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "ScreenContextAnalyticsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

@MainActor
private final class AnalyticsSpy: AnalyticsClient {
    private(set) var events: [AnalyticsEvent] = []
    private(set) var actions: [String] = []

    func capture(_ event: AnalyticsEvent) {
        events.append(event)
        actions.append("capture:\(event.name)")
    }

    func optIn() { actions.append("opt_in") }
    func optOut() { actions.append("opt_out") }
    func flush() { actions.append("flush") }
}
