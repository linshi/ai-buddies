import SwiftUI
import UsageCore

/// iOS settings screen (spec §5.3 / §8): plan, notifications, home default, appearance.
struct IOSSettingsView: View {
    @EnvironmentObject var model: IOSModel

    var body: some View {
        NavigationStack {
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
                }

                Section("通知") {
                    Toggle("接近上限提醒", isOn: Binding(
                        get: { model.settings.notificationsEnabled }, set: { model.settings.notificationsEnabled = $0 }))
                    if model.settings.notificationsEnabled {
                        HStack {
                            Text("阈值")
                            Slider(value: Binding(
                                get: { model.settings.notificationThreshold }, set: { model.settings.notificationThreshold = $0 }),
                                in: 50...95, step: 5)
                            Text("\(Int(model.settings.notificationThreshold))%").monospacedDigit().frame(width: 44)
                        }
                    }
                }

                Section("外观与首页") {
                    Picker("首页默认", selection: Binding(
                        get: { model.settings.homeDefaultToday }, set: { model.settings.homeDefaultToday = $0 })) {
                        Text("今日").tag(true); Text("本周").tag(false)
                    }
                    Picker("外观", selection: Binding(
                        get: { model.settings.appearance }, set: { model.settings.appearance = $0 })) {
                        ForEach(SettingsStore.Appearance.allCases) { Text($0.label).tag($0) }
                    }
                }

                Section {
                    Toggle("跨账号同步（公共数据库桥）", isOn: Binding(
                        get: { model.settings.usePublicDatabase }, set: { model.settings.usePublicDatabase = $0 }))
                    if let updated = model.lastUpdated {
                        LabeledContent("最后同步", value: updated.formatted(date: .abbreviated, time: .shortened))
                    }
                    Button("立即同步") { Task { await model.refresh() } }
                } header: {
                    Text("同步")
                } footer: {
                    Text("数据由 Mac 端发布到你的 iCloud，本机只读。Mac 与 iPhone 使用不同 Apple ID 时，两端都开启「跨账号同步」。")
                }
            }
            .navigationTitle("设置")
        }
    }
}
