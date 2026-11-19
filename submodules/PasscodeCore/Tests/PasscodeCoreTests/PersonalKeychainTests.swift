import XCTest
@testable import PasscodeCore

final class PersonalKeychainTests: XCTestCase {
    func testDefaultKeepsSharedGroup() throws {
        let environment = PasscodeEnvironment()
        try environment.configure(PasscodeConfiguration(appGroupIdentifier: "group.org.qxgram.tests", processRole: .mainApp), privateAccessGroup: { "TEAM.org.qxgram.tests" })
        XCTAssertEqual(try environment.sharedAccessGroup(), "group.org.qxgram.tests")
    }

    func testPersonalBuildUsesPrivateGroup() throws {
        let environment = PasscodeEnvironment()
        try environment.configure(PasscodeConfiguration(appGroupIdentifier: "group.org.qxgram.tests", processRole: .mainApp, usePrivateKeychainForSharedItems: true), privateAccessGroup: { "TEAM.org.qxgram.tests" })
        XCTAssertEqual(try environment.sharedAccessGroup(), "TEAM.org.qxgram.tests")
    }

    func testExtensionCannotUsePersonalMode() {
        let environment = PasscodeEnvironment()
        XCTAssertThrowsError(try environment.configure(PasscodeConfiguration(appGroupIdentifier: "group.org.qxgram.tests", processRole: .appExtension, usePrivateKeychainForSharedItems: true)))
    }
}
