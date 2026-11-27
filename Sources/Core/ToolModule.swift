import AppKit

/// Protocol implemented by every built-in tool module inside MakeTools.
public protocol ToolModule: AnyObject {
    var id: String { get }
    var title: String { get }
    var subtitle: String { get }
    var symbolName: String { get }
    func makeViewController() -> NSViewController
}

/// Central registry of tools displayed in the MakeTools sidebar.
public enum ToolRegistry {
    public static func defaultTools() -> [ToolModule] {
        [
            MarkdownPreviewTool(),
            DynamicIslandTool(),
            ExtensionsOverviewTool()
        ]
    }
}
