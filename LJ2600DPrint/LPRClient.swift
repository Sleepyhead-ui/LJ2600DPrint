import Foundation
import Network

enum LPRError: LocalizedError {
    case connectionFailed
    case serverRejected(String)
    case unexpectedReply

    var errorDescription: String? {
        switch self {
        case .connectionFailed: return "无法连接光猫的 LPR 服务"
        case .serverRejected(let message): return "LPR 服务拒绝任务：\(message)"
        case .unexpectedReply: return "LPR 服务返回了无法识别的响应"
        }
    }
}

final class LPRClient: @unchecked Sendable {
    private let host: String
    private let port: UInt16
    private let queue: String

    init(host: String, port: UInt16, queue: String) {
        self.host = host
        self.port = port
        self.queue = queue
    }

    func print(data: Data, jobName: String) async throws {
        guard !data.isEmpty else { throw LPRError.unexpectedReply }
        try await sendJob(jobName: jobName, dataLength: data.count) { connection in
            try await self.send(connection, data)
        }
    }

    func print(fileURL: URL, jobName: String) async throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let dataLength = (attributes[.size] as? NSNumber)?.intValue, dataLength > 0 else {
            throw LPRError.unexpectedReply
        }
        try await sendJob(jobName: jobName, dataLength: dataLength) { connection in
            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }
            while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
                try await self.send(connection, chunk)
            }
        }
    }

    private func sendJob(
        jobName: String,
        dataLength: Int,
        sendData: (NWConnection) async throws -> Void
    ) async throws {
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
        defer { connection.cancel() }
        try await connect(connection)

        try await send(connection, command(0x02, queue + "\n"))
        try await requireAck(connection)

        let hostName = "iphone"
        let safeName = jobName.replacingOccurrences(of: "\n", with: " " ).prefix(60)
        let controlName = "cfA001\(hostName)"
        let dataName = "dfA001\(hostName)"
        let control = Data("H\(hostName)\nP\(hostName)\nJ\(safeName)\nld\(dataName)\nU\(dataName)\nN\(safeName)\n".utf8)

        try await send(connection, command(0x02, "\(control.count) \(controlName)\n"))
        try await requireAck(connection)
        try await send(connection, control)
        try await send(connection, Data([0x00]))
        try await requireAck(connection)

        try await send(connection, command(0x03, "\(dataLength) \(dataName)\n"))
        try await requireAck(connection)
        try await sendData(connection)
        try await send(connection, Data([0x00]))
        try await requireAck(connection)
    }

    private func connect(_ connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var resumed = false
            connection.stateUpdateHandler = { state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    resumed = true
                    continuation.resume()
                case .failed, .cancelled:
                    resumed = true
                    continuation.resume(throwing: LPRError.connectionFailed)
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
        }
    }

    private func send(_ connection: NWConnection, _ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            })
        }
    }

    private func requireAck(_ connection: NWConnection) async throws {
        let byte = try await receiveByte(connection)
        guard byte == 0 else {
            throw LPRError.serverRejected(byte == 1 ? "权限或队列错误" : "错误码 \(byte)")
        }
    }

    private func receiveByte(_ connection: NWConnection) async throws -> UInt8 {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { data, _, _, error in
                if let error { continuation.resume(throwing: error) }
                else if let byte = data?.first { continuation.resume(returning: byte) }
                else { continuation.resume(throwing: LPRError.unexpectedReply) }
            }
        }
    }

    private func command(_ code: UInt8, _ text: String) -> Data {
        var data = Data([code])
        data.append(contentsOf: text.utf8)
        return data
    }
}
