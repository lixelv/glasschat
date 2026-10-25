import Foundation

/// Which tools the model is offered and which each search looks through. Hidden tools (named with "_", or of a
/// server set to on demand) are not offered until a search finds them; switched-off modules and servers are
/// offered only when `search_all_tools` found them.
@MainActor
enum ToolCatalog {
    enum Scope { case hidden, all }

    static func isHidden(_ name: String, group: String?, onDemand: Set<String>) -> Bool {
        HiddenTools.isHidden(name) || group.map(onDemand.contains) == true
    }

    /// What the model is offered: the necessary tools, the visible tools of what is on, and what a search found.
    static func offered(_ all: [String: MCPManager.Function], disabled: Set<String>, found: Set<String>,
                        onDemand: Set<String>) -> [String: MCPManager.Function] {
        all.filter { name, function in
            if found.contains(name) { return true }
            guard let group = function.group else { return true }
            return !disabled.contains(group) && !isHidden(name, group: group, onDemand: onDemand)
        }
    }

    /// What a search looks through (name → summary): `.hidden` the hidden tools of what is on, `.all` every tool
    /// but the necessary ones.
    static func candidates(_ all: [String: MCPManager.Function], scope: Scope, disabled: Set<String>,
                           onDemand: Set<String>) -> [String: String] {
        all.filter { name, function in
            guard let group = function.group else { return false }
            switch scope {
            case .all: return true
            case .hidden: return !disabled.contains(group) && isHidden(name, group: group, onDemand: onDemand)
            }
        }
        .mapValues(\.summary)
    }
}
