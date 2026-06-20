import SwiftUI

/// Shown when folder access has not been granted (spec §10 empty/guide state).
struct OnboardingView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("欢迎使用 AI Buddies", systemImage: "hand.wave.fill")
                .font(.headline)
            Text("AI Buddies 只读取本地 Claude / Codex 的用量日志（绝不联网上传代码或对话）。请授权这两个目录：")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(FolderAccess.Slot.allCases, id: \.self) { slot in
                grantRow(slot)
            }

            Text("提示：先照常用 `claude` 与 `codex` 两个命令行登录使用，AI Buddies 读取它们写下的产物。")
                .font(.caption).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func grantRow(_ slot: FolderAccess.Slot) -> some View {
        let granted = model.folders.hasAccess(slot)
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? .green : .secondary)
            Text(slot.displayName)
            Spacer()
            Button(granted ? "重新授权" : "授权") {
                model.grantAccess(slot)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }
}
