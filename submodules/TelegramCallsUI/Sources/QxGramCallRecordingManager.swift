import Foundation
import UIKit
import ReplayKit
import Photos
import TelegramCore

public final class QxGramCallRecordingManager {
    public static let shared = QxGramCallRecordingManager()

    public private(set) var isRecording: Bool = false
    public private(set) var startedAt: Double?
    public var onStateChanged: (() -> Void)?

    private var isStarting: Bool = false
    private var isStopping: Bool = false
    private var outputURL: URL?
    private let backgroundObserver: NSObjectProtocol?

    private init() {
        self.backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main, using: { [weak self] _ in
            self?.stop()
        })
    }

    deinit {
        if let backgroundObserver = self.backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
        }
    }

    public var isAvailable: Bool {
        return RPScreenRecorder.shared().isAvailable
    }

    public func toggle(completion: @escaping (Bool) -> Void) {
        if self.isRecording || self.isStarting {
            self.stop()
            completion(false)
            return
        }
        self.start(completion: completion)
    }

    private func start(completion: @escaping (Bool) -> Void) {
        guard !self.isStarting, !self.isStopping else {
            completion(false)
            return
        }
        guard let outputURL = self.makeOutputURL() else {
            Logger.shared.log("QxGram Call", "could not create call recording folder")
            completion(false)
            return
        }

        let recorder = RPScreenRecorder.shared()
        guard recorder.isAvailable else {
            Logger.shared.log("QxGram Call", "screen recorder unavailable")
            completion(false)
            return
        }

        self.isStarting = true
        recorder.startRecording(withMicrophoneEnabled: true) { [weak self] error in
            DispatchQueue.main.async {
                guard let self else {
                    completion(false)
                    return
                }
                self.isStarting = false
                if let error {
                    Logger.shared.log("QxGram Call", "start failed: \(error.localizedDescription)")
                    completion(false)
                    return
                }
                self.outputURL = outputURL
                self.startedAt = Date().timeIntervalSince1970
                self.isRecording = true
                self.onStateChanged?()
                completion(true)
            }
        }
    }

    public func stop() {
        guard self.isRecording, !self.isStopping else {
            return
        }
        guard let outputURL = self.outputURL else {
            self.isRecording = false
            self.startedAt = nil
            self.onStateChanged?()
            return
        }

        self.isStopping = true
        self.isRecording = false
        self.onStateChanged?()

        RPScreenRecorder.shared().stopRecording(withOutput: outputURL) { [weak self] error in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                self.isStopping = false
                self.startedAt = nil
                if let error {
                    Logger.shared.log("QxGram Call", "stop failed: \(error.localizedDescription)")
                } else {
                    self.saveToPhotos(outputURL)
                    Logger.shared.log("QxGram Call", "recording saved to app folder and photo library")
                }
                self.onStateChanged?()
            }
        }
    }

    private func makeOutputURL() -> URL? {
        let fileManager = FileManager.default
        guard let documents = try? fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            return nil
        }
        let folder = documents.appendingPathComponent("QxGramCallRecordings", isDirectory: true)
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: nil)
        } catch {
            Logger.shared.log("QxGram Call", "could not create recordings directory: \(error.localizedDescription)")
            return nil
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let fileName = "call-\(formatter.string(from: Date())).mp4"
        return folder.appendingPathComponent(fileName, isDirectory: false)
    }

    private func saveToPhotos(_ url: URL) {
        PHPhotoLibrary.shared().performChanges({
            let _ = PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }, completionHandler: { success, _ in
            if !success {
                Logger.shared.log("QxGram Call", "could not save recording to photo library")
            }
        })
    }
}
