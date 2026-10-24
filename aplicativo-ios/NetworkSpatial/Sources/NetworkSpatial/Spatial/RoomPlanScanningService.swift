import Foundation

#if canImport(RoomPlan) && os(iOS)
import RoomPlan
#endif

/// Dados brutos de cômodo capturados via sensor LiDAR / RoomPlan.
public struct CapturedRoomData: Identifiable, Sendable, Equatable {
    public var id: UUID
    public let suggestedName: String
    public let areaSqMeters: Double
    public let boundingWidthMeters: Double
    public let boundingLengthMeters: Double

    public init(
        id: UUID = UUID(),
        suggestedName: String,
        areaSqMeters: Double,
        boundingWidthMeters: Double,
        boundingLengthMeters: Double
    ) {
        self.id = id
        self.suggestedName = suggestedName
        self.areaSqMeters = areaSqMeters
        self.boundingWidthMeters = boundingWidthMeters
        self.boundingLengthMeters = boundingLengthMeters
    }
}

/// Erros emitidos durante o escaneamento espacial de cômodos.
public enum RoomPlanScanningError: LocalizedError, Sendable, Equatable {
    case unsupportedDevice
    case alreadyScanning
    case notScanning
    case captureFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedDevice:
            return "Este dispositivo não possui sensor LiDAR para escaneamento tridimensional."
        case .alreadyScanning:
            return "Uma sessão de escaneamento já está em andamento."
        case .notScanning:
            return "Nenhuma sessão de escaneamento está ativa no momento."
        case .captureFailed(let message):
            return "Falha na captura espacial: \(message)"
        }
    }
}

/// Contrato para serviços de escaneamento espacial com RoomPlan.
public protocol RoomPlanScanningServiceProtocol: AnyObject, Sendable {
    var isScanning: Bool { get }
    func startScan() async throws
    func stopScan() async throws -> [CapturedRoomData]
}

// MARK: - Native RoomPlan Scanner (iOS Nativo com LiDAR)

#if canImport(RoomPlan) && os(iOS)
public final class NativeRoomPlanScanner: NSObject, RoomPlanScanningServiceProtocol, RoomCaptureSessionDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var _isScanning: Bool = false
    private var captureSession: RoomCaptureSession?
    private var capturedRoomsStorage: [CapturedRoomData] = []
    private var stopContinuation: CheckedContinuation<[CapturedRoomData], Error>?

    public var isScanning: Bool {
        lock.withLock { _isScanning }
    }

    public override init() {
        super.init()
    }

    @MainActor
    public func startScan() async throws {
        guard LiDARCapability.isSupported else {
            throw RoomPlanScanningError.unsupportedDevice
        }

        let session = RoomCaptureSession()
        session.delegate = self
        self.captureSession = session

        lock.withLock {
            _isScanning = true
            capturedRoomsStorage.removeAll()
        }

        let config = RoomCaptureSession.Configuration()
        session.run(configuration: config)
    }

    @MainActor
    public func stopScan() async throws -> [CapturedRoomData] {
        guard let session = self.captureSession, isScanning else {
            throw RoomPlanScanningError.notScanning
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.stopContinuation = continuation
            session.stop()
        }
    }

    // MARK: - RoomCaptureSessionDelegate
    public func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        var width = 4.0
        var length = 4.0
        var area = 16.0

        if #available(iOS 17.0, *), !room.floors.isEmpty {
            let floorAreas = room.floors.map { Double($0.dimensions.x * $0.dimensions.y) }
            area = floorAreas.reduce(0, +)
            if let primaryFloor = room.floors.first {
                width = max(1.0, Double(primaryFloor.dimensions.x))
                length = max(1.0, Double(primaryFloor.dimensions.y))
            }
        } else if !room.walls.isEmpty {
            let wallLengths = room.walls.map { Double($0.dimensions.x) }
            width = max(1.0, wallLengths.max() ?? 4.0)
            let sorted = wallLengths.sorted(by: >)
            length = sorted.count > 1 ? max(1.0, sorted[1]) : width
            area = width * length
        }

        let extracted = CapturedRoomData(
            suggestedName: "Cômodo Escaneado",
            areaSqMeters: max(1.0, area),
            boundingWidthMeters: max(0.5, width),
            boundingLengthMeters: max(0.5, length)
        )

        lock.withLock {
            if capturedRoomsStorage.isEmpty {
                capturedRoomsStorage.append(extracted)
            } else {
                capturedRoomsStorage[0] = extracted
            }
        }
    }

    public func captureSession(_ session: RoomCaptureSession, didEndWith data: RoomPlan.CapturedRoomData, error: (any Error)?) {
        let finalRooms = lock.withLock {
            _isScanning = false
            return capturedRoomsStorage
        }

        if let error = error {
            stopContinuation?.resume(throwing: RoomPlanScanningError.captureFailed(error.localizedDescription))
        } else {
            stopContinuation?.resume(returning: finalRooms)
        }
        stopContinuation = nil
    }
}
#else
/// Fallback para plataformas sem suporte de compilação a RoomPlan (macOS CLI / Linux).
public final class NativeRoomPlanScanner: RoomPlanScanningServiceProtocol, @unchecked Sendable {
    public var isScanning: Bool { false }

    public init() {}

    public func startScan() async throws {
        throw RoomPlanScanningError.unsupportedDevice
    }

    public func stopScan() async throws -> [CapturedRoomData] {
        throw RoomPlanScanningError.unsupportedDevice
    }
}
#endif

// MARK: - Mock RoomPlan Scanner (Testes e Simulador)

public final class MockRoomPlanScanner: RoomPlanScanningServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _isScanning: Bool = false
    public var mockRooms: [CapturedRoomData]
    public var shouldThrowError: Bool

    public var isScanning: Bool {
        lock.withLock { _isScanning }
    }

    public init(
        mockRooms: [CapturedRoomData] = [
            CapturedRoomData(suggestedName: "Sala de Estar", areaSqMeters: 24.5, boundingWidthMeters: 5.0, boundingLengthMeters: 4.9),
            CapturedRoomData(suggestedName: "Cozinha", areaSqMeters: 14.0, boundingWidthMeters: 4.0, boundingLengthMeters: 3.5),
            CapturedRoomData(suggestedName: "Quarto Principal", areaSqMeters: 16.0, boundingWidthMeters: 4.0, boundingLengthMeters: 4.0),
            CapturedRoomData(suggestedName: "Banheiro", areaSqMeters: 4.8, boundingWidthMeters: 2.4, boundingLengthMeters: 2.0)
        ],
        shouldThrowError: Bool = false
    ) {
        self.mockRooms = mockRooms
        self.shouldThrowError = shouldThrowError
    }

    public func startScan() async throws {
        if shouldThrowError {
            throw RoomPlanScanningError.captureFailed("Erro simulado de inicialização de câmera.")
        }
        lock.withLock {
            _isScanning = true
        }
    }

    public func stopScan() async throws -> [CapturedRoomData] {
        if shouldThrowError {
            throw RoomPlanScanningError.captureFailed("Erro simulado ao finalizar malha 3D.")
        }
        return lock.withLock {
            _isScanning = false
            return mockRooms
        }
    }
}
