import SwiftUI

// ① Start screen: app name, create-group button, invite-code entry.
struct StartView: View {
    @EnvironmentObject var app: AppState
    @State private var code = ""
    @State private var isJoining = false

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            Text("hayo")
                .font(.system(size: 44, weight: .heavy, design: .rounded))

            Button {
                app.screen = .createGroup
            } label: {
                Text("グループを作成")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(width: 240, height: 56)
                    .background(Capsule().fill(Color.blue))
            }

            VStack(spacing: 12) {
                Text("グループコード入力").font(.headline)
                TextField("XXXXXX", text: $code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.center)
                    .font(.title3.monospaced())
                    .padding()
                    .frame(width: 240)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray5)))

                Button {
                    join()
                } label: {
                    if isJoining {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.right")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                            .frame(width: 72, height: 44)
                            .background(Capsule().fill(code.count == 6 ? Color.blue : Color.gray))
                    }
                }
                .disabled(code.count != 6 || isJoining)
            }

            Spacer()
            Spacer()
        }
        .padding()
    }

    private func join() {
        isJoining = true
        Task {
            defer { isJoining = false }
            do {
                if let groupId = try await GroupRepository.shared.findGroup(byCode: code) {
                    app.screen = .profileEntry(groupId: groupId)
                } else {
                    app.errorMessage = "グループが見つかりません。コードを確認してください。"
                }
            } catch {
                app.errorMessage = error.localizedDescription
            }
        }
    }
}
