import SwiftUI

struct PrintSettingsOverview: View {
    @Binding var pageMode: PageSelectionMode
    @Binding var pageRange: String
    @Binding var orientation: PrintOrientationOption
    @Binding var scaling: PrintScalingOption
    @Binding var copies: Int
    @Binding var duplex: Bool
    let pageCount: Int

    var body: some View {
        List {
            Section {
                NavigationLink {
                    PageSelectionSettings(pageMode: $pageMode, pageRange: $pageRange, pageCount: pageCount)
                } label: {
                    settingsRow("页面", systemImage: "doc.on.doc", detail: pageSummary)
                }
                NavigationLink {
                    LayoutSettings(orientation: $orientation, scaling: $scaling)
                } label: {
                    settingsRow("版式", systemImage: "rectangle.on.rectangle", detail: "\(orientation.title) · \(scaling.title)")
                }
                NavigationLink {
                    OutputSettings(copies: $copies, duplex: $duplex)
                } label: {
                    settingsRow("输出", systemImage: "printer", detail: "\(copies) 份 · \(duplex ? "双面" : "单面")")
                }
            }
        }
        .navigationTitle("打印设置")
    }

    private var pageSummary: String {
        pageMode == .all ? "全部 \(pageCount) 页" : (pageRange.isEmpty ? "尚未指定" : pageRange)
    }

    private func settingsRow(_ title: String, systemImage: String, detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage).frame(width: 24).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

struct PageSelectionSettings: View {
    @Binding var pageMode: PageSelectionMode
    @Binding var pageRange: String
    let pageCount: Int

    var body: some View {
        Form {
            Section {
                Picker("页面", selection: $pageMode) {
                    ForEach(PageSelectionMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            if pageMode == .custom {
                Section("页码范围") {
                    TextField("例如 1-3,5", text: $pageRange)
                        .keyboardType(.numbersAndPunctuation)
                    Text("文档共 \(pageCount) 页，可使用逗号和连字符。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("页面")
    }
}

struct LayoutSettings: View {
    @Binding var orientation: PrintOrientationOption
    @Binding var scaling: PrintScalingOption

    var body: some View {
        Form {
            Section("方向") {
                Picker("方向", selection: $orientation) {
                    ForEach(PrintOrientationOption.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("缩放") {
                Picker("缩放", selection: $scaling) {
                    ForEach(PrintScalingOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.inline)
            }
        }
        .navigationTitle("版式")
    }
}

struct OutputSettings: View {
    @Binding var copies: Int
    @Binding var duplex: Bool

    var body: some View {
        Form {
            Section("份数") {
                Stepper("\(copies) 份", value: $copies, in: 1...20)
            }
            Section("纸张正反面") {
                Toggle("双面打印", isOn: $duplex)
                if duplex {
                    LabeledContent("翻页方向", value: "长边")
                }
            }
        }
        .navigationTitle("输出")
    }
}

struct NetworkSettingsView: View {
    @Binding var gateway: String
    @Binding var queue: String

    var body: some View {
        Form {
            Section("光猫打印服务") {
                TextField("地址", text: $gateway)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                LabeledContent("端口", value: "515")
                TextField("LPR 队列", text: $queue)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .navigationTitle("打印服务")
    }
}
