import Foundation

public actor ThroughputMicroProber {
    public init() {}

    private let testURL = URL(string: "https://speed.cloudflare.com/__down?bytes=2097152")! // 2 MB payload rápido

    /// Executa um micro-teste leve de download limitado a no máximo 2.5 segundos.
    /// Retorna a taxa em Mbps ou nil caso ocorra timeout, bloqueio ou erro de conexão.
    public func measureThroughputMbps() async -> Double? {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 2.5
        configuration.timeoutIntervalForResource = 2.5
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let startTime = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)

        do {
            let (data, response) = try await session.data(from: testURL)
            let endTime = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            let elapsedSeconds = Double(endTime - startTime) / 1_000_000_000.0

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  elapsedSeconds > 0.05 else {
                return nil
            }

            let bytesReceived = Double(data.count)
            // (bytes * 8) / (1_000_000 * seconds) = Mbps
            let mbps = (bytesReceived * 8.0) / (1_000_000.0 * elapsedSeconds)
            return round(mbps * 10) / 10
        } catch {
            return nil
        }
    }
}
