import Foundation

/// Machine-readable output, for CI annotations and for anything that wants to
/// act on the findings rather than read them.
public enum JSONReport {
    struct Payload: Encodable {
        var filesChecked: Int
        var errors: Int
        var warnings: Int
        var accepted: Int
        var violations: [Violation]
    }

    public static func render(_ result: CheckResult, accepted: Int) -> String {
        let payload = Payload(
            filesChecked: result.filesChecked,
            errors: result.errors.count,
            warnings: result.warnings.count,
            accepted: accepted,
            violations: result.violations
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(payload),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}
