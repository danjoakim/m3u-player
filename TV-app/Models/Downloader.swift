import Foundation

/// Hvor langt en nedlasting har kommet.
struct LoadProgress: Equatable {
    enum Phase { case connecting, downloading, processing }

    var phase: Phase
    var received: Int64 = 0
    var expected: Int64 = 0

    /// Andel ferdig, eller nil hvis serveren ikke oppgir størrelsen.
    var fraction: Double? {
        guard phase == .downloading, expected > 0 else { return nil }
        return min(Double(received) / Double(expected), 1)
    }
}

/// Laster ned med fremdriftsmelding underveis.
nonisolated final class Downloader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private var buffer = Data()
    private var continuation: CheckedContinuation<(Data, URLResponse), Error>?
    private let onProgress: @Sendable (Int64, Int64) -> Void
    private var lastReport = Date.distantPast

    private init(onProgress: @escaping @Sendable (Int64, Int64) -> Void) {
        self.onProgress = onProgress
    }

    static func fetch(_ request: URLRequest,
                      onProgress: @escaping @Sendable (Int64, Int64) -> Void) async throws -> (Data, URLResponse) {
        let downloader = Downloader(onProgress: onProgress)
        let session = URLSession(configuration: .default, delegate: downloader, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                downloader.continuation = continuation
                session.dataTask(with: request).resume()
            }
        } onCancel: {
            session.invalidateAndCancel()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer.append(data)
        let now = Date()
        if now.timeIntervalSince(lastReport) > 0.15 {
            lastReport = now
            onProgress(Int64(buffer.count), dataTask.countOfBytesExpectedToReceive)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            continuation?.resume(throwing: error)
        } else if let response = task.response {
            onProgress(Int64(buffer.count), Int64(buffer.count))
            continuation?.resume(returning: (buffer, response))
        } else {
            continuation?.resume(throwing: URLError(.badServerResponse))
        }
        continuation = nil
    }
}
