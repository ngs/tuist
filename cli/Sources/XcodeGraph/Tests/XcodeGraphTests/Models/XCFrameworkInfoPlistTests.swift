import Foundation
import Path
import XCTest
@testable import XcodeGraph

final class XCFrameworkInfoPlistTests: XCTestCase {
    func test_codable() {
        // Given
        let subject: XCFrameworkInfoPlist = .test()

        // Then
        XCTAssertCodable(subject)
    }

    // MARK: - Bug reproduction: SupportedPlatformVariant is lost during decode (tuist/tuist#9723)

    func test_decode_from_plist_with_SupportedPlatformVariant() throws {
        // Given
        // A real xcframework Info.plist contains SupportedPlatformVariant to distinguish
        // device from simulator slices. Both slices have SupportedPlatform = "ios" but
        // the simulator slice additionally has SupportedPlatformVariant = "simulator".
        let plistData = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>AvailableLibraries</key>
            <array>
                <dict>
                    <key>LibraryIdentifier</key>
                    <string>ios-arm64</string>
                    <key>LibraryPath</key>
                    <string>MyFramework.framework</string>
                    <key>SupportedArchitectures</key>
                    <array>
                        <string>arm64</string>
                    </array>
                    <key>SupportedPlatform</key>
                    <string>ios</string>
                </dict>
                <dict>
                    <key>LibraryIdentifier</key>
                    <string>ios-arm64-simulator</string>
                    <key>LibraryPath</key>
                    <string>MyFramework.framework</string>
                    <key>SupportedArchitectures</key>
                    <array>
                        <string>arm64</string>
                    </array>
                    <key>SupportedPlatform</key>
                    <string>ios</string>
                    <key>SupportedPlatformVariant</key>
                    <string>simulator</string>
                </dict>
            </array>
        </dict>
        </plist>
        """.data(using: .utf8)!

        // When
        let decoded = try PropertyListDecoder().decode(XCFrameworkInfoPlist.self, from: plistData)

        // Then
        XCTAssertEqual(decoded.libraries.count, 2)

        let deviceLib = try XCTUnwrap(decoded.libraries.first { $0.identifier == "ios-arm64" })
        let simulatorLib = try XCTUnwrap(decoded.libraries.first { $0.identifier == "ios-arm64-simulator" })

        // Both libraries decode with the same platform (.iOS) — this is correct
        XCTAssertEqual(deviceLib.platform, .iOS)
        XCTAssertEqual(simulatorLib.platform, .iOS)

        // BUG: There is no way to distinguish device from simulator after decoding.
        // The SupportedPlatformVariant field from the plist is silently discarded.
        // The Library model has no platformVariant property, so both libraries
        // appear identical in terms of platform targeting.
        //
        // This means code that does `.first(where: { platform == .iOS })` will
        // arbitrarily pick one — usually the device slice — causing simulator
        // builds to fail with:
        //   ld: building for 'iOS-simulator', but linking in object file built for 'iOS'
        //
        // Asserting that the model CANNOT distinguish them proves the information loss.
        // When the bug is fixed, the Library model should expose platformVariant
        // and this test should be updated to verify it.
        let devicePlatformInfo = (deviceLib.platform, deviceLib.architectures)
        let simulatorPlatformInfo = (simulatorLib.platform, simulatorLib.architectures)

        // This assertion demonstrates the bug: both slices have identical platform info
        // despite being different (device vs simulator). When a fix adds platformVariant,
        // they should become distinguishable and this test should be updated.
        XCTAssertEqual(
            devicePlatformInfo.0, simulatorPlatformInfo.0,
            "Both libraries report the same platform — SupportedPlatformVariant is lost during decode"
        )
        XCTAssertEqual(
            devicePlatformInfo.1, simulatorPlatformInfo.1,
            "Both libraries report the same architectures — no way to distinguish device from simulator"
        )
    }
}
