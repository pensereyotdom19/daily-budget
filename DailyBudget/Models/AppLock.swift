import LocalAuthentication
import SwiftUI
import UIKit

/// Face ID lock. When on, the app locks each time you leave it, and your numbers are hidden in the
/// app switcher. The lock screen sits in its own window above everything, including open sheets.
@MainActor
@Observable
final class AppLock {
    static let enabledKey = "lock.enabled"

    private(set) var isLocked: Bool
    @ObservationIgnored private var window: UIWindow?
    @ObservationIgnored private var unlocking = false

    init() {
        isLocked = UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    /// "Face ID", "Touch ID" or "Passcode", for labels.
    static var methodName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }

    /// Asks for Face ID (or the phone's passcode if Face ID fails). True if it was you.
    static func verify(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }

    // MARK: App life cycle

    func sceneChanged(to phase: ScenePhase) {
        guard isEnabled else { hideWindow(); isLocked = false; return }
        switch phase {
        case .background:
            isLocked = true
            showWindow()
        case .inactive:
            showWindow()  // hide numbers in the app switcher
        case .active:
            if isLocked { showWindow(); Task { await unlock() } } else { hideWindow() }
        @unknown default:
            break
        }
    }

    func unlock() async {
        guard isLocked, !unlocking else { return }
        unlocking = true
        defer { unlocking = false }
        if await Self.verify(reason: "Unlock Daily Budget") {
            isLocked = false
            hideWindow()
        }
    }

    // MARK: Lock window

    private func showWindow() {
        if window == nil {
            guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
            let w = UIWindow(windowScene: scene)
            w.windowLevel = .alert + 1
            let host = UIHostingController(rootView: LockScreen(lock: self))
            host.view.backgroundColor = .clear
            w.rootViewController = host
            window = w
        }
        window?.isHidden = false
    }

    private func hideWindow() {
        window?.isHidden = true
    }
}

private struct LockScreen: View {
    let lock: AppLock

    var body: some View {
        ZStack {
            GlowBackground()
            VStack(spacing: 18) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Theme.base)
                    .frame(width: 84, height: 84)
                    .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                Text("Daily Budget is locked").font(.title3.weight(.bold))
                if lock.isLocked {
                    Button {
                        Task { await lock.unlock() }
                    } label: {
                        Text("Unlock with \(AppLock.methodName)")
                            .font(.headline).foregroundStyle(Theme.base)
                            .padding(.horizontal, 28).frame(height: 54)
                            .background(Theme.accentGradient, in: Capsule())
                    }
                    .buttonStyle(.pressable)
                }
            }
            .foregroundStyle(Theme.ink)
        }
        .preferredColorScheme(.light)
    }
}
