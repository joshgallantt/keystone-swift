import Foundation

/// Every rule the tool knows, in the order it reports them.
///
/// Order is boundaries first, then placement, then hygiene — which is also the
/// order they are worth fixing in. A misplaced file is cosmetic while the layer
/// it is in can still reach into storage.
public enum RuleRegistry {
    public static let all: [any Rule] = [
        ImportBoundaryRule(),
        TargetDependencyRule(),
        FrameworkBoundaryRule(),
        ThirdPartyBoundaryRule(),
        RestrictedSymbolRule(),
        TypeReferenceBoundaryRule(),
        LayerMixtureRule(),
        ModuleCycleRule(),
        DeclarationPlacementRule(),
        ExtensionBoundaryRule(),
        UndeclaredImportRule(),
        UnusedDependencyRule(),
        ContractBeforeImplementationRule(),
        LayerVocabularyRule(),
        SharedSingletonRule(),
        TestSupportRule(),
        TestDoubleRule(),
        DoubleOwnershipRule(),
        AcceptanceVocabularyRule(),
        TestNamingRule(),
        SnapshotArtifactRule(),
        UnclassifiedFileRule()
    ]

    /// Rules that can decide from a single file, used by the pre-write hook.
    public static var perFile: [any Rule] {
        all.filter { !$0.needsWholeProject }
    }

    public static var identifiers: [String] {
        Array(Set(all.flatMap(\.emittedIdentifiers))).sorted()
    }
}
