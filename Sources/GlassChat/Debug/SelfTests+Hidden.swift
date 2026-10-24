#if DEBUG
import Foundation

extension SelfTests {
    static func hidden() {
        expect(HiddenTools.isHidden("glasschat___app_list_chats"), "built-in with _ is hidden")
        expect(HiddenTools.isHidden("github___private"), "MCP tool with _ is hidden")
        expect(!HiddenTools.isHidden("glasschat__app_say"), "a plain tool is offered")
        expect(!HiddenTools.isHidden("_weird"), "no server part: not hidden")
        let offered = MCPManager.shared.functions(disabled: [])
        expect(offered["glasschat___app_list_chats"] == nil, "hidden tools are not offered")
        expect(offered["glasschat__app_say"] != nil, "visible tools are offered")
        expect(MCPManager.shared.functions(disabled: [], found: ["glasschat___app_list_chats"])["glasschat___app_list_chats"] != nil,
               "found by search_tools: offered")
    }
}
#endif
