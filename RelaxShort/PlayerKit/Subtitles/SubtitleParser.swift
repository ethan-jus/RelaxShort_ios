import Foundation

// MARK: - 字幕解析器（actor，可取消）

actor SubtitleParser {
    private var currentTask: Task<[PlayerSubtitleCue], Never>?

    func parse(url: URL, format: PlayerSubtitleFormat) async -> [PlayerSubtitleCue] {
        currentTask?.cancel()
        let task = Task<[PlayerSubtitleCue], Never> {
            // 使用 URLSession 异步获取字幕，带 8 秒超时
            let content: String
            if url.isFileURL {
                guard let c = try? String(contentsOf: url, encoding: .utf8) else { return [] }
                content = c
            } else {
                let req = URLRequest(url: url, timeoutInterval: 8)
                guard let (data, _) = try? await URLSession.shared.data(for: req),
                      let c = String(data: data, encoding: .utf8) else { return [] }
                content = c
            }
            guard !Task.isCancelled else { return [] }
            return format == .vtt ? parseVTT(content) : parseSRT(content)
        }
        currentTask = task
        return await task.value
    }

    func cancel() { currentTask?.cancel() }

    private func parseSRT(_ content: String) -> [PlayerSubtitleCue] {
        var cues: [PlayerSubtitleCue] = []
        let blocks = content.components(separatedBy: "\n\n")
        for (idx, block) in blocks.enumerated() {
            let lines = block.components(separatedBy: "\n").filter { !$0.isEmpty }
            guard lines.count >= 3 else { continue }
            let parts = lines[1].components(separatedBy: " --> ")
            guard parts.count == 2,
                  let start = parseTimestamp(parts[0]),
                  let end = parseTimestamp(parts[1]) else { continue }
            cues.append(PlayerSubtitleCue(
                index: idx, start: start, end: end,
                text: lines[2...].joined(separator: "\n")
            ))
        }
        return cues
    }

    private func parseVTT(_ content: String) -> [PlayerSubtitleCue] {
        var cues: [PlayerSubtitleCue] = []
        var start: TimeInterval = 0
        var end: TimeInterval = 0
        var textLines: [String] = []
        var cueIndex = 0

        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty
                || trimmed.hasPrefix("WEBVTT")
                || trimmed.hasPrefix("Kind:")
                || trimmed.hasPrefix("Language:") { continue }

            if trimmed.contains(" --> ") {
                if !textLines.isEmpty {
                    cues.append(PlayerSubtitleCue(
                        index: cueIndex, start: start, end: end,
                        text: textLines.joined(separator: "\n")
                    ))
                    cueIndex &+= 1
                    textLines = []
                }
                let parts = trimmed.components(separatedBy: " --> ")
                start = parseTimestamp(parts[0]) ?? 0
                end = parseTimestamp(parts.count > 1 ? parts[1] : parts[0]) ?? 0
            } else if Int(trimmed) == nil {
                textLines.append(trimmed.strippingVTTTags())
            }
        }

        if !textLines.isEmpty {
            cues.append(PlayerSubtitleCue(
                index: cueIndex, start: start, end: end,
                text: textLines.joined(separator: "\n")
            ))
        }
        return cues
    }

    private func parseTimestamp(_ raw: String) -> TimeInterval? {
        let clean = raw.components(separatedBy: " ").first ?? raw
        let parts = clean.components(separatedBy: ":")
        guard parts.count == 3 else { return nil }
        let secParts = parts[2].components(separatedBy: ".")
        guard let h = Double(parts[0]),
              let m = Double(parts[1]),
              let s = Double(secParts[0]) else { return nil }
        let ms = secParts.count > 1 ? (Double(secParts[1]) ?? 0) : 0
        return h * 3600 + m * 60 + s + ms / 1000.0
    }
}

extension String {
    func strippingVTTTags() -> String {
        var text = self
        for tag in ["<b>", "</b>", "<i>", "</i>", "<u>", "</u>", "<v>", "</v>"] {
            text = text.replacingOccurrences(of: tag, with: "")
        }
        if let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) {
            text = regex.stringByReplacingMatches(
                in: text, range: NSRange(text.startIndex..., in: text), withTemplate: ""
            )
        }
        return text
    }
}
