@preconcurrency import AVFoundation
import Foundation

public enum CaptureDeviceCatalog {
    public static func cameras() -> [CaptureDeviceOption] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        return discovery.devices.map {
            CaptureDeviceOption(id: $0.uniqueID, name: $0.localizedName)
        }
    }

    public static func microphones() -> [CaptureDeviceOption] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        return discovery.devices.map {
            CaptureDeviceOption(id: $0.uniqueID, name: $0.localizedName)
        }
    }

    public static func camera(withID id: String?) -> AVCaptureDevice? {
        if let id, let device = AVCaptureDevice(uniqueID: id) {
            return device
        }
        return AVCaptureDevice.default(for: .video)
    }

    public static func microphone(withID id: String?) -> AVCaptureDevice? {
        if let id, let device = AVCaptureDevice(uniqueID: id) {
            return device
        }
        return AVCaptureDevice.default(for: .audio)
    }
}
