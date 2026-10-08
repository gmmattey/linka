import Foundation
import Vision
import ImageIO
import NetworkInventory

struct VisionDeviceLabelOCR: DeviceLabelOCRService {
    func candidates(from imageData: Data) async throws -> [DeviceLabelCandidate] {
        guard imageData.count <= 20_000_000 else { throw NetworkInventoryError.invalidDevice }
        try Task.checkCancellation()
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            // Downsample before recognition: do not retain a full-resolution label or its text.
            guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2400
                  ] as CFDictionary) else { throw NetworkInventoryError.invalidDevice }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: image).perform([request])
            try Task.checkCancellation()
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            return DeviceLabelParser.candidates(from: text.components(separatedBy: "\n"))
        }
        return try await withTaskCancellationHandler {
            let result = try await worker.value
            try Task.checkCancellation()
            return result
        } onCancel: {
            worker.cancel()
        }
    }
}
