import Foundation

enum PrintOrientationOption: String, CaseIterable, Identifiable {
    case automatic
    case portrait
    case landscape
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: return "自动"
        case .portrait: return "纵向"
        case .landscape: return "横向"
        }
    }
}

enum PrintQualityOption: String, CaseIterable, Identifiable {
    case economy
    case standard
    case high
    var id: String { rawValue }
    var dpi: Int {
        switch self {
        case .economy: return 300
        case .standard: return 600
        case .high: return 1200
        }
    }
    var title: String {
        switch self {
        case .economy: return "省墨"
        case .standard: return "标准"
        case .high: return "高质量"
        }
    }
    var detail: String {
        switch self {
        case .economy: return "300 dpi · 速度快，适合草稿"
        case .standard: return "600 dpi · 日常文档推荐"
        case .high: return "1200 dpi · 细节更清晰，处理较慢"
        }
    }
}

enum PrintContentMode: String, CaseIterable, Identifiable {
    case text
    case graphics
    case photo

    var id: String { rawValue }
    var title: String {
        switch self {
        case .text: return "文字"
        case .graphics: return "图形"
        case .photo: return "图片"
        }
    }
    var detail: String {
        switch self {
        case .text: return "文字和细线，边缘清晰"
        case .graphics: return "图表、截图和混合内容"
        case .photo: return "照片和渐变，保留明暗层次"
        }
    }
    var systemImage: String {
        switch self {
        case .text: return "textformat"
        case .graphics: return "chart.bar.xaxis"
        case .photo: return "photo"
        }
    }
    var previewContrast: Double {
        switch self {
        case .text: return 2.2
        case .graphics: return 1.15
        case .photo: return 0.85
        }
    }
    var previewBrightness: Double {
        switch self {
        case .text: return 0
        case .graphics: return 0.07
        case .photo: return 0.11
        }
    }
}

enum PrintLightnessOption: Int, CaseIterable, Identifiable {
    case darkest = -2
    case dark = -1
    case normal = 0
    case light = 1
    case lightest = 2

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .darkest: return "最深"
        case .dark: return "较深"
        case .normal: return "标准"
        case .light: return "较浅"
        case .lightest: return "最浅"
        }
    }
    var inkScale: Double {
        switch self {
        case .darkest: return 1.20
        case .dark: return 1.05
        case .normal: return 0.90
        case .light: return 0.72
        case .lightest: return 0.55
        }
    }
    var previewBrightness: Double {
        Double(rawValue) * 0.04
    }
}

enum PrintScalingOption: String, CaseIterable, Identifiable {
    case fit
    case actual
    case fill
    var id: String { rawValue }
    var title: String {
        switch self {
        case .fit: return "适合页面"
        case .actual: return "实际大小"
        case .fill: return "填满页面"
        }
    }
}

enum PageRangeParser {
    static func parse(_ text: String, pageCount: Int) throws -> [Int] {
        let trimmed = text.replacingOccurrences(of: " ", with: "")
        guard !trimmed.isEmpty else { throw PageRangeError.empty }
        var result = Set<Int>()
        for component in trimmed.split(separator: ",") {
            if component.contains("-") {
                let bounds = component.split(separator: "-", omittingEmptySubsequences: false)
                guard bounds.count == 2,
                      let lower = Int(bounds[0]), let upper = Int(bounds[1]),
                      lower > 0, upper >= lower else { throw PageRangeError.invalid }
                for page in lower...upper { result.insert(page) }
            } else if let page = Int(component), page > 0 {
                result.insert(page)
            } else {
                throw PageRangeError.invalid
            }
        }
        guard !result.isEmpty else { throw PageRangeError.empty }
        guard result.allSatisfy({ $0 <= pageCount }) else {
            throw PageRangeError.outOfBounds(pageCount)
        }
        return result.sorted()
    }

    enum PageRangeError: LocalizedError {
        case empty
        case invalid
        case outOfBounds(Int)
        var errorDescription: String? {
            switch self {
            case .empty: return "请输入页码范围"
            case .invalid: return "页码格式不正确，例如 1-3,5"
            case .outOfBounds(let count): return "页码超出文档范围（共 \(count) 页）"
            }
        }
    }
}
