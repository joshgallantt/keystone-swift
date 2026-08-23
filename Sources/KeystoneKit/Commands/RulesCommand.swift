import Foundation

extension Commands {
    static func rules(_ arguments: Arguments) -> Int32 {
        guard let project = Commands.resolveProject(arguments) else { return ExitCode.undecidable }
        Output.write(RulesDocument.render(project.configuration))
        return ExitCode.clean
    }
}
