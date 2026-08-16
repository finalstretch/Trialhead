import Foundation

@main
struct Spike {
    static func main() async {
        do {
            try await run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write("error: \(error)\n".data(using: .utf8)!)
            exit(1)
        }
    }

    static func run(_ args: [String]) async throws {
        let api = TrialsAPI()

        switch args.first {
        case "fetch":
            guard args.count >= 2 else { throw SpikeError.usage(usage) }
            try await printStudy(api.study(nctId: args[1]))

        case "search":
            guard args.count >= 2 else { throw SpikeError.usage(usage) }
            var query = TrialsAPI.SearchQuery(condition: args[1])
            query.studyType = "INTERVENTIONAL"
            // NYC, 50mi — hardcoded for the spike; becomes the user profile later.
            query.geo = (40.7128, -74.0060, 50)
            let response = try await api.search(query)
            print("total matching: \(response.totalCount ?? -1)")
            print("returned:       \(response.studies.count)\n")
            for study in response.studies { printSummary(study) }

        case "dump":
            guard args.count >= 3, let count = Int(args[2]) else { throw SpikeError.usage(usage) }
            try await dump(condition: args[1], count: count, api: api)

        case "split":
            guard args.count >= 2 else { throw SpikeError.usage(usage) }
            try split(nctId: args[1])

        case "score":
            try score()

        case "evaluate":
            guard args.count >= 2 else { throw SpikeError.usage(usage) }
            let profile: Profile = args.count >= 3 && args[2] == "diabetes"
                ? .diabetesExample : .breastCancerExample
            try await evaluate(nctId: args[1], profile: profile, api: api)

        case "measure":
            try measure()

        default:
            throw SpikeError.usage(usage)
        }
    }

    static let usage = """
        usage:
          spike fetch <NCT_ID>              fetch one study, print eligibility blob
          spike search <condition>          search recruiting interventional trials near NYC
          spike dump <condition> <count>    save N studies to samples/ for the M1 parser spike
          spike split <NCT_ID>              stage-1 split one sample, print the tree
          spike score                       run stage-1 over all of samples/, grade the corpus
          spike evaluate <NCT_ID> [diabetes]  full pipeline: fetch, split, categorise, colour
          spike measure                     stage-2/3 distribution across samples/
        """

    // MARK: - M2: categorise and evaluate

    static func evaluate(nctId: String, profile: Profile, api: TrialsAPI) async throws {
        let study = try await api.study(nctId: nctId)
        let section = study.protocolSection
        let eligibility = section?.eligibilityModule
        let parsed = CriteriaParser.parse(eligibility?.eligibilityCriteria ?? "")

        let structured = Evaluator.evaluateStructured(eligibility, profile: profile)
        let evaluated = Evaluator.evaluate(parsed.criteria, profile: profile)
        let evaluation = TrialEvaluation(structured: structured, criteria: evaluated)

        print("── \(nctId) ──")
        print(section?.identificationModule?.briefTitle ?? "(no title)")
        print("\nprofile: \(profile.age.map(String.init) ?? "?")yo \(profile.sex?.rawValue ?? "?"), "
              + "\(profile.conditions.joined(separator: ", "))"
              + (profile.bmi.map { String(format: ", BMI %.0f", $0) } ?? ""))

        print("\n  🟢 \(evaluation.matches) likely   "
              + "🟠 \(evaluation.asks) to ask   "
              + "🔴 \(evaluation.blockers) blockers\n")

        if !structured.isEmpty {
            print("FROM THE TRIAL RECORD")
            for check in structured {
                print("  \(check.verdict.glyph) \(check.label) — \(check.rationale)")
            }
            print()
        }

        for kind in [Criterion.Kind.inclusion, .exclusion] {
            let group = evaluated.filter { $0.criterion.kind == kind }
            guard !group.isEmpty else { continue }
            print(kind == .inclusion ? "REQUIREMENTS" : "DISQUALIFIERS")
            for item in group {
                let indent = String(repeating: "  ", count: item.criterion.depth)
                let text = item.criterion.text
                print("  \(indent)\(item.verdict.glyph) \(text.prefix(88))\(text.count > 88 ? "…" : "")")
                print("  \(indent)   [\(item.category.label)] \(item.rationale)")
            }
            print()
        }
    }

    static func measure() throws {
        let dir = URL(fileURLWithPath: "samples")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "txt" }

        var byCategory: [Category: Int] = [:]
        var byVerdict: [Verdict: Int] = [:]
        var total = 0

        // Verdicts depend on whose profile we test against; categories don't.
        let profile = Profile.breastCancerExample

