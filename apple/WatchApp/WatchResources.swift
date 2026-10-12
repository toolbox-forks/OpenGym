import Foundation
import OpenGymKit
import ImageIO
import SwiftUI

final class WatchResources {
    static let shared = WatchResources()
    let catalogue: [String: JSONValue]
    private var tables: [String: [String: String]] = [:]
    private var nameTables: [String: [String: String]] = [:]
    private var instructionTables: [String: JSONValue] = [:]
    let languages = ["en","de","de-CH","es","fr","it","pt","pt-BR","pl","tr","ru","uk","zh","zh-TW","ko","hi","bn","th","hu","ar"]
    init() {
        let root = Self.json("catalogue")
        catalogue = root["exercises"].objectValue
    }
    static func url(_ name: String, extension ext: String = "json", directory: String = "Resources") -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext, subdirectory: directory)
    }
    static func json(_ name: String) -> JSONValue {
        guard let url = url(name), let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(JSONValue.self, from: data) else { return .object([:]) }
        return value
    }
    func language(_ requested: String) -> String {
        if languages.contains(requested) { return requested }
        let preferred = Locale.preferredLanguages.first ?? "en"
        if languages.contains(preferred) { return preferred }
        let prefix = String(preferred.prefix(2))
        return languages.contains(prefix) ? prefix : "en"
    }
    private func strings(_ name: String) -> [String: String] {
        Self.json(name).objectValue.compactMapValues(\.stringValue)
    }
    func text(_ source: String, lang: String, args: [String] = []) -> String {
        let lang = language(lang)
        if tables[lang] == nil { tables[lang] = strings("locale-" + lang) }
        var result = tables[lang]?[source] ?? source
        for (index, value) in args.enumerated() { result = result.replacingOccurrences(of: "{\(index)}", with: value) }
        return result
    }
    func name(_ id: String, lang: String) -> String {
        let lang = language(lang)
        if nameTables[lang] == nil { nameTables[lang] = strings("names-" + lang) }
        return nameTables[lang]?[id] ?? catalogue[id]?.text("n") ?? id
    }
    func instructions(_ id: String, lang: String) -> [String] {
        let lang = language(lang)
        if instructionTables[lang] == nil { instructionTables[lang] = Self.json("instructions-" + lang) }
        let rows = instructionTables[lang]?[id].arrayValue.compactMap(\.stringValue) ?? []
        if !rows.isEmpty { return rows }
        if instructionTables["en"] == nil { instructionTables["en"] = Self.json("instructions-en") }
        return instructionTables["en"]?[id].arrayValue.compactMap(\.stringValue) ?? []
    }
    func thumbnail(_ id: String) -> CGImage? {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("thumbnails")
        let cached = folder.appendingPathComponent(id + ".webp")
        let url = FileManager.default.fileExists(atPath: cached.path) ? cached : Self.url(id, extension: "webp", directory: "Resources/thumbnails")
        guard let url, let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
