import SwiftUI
import Auth

struct SettingsScreen: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var workspace: WorkspaceStore

    var body: some View {
        NavigationStack {
            Form {
                if let ws = workspace.current {
                    Section("Workspace") {
                        LabeledContent("Name", value: ws.name)
                        LabeledContent("Invite code") {
                            HStack {
                                Text(ws.invite_code).font(.headline.monospaced())
                                Button {
                                    UIPasteboard.general.string = ws.invite_code
                                } label: { Image(systemName: "doc.on.doc") }
                            }
                        }
                        if let link = inviteLink(for: ws) {
                            ShareLink(item: link,
                                      subject: Text("Join my HomeHunt workspace"),
                                      message: Text("Tap to join \"\(ws.name)\" on HomeHunt.")) {
                                Label("Share invite link", systemImage: "square.and.arrow.up")
                            }
                            Button {
                                UIPasteboard.general.string = link.absoluteString
                            } label: {
                                Label("Copy invite link", systemImage: "link")
                            }
                        }
                        Text("Tapping the link on a phone that has HomeHunt installed will sign them in and add them to this workspace automatically.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("Account") {
                    if let email = auth.session?.user.email {
                        LabeledContent("Email", value: email)
                    }
                    Button("Sign out", role: .destructive) {
                        Task { await auth.signOut() }
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func inviteLink(for ws: Workspace) -> URL? {
        var comps = URLComponents()
        comps.scheme = "homehunt"
        comps.host = "join"
        comps.queryItems = [URLQueryItem(name: "code", value: ws.invite_code)]
        return comps.url
    }
}
