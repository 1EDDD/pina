import Foundation

/// A single entitlement decision point for an app you own.
///
/// In Release builds, only the real entitlement supplied by your app's trusted
/// purchase/account layer is considered. The development override is compiled
/// out entirely unless the DEBUG configuration is active.
public enum EntitlementGate {
    public static func hasVIP(serverEntitlement: Bool) -> Bool {
        #if DEBUG
        return serverEntitlement || DevelopmentEntitlementOverride.isEnabled
        #else
        return serverEntitlement
        #endif
    }
}

#if DEBUG
/// Process-local QA switch for testing VIP-only UI and playback paths in Debug builds.
///
/// This does not change StoreKit transactions, server state, accounts, or credentials.
/// It resets to disabled whenever the app/test process restarts.
public enum DevelopmentEntitlementOverride {
    private static let lock = NSLock()
    private static var enabled = false

    public static var isEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return enabled
    }

    /// Enables a mock VIP state for the current Debug process only.
    public static func enableForDebugSession() {
        lock.lock()
        defer { lock.unlock() }
        enabled = true
    }

    /// Restores normal entitlement evaluation.
    public static func reset() {
        lock.lock()
        defer { lock.unlock() }
        enabled = false
    }
}
#endif
