#if DEBUG
import Foundation

extension SelfTests {
    static func modules() {
        let all = MCPManager.shared.allFunctions()
        let builtIn = all.keys.filter { $0.hasPrefix(MCPManager.registryPrefix + "__") }
        expect(builtIn.allSatisfy { AppModule.of($0) != nil }, "every built-in tool has a module")
        let necessary = Set(builtIn.filter { AppModule.of($0) == .necessary })
        expect(necessary == [MCPManager.searchName, MCPManager.searchAllName, "glasschat__app_say"],
               "necessary: the two searches and app_say")
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
    }
}
#endif
