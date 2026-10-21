import AppKit
import CoreGraphics
import ScreenCaptureKit

struct CaptureDisplay: Identifiable {
    let id: CGDirectDisplayID
    let name: String
}

struct CapturedScreen {
    let jpegData: Data
    let image: NSImage
}

@MainActor
final class ScreenCapture {
    /// Listing attached displays does not request screen-recording permission.
    func displays() -> [CaptureDisplay] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            return CaptureDisplay(id: number.uint32Value, name: screen.localizedName)
        }
    }

    /// Called only after the person chooses to analyze their screen.
    func capture(displayID: CGDirectDisplayID?) async throws -> CapturedScreen {
        let content = try await ScreenCaptureAccess.content()
        try Task.checkCancellation()
        let requestedID = displayID ?? CGMainDisplayID()
        guard let display = content.displays.first(where: { $0.displayID == requestedID }) else {
            throw ScreenCaptureError.displayUnavailable
        }
        let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        // Bound memory and image payload size while retaining the display's aspect ratio.
        let width = max(1, CGDisplayPixelsWide(display.displayID))
        let height = max(1, CGDisplayPixelsHigh(display.displayID))
        let scale = min(1.0, 2048.0 / Double(max(width, height)))
        configuration.width = max(1, Int(Double(width) * scale))
        configuration.height = max(1, Int(Double(height) * scale))
        configuration.showsCursor = false
        configuration.capturesAudio = false
        let image: CGImage
        do {
            image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch { throw ScreenCaptureAccess.describe(error) }
        try Task.checkCancellation()
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.82]) else {
            throw ScreenCaptureError.encodingFailed
        }
        return CapturedScreen(
            jpegData: data, image: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)))
    }
}

@MainActor
enum ScreenCaptureAccess {
    static func content() async throws -> SCShareableContent {
        // ScreenCaptureKit owns the permission decision. A legacy CoreGraphics
        // preflight result must not veto a working modern capture session.
        do { return try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) } catch {
            throw describe(error)
        }
    }

    static func describe(_ error: Error) -> Error {
        let native = error as NSError
        if native.domain == SCStreamErrorDomain && native.code == SCStreamError.Code.userDeclined.rawValue {
            return ScreenCaptureError.permissionRequired
        }
        return error
    }
}

private enum ScreenCaptureError: LocalizedError {
    case permissionRequired, displayUnavailable, encodingFailed

    var errorDescription: String? {
        switch self {
        case .permissionRequired:
            return
                "macOS denied screen access to this build of Lumen. In System Settings → Privacy & Security → Screen & System Audio Recording, remove the old Lumen entry and add this app again if it is already enabled. Then quit and reopen Lumen."
        case .displayUnavailable:
            return "The selected display is no longer available. Choose a display and try again."
        case .encodingFailed:
            return "The screenshot could not be prepared. Try capturing the screen again."
        }
    }
}
