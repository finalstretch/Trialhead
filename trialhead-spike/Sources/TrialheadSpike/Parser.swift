import Foundation

// Stage 1: structural split of the eligibilityCriteria blob.
// Deterministic, no model, no network. DESIGN.md §7.

struct Criterion {
    enum Kind: String { case inclusion, exclusion }

    let kind: Kind
    let text: String        // verbatim, markdown-unescaped
    let depth: Int          // 0 = top level
    let order: Int
    /// A structural label introducing the rows beneath it — "Treatment Arm 1:",
    /// "HU Regimen:" — rather than a rule anyone can answer. Excluded from
    /// question counts, since counting them inflates every total.
    let isHeading: Bool
}

struct ParseResult {
    let criteria: [Criterion]
    let foundInclusionHeader: Bool
    let foundExclusionHeader: Bool
    let orphanCharCount: Int      // text appearing before any recognized header
    let cohortHeaderCount: Int    // cohort/substudy-scoped headers seen

    var inclusion: [Criterion] { criteria.filter { $0.kind == .inclusion } }
    var exclusion: [Criterion] { criteria.filter { $0.kind == .exclusion } }
    var maxDepth: Int { criteria.map(\.depth).max() ?? 0 }
}

enum CriteriaParser {

    // Permissive on purpose. Observed variants: "Key Inclusion Criteria:",
    // "Main Study Inclusion Criteria:", no-colon forms, numbered prefixes
    // ("1.2. Inclusion criteria: Substudy 4"), cohort-scoped headers
    // ("Inclusion Criteria for Cohort 3:"), and participant-role-scoped headers
    // in dyad studies ("Daughter of Cancer Survivor Inclusion Criteria:").
    //
    // Allows up to 5 arbitrary prefix words, but anchors the tail on a colon or
    // end-of-line so prose ("Patients meeting inclusion criteria will be…")
    // doesn't false-positive.
    // Leading `(?:[*\-•]\s+)?` because some sponsors bullet the header itself
    // ("* INCLUSION CRITERIA:", NCT06313398).
    private static let headerPattern = #"^\s*(?:[*\-•]\s+)?(?:[\d.]+\s+)?(?:[\w'/()&-]+\s+){0,5}?(inclusion|exclusion)\s+criteri(?:a|on)(?:\s+for\s+[^:]{0,60})?(?:\s*\([^)]{0,60}\))?\s*(?::|$)"#

    // Bullets seen in the wild: *, -, •, "1.", "a)", "a.", "iv."
    private static let bulletPattern = #"^(\s*)(?:[*\-•‣▪]|\(?\d+[.)]|\(?[a-zA-Z][.)]|\(?[ivxIVX]+[.)])\s+(.*)$"#

    private static let headerRegex = try! NSRegularExpression(pattern: headerPattern, options: [.caseInsensitive])
    private static let bulletRegex = try! NSRegularExpression(pattern: bulletPattern, options: [])
    private static let cohortRegex = try! NSRegularExpression(
        pattern: #"(?:cohort|substudy|sub-study|arm|part|group)\s*[\dA-Z]"#, options: [.caseInsensitive])

    static func parse(_ raw: String) -> ParseResult {
        let text = unescapeMarkdown(normalizeInlineBullets(raw))
            .replacingOccurrences(of: "\r\n", with: "\n")
        let lines = text.components(separatedBy: "\n")

        var current: Criterion.Kind? = nil
        var foundInclusion = false
        var foundExclusion = false
        var orphanChars = 0
        var cohortHeaders = 0

        // (indent, kind, accumulated text) — depth resolved after the pass,
        // because indent width varies by study (2, 3, and 4 spaces all appear).
        var staged: [(indent: Int, kind: Criterion.Kind, text: String)] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            if let kind = matchHeader(line) {
                current = kind
                if kind == .inclusion { foundInclusion = true } else { foundExclusion = true }
                if matches(cohortRegex, line) { cohortHeaders += 1 }
                continue
            }

            guard let kind = current else {
                orphanChars += trimmed.count
                continue
            }

            if let (indent, content) = matchBullet(line), !content.isEmpty {
                staged.append((indent, kind, content))
            } else if !staged.isEmpty {
                // Unbulleted line: continuation of the previous criterion.
                staged[staged.count - 1].text += " " + trimmed
            } else {
                // A section whose criteria aren't bulleted at all — treat the
                // line as its own criterion rather than dropping it.
                staged.append((0, kind, trimmed))
            }
        }

        // Rank distinct indents into depth levels.
        let indentLevels = Array(Set(staged.map(\.indent))).sorted()
        let depthOf = Dictionary(uniqueKeysWithValues: indentLevels.enumerated().map { ($1, $0) })

        let texts = staged.map { $0.text.trimmingCharacters(in: .whitespaces) }
        let depths = staged.map { depthOf[$0.indent] ?? 0 }

        let criteria = staged.indices.map { index -> Criterion in
            let text = texts[index]
            // A heading ends with a colon and is followed by something nested
            // beneath it. Both halves matter: plenty of real criteria end in a
            // colon and then simply continue at the same level.
            let hasNestedChild = index + 1 < depths.count && depths[index + 1] > depths[index]
            // A trailing colon is the clearest signal, but not the only one:
            // "Treatment Arm 1 (MOMA-313 Monotherapy)" ends in a bracket and is
            // still plainly a label for the rows beneath it. Short + has children
            // is enough. Undercounting questions is safer than overcounting —
            // the row still displays either way.
            let looksLikeLabel = text.hasSuffix(":") || text.count < 60
            let isBareConnector = text.count <= 3   // stray "or" / "and" rows

            return Criterion(kind: staged[index].kind,
                             text: text,
                             depth: depths[index],
                             order: index,
                             isHeading: (hasNestedChild && looksLikeLabel) || isBareConnector)
        }

        return ParseResult(criteria: criteria,
                           foundInclusionHeader: foundInclusion,
                           foundExclusionHeader: foundExclusion,
                           orphanCharCount: orphanChars,
                           cohortHeaderCount: cohortHeaders)
    }

