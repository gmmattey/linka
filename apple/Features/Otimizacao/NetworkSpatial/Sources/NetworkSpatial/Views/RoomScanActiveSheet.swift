import SwiftUI

#if canImport(RoomPlan) && os(iOS)
import RoomPlan
import UIKit
#endif

/// Folha ativa de escaneamento espacial utilizando a API nativa RoomPlan e sensores LiDAR da Apple.
@available(iOS 17.0, macOS 14.0, *)
public struct RoomScanActiveSheet: View {
    @Environment(\.dismiss) private var dismiss
    public let onScanCompleted: ([CapturedRoomData]) -> Void
    public let onScanCancelled: () -> Void

    public init(
        onScanCompleted: @escaping ([CapturedRoomData]) -> Void,
        onScanCancelled: @escaping () -> Void = {}
    ) {
        self.onScanCompleted = onScanCompleted
        self.onScanCancelled = onScanCancelled
    }

    public var body: some View {
        #if canImport(RoomPlan) && os(iOS)
        if LiDARCapability.isSupported {
            RoomCaptureContainerView(
                onFinish: { @MainActor rooms in
                    dismiss()
                    onScanCompleted(rooms)
                },
                onCancel: { @MainActor in
                    dismiss()
                    onScanCancelled()
                }
            )
            .ignoresSafeArea()
        } else {
            fallbackUnavailableView
        }
        #else
        fallbackUnavailableView
        #endif
    }

    private var fallbackUnavailableView: some View {
        LiDARUnavailableSheet {
            dismiss()
            onScanCancelled()
        }
    }
}

#if canImport(RoomPlan) && os(iOS)
@objc(WiFiCheckRoomCaptureCoordinator)
public final class RoomCaptureCoordinator: NSObject, @preconcurrency RoomCaptureViewDelegate, @unchecked Sendable {
    public let onFinish: (@MainActor @Sendable ([CapturedRoomData]) -> Void)?
    public let onCancel: (@MainActor @Sendable () -> Void)?

    public override init() {
        self.onFinish = nil
        self.onCancel = nil
        super.init()
    }

    public init(onFinish: @escaping @MainActor @Sendable ([CapturedRoomData]) -> Void, onCancel: @escaping @MainActor @Sendable () -> Void) {
        self.onFinish = onFinish
        self.onCancel = onCancel
        super.init()
    }

    // MARK: - NSCoding
    public required init?(coder: NSCoder) {
        self.onFinish = nil
        self.onCancel = nil
        super.init()
    }

    public func encode(with coder: NSCoder) {}

    // MARK: - RoomCaptureViewDelegate
    nonisolated public func captureView(shouldPresent roomDataForProcessing: RoomPlan.CapturedRoomData, error: (any Error)?) -> Bool {
        return true
    }

    nonisolated public func captureView(didPresent processedResult: CapturedRoom, error: (any Error)?) {
        if error != nil {
            Task { @MainActor [weak self] in
                self?.onCancel?()
            }
            return
        }

        var width = 4.0
        var length = 4.0
        var area = 16.0

        if #available(iOS 17.0, *), !processedResult.floors.isEmpty {
            let floorAreas = processedResult.floors.map { Double($0.dimensions.x * $0.dimensions.y) }
            area = floorAreas.reduce(0, +)
            if let primaryFloor = processedResult.floors.first {
                width = max(1.0, Double(primaryFloor.dimensions.x))
                length = max(1.0, Double(primaryFloor.dimensions.y))
            }
        } else if !processedResult.walls.isEmpty {
            let wallLengths = processedResult.walls.map { Double($0.dimensions.x) }
            width = max(1.0, wallLengths.max() ?? 4.0)
            let sorted = wallLengths.sorted(by: >)
            length = sorted.count > 1 ? max(1.0, sorted[1]) : width
            area = width * length
        }

        let captured = CapturedRoomData(
            suggestedName: "Cômodo Escaneado",
            areaSqMeters: max(1.0, area),
            boundingWidthMeters: width,
            boundingLengthMeters: length
        )

        Task { @MainActor [weak self] in
            self?.onFinish?([captured])
        }
    }
}

struct RoomCaptureContainerView: UIViewRepresentable {
    let onFinish: @MainActor @Sendable ([CapturedRoomData]) -> Void
    let onCancel: @MainActor @Sendable () -> Void

    func makeCoordinator() -> RoomCaptureCoordinator {
        RoomCaptureCoordinator(onFinish: onFinish, onCancel: onCancel)
    }

    func makeUIView(context: Context) -> RoomCaptureView {
        let view = RoomCaptureView(frame: .zero)
        view.delegate = context.coordinator

        let config = RoomCaptureSession.Configuration()
        view.captureSession.run(configuration: config)
        return view
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}

    static func dismantleUIView(_ uiView: RoomCaptureView, coordinator: RoomCaptureCoordinator) {
        uiView.captureSession.stop()
    }
}
#endif
