import AVFoundation
import Combine
import UIKit

/// AVFoundation camera session: front/back switch, 0.5x / 1x / 2x zoom, photo capture.
final class CameraService: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var device: AVCaptureDevice?
    private var position: AVCaptureDevice.Position = .front
    private var captureCompletion: ((UIImage?) -> Void)?

    @Published var zoomLabel: String = "x1"

    /// Default is the front camera; pass `.back` for photo missions etc.
    func configure(position: AVCaptureDevice.Position = .front) {
        session.beginConfiguration()
        session.sessionPreset = .photo
        setDevice(position: position)
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        // On dual-wide virtual devices the native factor 1.0 is the 0.5x
        // ultra-wide — start at the standard 1x lens instead.
        setZoom(1.0)
        Task.detached { [session] in session.startRunning() }
    }

    func stop() {
        Task.detached { [session] in session.stopRunning() }
    }

    private func setDevice(position: AVCaptureDevice.Position) {
        self.position = position
        session.inputs.forEach { session.removeInput($0) }
        // Virtual device enables 0.5x on supported hardware.
        let device = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: position)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
        guard let device, let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)
        self.device = device
    }

    func flip() {
        session.beginConfiguration()
        setDevice(position: position == .back ? .front : .back)
        session.commitConfiguration()
        setZoom(1.0)
    }

    /// factor: 0.5, 1.0, 2.0
    func setZoom(_ factor: CGFloat) {
        guard let device else { return }
        // On virtual dual-wide devices 1.0 = ultra-wide; wide-angle starts at switchOver factor.
        let wideBase = device.virtualDeviceSwitchOverVideoZoomFactors.first?.doubleValue ?? 1.0
        let target: CGFloat
        switch factor {
        case 0.5: target = 1.0
        case 2.0: target = CGFloat(wideBase) * 2.0
        default: target = CGFloat(wideBase)
        }
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = min(max(target, device.minAvailableVideoZoomFactor),
                                         device.maxAvailableVideoZoomFactor)
            device.unlockForConfiguration()
            zoomLabel = factor == 0.5 ? "0.5" : (factor == 2.0 ? "x2" : "x1")
        } catch {}
    }

    func capture(completion: @escaping (UIImage?) -> Void) {
        captureCompletion = completion
        let settings = AVCapturePhotoSettings()
        output.capturePhoto(with: settings, delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard let data = photo.fileDataRepresentation(), var image = UIImage(data: data) else {
            captureCompletion?(nil); return
        }
        // Mirror front-camera shots to match the preview.
        if position == .front, let cg = image.cgImage {
            image = UIImage(cgImage: cg, scale: image.scale, orientation: .leftMirrored)
        }
        captureCompletion?(image)
    }
}
