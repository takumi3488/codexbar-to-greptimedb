import Foundation
import Testing

@testable import codexbar_to_greptimedb

@Test func timesOutWhenOperationHangsPastTheDeadline() async throws {
  await #expect(throws: ExportError.self) {
    try await withExportTimeout(seconds: 0.05) {
      hangForever()
      return "unreachable"
    }
  }
}

// Simulates a hang that never observes cancellation, such as a blocking call
// reached from async code. Not marked `async` so the blocking wait is legal.
private func hangForever() {
  let semaphore = DispatchSemaphore(value: 0)
  semaphore.wait()
}

@Test func returnsOperationResultWhenItCompletesBeforeTheDeadline() async throws {
  let result = try await withExportTimeout(seconds: 5) {
    "completed"
  }

  #expect(result == "completed")
}

@Test func propagatesOperationErrorsWithoutWaitingForTheDeadline() async throws {
  struct SampleError: Error, Equatable {}

  await #expect(throws: SampleError.self) {
    try await withExportTimeout(seconds: 5) {
      throw SampleError()
    }
  }
}
