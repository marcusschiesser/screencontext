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

    func testTemplateCreationIncludesCompleteUnicodeMultilineContentAndMetadata() throws {
        let client = AnalyticsSpy()
        let tracker = TemplateAnalyticsTracker(client: client)
        let template = ScreenContextTemplate(
            id: "custom.日本語",
            name: "Résumé 🎬",
            body: "First line\n{recording}\n{transcript} — 完"
        )

        tracker.created(template)

        let event = try XCTUnwrap(client.events.first)
        XCTAssertEqual(event.name, "template_created")
        XCTAssertEqual(event.properties["template_name"], .string(template.name))
        XCTAssertEqual(event.properties["template_body"], .string(template.body))
        XCTAssertEqual(event.properties["body_length"], .integer(template.body.count))
        XCTAssertEqual(event.properties["placeholder_count"], .integer(2))
        XCTAssertEqual(event.properties["origin"], .string("user"))
    }

    func testTemplateUpdateDebouncesAndDeduplicatesExactContent() async {
        let client = AnalyticsSpy()
        let tracker = TemplateAnalyticsTracker(
            client: client,
            updateDelay: .milliseconds(30)
        )
        let original = ScreenContextTemplate(id: "custom.one", name: "One", body: "A")
        let final = ScreenContextTemplate(id: "custom.one", name: "One ✨", body: "A\nB")

        tracker.scheduleUpdated(original)
        tracker.scheduleUpdated(final)
        try? await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(client.events.map(\.name), ["template_updated"])
        XCTAssertEqual(client.events.first?.properties["template_body"], .string("A\nB"))

        tracker.scheduleUpdated(final)
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(client.events.count, 1)
    }

    func testSelectionChangeFlushesPendingUpdateBeforeSelectionEvent() {
        let client = AnalyticsSpy()
        let tracker = TemplateAnalyticsTracker(client: client, updateDelay: .seconds(2))
        let edited = ScreenContextTemplate(id: "custom.one", name: "Edited", body: "Body")
        let selected = ScreenContextTemplate(id: "builtin.agent-mode", name: "Agent", body: "")

        tracker.scheduleUpdated(edited)
        tracker.flushPendingUpdate()
        tracker.selected(selected)

        XCTAssertEqual(client.events.map(\.name), ["template_updated", "template_selected"])
    }

    func testTemplateSelectionAndUseExcludeBodyAndRestoreReportsCount() {
        let client = AnalyticsSpy()
        let tracker = TemplateAnalyticsTracker(client: client)
        let template = ScreenContextTemplate(
            id: "builtin.agent-mode",
            name: "Agent mode",
            body: "Sensitive body"
        )

        tracker.selected(template)
        tracker.used(template)
        tracker.restoredBundledTemplates(count: 2)

        XCTAssertEqual(
            client.events.map(\.name),
            ["template_selected", "template_used", "bundled_templates_restored"]
        )
        XCTAssertNil(client.events[0].properties["template_body"])
        XCTAssertNil(client.events[1].properties["template_body"])
        XCTAssertEqual(client.events[2].properties["restored_count"], .integer(2))
    }

    func testDeletionAndOptOutCancellation() async {
        let defaults = makeDefaults()
        let client = AnalyticsSpy()
        let controller = AnalyticsConsentController(
            client: client,
            defaults: defaults,
            templateUpdateDelay: .milliseconds(30)
        )
        let deleted = ScreenContextTemplate(id: "custom.delete", name: "Delete", body: "全部")
        controller.templates.deleted(deleted)
        controller.templates.scheduleUpdated(ScreenContextTemplate(
            id: "custom.pending",
            name: "Pending",
            body: "Never sent"
        ))

        controller.setEnabled(false)
        try? await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(client.events.map(\.name), ["template_deleted"])
        XCTAssertEqual(client.actions.last, "opt_out")
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
