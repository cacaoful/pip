import AppKit
import Foundation
import IOKit

/// Who currently owns the macOS secure input session (Secure Keyboard Entry).
///
/// While any process holds it, the window server stops delivering key events to
/// every other app: global `NSEvent` monitors and `CGEventTap` callbacks both go
/// silent, and `CGEventSource.keyState` polling is blocked too. Modifier
/// (`flagsChanged`) events still arrive, which is why a hold-to-talk hotkey can
/// look half-working. Nothing in-process can bypass this by design.
enum SecureInputHolder: Equatable {
    case none
    /// Pip itself holds it, e.g. one of its own secure fields is focused.
    case ownProcess
    case otherApp(pid: pid_t, name: String?)
    /// Owner exited without releasing the lock. Only a logout or reboot clears it.
    case stale(pid: pid_t)
}

struct SecureInputStatus: Equatable {
    let holder: SecureInputHolder

    var blocksHotkeys: Bool {
        switch holder {
        case .none, .ownProcess: return false
        case .otherApp, .stale: return true
        }
    }

    /// Short line for the floating indicator.
    /// Hold-to-talk still works (Fn is a modifier); Fn+Space hands-free does not.
    var indicatorMessage: String? {
        switch holder {
        case .none, .ownProcess:
            return nil
        case let .otherApp(_, name):
            return "Fn+Space blocked by \(name ?? "another app") — leave its password field"
        case .stale:
            return "Fn+Space blocked — Apple menu → Log Out of Mac"
        }
    }

    /// Longer explanation for logs and any settings surface.
    var explanation: String? {
        switch holder {
        case .none, .ownProcess:
            return nil
        case let .otherApp(pid, name):
            let who = name ?? "Another app (pid \(pid))"
            return """
            \(who) has macOS Secure Keyboard Entry active, so the system is not \
            delivering key presses to Pip. Leave that app's password field, or \
            uncheck Secure Keyboard Entry in its Edit menu.
            """
        case let .stale(pid):
            return """
            A secure input session is still registered to process \(pid), which no \
            longer exists. macOS will keep blocking key delivery to Pip until you \
            log out of your Mac account (Apple menu → Log Out) and sign back in. \
            That closes every open app and window.
            """
        }
    }
}

enum SecureInputInspector {
    static func currentStatus() -> SecureInputStatus {
        resolveStatus(
            holderPID: consoleSecureInputPID(),
            ownPID: ProcessInfo.processInfo.processIdentifier,
            isRunning: processExists,
            appName: { NSRunningApplication(processIdentifier: $0)?.localizedName }
        )
    }

    static func resolveStatus(
        holderPID: pid_t?,
        ownPID: pid_t,
        isRunning: (pid_t) -> Bool,
        appName: (pid_t) -> String?
    ) -> SecureInputStatus {
        guard let holderPID, holderPID > 0 else {
            return SecureInputStatus(holder: .none)
        }
        if holderPID == ownPID {
            return SecureInputStatus(holder: .ownProcess)
        }
        guard isRunning(holderPID) else {
            return SecureInputStatus(holder: .stale(pid: holderPID))
        }
        return SecureInputStatus(holder: .otherApp(pid: holderPID, name: appName(holderPID)))
    }

    /// Reads `kCGSSessionSecureInputPID` from the on-console session in
    /// `IOConsoleUsers`. Equivalent to:
    /// `ioreg -l -d 1 -w 0 | grep kCGSSessionSecureInputPID`
    static func consoleSecureInputPID() -> pid_t? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IOService:/IOResources")
        guard entry != MACH_PORT_NULL else { return nil }
        defer { IOObjectRelease(entry) }

        guard let property = IORegistryEntryCreateCFProperty(
            entry,
            "IOConsoleUsers" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? [[String: Any]] else { return nil }

        for session in property {
            guard session["kCGSSessionOnConsoleKey"] as? Bool == true else { continue }
            if let pid = session["kCGSSessionSecureInputPID"] as? pid_t, pid > 0 {
                return pid
            }
        }
        return nil
    }

    private static func processExists(_ pid: pid_t) -> Bool {
        // EPERM means the process exists but is owned by another user.
        kill(pid, 0) == 0 || errno == EPERM
    }
}

/// Rate limits secure-input warnings so a stuck lock cannot nag on every hotkey press.
final class SecureInputWarningThrottle {
    let interval: TimeInterval
    private var lastWarnedAt: Date?
    private var lastHolder: SecureInputHolder?

    init(interval: TimeInterval = 300) {
        self.interval = interval
    }

    func shouldWarn(for status: SecureInputStatus, now: Date = Date()) -> Bool {
        guard status.blocksHotkeys else {
            lastWarnedAt = nil
            lastHolder = nil
            return false
        }
        if lastHolder != status.holder {
            lastHolder = status.holder
            lastWarnedAt = now
            return true
        }
        if let lastWarnedAt, now.timeIntervalSince(lastWarnedAt) < interval {
            return false
        }
        lastWarnedAt = now
        return true
    }
}
