import AVFoundation
import SwiftUI
import UIKit

struct QRCodeScannerView: View {
    @Environment(\.dismiss) private var dismiss
    let onScan: (String?) -> Void

    var body: some View {
        NavigationStack {
            CameraScanner(onScan: onScan)
                .navigationTitle("Scan configuration")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .accessibilityIdentifier("cancelQRScanner")
                    }
                }
        }
    }
}

private struct CameraScanner: UIViewControllerRepresentable {
    let onScan: (String?) -> Void

    func makeUIViewController(context: Context) -> QRScannerController {
        QRScannerController(onScan: onScan)
    }

    func updateUIViewController(_ controller: QRScannerController, context: Context) {}

    static func dismantleUIViewController(_ controller: QRScannerController, coordinator: ()) {
        controller.shutdown()
    }
}

private final class QRScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    // All session configuration/start/stop operations run off the main thread,
    // in order, including stops queued during permission prompts or dismissal.
    private let cameraQueue = DispatchQueue(label: "Moley.QRCamera")
    private var configured = false // cameraQueue only
    private let preview = AVCaptureVideoPreviewLayer()
    private let message = UILabel()
    private let retry = UIButton(type: .system)
    private let settings = UIButton(type: .system)
    private var visible = false
    private var finished = false
    private var requestingPermission = false
    private let onScan: (String?) -> Void

    init(onScan: @escaping (String?) -> Void) {
        self.onScan = onScan
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        preview.session = session
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)

        message.numberOfLines = 0
        message.textAlignment = .center
        message.font = .preferredFont(forTextStyle: .body)
        message.adjustsFontForContentSizeCategory = true
        message.textColor = .white
        message.accessibilityIdentifier = "qrScannerMessage"
        retry.setTitle("Try camera again", for: .normal)
        retry.addTarget(self, action: #selector(startIfAllowed), for: .touchUpInside)
        settings.setTitle("Open Settings", for: .normal)
        settings.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        let panel = UIStackView(arrangedSubviews: [message, retry, settings])
        panel.axis = .vertical
        panel.spacing = 12
        panel.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        panel.isLayoutMarginsRelativeArrangement = true
        panel.directionalLayoutMargins = .init(top: 20, leading: 20, bottom: 20, trailing: 20)
        panel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            panel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            panel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(pause), name: UIApplication.willResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(startIfAllowed), name: UIApplication.didBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(cameraInterrupted), name: AVCaptureSession.wasInterruptedNotification, object: session)
        center.addObserver(self, selector: #selector(startIfAllowed), name: AVCaptureSession.interruptionEndedNotification, object: session)
        center.addObserver(self, selector: #selector(cameraFailed), name: AVCaptureSession.runtimeErrorNotification, object: session)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        visible = true
        startIfAllowed()
    }

    override func viewWillDisappear(_ animated: Bool) {
        visible = false
        pause()
        super.viewWillDisappear(animated)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview.frame = view.bounds
        let angle: CGFloat
        switch view.window?.windowScene?.interfaceOrientation {
        case .landscapeLeft: angle = 180
        case .landscapeRight: angle = 0
        case .portraitUpsideDown: angle = 270
        default: angle = 90
        }
        if let connection = preview.connection, connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }

    @objc private func startIfAllowed() {
        // Capture-session notifications can arrive from the camera queue.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.startIfAllowed() }
            return
        }
        guard visible, !finished, UIApplication.shared.applicationState == .active else { return }
        #if targetEnvironment(simulator)
        show("Camera scanning requires a physical iPhone or iPad. Cancel and choose a configuration file or paste its text instead.")
        return
        #else
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            guard !requestingPermission else { return }
            requestingPermission = true
            show("Allow camera access to scan your configuration QR code.")
            AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.requestingPermission = false
                    self?.startIfAllowed()
                }
            }
        case .authorized:
            show("Point the camera at your personal configuration QR code. Keep the entire code visible. Images are not saved or uploaded.")
            preview.isHidden = false
            cameraQueue.async { [self] in
                do {
                    try configure()
                    if !session.isRunning { session.startRunning() }
                    DispatchQueue.main.async { [weak self] in self?.view.setNeedsLayout() }
                } catch {
                    DispatchQueue.main.async { [weak self] in
                        self?.show("The camera is unavailable. Try again, or cancel and import a file or paste the configuration.", canRetry: true)
                    }
                }
            }
        case .denied:
            show("Camera access is off. Enable it in Settings, or cancel and import a file or paste the configuration.", canOpenSettings: true)
        case .restricted:
            show("Camera access is restricted on this device. Cancel and import a file or paste the configuration.")
        @unknown default:
            show("Camera scanning is unavailable. Cancel and import a file or paste the configuration.")
        }
        #endif
    }

    private func configure() throws {
        guard !configured else { return }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw ProfileError(message: "Camera unavailable.")
        }
        let input = try AVCaptureDeviceInput(device: device)
        let output = AVCaptureMetadataOutput()
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.high) { session.sessionPreset = .high }
        guard session.canAddInput(input) else { throw ProfileError(message: "Camera unavailable.") }
        session.addInput(input)
        guard session.canAddOutput(output) else {
            session.removeInput(input)
            throw ProfileError(message: "QR scanning unavailable.")
        }
        session.addOutput(output)
        guard output.availableMetadataObjectTypes.contains(.qr) else {
            session.removeOutput(output)
            session.removeInput(input)
            throw ProfileError(message: "QR scanning unavailable.")
        }
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        configured = true
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard visible, !finished, UIApplication.shared.applicationState == .active else { return }
        let codes = objects.compactMap { $0 as? AVMetadataMachineReadableCodeObject }.filter { $0.type == .qr }
        guard codes.count == 1, let code = codes.first else { return }
        finished = true
        pause()
        onScan(code.stringValue)
    }

    private func show(_ text: String, canRetry: Bool = false, canOpenSettings: Bool = false) {
        message.text = text
        retry.isHidden = !canRetry
        settings.isHidden = !canOpenSettings
    }

    @objc private func pause() {
        // Hide the last camera frame before iOS takes an app-switcher snapshot.
        preview.isHidden = true
        cameraQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    @objc private func cameraInterrupted() {
        DispatchQueue.main.async { [weak self] in
            self?.show("The camera was interrupted. Close other camera apps, or cancel and use file import.", canRetry: true)
        }
    }

    @objc private func cameraFailed() {
        DispatchQueue.main.async { [weak self] in
            self?.pause()
            self?.show("The camera could not continue. Try again, or cancel and use file import.", canRetry: true)
        }
    }

    @objc private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func shutdown() {
        visible = false
        finished = true
        NotificationCenter.default.removeObserver(self)
        pause()
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}
