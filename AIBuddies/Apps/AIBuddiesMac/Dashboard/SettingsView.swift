import SwiftUI
import UsageCore

/// Settings pane (spec §8).
struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section("套餐") {
                Picker("Claude 套餐", selection: Binding(
                    get: { model.settings.claudePlan }, set: { model.settings.claudePlan = $0 })) {
                    ForEach(SettingsStore.ClaudePlan.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Codex 套餐", selection: Binding(
                    get: { model.settings.codexPlan }, set: { model.settings.codexPlan = $0 })) {
                    ForEach(SettingsStore.CodexPlan.allCases) { Text($0.rawValue).tag($0) }
                }
                HStack {
                    Text("月付价 (USD)")
                    Spacer()
                    TextField("月付价", value: Binding(
                        get: { model.settings.planPriceUSD }, set: { model.settings.planPriceUSD = $0 }),
                        format: .number)
                        .frame(width: 90).multilineTextAlignment(.trailing)
                }
            }

            Section("显示") {
                Picker("菜单栏显示", selection: Binding(
                    get: { model.settings.menuBarDisplay }, set: { model.settings.menuBarDisplay = $0 })) {
                    ForEach(SettingsStore.MenuBarDisplay.allCases) { Text($0.label).tag($0) }
                }
                Picker("刷新间隔", selection: Binding(
                    get: { model.settings.refreshInterval }, set: { model.settings.refreshInterval = $0 })) {
                    ForEach(SettingsStore.RefreshInterval.allCases) { Text($0.label).tag($0) }
                }
                Picker("外观", selection: Binding(
                    get: { model.settings.appearance }, set: { model.settings.appearance = $0 })) {
                    ForEach(SettingsStore.Appearance.allCases) { Text($0.label).tag($0) }
                }
            }

            Section("通知") {
                Toggle("接近上限提醒", isOn: Binding(
                    get: { model.settings.notificationsEnabled }, set: { model.settings.notificationsEnabled = $0 }))
                HStack {
                    Text("阈值")
                    Slider(value: Binding(
                        get: { model.settings.notificationThreshold }, set: { model.settings.notificationThreshold = $0 }),
                        in: 50...95, step: 5)
                    Text("\(Int(model.settings.notificationThreshold))%").monospacedDigit().frame(width: 44)
                }
                .disabled(!model.settings.notificationsEnabled)
            }

            Section("隐私 (iOS 同步)") {
                Toggle("项目名脱敏（哈希）", isOn: Binding(
                    get: { model.settings.hashProjectNames }, set: { model.settings.hashProjectNames = $0 }))
                Toggle("跨账号同步（公共数据库桥）", isOn: Binding(
                    get: { model.settings.usePublicDatabase }, set: { model.settings.usePublicDatabase = $0 }))
                Text("当 Mac 与 iPhone 使用不同 Apple ID 时开启；两端都需开启。会改用容器的公共数据库（私密性弱于私有库）。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("数据访问") {
                ForEach(FolderAccess.Slot.allCases, id: \.self) { slot in
                    HStack {
                        Image(systemName: model.folders.hasAccess(slot) ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(model.folders.hasAccess(slot) ? .green : .secondary)
                        Text(slot.displayName)
                        Spacer()
                        Button("授权") { model.grantAccess(slot) }.controlSize(.small)
                    }
                }
                Button("重置所有授权", role: .destructive) { model.resetAccess() }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("设置")
    }
}