        for file in files {
            let raw = try String(contentsOf: file, encoding: .utf8)
            let parsed = CriteriaParser.parse(raw)
            for item in Evaluator.evaluate(parsed.criteria, profile: profile) {
                byCategory[item.category, default: 0] += 1
                byVerdict[item.verdict, default: 0] += 1
                total += 1
            }
        }

        guard total > 0 else { throw SpikeError.usage("no criteria found in samples/") }
        let pct = { (n: Int) in String(format: "%5.1f%%", Double(n) / Double(total) * 100) }

        print("═══ STAGE-2/3 MEASURE — \(files.count) studies, \(total) rules ═══\n")

        print("WHAT KIND OF RULE (profile-independent)")
        for (category, count) in byCategory.sorted(by: { $0.value > $1.value }) {
            let bar = String(repeating: "█", count: max(1, count * 40 / total))
            print(String(format: "  %-20@ %5d  %@  %@", category.label as NSString, count, pct(count), bar))
        }

        print("\nVERDICT (against the sample profile)")
        for verdict in [Verdict.match, .ask, .blocker] {
            let count = byVerdict[verdict] ?? 0
            let bar = String(repeating: "█", count: max(1, count * 40 / total))
            print(String(format: "  %@ %-8@ %5d  %@  %@",
                         verdict.glyph, verdict.rawValue as NSString, count, pct(count), bar))
        }

