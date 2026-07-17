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
            output.append(contentsOf: Data("\u{1B}*b1030m".utf8))

            var block = Data()
            var lineCount = 0
            var reference = [UInt8](repeating: 0, count: page.bytesPerRow)
            for lineIndex in 0..<page.height {
                let start = lineIndex * page.bytesPerRow
                let end = start + page.bytesPerRow
                let line = [UInt8](page.data[start..<end])
                var encoded: [UInt8]

                if lineIndex % 128 == 0 {
                    appendBlock(&output, block: block, lineCount: lineCount)
                    block.removeAll(keepingCapacity: true)
                    lineCount = 0
                    encoded = encodeLine(line)
                } else {
                    encoded = encodeLine(line, reference: reference)
                    if block.count + encoded.count >= 16350 {
                        appendBlock(&output, block: block, lineCount: lineCount)
                        block.removeAll(keepingCapacity: true)
                        lineCount = 0
                        encoded = encodeLine(line)
                    }
                }

                block.append(contentsOf: encoded)
                lineCount += 1
                reference = line
            }
            if lineCount > 0 { appendBlock(&output, block: block, lineCount: lineCount) }
            output.append(contentsOf: Data("1030M".utf8))
            output.append(0x0C)
        }

        output.append(contentsOf: Data("\u{1B}%-12345X@PJL\n".utf8))
        output.append(contentsOf: Data("@PJL EOJ NAME=\"\(safe(jobName))\"\n".utf8))
        output.append(contentsOf: Data("\u{1B}%-12345X\n".utf8))
        return output
    }

    private static func encodeLine(_ line: [UInt8], reference: [UInt8]? = nil) -> [UInt8] {
        if line.allSatisfy({ $0 == 0 }) { return [0xFF] }
        guard let reference else {
            var output: [UInt8] = [1]
            writeSubstitute(offset: 0, bytes: line[...], to: &output)
            return output
        }

        precondition(line.count == reference.count)
        var end = line.count
        while end > 0, line[end - 1] == reference[end - 1] { end -= 1 }

        var output: [UInt8] = [0]
        var edits = 0
        var position = 0
        while position < end {
            var mismatch = position
            while mismatch < end, line[mismatch] == reference[mismatch] { mismatch += 1 }
            let offset = mismatch - position
            position = mismatch
            if position == end { break }

            edits += 1
            if edits == 254 {
                writeSubstitute(offset: offset, bytes: line[position..<end], to: &output)
                position = end
                break
            }

            let substituteCount = substituteLength(
                line: line,
                reference: reference,
                start: position,
                end: end
            )
            if substituteCount > 0 {
                writeSubstitute(
                    offset: offset,
                    bytes: line[position..<(position + substituteCount)],
                    to: &output
                )
                position += substituteCount
            } else {
                let repeatCount = repeatLength(line: line, start: position, end: end)
                writeRepeat(offset: offset, count: repeatCount, value: line[position], to: &output)
                position += repeatCount
            }
        }
        output[0] = UInt8(edits)
        return output
    }

    private static func appendBlock(_ output: inout Data, block: Data, lineCount: Int) {
        guard !block.isEmpty else { return }
        output.append(contentsOf: Data("\(block.count + 2)w".utf8))
        output.append(0)
        output.append(UInt8(clamping: lineCount))
        output.append(block)
    }

    private static func writeSubstitute(
        offset: Int,
        bytes: ArraySlice<UInt8>,
        to output: inout [UInt8]
    ) {
        precondition(offset >= 0 && !bytes.isEmpty)
        let count = bytes.count - 1
        output.append(UInt8((min(offset, 15) << 3) | min(count, 7)))
        writeOverflow(offset - 15, to: &output)
        writeOverflow(count - 7, to: &output)
        output.append(contentsOf: bytes)
    }

    private static func writeRepeat(
        offset: Int,
        count: Int,
        value: UInt8,
        to output: inout [UInt8]
    ) {
        precondition(offset >= 0 && count >= 2)
        let encodedCount = count - 2
        output.append(UInt8(0x80 | (min(offset, 3) << 5) | min(encodedCount, 31)))
        writeOverflow(offset - 3, to: &output)
        writeOverflow(encodedCount - 31, to: &output)
        output.append(value)
    }

    private static func repeatLength(line: [UInt8], start: Int, end: Int) -> Int {
        var next = start + 1
        while next < end, line[next] == line[start] { next += 1 }
        return next - start
    }

    private static func substituteLength(
        line: [UInt8],
        reference: [UInt8],
        start: Int,
        end: Int
    ) -> Int {
        guard start < end else { return 0 }
        var current = start
        var next = start + 1
        var previous = start
        while next < end {
            if line[current] == reference[current], line[next] == reference[next] {
                return current - start
            }
            if line[current] == line[next], line[current] == line[previous] {
                return previous - start
            }
            previous = current
            current = next
            next += 1
        }
        return end - start
    }

    private static func writeOverflow(_ value: Int, to output: inout [UInt8]) {
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
