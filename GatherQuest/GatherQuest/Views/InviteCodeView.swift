import SwiftUI

// ③ Invite code display: show code, tap to copy, proceed to profile entry.
struct InviteCodeView: View {
    @EnvironmentObject var app: AppState
    let groupId: String
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Text("グループ参加コード")
                .font(.largeTitle.bold())

            Button {
                UIPasteboard.general.string = code
                copied = true
            } label: {
                VStack(spacing: 8) {
                    Text(code)
                        .font(.system(size: 40, weight: .heavy, design: .monospaced))
                        .foregroundColor(.primary)
                    Text(copied ? "コピーしました ✓" : "コードをタッチしてコピー")
                        .font(.caption)
                        .foregroundColor(copied ? .green : .secondary)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(.systemGray5)))
            }
            .padding(.horizontal, 40)

            Spacer()

            Button {
                app.screen = .profileEntry(groupId: groupId)
            } label: {
                Text("グループ画面に移動")
                    .font(.headline).foregroundColor(.white)
                    .frame(width: 240, height: 56)
                    .background(Capsule().fill(Color.blue))
            }

            Spacer()
        }
        .padding()
    }
}
