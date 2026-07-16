import Foundation

// `operation` runs in its own unstructured Task, so a hang that never observes
// cancellation cannot block this call from returning once the deadline elapses.
// A structured task group would wait for that hung child before returning.
func withExportTimeout<T: Sendable>(
  seconds: TimeInterval,
  operation: @escaping @Sendable () async throws -> T
) async throws -> T {
  try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
    let gate = TimeoutRaceGate<T>()

    let operationTask = Task {
      do {
        let value = try await operation()
        gate.resume(continuation, with: .success(value))
      } catch {
        gate.resume(continuation, with: .failure(error))
      }
    }

    Task {
      try? await Task.sleep(for: .seconds(seconds))
      gate.resume(continuation, with: .failure(ExportError.exportTimedOut(seconds: seconds)))
      operationTask.cancel()
    }
  }
}

private final class TimeoutRaceGate<T: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var didResume = false

  func resume(_ continuation: CheckedContinuation<T, Error>, with result: Result<T, Error>) {
    lock.lock()
    let shouldResume = !didResume
    didResume = true
    lock.unlock()

    guard shouldResume else { return }
    continuation.resume(with: result)
  }
}
