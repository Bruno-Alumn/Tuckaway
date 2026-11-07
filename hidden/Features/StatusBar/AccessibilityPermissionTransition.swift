// Accessibility notifications describe changes across all apps. Only restoring
// this app's own permission should retry its previously blocked collapse.
struct AccessibilityPermissionTransition {
    private var wasTrusted: Bool

    init(isTrusted: Bool) {
        wasTrusted = isTrusted
    }

    mutating func permissionWasRestored(isTrusted: Bool) -> Bool {
        defer { wasTrusted = isTrusted }
        return !wasTrusted && isTrusted
    }
}

// macOS keeps a permission only for builds that meet the designated requirement
// recorded when it was granted. Grants made under 1.9.0 or earlier name only the
// Tuckaway Release Signing certificate, so the first launch signed with the
// Developer ID finds Accessibility (and Screen Recording) switched on in
// System Settings but not working, and flipping the switch doesn't help.
// Removing the stale entry lets macOS ask again cleanly.
enum StaleGrantReset {
    // Resets once per certificate change, and only for a permission that isn't
    // working. With no certificate on record (the first launch of a build that
    // records one), only a Developer ID build resets: an older release may have
    // installed it directly.
    static func shouldReset(isGranted: Bool, certificate: String?, recordedCertificate: String?,
                            isDeveloperID: Bool) -> Bool {
        guard !isGranted, let certificate else { return false }
        guard let recordedCertificate else { return isDeveloperID }
        return recordedCertificate != certificate
    }
}