        print("\n  note: red verdicts come only from the trial record's age/sex fields,")
        print("        which aren't in these text-only samples. Use `spike evaluate` for those.")
    }

    // MARK: - M1: stage-1 splitting

    static func split(nctId: String) throws {
        let path = URL(fileURLWithPath: "samples/\(nctId).txt")
        let raw = try String(contentsOf: path, encoding: .utf8)
        let result = CriteriaParser.parse(raw)

        print("── \(nctId) ──")
        print("headers: inclusion=\(result.foundInclusionHeader) exclusion=\(result.foundExclusionHeader)")
        print("criteria: \(result.inclusion.count) inclusion, \(result.exclusion.count) exclusion")
        print("max depth: \(result.maxDepth)  cohort headers: \(result.cohortHeaderCount)\n")

        for kind in [Criterion.Kind.inclusion, .exclusion] {
            let group = result.criteria.filter { $0.kind == kind }
            guard !group.isEmpty else { continue }
            print(kind.rawValue.uppercased())
            for c in group {
                let indent = String(repeating: "  ", count: c.depth)
                let flag = c.text.count > ParseScore.longRow ? " ⚠️LONG" : ""
                print("\(indent)• \(c.text.prefix(120))\(c.text.count > 120 ? "…" : "")\(flag)")
            }
            print()
        }
    }

    static func score() throws {
        let dir = URL(fileURLWithPath: "samples")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "txt" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !files.isEmpty else { throw SpikeError.usage("no samples/ — run `spike dump` first") }

        var scores: [ParseScore] = []
        for file in files {
            let raw = try String(contentsOf: file, encoding: .utf8)
            let nctId = file.deletingPathExtension().lastPathComponent
            scores.append(ParseScore(nctId: nctId, result: CriteriaParser.parse(raw), sourceLength: raw.count))
        }

        let clean = scores.filter { $0.grade == .clean }
        let mangled = scores.filter { $0.grade == .mangled }
        let unparseable = scores.filter { $0.grade == .unparseable }
        let pct = { (n: Int) in String(format: "%.0f%%", Double(n) / Double(scores.count) * 100) }

        print("═══ STAGE-1 SCORE — \(scores.count) studies ═══\n")
        print("  clean        \(clean.count)\t\(pct(clean.count))")
        print("  mangled      \(mangled.count)\t\(pct(mangled.count))")
        print("  unparseable  \(unparseable.count)\t\(pct(unparseable.count))")

        let allCriteria = scores.flatMap { $0.result.criteria }
        let counts = scores.map { $0.result.criteria.count }.sorted()
        print("\n  criteria extracted: \(allCriteria.count) total")
        print("  per study:          min \(counts.first ?? 0), median \(counts[counts.count / 2]), max \(counts.last ?? 0)")
        print("  max nesting depth:  \(scores.map { $0.result.maxDepth }.max() ?? 0)")
        print("  studies w/ cohort headers: \(scores.filter { $0.result.cohortHeaderCount > 0 }.count)")

        // Failure reasons, most common first.
        var reasonCounts: [String: Int] = [:]
        for s in mangled + unparseable {
            for r in s.reasons {
                // Strip leading counts so reasons aggregate.
                let key = r.replacingOccurrences(of: #"^\d+"#, with: "N", options: .regularExpression)
                reasonCounts[key, default: 0] += 1
            }
        }
        if !reasonCounts.isEmpty {
            print("\n  why they failed:")
            for (reason, count) in reasonCounts.sorted(by: { $0.value > $1.value }) {
                print("    \(count)×  \(reason)")
            }
        }

        if !(mangled + unparseable).isEmpty {
            print("\n  inspect these:")
            for s in (unparseable + mangled).prefix(12) {
                print("    spike split \(s.nctId)\t[\(s.grade.rawValue)] \(s.reasons.joined(separator: "; "))")
            }
        }
    }

    // MARK: - Output

    static func printStudy(_ study: Study) throws {
        guard let p = study.protocolSection else { print("empty record"); return }

        print("── \(p.identificationModule?.nctId ?? "?") ──")
        print(p.identificationModule?.briefTitle ?? "(no title)")
        print()
        print("status:     \(p.statusModule?.overallStatus ?? "?")")
        print("type:       \(p.designModule?.studyType ?? "?")")
        print("phases:     \(p.designModule?.phases?.joined(separator: ", ") ?? "— (none: expected on observational)")")
        print("enrollment: \(p.designModule?.enrollmentInfo?.count.map(String.init) ?? "?")")
        print("sponsor:    \(p.sponsorCollaboratorsModule?.leadSponsor?.name ?? "?")")

        if let e = p.eligibilityModule {
            let minAge = AgeBound(e.minimumAge)
            let maxAge = AgeBound(e.maximumAge)
            print("\nstructured eligibility:")
            print("  sex:               \(e.sex ?? "?")")
            print("  age:               \(minAge.map { fmt($0.years) } ?? "—") to \(maxAge.map { fmt($0.years) } ?? "—")  (raw: \(e.minimumAge ?? "nil") / \(e.maximumAge ?? "nil"))")
            print("  healthyVolunteers: \(e.healthyVolunteers.map(String.init) ?? "?")")
            print("  stdAges:           \(e.stdAges?.joined(separator: ", ") ?? "—")")
        }

        let sites = p.contactsLocationsModule?.locations ?? []
        let geocoded = sites.filter { $0.geoPoint != nil }.count
        print("\nsites: \(sites.count)  (\(geocoded) geocoded)")
        for site in sites.prefix(3) {
            let place = [site.city, site.state, site.country].compactMap { $0 }.joined(separator: ", ")
            print("  • \(site.facility ?? "?") — \(place) [\(site.status ?? "no site status")]")
        }
        if sites.count > 3 { print("  … \(sites.count - 3) more") }

        // The blob. This is what M1 has to take apart.
        let criteria = p.eligibilityModule?.eligibilityCriteria ?? ""
        print("\n── eligibilityCriteria (\(criteria.count) chars) ──")
        print(criteria.isEmpty ? "(empty)" : criteria)
    }

    static func printSummary(_ study: Study) {
        guard let p = study.protocolSection else { return }
        let id = p.identificationModule?.nctId ?? "?"
        let title = p.identificationModule?.briefTitle ?? "(no title)"
        let phase = p.designModule?.phases?.joined(separator: "/") ?? "—"
        let chars = p.eligibilityModule?.eligibilityCriteria?.count ?? 0
        print("\(id)  [\(phase)]  \(chars) chars")
        print("  \(title.prefix(78))")
    }

    static func fmt(_ years: Double) -> String {
        years == years.rounded() ? "\(Int(years))y" : String(format: "%.1fy", years)
    }

    // MARK: - Sample corpus for M1

    static func dump(condition: String, count: Int, api: TrialsAPI) async throws {
        let dir = URL(fileURLWithPath: "samples")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var collected = 0
        var token: String? = nil

        while collected < count {
            var query = TrialsAPI.SearchQuery(condition: condition)
            query.studyType = "INTERVENTIONAL"
            query.pageSize = min(50, count - collected)
            query.pageToken = token

            let response = try await api.search(query)
            if response.studies.isEmpty { break }

            for study in response.studies {
                guard let nctId = study.protocolSection?.identificationModule?.nctId,
                      let criteria = study.protocolSection?.eligibilityModule?.eligibilityCriteria,
                      !criteria.isEmpty
                else { continue }

                try criteria.write(to: dir.appendingPathComponent("\(nctId).txt"),
                                   atomically: true, encoding: .utf8)
                collected += 1
            }

            token = response.nextPageToken
            if token == nil { break }
        }

        print("wrote \(collected) criteria blobs to samples/")
    }
}
