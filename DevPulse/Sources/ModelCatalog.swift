import Foundation

/// Loads the shared AI model catalog (single source of truth: the
/// devpulse-website repo's `src/data/models.json`, copied into the app
/// bundle by build.sh). Falls back to the bundled Swift literal if the
/// JSON isn't present.

private struct CatalogQuant: Decodable {
    let format: String
    let bits: Int
    let vramGb: Double
    let quality: String
}

private struct CatalogEntry: Decodable {
    let name: String
    let slug: String
    let provider: String
    let parameters: String
    let architecture: String
    let license: String
    let capabilities: [String]
    let quantizations: [CatalogQuant]
    let ollamaTag: String?
}

enum ModelCatalog {
    /// Resolve catalog: prefer the JSON in the app bundle, fall back to
    /// the in-source `aiModelDatabase` literal.
    static func load() -> [AIModel] {
        if let bundleModels = loadFromBundle(), !bundleModels.isEmpty {
            return bundleModels
        }
        return aiModelDatabaseFallback
    }

    private static func loadFromBundle() -> [AIModel]? {
        guard let url = Bundle.main.url(forResource: "models", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        do {
            let entries = try JSONDecoder().decode([CatalogEntry].self, from: data)
            return entries.map { mapEntry($0) }
        } catch {
            NSLog("ModelCatalog: failed to decode models.json: \(error)")
            return nil
        }
    }

    /// Map the website's richer schema down to the macOS app's AIModel.
    private static func mapEntry(_ e: CatalogEntry) -> AIModel {
        // Pick representative quants the app understands: Q4_K_M and Q8_0.
        // If the source omits them, keep whatever is provided.
        let preferred = ["Q4_K_M", "Q8_0"]
        let pickedQuants: [AIQuantization] = {
            let bySlug = preferred.compactMap { name in
                e.quantizations.first(where: { $0.format == name })
            }
            let source = bySlug.isEmpty ? e.quantizations : bySlug
            return source.map { q in
                AIQuantization(
                    level: q.format,
                    ramRequiredMB: Int(q.vramGb * 1024),
                    quality: q.quality.lowercased()
                )
            }
        }()

        // Map task-style capabilities the app uses ("chat", "code", "reasoning").
        // Website schema has more (vision, multilingual, rag, tool-use, edge);
        // the app only renders the first three at the moment, but we keep all.
        let tasks = e.capabilities

        return AIModel(
            name: e.name,
            parameters: e.parameters,
            family: e.provider,
            quantizations: pickedQuants,
            tasks: tasks,
            ollamaSlug: e.ollamaTag,
            websiteSlug: e.slug,
            lab: e.provider,
            license: e.license
        )
    }
}