    // MARK: - Helpers

    /// Some sponsors submit every criterion on ONE line, using inline `\*` as the
    /// separator instead of newlines (NCT07716176). Nothing to split on, so the
    /// whole section lands as a single 1000+ char criterion. Detect the pattern and
    /// restore the line breaks.
    ///
    /// Runs on the raw text, before unescaping, since the signal is the escape
    /// sequence itself. `\*\*` (bold) is masked out first so it can't trigger this.
    static func normalizeInlineBullets(_ raw: String) -> String {
        let boldPlaceholder = "\u{0}BOLD\u{0}"
        return raw.components(separatedBy: "\n").map { line -> String in
            let masked = line.replacingOccurrences(of: #"\*\*"#, with: boldPlaceholder)
            let bulletCount = masked.components(separatedBy: #"\*"#).count - 1
            guard bulletCount >= 3 else { return line }
            return masked
                .replacingOccurrences(of: #"\*"#, with: "\n* ")
                .replacingOccurrences(of: boldPlaceholder, with: #"\*\*"#)
        }.joined(separator: "\n")
    }

    /// The API embeds literal markdown escapes: `\-`, `\*\*`, `\[`, `\]`.
    static func unescapeMarkdown(_ s: String) -> String {
        var out = ""
        var escaping = false
        for ch in s {
            if escaping {
                // Only unescape punctuation markdown would have escaped.
                if !"-*[]_#.()+!`>".contains(ch) { out.append("\\") }
                out.append(ch)
                escaping = false
            } else if ch == "\\" {
                escaping = true
            } else {
                out.append(ch)
            }
        }
        if escaping { out.append("\\") }
        return out
    }

    private static func matchHeader(_ line: String) -> Criterion.Kind? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let m = headerRegex.firstMatch(in: line, range: range),
              let r = Range(m.range(at: 1), in: line)
        else { return nil }
        return Criterion.Kind(rawValue: line[r].lowercased())
    }

    private static func matchBullet(_ line: String) -> (indent: Int, content: String)? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let m = bulletRegex.firstMatch(in: line, range: range),
              let indentRange = Range(m.range(at: 1), in: line),
              let contentRange = Range(m.range(at: 2), in: line)
        else { return nil }
        return (line[indentRange].count, String(line[contentRange]))
    }

    private static func matches(_ regex: NSRegularExpression, _ s: String) -> Bool {
        regex.firstMatch(in: s, range: NSRange(s.startIndex..<s.endIndex, in: s)) != nil
    }
}

// MARK: - Automated scoring

/// Heuristic quality grade. A proxy for hand-scoring, not a replacement —
/// eyeball the flagged studies before trusting the aggregate.
struct ParseScore {
    enum Grade: String { case clean, mangled, unparseable }

    let nctId: String
    let grade: Grade
    let reasons: [String]
    let result: ParseResult

    /// Long criteria are common and legitimate — a criterion can carry an inline
    /// definition ("Postmenopausal status is defined as…"). Length alone is NOT a
    /// parse failure; it's a UI problem, solved by expandable rows. Only flag it
    /// as unsplit when there is *evidence* of swallowing.
    static let longRow = 600
    /// Shorter than this is probably a stray fragment.
    static let tooShort = 12
    /// Whole-blob chars per extracted criterion. High means under-splitting.
    static let maxCharsPerCriterion = 500

    init(nctId: String, result: ParseResult, sourceLength: Int) {
        self.nctId = nctId
        self.result = result

        var reasons: [String] = []

        if !result.foundInclusionHeader && !result.foundExclusionHeader {
            self.grade = .unparseable
            self.reasons = ["no inclusion/exclusion headers found"]
            return
        }
        if !result.foundInclusionHeader { reasons.append("no inclusion header") }
        if !result.foundExclusionHeader { reasons.append("no exclusion header") }

        // Real evidence of swallowing: a section header buried inside a criterion.
        // Requires header punctuation (optional parenthetical, then a colon) so
        // prose references — "whose lesions meet the inclusion criteria, or…" —
        // don't count.
        let swallowed = result.criteria.filter {
            $0.text.range(of: #"(?i)\b(inclusion|exclusion)\s+criteri\w*(?:\s*\([^)]{0,60}\))?\s*:"#,
                          options: .regularExpression) != nil
        }
        if !swallowed.isEmpty { reasons.append("\(swallowed.count) criteria contain a buried section header") }

        if result.criteria.isEmpty {
            reasons.append("no criteria extracted")
        } else {
            let ratio = sourceLength / result.criteria.count
            if ratio > Self.maxCharsPerCriterion {
                reasons.append("\(ratio) chars per criterion (under-split)")
            }
        }

        let short = result.criteria.filter { $0.text.count < Self.tooShort }
        if short.count * 5 > result.criteria.count && !short.isEmpty {
            reasons.append("\(short.count) fragments <\(Self.tooShort) chars")
        }
        if result.orphanCharCount > 200 { reasons.append("\(result.orphanCharCount) orphan chars before first header") }

        self.reasons = reasons
        self.grade = reasons.isEmpty ? .clean : .mangled
    }

    /// Rows the UI will need to truncate-and-expand. Not a defect.
    var longRowCount: Int { result.criteria.filter { $0.text.count > Self.longRow }.count }
}
