import Foundation
import Testing
@testable import BirdCount

@Suite("CloudConfig")
struct CloudConfigTests {
    @Test func bothEnvironmentsLoadFromBundledJSON() {
        for env in ["dev", "prod"] {
            // Tests are hosted in the app, so .main is the app bundle.
            let config = CloudConfig.load(environment: env)
            #expect(config.apiBaseURL.scheme == "https")
            #expect(config.hostedUIDomain.contains("birdcount-\(env)"))
            #expect(!config.clientId.isEmpty)
            #expect(config.redirectURI.hasPrefix("\(config.callbackScheme)://"))
            #expect(config.authorizeURL.absoluteString.hasSuffix("/oauth2/authorize"))
        }
    }

    @Test func debugBuildsDefaultToDev() {
        UserDefaults.standard.removeObject(forKey: "CloudEnvOverride")
        #if DEBUG
        #expect(CloudConfig.activeEnvironment == "dev")
        #else
        #expect(CloudConfig.activeEnvironment == "prod")
        #endif
    }

    @Test func overrideWinsAndBogusValuesAreIgnored() {
        defer { UserDefaults.standard.removeObject(forKey: "CloudEnvOverride") }
        UserDefaults.standard.set("prod", forKey: "CloudEnvOverride")
        #expect(CloudConfig.activeEnvironment == "prod")
        UserDefaults.standard.set("staging", forKey: "CloudEnvOverride")
        #if DEBUG
        #expect(CloudConfig.activeEnvironment == "dev")
        #endif
    }
}
