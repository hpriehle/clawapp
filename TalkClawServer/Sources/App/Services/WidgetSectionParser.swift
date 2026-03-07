import Foundation

/// Parses and manipulates the named TC:* sections in widget HTML files.
enum WidgetSectionParser {
    /// Known section names
    static let sectionNames = ["TC:VARS", "TC:HTML", "TC:STYLE", "TC:SCRIPT", "TC:ROUTES"]

    /// Extract all named sections from the widget HTML.
    /// Returns a dictionary of section name → content between the markers.
    static func parseSections(from html: String) -> [String: String] {
        var sections: [String: String] = [:]

        for name in sectionNames {
            if name == "TC:VARS" {
                // TC:VARS uses a single comment block: <!-- TC:VARS ... -->
                let pattern = "<!--\\s*TC:VARS\\s*\\n([\\s\\S]*?)\\n-->"
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                   let range = Range(match.range(at: 1), in: html) {
                    sections[name] = String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } else {
                // Other sections use paired markers: <!-- TC:NAME --> ... <!-- /TC:NAME -->
                let startMarker = "<!-- \(name) -->"
                let endMarker = "<!-- /\(name) -->"
                guard let startRange = html.range(of: startMarker),
                      let endRange = html.range(of: endMarker) else { continue }
                let content = String(html[startRange.upperBound..<endRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                sections[name] = content
            }
        }

        // TC:ROUTES also uses comment block style
        let routesPattern = "<!--\\s*TC:ROUTES\\s*\\n([\\s\\S]*?)\\n-->"
        if let regex = try? NSRegularExpression(pattern: routesPattern),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            sections["TC:ROUTES"] = String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return sections
    }

    /// Replace a named section's content in the full HTML.
    static func mergeSection(_ name: String, content: String, into html: String) -> String {
        var result = html

        if name == "TC:VARS" || name == "TC:ROUTES" {
            // Comment block style
            let pattern = "(<!--\\s*\(NSRegularExpression.escapedPattern(for: name))\\s*\\n)[\\s\\S]*?(\\n-->)"
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: range,
                    withTemplate: "$1\(NSRegularExpression.escapedTemplate(for: content))\n$2"
                )
            }
        } else {
            // Paired marker style
            let startMarker = "<!-- \(name) -->"
            let endMarker = "<!-- /\(name) -->"
            if let startRange = result.range(of: startMarker),
               let endRange = result.range(of: endMarker) {
                result.replaceSubrange(startRange.upperBound..<endRange.lowerBound, with: "\n\(content)\n")
            }
        }

        return result
    }

    /// Merge multiple sections into the HTML.
    static func mergeSections(_ sections: [String: String], into html: String) -> String {
        var result = html
        for (name, content) in sections {
            result = mergeSection(name, content: content, into: result)
        }
        return result
    }

    /// Remove the TC:ROUTES block from HTML before serving to the browser.
    static func stripRoutes(from html: String) -> String {
        let pattern = "<!--\\s*TC:ROUTES\\s*\\n[\\s\\S]*?\\n-->"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return html }
        let range = NSRange(html.startIndex..., in: html)
        return regex.stringByReplacingMatches(in: html, range: range, withTemplate: "")
    }

    /// Inject `window.TALKCLAW_VARS = {...}` into the HTML before the TC:SCRIPT section.
    /// Merges TC:VARS defaults with live render_vars (live values take precedence).
    static func injectVars(defaults: [String: String], live: [String: String], into html: String) -> String {
        var merged = defaults
        for (key, value) in live {
            merged[key] = value
        }

        guard let jsonData = try? JSONSerialization.data(
            withJSONObject: merged,
            options: [.sortedKeys]
        ),
        var jsonString = String(data: jsonData, encoding: .utf8) else {
            return html
        }

        // Escape </ sequences to prevent premature script tag closing (XSS vector)
        jsonString = jsonString.replacingOccurrences(of: "</", with: "<\\/")

        let injection = "<script>window.TALKCLAW_VARS = \(jsonString);</script>"
        let scriptMarker = "<!-- TC:SCRIPT -->"

        if let range = html.range(of: scriptMarker) {
            var result = html
            result.insert(contentsOf: "\(injection)\n", at: range.lowerBound)
            return result
        }

        return html
    }

    /// Parse the TC:VARS section JSON into a dictionary.
    static func parseVarsDefaults(from html: String) -> [String: String] {
        let sections = parseSections(from: html)
        guard let varsJSON = sections["TC:VARS"],
              let data = varsJSON.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        // Convert all values to strings for simplicity
        var result: [String: String] = [:]
        for (key, value) in dict {
            result[key] = "\(value)"
        }
        return result
    }

    /// Parse TC:ROUTES section into route definition structs.
    struct RouteDefinition {
        let method: String
        let path: String
        let description: String
        let handler: String
    }

    static func parseRoutes(from html: String) -> [RouteDefinition] {
        let sections = parseSections(from: html)
        guard let routesJSON = sections["TC:ROUTES"],
              let data = routesJSON.data(using: .utf8),
              let routes = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return routes.compactMap { route in
            guard let method = route["method"] as? String,
                  let path = route["path"] as? String,
                  let handler = route["handler"] as? String else { return nil }
            let description = route["description"] as? String ?? ""
            return RouteDefinition(method: method, path: path, description: description, handler: handler)
        }
    }
}
