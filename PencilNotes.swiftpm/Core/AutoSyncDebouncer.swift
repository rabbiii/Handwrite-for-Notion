import Foundation

/// One pending request, replaced on each activity. Networking is serialized by
/// the app so a slow upload cannot append concurrent blocks.
@MainActor
final class AutoSyncDebouncer {
    private var task: Task<Void, Never>?
    func cancel() { task?.cancel(); task = nil }
    func schedule(delay: TimeInterval = 0.5, action: @escaping @MainActor () async -> Void) {
        cancel()
        task = Task {
            do { try await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000)) }
            catch { return }
            guard !Task.isCancelled else { return }
            await action()
        }
    }
}
