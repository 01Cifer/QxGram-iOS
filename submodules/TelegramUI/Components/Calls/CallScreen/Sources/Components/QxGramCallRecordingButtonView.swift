import Foundation
import UIKit
import Display

final class QxGramCallRecordingButtonView: HighlightTrackingButton {
    var pressAction: (() -> Void)?

    private let dotView = UIView()
    private let textLabel = UILabel()
    private var timer: Foundation.Timer?
    private var currentSize: CGSize = CGSize(width: 104.0, height: 40.0)
    private var isRecording: Bool = false
    private var startedAt: Double?

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.backgroundColor = UIColor(white: 0.0, alpha: 0.4)

        self.textLabel.textColor = .white
        self.textLabel.textAlignment = .center
        self.textLabel.lineBreakMode = .byClipping
        self.addSubview(self.textLabel)

        self.dotView.backgroundColor = UIColor(red: 1.0, green: 0.27, blue: 0.27, alpha: 1.0)
        self.dotView.isHidden = true
        self.addSubview(self.dotView)

        self.addTarget(self, action: #selector(self.pressed), for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.timer?.invalidate()
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        if newWindow == nil {
            self.timer?.invalidate()
            self.timer = nil
        }
        super.willMove(toWindow: newWindow)
    }

    @objc private func pressed() {
        self.pressAction?()
    }

    func update(size: CGSize, isRecording: Bool, startedAt: Double?) {
        self.currentSize = size
        self.isRecording = isRecording
        self.startedAt = startedAt
        self.layer.cornerRadius = floor(size.height * 0.5)
        self.layer.masksToBounds = true
        self.dotView.layer.cornerRadius = 4.0
        self.dotView.isHidden = !isRecording

        self.updateTitle()

        if isRecording {
            if self.timer == nil {
                self.timer = Foundation.Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true, block: { [weak self] _ in
                    self?.updateTitle()
                })
            }
        } else {
            self.timer?.invalidate()
            self.timer = nil
        }
    }

    private func updateTitle() {
        let size = self.currentSize
        let dotSize: CGFloat = 8.0
        let font = UIFont.systemFont(ofSize: 13.0, weight: .semibold)
        self.textLabel.font = font

        if self.isRecording {
            let elapsed = max(0, Int(floor(Date().timeIntervalSince1970 - (self.startedAt ?? Date().timeIntervalSince1970))))
            self.textLabel.text = String(format: "%02d:%02d", elapsed / 60, elapsed % 60)
            self.dotView.frame = CGRect(origin: CGPoint(x: 9.0, y: floor((size.height - dotSize) * 0.5)), size: CGSize(width: dotSize, height: dotSize))
            self.textLabel.frame = CGRect(origin: CGPoint(x: 17.0, y: 0.0), size: CGSize(width: size.width - 25.0, height: size.height))
        } else {
            self.textLabel.text = "🎬 Запись"
            self.textLabel.frame = CGRect(origin: CGPoint(x: 8.0, y: 0.0), size: CGSize(width: size.width - 16.0, height: size.height))
        }
    }
}
