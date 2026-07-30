import Foundation
import Network

enum GatewayServiceState: Equatable {
    case unknown
    case checking
    case online
    case offline
    case recovering
    case failed
}

enum GatewayRecoveryError: LocalizedError {
    case invalidGateway
    case invalidMAC
    case telnetControlFailed
    case telnetConnectionFailed
    case telnetLoginFailed
    case printerNotConnected
    case serviceDidNotStart

    var errorDescription: String? {
        switch self {
        case .invalidGateway: return "光猫地址格式不正确"
        case .invalidMAC: return "请输入光猫背面标签上的完整 MAC 地址"
        case .telnetControlFailed: return "光猫未能开启维护通道"
        case .telnetConnectionFailed: return "无法连接光猫维护通道"
        case .telnetLoginFailed: return "光猫维护通道登录失败"
        case .printerNotConnected: return "光猫没有识别到 USB 打印机"
        case .serviceDidNotStart: return "打印服务启动后仍无法连接"
        }
    }
}

@MainActor
final class GatewayServiceController: ObservableObject {
    @Published private(set) var state: GatewayServiceState = .unknown
    @Published private(set) var detail = "尚未检查"
    @Published private(set) var isWorking = false

    func check(gateway: String) async {
        guard !isWorking else { return }
        isWorking = true
        state = .checking
        detail = "正在连接打印服务…"
        let online = await GatewayRecoveryClient.isPortOpen(
            host: gateway.trimmingCharacters(in: .whitespacesAndNewlines),
            port: 515
        )
        state = online ? .online : .offline
        detail = online ? "打印服务在线，可以发送任务" : "打印服务未响应，可以尝试恢复"
        isWorking = false
    }

    func recover(gateway: String, macAddress: String) async {
        guard !isWorking else { return }
        isWorking = true
        state = .recovering
        detail = "准备恢复…"

        do {
            try await GatewayRecoveryClient.recover(
                host: gateway.trimmingCharacters(in: .whitespacesAndNewlines),
                macAddress: macAddress
            ) { [weak self] message in
                Task { @MainActor in self?.detail = message }
            }
            state = .online
            detail = "打印服务已恢复，可以发送任务"
        } catch {
            state = .failed
            detail = error.localizedDescription
        }
        isWorking = false
    }
}

enum GatewayRecoveryClient {
    static func normalizedMAC(_ value: String) -> String? {
        let hex = value.uppercased().filter { $0.isHexDigit }
        guard hex.count == 12 else { return nil }
        return hex
    }

    static func formattedMAC(_ value: String) -> String {
        guard let hex = normalizedMAC(value) else { return value }
        return stride(from: 0, to: 12, by: 2)
            .map { offset in
                let start = hex.index(hex.startIndex, offsetBy: offset)
                let end = hex.index(start, offsetBy: 2)
                return String(hex[start..<end])
            }
            .joined(separator: ":")
    }

