import SwiftUI

struct PrintSettingsOverview: View {
    @Binding var pageRange: String
    @Binding var orientation: PrintOrientationOption
    @Binding var scaling: PrintScalingOption
    @Binding var quality: PrintQualityOption
    @Binding var copies: Int
    @Binding var duplex: Bool
    let pageCount: Int

    var body: some View {
        List {
            Section {
                NavigationLink {
                    PageSelectionSettings(pageRange: $pageRange, pageCount: pageCount)
                } label: {
                    settingsRow("页面", systemImage: "doc.on.doc", detail: pageSummary)
                }
                NavigationLink {
                    LayoutSettings(orientation: $orientation, scaling: $scaling)
                } label: {
                    settingsRow("版式", systemImage: "rectangle.on.rectangle", detail: "\(orientation.title) · \(scaling.title)")
                }
                NavigationLink {
                    QualitySettings(quality: $quality)
                } label: {
                    settingsRow("画质", systemImage: "sparkles", detail: "\(quality.title) · \(quality.dpi) dpi")
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
        pageRange.trimmingCharacters(in: .whitespaces).isEmpty ? "全部 \(pageCount) 页" : pageRange
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
    @Binding var pageRange: String
    let pageCount: Int

    var body: some View {
        Form {
            Section("页码范围（可选）") {
                TextField("留空打印全部，例如 1-3,5", text: $pageRange)
                    .keyboardType(.numbersAndPunctuation)
                Text("留空时打印全部 \(pageCount) 页；也可以使用逗号和连字符。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("页面")
    }
}

struct LayoutSettings: View {
    @Binding var orientation: PrintOrientationOption
    @Binding var scaling: PrintScalingOption

    var body: some View {
        List {
            Section("方向") {
                ForEach(PrintOrientationOption.allCases) { option in
                    selectionButton(
                        title: option.title,
                        detail: orientationDetail(option),
                        selected: orientation == option
                    ) { orientation = option }
                }
            }
            Section("缩放") {
                ForEach(PrintScalingOption.allCases) { option in
                    selectionButton(
                        title: option.title,
                        detail: scalingDetail(option),
                        selected: scaling == option
                    ) { scaling = option }
                }
            }
        }
        .navigationTitle("版式")
    }

    private func selectionButton(
        title: String,
        detail: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).foregroundStyle(.primary)
                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                if selected { Image(systemName: "checkmark").fontWeight(.semibold) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func orientationDetail(_ option: PrintOrientationOption) -> String {
        switch option {
        case .automatic: return "根据文档页面自动选择"
        case .portrait: return "纸张以纵向显示"
        case .landscape: return "纸张以横向显示"
        }
    }

    private func scalingDetail(_ option: PrintScalingOption) -> String {
        switch option {
        case .fit: return "完整内容缩放到可打印区域"
        case .actual: return "按文档原始尺寸输出"
        case .fill: return "填满纸张，边缘可能被裁切"
        }
    }
}

struct QualitySettings: View {
    @Binding var quality: PrintQualityOption

    var body: some View {
        List {
            Section {
                ForEach(PrintQualityOption.allCases) { option in
                    Button { quality = option } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(option.title).foregroundStyle(.primary)
                                Text(option.detail).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if quality == option { Image(systemName: "checkmark").fontWeight(.semibold) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if quality == .high {
                Section {
                    Text("1200 dpi 会显著增加渲染内存、任务大小和等待时间，建议仅用于细线或小字号文档。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("画质")
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
                if duplex { LabeledContent("翻页方向", value: "长边") }
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
