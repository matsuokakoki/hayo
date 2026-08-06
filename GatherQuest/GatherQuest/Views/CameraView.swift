import SwiftUI
import AVFoundation

// ⑪ Camera: shared for departure / arrival / mission / SNAP.
// Departure only: BeReal-style circular preview frame.
struct CameraView: View {
    let groupId: String
    let purpose: CameraPurpose
    let headerMission: Mission?
    let onDone: () -> Void

    @StateObject private var camera = CameraService()
    @State private var captured: UIImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let captured {
                // ⑫ preview & caption
                PhotoPreviewView(groupId: groupId, purpose: purpose,
                                 image: captured,
                                 onRetake: { self.captured = nil },
                                 onDone: onDone)
            } else {
                VStack(spacing: 0) {
                    // Mission band on top (if any active mission)
                    if case .mission(let m) = purpose {
                        missionBand(m)
                    } else if let headerMission, headerMission.isActive {
                        missionBand(headerMission)
                    }

                    Spacer()

                    // Preview
                    CameraPreview(session: camera.session)
                        .aspectRatio(3 / 4, contentMode: .fit)
                        .clipShape(previewShape)
                        .overlay(previewShape.stroke(Color.white, lineWidth: purpose.isCircular ? 4 : 0))
                        .padding(.horizontal, purpose.isCircular ? 32 : 0)

                    if purpose.isCircular {
                        Text("出発写真を撮ろう！マップのアイコンになるよ")
                            .font(.caption).foregroundColor(.white)
                            .padding(.top, 12)
                    }

                    Spacer()

                    // Zoom buttons
                    HStack(spacing: 16) {
                        ForEach(["0.5", "x1", "x2"], id: \.self) { z in
                            Button {
                                camera.setZoom(z == "0.5" ? 0.5 : (z == "x2" ? 2.0 : 1.0))
                            } label: {
                                Text(z)
                                    .font(.caption.bold())
                                    .foregroundColor(camera.zoomLabel == z ? .yellow : .white)
                                    .frame(width: 44, height: 44)
                                    .background(Circle().fill(Color.white.opacity(0.2)))
                            }
                        }
                    }
                    .padding(.bottom, 20)

                    // Bottom controls
                    HStack {
                        Button { onDone() } label: {
                            Image(systemName: "chevron.left")
                                .font(.title2).foregroundColor(.white)
                                .frame(width: 60, height: 60)
                                .background(Circle().fill(Color.white.opacity(0.2)))
                        }
                        Spacer()
                        Button {
                            camera.capture { image in
                                DispatchQueue.main.async { captured = image }
                            }
                        } label: {
                            ZStack {
                                Circle().stroke(Color.white, lineWidth: 5).frame(width: 76, height: 76)
                                Circle().fill(Color.white).frame(width: 62, height: 62)
                            }
                        }
                        Spacer()
                        Button { camera.flip() } label: {
                            Image(systemName: "arrow.triangle.2.circlepath.camera")
                                .font(.title2).foregroundColor(.white)
                                .frame(width: 60, height: 60)
                                .background(Circle().fill(Color.white.opacity(0.2)))
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
                }
            }
        }
        .onAppear { camera.configure() }
        .onDisappear { camera.stop() }
    }

    private var previewShape: AnyShape {
        purpose.isCircular ? AnyShape(Circle()) : AnyShape(Rectangle())
    }

    private func missionBand(_ mission: Mission) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(mission.expiresAt.timeIntervalSince(context.date)))
            VStack(spacing: 4) {
                Text(mission.title)
                    .font(.subheadline.bold()).foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.8))
                Text(String(format: "%02d:%02d", remaining / 60, remaining % 60))
                    .font(.headline.monospacedDigit()).foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.25)))
            }
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
