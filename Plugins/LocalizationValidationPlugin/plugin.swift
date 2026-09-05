import Foundation
import PackagePlugin

@main
struct LocalizationValidationPlugin: BuildToolPlugin {
    func createBuildCommands(
        context: PluginContext,
        target: Target
    ) throws -> [Command] {
        let validator = try context.tool(named: "LocalizationValidator")
        let packageDirectory = context.package.directoryURL
        let catalog = packageDirectory
            .appendingPathComponent("Sources/ScreenContext/Resources/Localizable.xcstrings")
        let appLanguage = packageDirectory
            .appendingPathComponent("Sources/ScreenContextCore/Models/Preferences.swift")
        let sourceFiles = swiftSourceFiles(in: packageDirectory)
        let output = context.pluginWorkDirectoryURL
            .appendingPathComponent("translations.valid")

        return [
            .buildCommand(
                displayName: "Validate complete ScreenContext translations",
                executable: validator.url,
                arguments: [
                    catalog.path,
                    appLanguage.path,
                    output.path,
                ] + sourceFiles.map(\.path),
                inputFiles: [catalog] + sourceFiles,
                outputFiles: [output]
            ),
        ]
    }

    private func swiftSourceFiles(in packageDirectory: URL) -> [URL] {
        let root = packageDirectory.appendingPathComponent("Sources")
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator.compactMap { item in
            guard let url = item as? URL, url.pathExtension == "swift" else {
                return nil
            }
            return url
        }
            .sorted { $0.path < $1.path }
    }
}
