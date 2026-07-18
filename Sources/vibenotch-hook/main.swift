import Foundation
import VibeNotchCore

// Hook client. Fail-open always: never block the agent if the app is down.
// Real IPC wiring (PermissionRequest blocking + notify) lands in a later task.
// For now this is a no-op that exits cleanly so it can be installed and smoke-tested.

_ = VNPaths.socket
exit(0)
