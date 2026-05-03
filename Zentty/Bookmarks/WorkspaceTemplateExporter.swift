import Foundation

enum WorkspaceTemplateExporter {
    static let fileExtension = "zenttypreset"

    struct ExportEnvelope: Codable, Equatable, Sendable {
        static let currentSchemaVersion = 1

        var schemaVersion: Int
        var exportedAt: Date
        var template: WorkspaceTemplate

        init(
            schemaVersion: Int = ExportEnvelope.currentSchemaVersion,
            exportedAt: Date = Date(),
            template: WorkspaceTemplate
        ) {
            self.schemaVersion = schemaVersion
            self.exportedAt = exportedAt
            self.template = template
        }
    }

    static func export(_ template: WorkspaceTemplate) throws -> Data {
        let envelope = ExportEnvelope(template: presetCopy(of: template))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(envelope)
    }

    static func write(_ template: WorkspaceTemplate, to url: URL) throws {
        let data = try export(template)
        try data.write(to: url, options: .atomic)
    }

    enum ImportError: LocalizedError, Equatable {
        case schemaVersionTooNew(found: Int, supported: Int)

        var errorDescription: String? {
            switch self {
            case .schemaVersionTooNew(let found, let supported):
                return "This preset was created by a newer version of Zentty (schema \(found), supported up to \(supported)). Update Zentty to import it."
            }
        }
    }

    static func importTemplate(from data: Data) throws -> WorkspaceTemplate {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(ExportEnvelope.self, from: data)
        if envelope.schemaVersion > ExportEnvelope.currentSchemaVersion {
            throw ImportError.schemaVersionTooNew(
                found: envelope.schemaVersion,
                supported: ExportEnvelope.currentSchemaVersion
            )
        }
        var template = envelope.template
        template.id = UUID()
        template.createdAt = Date()
        template.updatedAt = Date()
        template.lastUsedAt = nil
        template.pinned = false
        return template
    }

    static func read(from url: URL) throws -> WorkspaceTemplate {
        let data = try Data(contentsOf: url)
        return try importTemplate(from: data)
    }

    private static func presetCopy(of template: WorkspaceTemplate) -> WorkspaceTemplate {
        guard template.kind == .bookmark else {
            return template
        }
        return template.strippingWorkingDirectories()
    }
}
