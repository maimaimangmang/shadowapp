import Darwin
import Foundation

/// An OS-owned, per-profile lease. The descriptor is closed on release or process exit.
/// Lock files live outside profile folders and are never unlinked while in use.
public final class ProfileOperationLease {
    private var descriptor: Int32

    init(url: URL) throws {
        let fd = Darwin.open(url.path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
            Darwin.close(fd)
            throw LauncherError("空间操作锁不可用，请检查数据目录。", "The profile operation lock is unavailable. Check the data folder.")
        }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(fd)
            throw LauncherError("另一个启动器正在操作此空间，请稍后重试。", "Another launcher is working on this profile. Try again shortly.")
        }
        descriptor = fd
    }

    public func release() {
        guard descriptor >= 0 else { return }
        Darwin.close(descriptor)
        descriptor = -1
    }

    deinit { release() }
}
