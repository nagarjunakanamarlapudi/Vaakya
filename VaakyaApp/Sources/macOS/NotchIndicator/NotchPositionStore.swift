#if os(macOS)
import AppKit

enum NotchPositionStore {
    private static let keyPrefix = "notchIndicator.position.x."

    static func savedX(for screen: NSScreen) -> CGFloat? {
        guard let id = screenID(screen) else { return nil }
        let key = keyPrefix + id
        guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
        return CGFloat(UserDefaults.standard.double(forKey: key))
    }

    static func save(x: CGFloat, for screen: NSScreen) {
        guard let id = screenID(screen) else { return }
        UserDefaults.standard.set(Double(x), forKey: keyPrefix + id)
    }

    static func reset(for screen: NSScreen) {
        guard let id = screenID(screen) else { return }
        UserDefaults.standard.removeObject(forKey: keyPrefix + id)
    }

    private static func screenID(_ screen: NSScreen) -> String? {
        // CGDirectDisplayID is unique per physical display and stable across renames / display
        // configuration changes — unlike localizedName, which collides on identical monitors.
        if let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return "id.\(num.uint32Value)"
        }
        #if DEBUG
        print("[NotchPositionStore] screen has no NSScreenNumber; position will not persist")
        #endif
        return nil
    }
}
#endif
