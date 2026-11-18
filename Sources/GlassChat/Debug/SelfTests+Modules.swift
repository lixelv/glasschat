#if DEBUG
import Foundation

extension SelfTests {
    static func modules() {
        let all = MCPManager.shared.allFunctions()
        let builtIn = all.keys.filter { $0.hasPrefix(MCPManager.registryPrefix + "__") }
        expect(builtIn.allSatisfy { AppModule.of($0) != nil }, "every built-in tool has a module")
        let necessary = Set(builtIn.filter { AppModule.of($0) == .necessary })
        expect(necessary == [MCPManager.searchName, MCPManager.searchAllName, "glasschat__app_say", "glasschat__app_ask_user",
                             "glasschat__app_expand_notch"],
               "necessary: the two searches, app_say, app_ask_user and app_expand_notch")
        expect(AppModule.of("glasschat__app_bash") == .files && AppModule.of("glasschat___mcp_registry_add") == .mcp
               && AppModule.of("glasschat___app_set_model") == .models && AppModule.of("glasschat___app_alert") == .user,
               "tools sit in their modules")
        expect(AppModule.files.key == "__app__.files", "a module's switch key")
        expect(!AppModule.switchable.contains(.necessary), "necessary cannot be switched off")

        let everyModule = Set(AppModule.switchable.map(\.key))
        expect(AppSettings.migratedDisabled(["__app__", "srv"]) == everyModule.union(["srv"]),
               "the old App switch becomes every module")
        expect(AppSettings.migratedDisabled(["srv"]) == ["srv"], "other switches stay")

        let offered = MCPManager.shared.functions(disabled: everyModule)
        expect(necessary.isSubset(of: Set(offered.keys)), "necessary tools are offered with every module off")
        expect(offered["glasschat__app_read"] == nil, "a switched-off module is not offered")
        expect(all["glasschat___app_notify"] != nil && all["glasschat___app_alert"] != nil, "notify and alert are hidden")
        let ask = (try? JSONEncoder().encode(all["glasschat__app_ask_user"]!.definition).count) ?? .max
        expect(ask <= 600, "app_ask_user is short (\(ask) bytes)")

        // The two searches: search_tools among the hidden tools of what is on, search_all_tools among every tool.
        func function(_ group: String?) -> MCPManager.Function {
            MCPManager.Function(definition: .null, target: .search, group: group, summary: "s")
        }
        let fixture: [String: MCPManager.Function] = [
            "glasschat__search_tools": function(nil),
            "glasschat__app_read": function(AppModule.files.key),
            "glasschat___app_list_chats": function(AppModule.chats.key),
            "glasschat___app_set_model": function(AppModule.models.key),
            "ddg__search": function("ddg-id"),
            "gh__issues": function("gh-id"),
        ]
        let off: Set<String> = [AppModule.models.key]
        let demand: Set<String> = ["ddg-id"]
        expect(Set(ToolCatalog.candidates(fixture, scope: .hidden, disabled: off, onDemand: demand).keys)
               == ["glasschat___app_list_chats", "ddg__search"], "search_tools: hidden tools and on-demand servers that are on")
        expect(Set(ToolCatalog.candidates(fixture, scope: .all, disabled: off, onDemand: demand).keys)
               == Set(fixture.keys).subtracting(["glasschat__search_tools"]), "search_all_tools: every tool but the searches")
        let offeredNow = ToolCatalog.offered(fixture, disabled: off, found: [], onDemand: demand)
        expect(Set(offeredNow.keys) == ["glasschat__search_tools", "glasschat__app_read", "gh__issues"],
               "offered: visible tools of what is on")
        expect(ToolCatalog.offered(fixture, disabled: off, found: ["ddg__search", "glasschat___app_set_model"], onDemand: demand).count == 5,
               "found tools are offered, switched off or on demand")
    }
}
#endif
