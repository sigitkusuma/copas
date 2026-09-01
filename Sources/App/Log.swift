import OSLog

/// The app's loggers, one per area.
///
/// `os.Logger` rather than `print`: these survive into Console.app on a machine
/// that is not attached to Xcode, which is the only place a bug reported by
/// somebody else can be looked at.
enum Log {
    private static let subsystem = "com.sigitkusuma.copas"

    static let store = Logger(subsystem: subsystem, category: "store")
    static let app = Logger(subsystem: subsystem, category: "app")
}
