import SwiftUI

struct AccountRoute: Hashable {}

/// Plan → Backup & sync. Sign in to the Daily Budget server so your data is saved online too.
struct AccountView: View {
    @Environment(SyncManager.self) private var sync
    @State private var email = ""
    @State private var password = ""
    @State private var signingIn = false
    @State private var error: String?
    @State private var confirmSignOut = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ScreenHeader(caption: "Account", title: "Backup & sync")
                if let session = sync.session {
                    signedInCard(session)
                } else {
                    signInCard
                }
                if let notice = sync.notice {
                    Label(notice, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.warn)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .glassCard(radius: 18)
                }
                explainer
            }
            .padding(.horizontal, 18)
            .padding(.top, 4)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(GlowBackground())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .confirmationDialog("Sign out?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { sync.signOut() }
        } message: {
            Text("Your data stays on this phone. Changes stop backing up until you sign in again.")
        }
    }

    // MARK: Signed out

    private var signInCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Sign in to back up", systemImage: "icloud.and.arrow.up.fill")
                .font(.headline)
                .labelStyle(TintedIconLabelStyle(color: Theme.sky))

            VStack(spacing: 0) {
                TextField("Email", text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .frame(height: 50)
                Divider().overlay(Color.white.opacity(0.16))
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .frame(height: 50)
                    .onSubmit(signIn)
            }
            .padding(.horizontal, 16)
            .glassCard(radius: 20)

            if let error {
                Text(error).font(.footnote).foregroundStyle(Theme.warn)
            }

            Button(action: signIn) {
                HStack(spacing: 8) {
                    if signingIn { ProgressView().tint(Theme.base) }
                    Text(signingIn ? "Signing in…" : "Sign in")
                }
                .font(.headline)
                .foregroundStyle(Theme.base)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(Theme.accentGradient, in: Capsule())
                .opacity(canSignIn ? 1 : 0.45)
            }
            .buttonStyle(.pressable)
            .disabled(!canSignIn)

            if signingIn {
                Text("The free server may take up to a minute to wake up.")
                    .font(.caption).foregroundStyle(Theme.secondary)
            }
        }
        .padding(16)
        .glassCard(radius: 26)
    }

    private var canSignIn: Bool {
        !signingIn && email.contains("@") && password.count >= 10
    }

    private func signIn() {
        guard canSignIn else { return }
        signingIn = true
        error = nil
        Task {
            do {
                try await sync.signIn(email: email, password: password)
                password = ""
            } catch {
                self.error = error.localizedDescription
            }
            signingIn = false
        }
    }

    // MARK: Signed in

    private func signedInCard(_ session: AccountSession) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: statusSymbol)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(statusColor)
                    .symbolEffect(.pulse, isActive: sync.status == .syncing)
                    .frame(width: 44, height: 44)
                    .background(statusColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle).font(.headline)
                    Text(statusDetail).font(.caption).foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 0)
            }

            Divider().overlay(Color.white.opacity(0.14))

            row("Account", session.email)
            row("Waiting to upload", sync.pending == 0 ? "Nothing" : "\(sync.pending)")

            HStack(spacing: 10) {
                Button {
                    Task { await sync.syncNow() }
                } label: {
                    Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.base)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Theme.accentGradient, in: Capsule())
                }
                .buttonStyle(.pressable)
                .disabled(sync.status == .syncing)

                Button { confirmSignOut = true } label: {
                    Text("Sign out")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .glassCard(radius: 23)
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(16)
        .glassCard(radius: 26)
    }

    private var statusSymbol: String {
        switch sync.status {
        case .syncing: return "arrow.triangle.2.circlepath"
        case .failed: return "icloud.slash.fill"
        default: return "checkmark.icloud.fill"
        }
    }

    private var statusColor: Color {
        if case .failed = sync.status { return Theme.warn }
        return Theme.mint
    }

    private var statusTitle: String {
        switch sync.status {
        case .syncing: return String(localized: "Syncing…")
        case .failed: return String(localized: "Not synced")
        default: return sync.pending > 0 ? String(localized: "Changes waiting") : String(localized: "Backed up")
        }
    }

    private var statusDetail: String {
        if case .failed(let message) = sync.status { return message }
        return SyncStatusText.lastSynced(sync.lastSyncedAt)
    }

    private func row(_ title: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Theme.secondary)
            Spacer()
            Text(value).lineLimit(1).truncationMode(.middle)
        }
        .font(.subheadline)
    }

    private var explainer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How it works").font(.subheadline.weight(.semibold))
            Text("Everything is still saved on this phone first, so the app works without internet. When you're signed in, changes are copied to your server a few seconds later, and when you open or leave the app.")
            Text("If you ever reinstall the app, sign in again and your plan, bills and expenses come back.")
        }
        .font(.footnote)
        .foregroundStyle(Theme.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassCard(radius: 18)
    }
}

/// The small "Backup & sync" row on the Plan screen.
struct SyncCard: View {
    @Environment(SyncManager.self) private var sync

    var body: some View {
        NavigationLink(value: AccountRoute()) {
            HStack(spacing: 12) {
                Image(systemName: sync.isSignedIn ? "checkmark.icloud.fill" : "icloud.slash")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(sync.isSignedIn ? Theme.mint : Theme.secondary)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Backup & sync").font(.subheadline.weight(.semibold))
                    Text(subtitle).font(.caption).foregroundStyle(Theme.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.secondary)
            }
            .padding(14)
            .glassCard(radius: 22)
        }
        .buttonStyle(.pressable)
    }

    private var subtitle: String {
        guard sync.isSignedIn else { return String(localized: "Off · sign in to back up your data") }
        switch sync.status {
        case .syncing: return String(localized: "Syncing…")
        case .failed: return String(localized: "Not synced · tap for details")
        default: 
            let last = SyncStatusText.lastSynced(sync.lastSyncedAt)
            return sync.pending > 0 ? last + " · " + String(localized: "\(sync.pending) waiting") : last
        }
    }
}

enum SyncStatusText {
    static func lastSynced(_ date: Date?, now: Date = .now) -> String {
        guard let date else { return String(localized: "Not synced yet") }
        if now.timeIntervalSince(date) < 60 { return String(localized: "Synced just now") }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        let ago = f.localizedString(for: date, relativeTo: now)
        return String(localized: "Synced \(ago)")
    }
}

struct TintedIconLabelStyle: LabelStyle {
    var color: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon.foregroundStyle(color)
            configuration.title
        }
    }
}
