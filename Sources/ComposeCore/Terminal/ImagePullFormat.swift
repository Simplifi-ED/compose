import Foundation
import TerminalProgress

package enum ImagePullPhase: Equatable, Sendable {
    case fetching
    case unpacking
    case complete
    case failed
}

package struct ImagePullState: Equatable, Sendable {
    package var phase: ImagePullPhase
    package var items: Int
    package var totalItems: Int
    package var size: Int64
    package var totalSize: Int64

    package init(
        phase: ImagePullPhase = .fetching,
        items: Int = 0,
        totalItems: Int = 0,
        size: Int64 = 0,
        totalSize: Int64 = 0
    ) {
        self.phase = phase
        self.items = items
        self.totalItems = totalItems
        self.size = size
        self.totalSize = totalSize
    }

    package mutating func apply(_ events: [ProgressUpdateEvent]) {
        for event in events {
            apply(event)
        }
    }

    private mutating func apply(_ event: ProgressUpdateEvent) {
        switch event {
        case .setDescription(let value):
            phase = ImagePullFormat.phase(from: value)
        case .addItems(let value):
            items += value
        case .setItems(let value):
            items = value
        case .addTotalItems(let value):
            totalItems += value
        case .setTotalItems(let value):
            totalItems = value
        case .addSize(let value):
            size += value
        case .setSize(let value):
            size = value
        case .addTotalSize(let value):
            totalSize += value
        case .setTotalSize(let value):
            totalSize = value
        default:
            break
        }
    }
}

package enum ImagePullFormat {
    package static func phase(from description: String) -> ImagePullPhase {
        let lowered = description.lowercased()
        if lowered.contains("unpack") {
            return .unpacking
        }
        if lowered.contains("complete") || lowered.contains("done") {
            return .complete
        }
        return .fetching
    }

    package static func statusLine(
        reference: String,
        state: ImagePullState,
        mode: TerminalMode,
        width: Int = ANSIPrefix.defaultWidth,
        spinnerFrame: String = ProgressFormat.spinnerFrames[0]
    ) -> String {
        let status = statusText(for: state)
        switch mode {
        case .interactive:
            let mark = mark(for: state.phase, spinnerFrame: spinnerFrame)
            return "\(mark) \(ANSIPrefix.format(serviceName: reference, mode: .interactive, width: width))\(status)"
        case .plain, .pipe:
            return "\(ANSIPrefix.format(serviceName: reference, mode: .plain, width: width))\(status)"
        }
    }

    package static func completionLine(reference: String, state: ImagePullState, width: Int) -> String {
        "\(ANSIPrefix.format(serviceName: reference, mode: .plain, width: width))\(statusText(for: state))"
    }

    private static func statusText(for state: ImagePullState) -> String {
        switch state.phase {
        case .fetching:
            return "Pulling" + progressSuffix(for: state)
        case .unpacking:
            return "Unpacking" + progressSuffix(for: state)
        case .complete:
            return "Pull complete"
        case .failed:
            return "Pull failed"
        }
    }

    private static func progressSuffix(for state: ImagePullState) -> String {
        var parts: [String] = []
        if state.totalItems > 0 {
            parts.append("layer \(state.items)/\(state.totalItems)")
        }
        if state.totalSize > 0 {
            let current = max(0, state.size).formatted(.byteCount(style: .file))
            let total = state.totalSize.formatted(.byteCount(style: .file))
            parts.append("\(current)/\(total)")
        }
        guard !parts.isEmpty else { return "" }
        return " (" + parts.joined(separator: ", ") + ")"
    }

    private static func mark(for phase: ImagePullPhase, spinnerFrame: String) -> String {
        let state: ProgressMarkState = switch phase {
        case .fetching, .unpacking:
            .inProgress(spinnerFrame: spinnerFrame)
        case .complete:
            .succeeded
        case .failed:
            .failed
        }
        return ProgressFormat.mark(for: state)
    }
}
