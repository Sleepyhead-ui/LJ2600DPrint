import Foundation

/// Minimal HBP encoder derived from the public brlaser line/block format.
/// The project remains experimental until a real LJ2600D job is verified.
enum BrLaserEncoder {
    static func encode(pages: [RasterPage], jobName: String) throws -> Data {
        guard !pages.isEmpty else { throw EncoderError.noPages }
        var output = Data("\u{1B}%-12345X@PJL \n".utf8)
        output.append(contentsOf: Data("@PJL JOB NAME=\"\(safe(jobName))\"\n".utf8))
        output.append(contentsOf: Data("@PJL SET ECONOMODE=OFF\n".utf8))
        output.append(contentsOf: Data("@PJL SET MEDIATYPE=REGULAR\n".utf8))
        output.append(contentsOf: Data("@PJL SET RESOLUTION=600\n".utf8))
        output.append(contentsOf: Data("@PJL ENTER LANGUAGE=PCL\n".utf8))

        for page in pages {
            guard page.bytesPerRow > 0, page.height > 0 else { continue }
            output.append(contentsOf: Data("\u{1B}&u600D".utf8))
            output.append(contentsOf: Data("\u{1B}*t600R".utf8))
            output.append(contentsOf: Data("\u{1B}&n8WdRegular".utf8))
            output.append(contentsOf: Data("\u{1B}&l7H".utf8))
            output.append(contentsOf: Data("\u{1B}&l0S\u{1B}&l1X\u{1B}&l0O".utf8))
            output.append(contentsOf: Data("\u{1B}&l4096a26a6d1E".utf8))
            output.append(contentsOf: Data("\u{1B}&l0U\u{1B}&l0Z".utf8))
            output.append(contentsOf: Data("\u{1B}*p0X\u{1B}*p0Y".utf8))
            output.append(contentsOf: Data("\u{1B}*b1030M".utf8))

            var block = Data()
            var lineCount = 0
            for lineIndex in 0..<page.height {
                let start = lineIndex * page.bytesPerRow
                let end = start + page.bytesPerRow
                let line = page.data.subdata(in: start..<end)
                // Full-line encoding is intentionally used first; it is easier to
                // validate against the printer than delta compression.
                let encoded = encodeLine(line)
                if lineCount == 128 || block.count + encoded.count >= 16350 {
                    appendBlock(&output, block: block, lineCount: lineCount)
                    block.removeAll(keepingCapacity: true)
                    lineCount = 0
                }
                block.append(encoded)
                lineCount += 1
            }
            if lineCount > 0 { appendBlock(&output, block: block, lineCount: lineCount) }
            output.append(0x0C)
        }

        output.append(contentsOf: Data("\u{1B}%-12345X@PJL\n".utf8))
        output.append(contentsOf: Data("@PJL EOJ NAME=\"\(safe(jobName))\"\n".utf8))
        output.append(contentsOf: Data("\u{1B}%-12345X\n".utf8))
        return output
    }

    private static func encodeLine(_ line: Data) -> Data {
        if line.allSatisfy({ $0 == 0 }) { return Data([0xFF]) }
        var result = Data([1])
        // Substitute command: offset 0, count field is min(line.count - 1, 7).
        result.append(0x07)
        writeOverflow(line.count - 8, to: &result)
        result.append(line)
        return result
    }

    private static func appendBlock(_ output: inout Data, block: Data, lineCount: Int) {
        guard !block.isEmpty else { return }
        output.append(contentsOf: Data("\u{1B}*b\(block.count + 2)W".utf8))
        output.append(0)
        output.append(UInt8(clamping: lineCount))
        output.append(block)
    }

    private static func writeOverflow(_ value: Int, to output: inout Data) {
        guard value >= 0 else { return }
        if value < 255 {
            output.append(UInt8(value))
        } else {
            output.append(contentsOf: repeatElement(UInt8(255), count: value / 255))
            output.append(UInt8(value % 255))
        }
    }

    private static func safe(_ value: String) -> String {
        let cleaned = value.unicodeScalars.map { scalar -> String in
            let code = scalar.value
            if code >= 32, code < 127, code != 34, code != 92 {
                return String(scalar)
            }
            return " "
        }.joined()
        return String(cleaned.prefix(79))
    }

    enum EncoderError: LocalizedError {
        case noPages
        var errorDescription: String? { "没有可打印的页面" }
    }
}
