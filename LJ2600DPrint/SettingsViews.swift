import SwiftUI
import UniformTypeIdentifiers

struct PrintSettingsOverview: View {
    let documentURL: URL
    @Binding var pageRange: String
    @Binding var orientation: PrintOrientationOption
    @Binding var scaling: PrintScalingOption
    @Binding var quality: PrintQualityOption
    @Binding var copies: Int
    @Binding var duplex: Bool
    @Binding var contentMode: PrintContentMode
    @Binding var lightness: PrintLightnessOption
    @Binding var imageAdjustments: ImagePrintAdjustments
    @Binding var pagesPerSheet: PagesPerSheetOption
    @Binding var drawPageBorder: Bool
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
                    LayoutSettings(
                        orientation: $orientation,
                        scaling: $scaling,
                        pagesPerSheet: $pagesPerSheet,
                        drawPageBorder: $drawPageBorder
                    )
                } label: {
                    settingsRow(
                        "版式",
                        systemImage: "rectangle.on.rectangle",
                        detail: "\(orientation.title) · \(scaling.title) · \(pagesPerSheet.title)"
                    )
                }
                if isImage {
                    NavigationLink {
                        ImageAdjustmentSettings(
                            url: documentURL,
                            adjustments: $imageAdjustments,
                            orientation: orientation,
                            scaling: scaling,
                            contentMode: contentMode,
                            lightness: lightness
                        )
                    } label: {
                        settingsRow("图片调整", systemImage: "crop.rotate", detail: imageAdjustments.summary)
                    }
                }
                NavigationLink {
                    ContentModeSettings(
                        url: documentURL,
                        contentMode: $contentMode,
                        lightness: $lightness,
                        orientation: orientation,
                        scaling: scaling,
                        imageAdjustments: imageAdjustments
                    )
                } label: {
                    settingsRow(
                        "内容优化",
                        systemImage: "circle.lefthalf.filled",
                        detail: "\(contentMode.title) · \(lightness.title)"
                    )
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

    private var isImage: Bool {
        UTType(filenameExtension: documentURL.pathExtension)?.conforms(to: .image) == true
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

struct ImageAdjustmentSettings: View {
    let url: URL
    @Binding var adjustments: ImagePrintAdjustments
    let orientation: PrintOrientationOption
    let scaling: PrintScalingOption
    let contentMode: PrintContentMode
    let lightness: PrintLightnessOption

    var body: some View {
        List {
            Section {
                PagePaperView(
                    url: url,
                    pageNumber: 1,
                    orientation: orientation,
                    scaling: scaling,
                    contentMode: contentMode,
                    lightness: lightness,
                    imageAdjustments: adjustments
                )
                .frame(maxWidth: .infinity)
                .frame(height: 250)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section("旋转") {
                HStack {
                    Spacer()
                    rotationButton(systemImage: "rotate.left", label: "向左旋转") {
                        adjustments.rotation = adjustments.rotation.rotatedCounterclockwise()
                    }
                    Spacer()
                    Text(adjustments.rotation.title)
                        .font(.body.monospacedDigit().weight(.medium))
                        .frame(width: 64)
                    Spacer()
                    rotationButton(systemImage: "rotate.right", label: "向右旋转") {
                        adjustments.rotation = adjustments.rotation.rotatedClockwise()
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            Section("裁剪") {
                Picker("居中裁剪比例", selection: $adjustments.crop) {
                    ForEach(ImageCropOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("页边距") {
                HStack(spacing: 12) {
                    Slider(value: $adjustments.marginMillimeters, in: 0...20, step: 2)
                    Text("\(Int(adjustments.marginMillimeters)) mm")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .trailing)
                }
            }
        }
        .navigationTitle("图片调整")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    adjustments = .none
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .disabled(adjustments == .none)
                .accessibilityLabel("还原图片调整")
            }
        }
    }

    private func rotationButton(
        systemImage: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .accessibilityLabel(label)
    }
}

struct ContentModeSettings: View {
    let url: URL
    @Binding var contentMode: PrintContentMode
    @Binding var lightness: PrintLightnessOption
    let orientation: PrintOrientationOption
    let scaling: PrintScalingOption
    let imageAdjustments: ImagePrintAdjustments

    var body: some View {
        List {
            Section {
                PagePaperView(
                    url: url,
                    pageNumber: 1,
                    orientation: orientation,
                    scaling: scaling,
                    contentMode: contentMode,
                    lightness: lightness,
                    imageAdjustments: imageAdjustments
                )
                .frame(maxWidth: .infinity)
                .frame(height: 230)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section {
                ForEach(PrintContentMode.allCases) { option in
                    Button { contentMode = option } label: {
                        HStack(spacing: 14) {
                            Image(systemName: option.systemImage)
                                .frame(width: 28)
                                .foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(option.title).foregroundStyle(.primary)
                                Text(option.detail)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if contentMode == option {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("打印深浅") {
                HStack(spacing: 12) {
                    Image(systemName: "circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: lightnessValue, in: -2...2, step: 1)
                    Image(systemName: "circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(lightness.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
            }
        }
        .navigationTitle("内容优化")
    }

    private var lightnessValue: Binding<Double> {
        Binding(
            get: { Double(lightness.rawValue) },
            set: { lightness = PrintLightnessOption(rawValue: Int($0.rounded())) ?? .normal }
        )
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
    @Binding var pagesPerSheet: PagesPerSheetOption
    @Binding var drawPageBorder: Bool

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
            Section {
                Picker("每张纸页数", selection: pagesPerSheetSelection) {
                    ForEach(PagesPerSheetOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                if pagesPerSheet != .one {
                    Toggle("显示页面边框", isOn: $drawPageBorder)
                }
            } header: {
                Text("多合一")
            } footer: {
                if pagesPerSheet == .one {
                    Text("每个文档页面输出为一个纸面。")
                } else {
                    Text("页面按从左到右、从上到下排列；最后不足的位置保持空白。")
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
        case .automatic:
            return pagesPerSheet == .one ? "根据文档页面自动选择" : "2 合 1 使用横向，4 合 1 使用纵向"
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

    private var pagesPerSheetSelection: Binding<PagesPerSheetOption> {
        Binding(
            get: { pagesPerSheet },
            set: { option in
                pagesPerSheet = option
                if option != .one && scaling == .actual { scaling = .fit }
            }
        )
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
    @Binding var gatewayMAC: String
    @StateObject private var service = GatewayServiceController()

    var body: some View {
        Form {
            Section("连接") {
                TextField("地址", text: $gateway)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                LabeledContent("端口", value: "515")
                TextField("LPR 队列", text: $queue)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section("服务状态") {
                HStack(spacing: 12) {
                    Image(systemName: stateIcon)
                        .foregroundStyle(stateColor)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(stateTitle)
                            .font(.body.weight(.medium))
                        Text(service.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if service.isWorking {
                        ProgressView()
                    }
                }
                .padding(.vertical, 4)

                Button {
                    Task { await service.check(gateway: gateway) }
                } label: {
                    Label("重新检查", systemImage: "arrow.clockwise")
                }
                .disabled(service.isWorking)
            }

            Section {
                TextField("AA:BB:CC:DD:EE:FF", text: $gatewayMAC)
                    .keyboardType(.asciiCapable)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .onSubmit {
                        gatewayMAC = GatewayRecoveryClient.formattedMAC(gatewayMAC)
                    }

                Button {
                    gatewayMAC = GatewayRecoveryClient.formattedMAC(gatewayMAC)
                    Task {
                        await service.recover(gateway: gateway, macAddress: gatewayMAC)
                    }
                } label: {
                    Label("恢复打印服务", systemImage: "wrench.and.screwdriver")
                }
                .disabled(service.isWorking || service.state == .online)
            } header: {
                Text("光猫维护")
            } footer: {
                Text("MAC 地址只保存在本机。恢复时会临时开启 Telnet，确认 USB 打印机后启动服务，并在完成后关闭 Telnet。")
            }
        }
        .navigationTitle("打印服务")
        .task {
            await service.check(gateway: gateway)
        }
    }

    private var stateTitle: String {
        switch service.state {
        case .unknown: return "尚未检查"
        case .checking: return "正在检查"
        case .online: return "服务在线"
        case .offline: return "服务离线"
        case .recovering: return "正在恢复"
        case .failed: return "恢复失败"
        }
    }

    private var stateIcon: String {
        switch service.state {
        case .online: return "checkmark.circle.fill"
        case .offline, .failed: return "exclamationmark.triangle.fill"
        case .checking, .recovering: return "clock.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    private var stateColor: Color {
        switch service.state {
        case .online: return .green
        case .offline, .failed: return .orange
        default: return .secondary
        }
    }
}
