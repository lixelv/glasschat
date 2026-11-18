import Foundation

/// The built-in tools in parts the user switches on and off one by one ("App" in the Tools popover).
/// `necessary` (the two searches, app_say, app_ask_user and app_expand_notch) is always on and not shown.
enum AppModule: String, CaseIterable, Sendable {
    case necessary, files, user, clipboard, chats, models, mcp, visualize

    /// Its switch in `AppSettings.disabledTools`.
    var key: String { AppTool.key + "." + rawValue }

    /// The switch its tools belong to; nil for `necessary`, which cannot be switched off.
    var group: String? { self == .necessary ? nil : key }

    static var switchable: [AppModule] { allCases.filter { $0 != .necessary } }

    var title: String {
        switch self {
        case .necessary: "Necessary"
        case .files: "Files & Terminal"
        case .user: "Notifications & Alerts"
        case .clipboard: "Clipboard"
        case .chats: "Chats"
        case .models: "Models"
        case .mcp: "MCP Servers"
        case .visualize: "Visualize"
        }
    }

    var summary: String {
        switch self {
        case .necessary: "Tool search, speaking and questions with suggested answers"
        case .files: "Read, write and edit files; run commands in zsh"
        case .user: "Notifications and alert windows"
        case .clipboard: "Read and replace the clipboard's text"
        case .chats: "List, create, switch, rename and delete chats"
        case .models: "List models and change a chat's model"
        case .mcp: "Switch MCP servers and edit their registry"
        case .visualize: "Charts, diagrams and pages drawn in the chat; their libraries"
        }
    }

    /// The module of a built-in function ("glasschat__app_read"); nil for other servers' tools.
    static func of(_ functionName: String) -> AppModule? {
        let prefix = MCPManager.registryPrefix + "__"
        guard functionName.hasPrefix(prefix) else { return nil }
        let name = String(functionName.dropFirst(prefix.count))
        if name == "search_tools" || name == "search_all_tools" { return .necessary }
        if let tool = AppTool(rawValue: name) { return tool.module }
        if MCPManager.RegistryTool(rawValue: name) != nil { return .mcp }
        return nil
    }
}
