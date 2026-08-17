import AppKit
import Vision

enum TextRecognitionError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Shot couldn’t prepare the image for text recognition."
        }
    }
}

enum TextRecognizer {
    static func recognize(
        image: NSImage,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            completion(.failure(TextRecognitionError.invalidImage))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let request = VNRecognizeTextRequest { request, error in
                let result: Result<String, Error>
                if let error {
                    result = .failure(error)
                } else {
                    let text = (request.results as? [VNRecognizedTextObservation])?
                        .compactMap { $0.topCandidates(1).first?.string }
                        .joined(separator: "\n") ?? ""
                    result = .success(text)
                }

                DispatchQueue.main.async {
                    completion(result)
                }
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true

            do {
                try VNImageRequestHandler(cgImage: cgImage).perform([request])
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
}
