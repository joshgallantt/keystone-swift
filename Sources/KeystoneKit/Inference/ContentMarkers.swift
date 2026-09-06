import Foundation

/// What a file's own contents say about the layer it belongs to.
///
/// Placement reads names — a directory called `Domain`, a target the manifest
/// calls a test. Names are what somebody meant; contents are what they wrote.
/// Measured over thirty-two open-source iOS apps, 94% of production modules were
/// placed by guessing, and the guessing existed because 196 of them held no file
/// with any evidence of its own — evidence that was sitting in the source,
/// unread. A package of 236 files, 124 of them declaring `: View`, was called
/// the domain.
///
/// The vocabulary here is the platform's, never a project's. `View`, `App`,
/// `NSManagedObject` and `URLSession` belong to Apple, the way `FrameworkCatalog`
/// already argues its own roster does. A project's own protocol — `Endpoint`,
/// `FrontendComponent` — is not read, because a list of those would be the knob
/// that admits the inference failed.
///
/// One asymmetry decides how this may be used: `domain` and `library` have no
/// marker. They are what is left when a file touches no screen, no store and no
/// wire, and absence is not evidence. So contents can say a file IS presentation,
/// composition, data or a test, and can never say a file is the domain — which is
/// exactly the claim the old fallback made on no evidence at all.
public enum ContentMarkers {
    /// Types the platform owns whose adoption places a file in a layer.
    static let presentationConformances: Set<String> = [
        "View", "Scene", "ViewModifier", "ButtonStyle", "LabelStyle", "ToggleStyle",
        "TextFieldStyle", "ProgressViewStyle", "Shape", "InsettableShape", "PreviewProvider",
        "UIView", "UIViewController", "UIViewRepresentable", "UIViewControllerRepresentable",
        "NSView", "NSViewController", "NSViewRepresentable", "UIHostingController",
        "UITableViewCell", "UICollectionViewCell", "Commands", "Transition",
        // A SwiftUI state object is presentation whatever it is called, and it
        // conforms to no view protocol. Nine of the twenty-six files in one
        // module were these, and every conformance-only reading missed them.
        "ObservableObject",
    ]
    static let presentationAttributes: Set<String> = ["Observable"]

    /// An entry point is the one thing composition is unambiguously made of.
    static let compositionConformances: Set<String> = ["App"]
    static let compositionAttributes: Set<String> = ["main", "UIApplicationMain", "NSApplicationMain"]

    static let dataConformances: Set<String> = [
        "NSManagedObject", "NSPersistentContainer", "NSFetchedResultsController",
    ]
    static let dataAttributes: Set<String> = ["Model"]
    static let dataImports: Set<String> = ["CoreData", "SwiftData"]
    /// Reached through Foundation, which every layer may import, so an import
    /// rule cannot see them. `RestrictedSymbolRule` already reads them this way.
    static let dataSymbols: Set<String> = [
        "URLSession", "URLRequest", "FileManager", "UserDefaults", "NSFetchRequest",
    ]

    static let testConformances: Set<String> = ["XCTestCase"]
    static let testImports: Set<String> = ["XCTest", "Testing"]

    /// Every layer whose machinery this file is built on.
    ///
    /// More than one is not an ambiguity to resolve. A file holding a screen and
    /// a network call is two layers in one file, and the contradiction is worth
    /// reporting rather than voting on — so this returns the set, and the caller
    /// decides.
    public static func layers(in facts: SourceFacts) -> Set<Role> {
        var found: Set<Role> = []

        let imports = Set(facts.imports.map(\.module))
        let referenced = Set(facts.typeReferences.map(\.name))
        let declarations = facts.declarations + facts.extensions
        let conformances = Set(declarations.flatMap(\.inheritedTypes))
        let attributes = Set(declarations.flatMap(\.attributes))

        if !conformances.isDisjoint(with: testConformances) || !imports.isDisjoint(with: testImports) {
            found.insert(.tests)
        }
        if !conformances.isDisjoint(with: presentationConformances)
            || !attributes.isDisjoint(with: presentationAttributes) {
            found.insert(.presentation)
        }
        if !conformances.isDisjoint(with: compositionConformances)
            || !attributes.isDisjoint(with: compositionAttributes) {
            found.insert(.composition)
        }
        if !conformances.isDisjoint(with: dataConformances)
            || !attributes.isDisjoint(with: dataAttributes)
            || !imports.isDisjoint(with: dataImports)
            || !referenced.isDisjoint(with: dataSymbols) {
            found.insert(.data)
        }

        return found
    }

    /// The one layer this file's contents place it in, or nothing.
    ///
    /// Nothing when the file says nothing, and nothing when it says two things:
    /// a file that is both a screen and a store has not told us where it
    /// belongs, it has told us it is in the wrong shape.
    public static func role(of facts: SourceFacts) -> Role? {
        let layers = ContentMarkers.layers(in: facts)
        return layers.count == 1 ? layers.first : nil
    }
}
