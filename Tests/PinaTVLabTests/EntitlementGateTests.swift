import XCTest
@testable import PinaTVLab

final class EntitlementGateTests: XCTestCase {
    func testRealVIPEntitlementIsAlwaysHonored() {
        XCTAssertTrue(EntitlementGate.hasVIP(serverEntitlement: true))
    }

    func testMissingRealEntitlementIsNotVIPByDefault() {
        #if DEBUG
        DevelopmentEntitlementOverride.reset()
        #endif
        XCTAssertFalse(EntitlementGate.hasVIP(serverEntitlement: false))
    }

    #if DEBUG
    override func setUp() {
        super.setUp()
        DevelopmentEntitlementOverride.reset()
    }

    override func tearDown() {
        DevelopmentEntitlementOverride.reset()
        super.tearDown()
    }

    func testDebugOverrideEnablesVIPOnlyInCurrentProcess() {
        XCTAssertFalse(EntitlementGate.hasVIP(serverEntitlement: false))

        DevelopmentEntitlementOverride.enableForDebugSession()

        XCTAssertTrue(DevelopmentEntitlementOverride.isEnabled)
        XCTAssertTrue(EntitlementGate.hasVIP(serverEntitlement: false))
    }

    func testResetReturnsToRealEntitlementState() {
        DevelopmentEntitlementOverride.enableForDebugSession()
        DevelopmentEntitlementOverride.reset()

        XCTAssertFalse(DevelopmentEntitlementOverride.isEnabled)
        XCTAssertFalse(EntitlementGate.hasVIP(serverEntitlement: false))
    }
    #endif
}
