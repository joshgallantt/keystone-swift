import Foundation

/// Protocols the platform declares, which a project cannot see the shape of.
///
/// The extension rule permits a protocol extension, because that is one of the
/// two jobs only an extension can do. The symbol index can answer "is this a
/// protocol" for anything the project declared, and nothing for anything it did
/// not — so `extension View { func sheetHost() }`, the ordinary way to write a
/// SwiftUI modifier, looked exactly like `extension String { ... }`.
///
/// This is platform knowledge rather than project knowledge, which is why it
/// can be a fixed list, and why it sits beside `FrameworkCatalog` rather than
/// in anyone's configuration. Add to it there if a project extends a protocol
/// this misses.
public enum PlatformProtocols {
    public static func contains(_ name: String) -> Bool {
        known.contains(name)
    }

    public static let known: Set<String> = [
        // Swift standard library
        "Equatable", "Hashable", "Comparable", "Identifiable", "Sendable",
        "Codable", "Encodable", "Decodable", "Error", "LocalizedError",
        "CaseIterable", "RawRepresentable", "CustomStringConvertible",
        "CustomDebugStringConvertible", "TextOutputStreamable",
        "Sequence", "Collection", "BidirectionalCollection", "RandomAccessCollection",
        "MutableCollection", "RangeReplaceableCollection", "IteratorProtocol",
        "StringProtocol", "OptionSet", "Strideable", "Numeric", "AdditiveArithmetic",
        "BinaryInteger", "BinaryFloatingPoint", "FloatingPoint", "SignedNumeric",
        "AsyncSequence", "AsyncIteratorProtocol", "Actor", "GlobalActor",
        "ExpressibleByStringLiteral", "ExpressibleByIntegerLiteral",
        "ExpressibleByArrayLiteral", "ExpressibleByDictionaryLiteral",
        "ExpressibleByStringInterpolation", "ExpressibleByNilLiteral",

        // SwiftUI
        "View", "ViewModifier", "Shape", "InsettableShape", "Animatable",
        "Layout", "Scene", "Commands", "Gesture", "DynamicProperty",
        "ButtonStyle", "PrimitiveButtonStyle", "LabelStyle", "ToggleStyle",
        "TextFieldStyle", "TextEditorStyle", "ProgressViewStyle", "MenuStyle",
        "PickerStyle", "ListStyle", "GaugeStyle", "GroupBoxStyle", "FormStyle",
        "ControlGroupStyle", "DisclosureGroupStyle", "IndexViewStyle",
        "TabViewStyle", "WindowStyle", "ShapeStyle", "Transition",
        "EnvironmentKey", "PreferenceKey", "FocusedValueKey", "ToolbarContent",
        "TableRowContent", "TableColumnContent", "CustomAnimation", "Widget",
        "WidgetBundle", "WidgetConfiguration", "Transferable", "ChartContent",

        // Combine and observation
        "Publisher", "Subscriber", "Subject", "Scheduler", "Cancellable",
        "ObservableObject", "Observable",

        // Foundation and UIKit protocols people genuinely extend
        "NSObjectProtocol", "Numeric", "DataProtocol", "ContiguousBytes",
        "AttributedStringProtocol", "FormatStyle", "ParseableFormatStyle",
        "AppIntent", "EntityQuery"
    ]
}
