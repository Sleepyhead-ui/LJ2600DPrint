import Foundation

enum PageSelectionMode: String, CaseIterable, Identifiable {
    case all
    case custom
    var id: String { rawValue }
    var title: String { self == .all ? "全部页面" : "指定页码" }
}

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
