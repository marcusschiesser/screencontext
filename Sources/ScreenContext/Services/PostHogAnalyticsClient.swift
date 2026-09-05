import ScreenContextCore
import Foundation
import PostHog

@MainActor
final class PostHogAnalyticsClient: AnalyticsClient {
    private let sdk: PostHogSDK

    init(projectToken: String) {
        let config = PostHogConfig(
            projectToken: projectToken,
            host: "https://us.i.posthog.com"
        )
        config.captureApplicationLifecycleEvents = false
        config.captureScreenViews = false
        config.enableSwizzling = false
        config.capturePushNotificationSubscriptions = false
        config.capturePushNotificationOpened = false
        config.preloadFeatureFlags = false
        config.sendFeatureFlagEvent = false
        config.personProfiles = .never
        config.setDefaultPersonProperties = false
        config.errorTrackingConfig.autoCapture = false
        sdk = PostHogSDK.with(config)
    }

    func capture(_ event: AnalyticsEvent) {
        sdk.capture(event.name, properties: event.properties.mapValues(\.postHogValue))
    }

    func optIn() {
        sdk.optIn()
    }

    func optOut() {
        sdk.optOut()
    }

    func flush() {
        sdk.flush()
    }
}

private extension AnalyticsProperty {
    var postHogValue: Any {
        switch self {
        case let .string(value): value
        case let .bool(value): value
        case let .integer(value): value
        case let .double(value): value
        }
    }
}
