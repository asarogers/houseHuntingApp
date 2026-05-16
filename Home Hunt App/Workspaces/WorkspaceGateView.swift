import SwiftUI

struct WorkspaceGateView: View {
    @EnvironmentObject var workspace: WorkspaceStore
    @EnvironmentObject var auth: AuthStore
    @State private var mode: Mode = .choose
    @State private var name = ""
    @State private var code = ""

    enum Mode { case choose, create, join }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("Set up your workspace").font(.title2).bold()

            switch mode {
            case .choose:
                Button("Create a new workspace") { mode = .create }
                    .buttonStyle(.borderedProminent)
                Button("Join with an invite code") { mode = .join }
                    .buttonStyle(.bordered)

            case .create:
                TextField("Workspace name (e.g., \"Our home search\")", text: $name)
                    .padding().background(.thinMaterial, in: .rect(cornerRadius: 12))
                Button {
                    Task { await workspace.create(name: name) }
                } label: {
                    Text(workspace.loading ? "Creating…" : "Create")
                        .frame(maxWidth: .infinity).padding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || workspace.loading)
                Button("Back") { mode = .choose }.font(.footnote)

            case .join:
                TextField("Invite code", text: $code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding().background(.thinMaterial, in: .rect(cornerRadius: 12))
                Button {
                    Task { await workspace.join(code: code) }
                } label: {
                    Text(workspace.loading ? "Joining…" : "Join")
                        .frame(maxWidth: .infinity).padding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(code.isEmpty || workspace.loading)
                Button("Back") { mode = .choose }.font(.footnote)
            }

            if let err = workspace.error {
                Text(err).font(.footnote).foregroundStyle(.red)
            }
            Spacer()
            Button("Sign out") { Task { await auth.signOut() } }
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding()
    }
}
