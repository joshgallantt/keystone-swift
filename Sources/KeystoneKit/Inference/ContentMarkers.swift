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

    /// Endings of a *superclass* name that make the subclass a screen.
    ///
    /// Apple names consistently, and the roster above cannot list every base
    /// class in the SDK: `ASCredentialProviderViewController` is not in it, so
    /// duckduckgo's autofill view controller fell through to its directory —
    /// `CredentialProvider/`, which ends in a data word — and was read as the
    /// data layer, then reported 144 times for using the views it exists to
    /// show. A superclass is a declaration, and one whose own name ends in
    /// `ViewController` is not a repository whatever folder it sits in.
    static let presentationConformanceSuffixes: [String] = [
        "ViewController", "View", "Cell", "ViewModel",
    ]

    static func isPresentationConformance(_ name: String) -> Bool {
        if presentationConformances.contains(name) { return true }
        // Longer than the suffix itself, so the exact names above stay the
        // roster and this only ever reaches further.
        return presentationConformanceSuffixes.contains {
            name.count > $0.count && name.hasSuffix($0)
        }
    }

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

    /// Every layer whose machinery this file is built on, and the thing that
    /// said so.
    ///
    /// More than one is not an ambiguity to resolve. A file holding a screen and
    /// a network call is two layers in one file, and the contradiction is worth
    /// reporting rather than voting on — so this returns them all, with a
    /// witness for each, and the caller decides.
    public static func layers(in facts: SourceFacts) -> [Role: String] {
        var found: [Role: String] = [:]

        let imports = Set(facts.imports.map(\.module))
        let referenced = Set(facts.typeReferences.map(\.name))
        let declarations = facts.declarations + facts.extensions
        let conformances = Set(declarations.flatMap(\.inheritedTypes))
        let attributes = Set(declarations.flatMap(\.attributes))

        func witness(_ role: Role, _ candidates: Set<String>, in present: Set<String>, as shape: (String) -> String) {
            guard found[role] == nil, let name = present.intersection(candidates).sorted().first else { return }
            found[role] = shape(name)
        }

        witness(.tests, testConformances, in: conformances) { "`: \($0)`" }
        witness(.tests, testImports, in: imports) { "`import \($0)`" }

        if found[.presentation] == nil,
           let name = conformances.filter(isPresentationConformance).sorted().first {
            found[.presentation] = "`: \(name)`"
        }
        witness(.presentation, presentationAttributes, in: attributes) { "`@\($0)`" }

        witness(.composition, compositionConformances, in: conformances) { "`: \($0)`" }
        witness(.composition, compositionAttributes, in: attributes) { "`@\($0)`" }

        witness(.data, dataConformances, in: conformances) { "`: \($0)`" }
        witness(.data, dataAttributes, in: attributes) { "`@\($0)`" }
        witness(.data, dataImports, in: imports) { "`import \($0)`" }
        witness(.data, dataSymbols, in: referenced) { "`\($0)`" }

        return found
    }

    /// What each layer's machinery was DECLARED with, and where.
    ///
    /// Declarations only — a conformance, a subclass, an attribute. No import
    /// and no symbol, because those are the two things other rules already
    /// read: `framework-purity` reports `import CoreData` in a screen, and
    /// `restricted-symbols` reports `UserDefaults` in one. A mixture rule that
    /// counted them said the same thing a second time, in different words, on
    /// the same line of the same file.
    ///
    /// What is left is the case that gives the rule its name: two layers
    /// declared in one file, which no import records and no module boundary
    /// crosses, so nothing else in the tool can see it.
    public static func declaredLayers(in facts: SourceFacts) -> [Role: (witness: String, line: Int)] {
        var found: [Role: (witness: String, line: Int)] = [:]

        // Earliest line, not first in the array: extensions are appended after
        // declarations, so reading in array order would report a conformance on
        // line 90 while the one on line 12 went unmentioned.
        let declarations = (facts.declarations + facts.extensions).sorted { $0.line < $1.line }

        func look(_ role: Role, conformances: Set<String>, attributes: Set<String>) {
            for declaration in declarations {
                if let name = declaration.inheritedTypes.sorted().first(where: {
                    role == .presentation ? isPresentationConformance($0) : conformances.contains($0)
                }) {
                    found[role] = ("`: \(name)`", declaration.line)
                    return
                }
                if let name = Set(declaration.attributes).intersection(attributes).sorted().first {
                    found[role] = ("`@\(name)`", declaration.line)
                    return
                }
            }
        }

        look(.tests, conformances: testConformances, attributes: [])
        look(.presentation, conformances: presentationConformances, attributes: presentationAttributes)
        look(.composition, conformances: compositionConformances, attributes: compositionAttributes)
        look(.data, conformances: dataConformances, attributes: dataAttributes)

        return found
    }

    /// The one layer this file DECLARES ITSELF to be, or nothing.
    ///
    /// Only what the file says it *is* — a conformance, a subclass, an
    /// attribute. Not what it touches. That distinction decides whether a fact
    /// may outrank a directory name, and both directions matter:
    ///
    /// A file in `Domain/` that names `URLSession` is a domain file doing
    /// something the domain forbids. That is the violation `restricted-symbols`
    /// exists to report, and re-reading the file as `data` because it mentions a
    /// session would delete the finding by agreeing with the mistake.
    ///
    /// A file in `UseCases/` that declares `: View` is not a use case. It has
    /// said what it is, the compiler agrees, and the folder is a bucket somebody
    /// named once.
    ///
    /// So: what a file IS outranks what a folder is called. What a file merely
    /// USES does not — that is for the rules to judge, against the layer the
    /// project put it in.
    public static func declaredRole(of facts: SourceFacts) -> Role? {
        let declarations = facts.declarations + facts.extensions
        let conformances = Set(declarations.flatMap(\.inheritedTypes))
        let attributes = Set(declarations.flatMap(\.attributes))

        var found: Set<Role> = []
        if !conformances.isDisjoint(with: testConformances) { found.insert(.tests) }
        if conformances.contains(where: isPresentationConformance)
            || !attributes.isDisjoint(with: presentationAttributes) { found.insert(.presentation) }
        if !conformances.isDisjoint(with: compositionConformances)
            || !attributes.isDisjoint(with: compositionAttributes) { found.insert(.composition) }
        if !conformances.isDisjoint(with: dataConformances)
            || !attributes.isDisjoint(with: dataAttributes) { found.insert(.data) }

        return found.count == 1 ? found.first : nil
    }

    /// The one layer this file TOUCHES, or nothing.
    ///
    /// Weaker than `declaredRole`, and used later: an `import CoreData` says
    /// something about a file, but not the same thing a `: NSManagedObject`
    /// says. So this is read only after every name in the path has been read
    /// and none of them spoke — the last question before giving up on a file
    /// altogether.
    ///
    /// Splitting placement across two rungs rather than one is what keeps both
    /// answers honest. Reading usage as strongly as declaration re-labelled a
    /// file in `Domain/` naming `URLSession` as `data`, which deletes
    /// `restricted-symbols` by agreeing with the mistake. Refusing to read
    /// usage at all left 717 files across the sample with no layer, and a file
    /// with no layer gets no rule at all — the quieter failure, and the worse
    /// one.
    ///
    /// Nothing when the file says nothing, and nothing when it says two things:
    /// a file that is both a screen and a store has not told us where it
    /// belongs, it has told us it is in the wrong shape.
    public static func usedRole(of facts: SourceFacts) -> Role? {
        let layers = ContentMarkers.layers(in: facts)
        return layers.count == 1 ? layers.keys.first : nil
    }
}
