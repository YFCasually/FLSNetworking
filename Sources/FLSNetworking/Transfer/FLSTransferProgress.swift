import Foundation

/// An immutable snapshot; callbacks are delivered on a worker queue, not the main actor.
public struct FLSTransferProgress: Sendable {
    public let completedBytes: Int64
    public let totalBytes: Int64
    public var fractionCompleted: Double? {
        totalBytes > 0 ? min(1, max(0, Double(completedBytes) / Double(totalBytes))) : nil
    }

    init(_ progress: Progress) {
        completedBytes = progress.completedUnitCount
        totalBytes = progress.totalUnitCount
    }
}
