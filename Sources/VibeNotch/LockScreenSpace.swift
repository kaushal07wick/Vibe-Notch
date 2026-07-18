import AppKit

/// Labs: pin the notch window into a max-level CGS space so it stays visible
/// over the lock screen and full-screen apps (private SkyLight API — the same
/// technique boring.notch ships). Off by default; enable via Labs menu.
@MainActor
final class LockScreenSpace {
    private let space: CGSSpaceID
    private var attached: Int32?

    init() {
        space = CGSSpaceCreate(_CGSDefaultConnection(), 0x1, nil) // flag MUST be 1
        CGSSpaceSetAbsoluteLevel(_CGSDefaultConnection(), space, 2_147_483_647)
        CGSShowSpaces(_CGSDefaultConnection(), [space] as NSArray)
    }

    func attach(_ window: NSWindow) {
        detach()
        CGSAddWindowsToSpaces(_CGSDefaultConnection(), [window.windowNumber] as NSArray, [space] as NSArray)
        attached = Int32(window.windowNumber)
    }

    func detach() {
        guard let number = attached else { return }
        CGSRemoveWindowsFromSpaces(_CGSDefaultConnection(), [number] as NSArray, [space] as NSArray)
        attached = nil
    }

    deinit {
        CGSHideSpaces(_CGSDefaultConnection(), [space] as NSArray)
        CGSSpaceDestroy(_CGSDefaultConnection(), space)
    }
}

// Private SkyLight symbols (widely used; see boring.notch / Parrot).
private typealias CGSConnectionID = UInt
private typealias CGSSpaceID = UInt64
@_silgen_name("_CGSDefaultConnection")
private func _CGSDefaultConnection() -> CGSConnectionID
@_silgen_name("CGSSpaceCreate")
private func CGSSpaceCreate(_ cid: CGSConnectionID, _ flag: Int, _ options: NSDictionary?) -> CGSSpaceID
@_silgen_name("CGSSpaceDestroy")
private func CGSSpaceDestroy(_ cid: CGSConnectionID, _ space: CGSSpaceID)
@_silgen_name("CGSSpaceSetAbsoluteLevel")
private func CGSSpaceSetAbsoluteLevel(_ cid: CGSConnectionID, _ space: CGSSpaceID, _ level: Int)
@_silgen_name("CGSShowSpaces")
private func CGSShowSpaces(_ cid: CGSConnectionID, _ spaces: NSArray)
@_silgen_name("CGSHideSpaces")
private func CGSHideSpaces(_ cid: CGSConnectionID, _ spaces: NSArray)
@_silgen_name("CGSAddWindowsToSpaces")
private func CGSAddWindowsToSpaces(_ cid: CGSConnectionID, _ windows: NSArray, _ spaces: NSArray)
@_silgen_name("CGSRemoveWindowsFromSpaces")
private func CGSRemoveWindowsFromSpaces(_ cid: CGSConnectionID, _ windows: NSArray, _ spaces: NSArray)
