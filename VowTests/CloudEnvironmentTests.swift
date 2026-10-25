import CloudKit
import XCTest
@testable import Vow

/// Reading the iCloud environment from a provisioning profile, and the join messages that name it. A profile is built
/// as its property list between bytes that stand in for the CMS signature around it; errors are made locally.
final class CloudEnvironmentTests: XCTestCase {

    // MARK: - Fixtures

    private func profile(entitlements: String) -> Data {
        let plist: String = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Name</key>
                <string>iOS Team Provisioning Profile: app.dabora.vow</string>
                <key>Entitlements</key>
                <dict>
                    \(entitlements)
                    <key>com.apple.developer.icloud-container-identifiers</key>
                    <array>
                        <string>iCloud.app.dabora.vow</string>
                    </array>
                </dict>
            </dict>
            </plist>
            """
        var data: Data = Data([0x30, 0x82, 0x2E, 0x5B, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x02])
        data.append(Data(plist.utf8))
        data.append(Data([0xA0, 0x82, 0x0D, 0x3C, 0x30, 0x82, 0x04, 0x34, 0x00, 0xFF]))
        return data
    }

    // MARK: - Profile

    func testDevelopmentProfileIsDevelopment() {
        let data: Data = profile(entitlements: "<key>get-task-allow</key><true/>")
        XCTAssertEqual(CloudEnvironment.environment(profile: data), .development)
    }

    func testDistributionProfileIsProduction() {
        let data: Data = profile(entitlements: "<key>get-task-allow</key><false/>")
        XCTAssertEqual(CloudEnvironment.environment(profile: data), .production)
    }

    func testProfileWithoutGetTaskAllowIsProduction() {
        let data: Data = profile(entitlements: "<key>aps-environment</key><string>production</string>")
        XCTAssertEqual(CloudEnvironment.environment(profile: data), .production)
    }

    func testUnreadableProfileIsProduction() {
        XCTAssertEqual(CloudEnvironment.environment(profile: Data("not a profile".utf8)), .production)
        XCTAssertEqual(CloudEnvironment.environment(profile: Data()), .production)
        // Cut off before its </plist>.
        let whole: Data = profile(entitlements: "<key>get-task-allow</key><true/>")
        let cut: Data = whole.prefix(whole.count - 40)
        XCTAssertEqual(CloudEnvironment.environment(profile: cut), .production)
    }

    func testProfilePlistIsTheSignedPayload() {
        let plist: [String: Any]? = CloudEnvironment.profilePlist(profile(entitlements: ""))
        XCTAssertEqual(plist?["Name"] as? String, "iOS Team Provisioning Profile: app.dabora.vow")
        XCTAssertNotNil(plist?["Entitlements"] as? [String: Any])
    }

    func testLabels() {
        XCTAssertEqual(CloudEnvironment.development.label, "Development (Xcode build)")
        XCTAssertEqual(CloudEnvironment.production.label, "Production")
    }

    // MARK: - Join messages

    func testInviteNotFoundNamesThisBuildsEnvironment() {
        let error: CKError = CKError(.unknownItem)
        XCTAssertEqual(CloudErrors.joinMessage(error, accepted: false, environment: .development),
                       "Invite not found (code 11). Its group may be gone, or it's from a TestFlight build.")
        XCTAssertEqual(CloudErrors.joinMessage(error, accepted: false, environment: .production),
                       "Invite not found (code 11). Its group may be gone, or it's from a test build.")
    }

    func testAcceptedInviteWhoseGroupDidNotLoad() {
        XCTAssertEqual(CloudErrors.joinMessage(CKError(.zoneNotFound), accepted: true, environment: .development),
                       "The group didn't load yet (code 26). Open the link again in a minute.")
        XCTAssertEqual(CloudErrors.joinMessage(CloudError.groupMissing, accepted: true, environment: .production),
                       "The group didn't load yet. Open the link again in a minute.")
    }

    func testOtherJoinFailuresReadAsAnywhereElse() {
        let offline: CKError = CKError(.networkUnavailable)
        XCTAssertEqual(CloudErrors.joinMessage(offline, accepted: false, environment: .development), "You're offline.")
        let signedOut: CKError = CKError(.notAuthenticated)
        XCTAssertEqual(CloudErrors.joinMessage(signedOut, accepted: true, environment: .production),
                       CloudErrors.message(signedOut))
        XCTAssertEqual(CloudErrors.joinMessage(CloudError.invalidLink, accepted: false, environment: .production),
                       "That invite link doesn't work.")
    }
}