    static func isPortOpen(host: String, port: UInt16) async -> Bool {
        guard isValidIPv4(host), let endpointPort = NWEndpoint.Port(rawValue: port) else {
            return false
        }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: .tcp)
        return await withCheckedContinuation { continuation in
            let gate = OneShot<Bool>()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if gate.finish(true, continuation: continuation) { connection.cancel() }
                case .failed, .cancelled:
                    _ = gate.finish(false, continuation: continuation)
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 2) {
                if gate.finish(false, continuation: continuation) { connection.cancel() }
            }
        }
    }

    static func recover(
        host: String,
        macAddress: String,
        progress: @escaping @Sendable (String) -> Void
    ) async throws {
        guard isValidIPv4(host) else { throw GatewayRecoveryError.invalidGateway }
        guard let mac = normalizedMAC(macAddress) else { throw GatewayRecoveryError.invalidMAC }

        progress("检查打印服务…")
        if await isPortOpen(host: host, port: 515) { return }

        let telnetWasOpen = await isPortOpen(host: host, port: 23)
        if !telnetWasOpen {
            progress("正在开启临时维护通道…")
            try await setTelnet(enabled: true, host: host, mac: mac)
            guard await isPortOpen(host: host, port: 23) else {
                try? await setTelnet(enabled: false, host: host, mac: mac)
                throw GatewayRecoveryError.telnetControlFailed
            }
        }

        do {
            progress("正在检查 USB 打印机…")
            try await runRecoveryCommand(host: host, mac: mac)
            progress("正在验证打印服务…")
            guard await isPortOpen(host: host, port: 515) else {
                throw GatewayRecoveryError.serviceDidNotStart
            }
            if !telnetWasOpen {
                progress("正在关闭临时维护通道…")
                try? await setTelnet(enabled: false, host: host, mac: mac)
            }
        } catch {
            if !telnetWasOpen {
                try? await setTelnet(enabled: false, host: host, mac: mac)
            }
            throw error
        }
    }

    private static func setTelnet(enabled: Bool, host: String, mac: String) async throws {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.path = "/cgi-bin/telnetenable.cgi"
        components.queryItems = [
            URLQueryItem(name: "telnetenable", value: enabled ? "1" : "0"),
            URLQueryItem(name: "key", value: mac)
        ]
        guard let url = components.url else { throw GatewayRecoveryError.invalidGateway }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GatewayRecoveryError.telnetControlFailed
        }
        let text = String(decoding: data, as: UTF8.self)
        guard text.localizedCaseInsensitiveContains("telnet") else {
            throw GatewayRecoveryError.telnetControlFailed
        }
    }

    private static func runRecoveryCommand(host: String, mac: String) async throws {
        let session = TelnetSession(host: host)
        defer { session.close() }
        do {
            try await session.connect()
            _ = try await session.receive(until: ["login:"])
            try await session.sendLine("admin")
            _ = try await session.receive(until: ["Password:"])
            try await session.sendLine("Fh@" + String(mac.suffix(6)))
            let login = try await session.receive(until: ["#", "Login incorrect"])
            guard !login.localizedCaseInsensitiveContains("Login incorrect") else {
                throw GatewayRecoveryError.telnetLoginFailed
            }

            try await session.sendLine("stty -echo")
            _ = try? await session.receive(until: ["#"], timeout: 2)
            try await session.sendLine(recoveryShellCommand(host: host))
            let result = try await session.receive(until: ["__LJ_DONE__"], timeout: 12)
            try? await session.sendLine("stty echo")

            if result.contains("__NO_PRINTER__") {
                throw GatewayRecoveryError.printerNotConnected
            }
            guard result.contains("__READY__") else {
                throw GatewayRecoveryError.serviceDidNotStart
            }
        } catch let error as GatewayRecoveryError {
            throw error
        } catch {
            throw GatewayRecoveryError.telnetConnectionFailed
        }
    }

    private static func recoveryShellCommand(host: String) -> String {
        "if [ ! -c /dev/lp0 ]; then echo __NO_PRINTER__; else if [ -x /osgi/lj2600d-print/install.sh ]; then /osgi/lj2600d-print/install.sh >/var/tmp/lj2600d-recover.log 2>&1; sleep 2; fi; mkdir -p /var/tmp/lpdspool; ln -sf /dev/lp0 /var/tmp/lpdspool/LJ2600D; ln -sf /dev/lp0 /var/tmp/lpdspool/lp; if ! netstat -lnt 2>/dev/null | grep -q ':515 '; then nohup /usr/bin/tcpsvd -E \(host) 515 /usr/bin/softlimit -m 16777216 /usr/sbin/lpd /var/tmp/lpdspool >/var/tmp/lpd.log 2>&1 & sleep 2; fi; if netstat -lnt 2>/dev/null | grep -q ':515 '; then echo __READY__; else echo __FAILED__; fi; fi; echo __LJ_DONE__"
    }

    private static func isValidIPv4(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { part in
            guard !part.isEmpty, part.count <= 3, part.allSatisfy({ $0.isNumber }),
                  let number = Int(part) else { return false }
            return (0...255).contains(number)
        }
    }
}

private final class OneShot<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false

    @discardableResult
    func finish(
        _ value: Value,
        continuation: CheckedContinuation<Value, Never>
    ) -> Bool {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return false
        }
        completed = true
        lock.unlock()
        continuation.resume(returning: value)
        return true
    }
}

private final class ThrowingOneShot<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false

    @discardableResult
    func finish(
        _ result: Result<Value, Error>,
        continuation: CheckedContinuation<Value, Error>
    ) -> Bool {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return false
        }
        completed = true
        lock.unlock()
        continuation.resume(with: result)
        return true
    }
}

private final class TelnetSession: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "LJ2600DPrint.telnet")

    init(host: String) {
        connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: 23)!,
            using: .tcp
        )
    }

    func connect(timeout: TimeInterval = 5) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let gate = ThrowingOneShot<Void>()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    _ = gate.finish(.success(()), continuation: continuation)
                case .failed(let error):
                    _ = gate.finish(.failure(error), continuation: continuation)
                case .cancelled:
                    _ = gate.finish(.failure(GatewayRecoveryError.telnetConnectionFailed), continuation: continuation)
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                if gate.finish(.failure(GatewayRecoveryError.telnetConnectionFailed), continuation: continuation) {
                    self?.connection.cancel()
                }
            }
        }
    }

    func sendLine(_ line: String) async throws {
        var data = Data(line.utf8)
        data.append(contentsOf: [13, 10])
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            })
        }
    }

    func receive(until patterns: [String], timeout: TimeInterval = 5) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let gate = ThrowingOneShot<String>()
            var received = Data()
            var receiveNext: (() -> Void)?
            receiveNext = { [weak self] in
                guard let self else { return }
                self.connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) {
                    data, _, isComplete, error in
                    if let error {
                        _ = gate.finish(.failure(error), continuation: continuation)
                        return
                    }
                    if let data { received.append(data) }
                    let text = String(decoding: received, as: UTF8.self)
                    if patterns.contains(where: { text.localizedCaseInsensitiveContains($0) }) {
                        _ = gate.finish(.success(text), continuation: continuation)
                    } else if isComplete {
                        _ = gate.finish(.failure(GatewayRecoveryError.telnetConnectionFailed), continuation: continuation)
                    } else {
                        receiveNext?()
                    }
                }
            }
            receiveNext?()
            queue.asyncAfter(deadline: .now() + timeout) {
                _ = gate.finish(.failure(GatewayRecoveryError.telnetConnectionFailed), continuation: continuation)
            }
        }
    }

    func close() {
        connection.cancel()
    }
}
