import Foundation

/// Tools whose name starts with "_" (built-in or from an MCP server) are not offered to the model;
/// `search_tools` finds them, and a found one is offered for the rest of the answer.
enum HiddenTools {
    /// `server__tool`: whether the tool part starts with "_".
    static func isHidden(_ functionName: String) -> Bool {
        guard let range = functionName.range(of: "__") else { return false }
        return functionName[range.upperBound...].hasPrefix("_")
    }
}
