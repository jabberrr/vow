import Foundation

/// The CloudKit environment this build's container talks to. Development and Production keep separate data, so a
/// group made in one, and its invite link, can't be found from the other. The entitlements don't name an
/// environment, so it follows the signing: a development-signed build (run from Xcode) uses Development, and a
/// distribution-signed one (TestFlight, the App Store, Ad Hoc) uses Production. An Ad Hoc or development export that
/// picked the other environment by hand would be misread; nothing public tells the app its signed entitlements.
enum CloudEnvironment: Equatable {
    case development
    case production

    /// This build's, read once.
    static let current: CloudEnvironment = CloudEnvironment.detect()

    /// What Settings shows. Development comes from Xcode, so it says so; Production covers TestFlight, the App Store
    /// and Ad Hoc builds alike.
    var label: String {
        switch self {
        case .development:
            return "Development (Xcode build)"
        case .production:
            return "Production"
        }
    }

    /// The Simulator is always Development. On a device, a development profile lets a debugger attach
    /// (`get-task-allow`); TestFlight and App Store builds carry no profile at all.
    private static func detect() -> CloudEnvironment {
        #if targetEnvironment(simulator)
        return .development
        #else
        guard let url: URL = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data: Data = try? Data(contentsOf: url) else { return .production }
        return environment(profile: data)
        #endif
    }

    /// Development when the provisioning profile's entitlements allow a debugger, else Production, as for a profile
    /// that can't be read.
    static func environment(profile data: Data) -> CloudEnvironment {
        guard let plist: [String: Any] = profilePlist(data),
              let entitlements: [String: Any] = plist["Entitlements"] as? [String: Any],
              let debuggable: Bool = entitlements["get-task-allow"] as? Bool, debuggable else { return .production }
        return .development
    }

    /// A provisioning profile is a signed (CMS) file whose payload, an XML property list, sits in it as plain text:
    /// the bytes from `<?xml` through the first `</plist>` after it.
    static func profilePlist(_ data: Data) -> [String: Any]? {
        guard let start: Range<Data.Index> = data.range(of: Data("<?xml".utf8)),
              let end: Range<Data.Index> = data.range(of: Data("</plist>".utf8), options: [],
                                                      in: start.upperBound..<data.endIndex) else { return nil }
        let slice: Data = data.subdata(in: start.lowerBound..<end.upperBound)
        let parsed: Any? = try? PropertyListSerialization.propertyList(from: slice, options: [], format: nil)
        return parsed as? [String: Any]
    }
}
