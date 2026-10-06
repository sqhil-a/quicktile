import Foundation

public enum WebsiteIcons {
    public static func origin(_ text: String) -> URL? {
        guard let url = try? Validation.website(text), var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        parts.scheme = "https"; parts.path = "/"; parts.query = nil; parts.fragment = nil
        return parts.url
    }
    public static func candidates(html: String, origin: URL) -> [URL] {
        let links = try! NSRegularExpression(pattern: "<link\\b[^>]*>", options: .caseInsensitive)
        let attrs = try! NSRegularExpression(pattern: #"([\w-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#)
        var preferred: [URL] = [], ordinary: [URL] = []
        for match in links.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let range = Range(match.range, in: html) else { continue }
            let tag = String(html[range]); var values: [String: String] = [:]
            for attribute in attrs.matches(in: tag, range: NSRange(tag.startIndex..., in: tag)) {
                guard let keyRange = Range(attribute.range(at: 1), in: tag) else { continue }
                for index in 2...4 { if let valueRange = Range(attribute.range(at: index), in: tag) { values[String(tag[keyRange]).lowercased()] = String(tag[valueRange]); break } }
            }
            let rel = values["rel", default: ""].lowercased().split(separator: " ")
            guard rel.contains("icon") || rel.contains("apple-touch-icon"), let href = values["href"],
                  let url = URL(string: href.replacingOccurrences(of: "&amp;", with: "&"), relativeTo: origin)?.absoluteURL,
                  url.scheme == "https", url.user == nil, url.password == nil else { continue }
            if rel.contains("apple-touch-icon") { preferred.append(url) } else { ordinary.append(url) }
        }
        var seen = Set<URL>()
        return (preferred + ordinary + [origin.appendingPathComponent("apple-touch-icon.png"), origin.appendingPathComponent("favicon.ico")]).filter { seen.insert($0).inserted }
    }
}
