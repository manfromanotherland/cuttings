// SPDX-License-Identifier: MIT
// Regression checks against the generated Safari action graph, not a second
// implementation of its capture logic. This does not execute Apple Shortcuts;
// native serialization validation and an iPhone Share Sheet rerun remain needed.
// Run: swift shortcuts/test-shortcut.swift <unsigned.shortcut>
import Foundation

typealias Object = [String: Any]
struct Failure: Error, CustomStringConvertible { let description: String }
func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw Failure(description: message) }
}
guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: swift shortcuts/test-shortcut.swift <unsigned.shortcut>")
}
let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let workflow = try PropertyListSerialization.propertyList(from: data, format: nil) as! Object
let actions = workflow["WFWorkflowActions"] as! [Object]
func parameters(_ action: Object) -> Object { action["WFWorkflowActionParameters"] as! Object }
func kind(_ action: Object) -> String {
    String((action["WFWorkflowActionIdentifier"] as! String).dropFirst("is.workflow.actions.".count))
}

// Evaluate the per-item capture branches. ZIP creation and saving are out of scope.
let start = try actions.firstIndex { action in
    guard kind(action) == "gettext", let text = parameters(action)["WFTextActionText"] as? String,
          let bytes = text.data(using: .utf8),
          let dictionary = try? JSONSerialization.jsonObject(with: bytes) as? Object else { return false }
    return dictionary.count == 1 && dictionary["version"] as? Int == 1
}.unwrap("Missing per-item manifest initialization")
let safariIf = try actions.firstIndex {
    kind($0) == "conditional" && parameters($0)["WFConditionalActionString"] as? String == "Safari Web Page"
}.unwrap("Missing Safari branch")
let safariGroup = parameters(actions[safariIf])["GroupingIdentifier"] as! String
let end = try actions.indices.first {
    $0 > safariIf && kind(actions[$0]) == "conditional"
        && parameters(actions[$0])["GroupingIdentifier"] as? String == safariGroup
        && parameters(actions[$0])["WFControlFlowMode"] as? Int == 2
}.unwrap("Missing Safari branch boundary")
try require(start < safariIf, "Manifest initialization must precede the Safari branch")
let graph = Array(actions[start...end])

extension Optional {
    func unwrap(_ message: String) throws -> Wrapped {
        guard let value = self else { throw Failure(description: message) }
        return value
    }
}

struct SafariFixture {
    let url: String
    let title: String
    let selection: String?
    var type = "Safari Web Page"
    var responseType = "Image"
}

struct SafariGraph {
    var variables: Object = [:]
    var outputs: Object = [:]
    var downloads: [String] = []
    var payloads: [String] = []

    func resolve(_ value: Any?) throws -> Any? {
        guard let value else { return nil }
        guard let object = value as? Object else { return value }
        if let serialization = object["WFSerializationType"] as? String {
            if serialization == "WFTextTokenAttachment" { return try resolve(object["Value"]) }
            try require(serialization == "WFTextTokenString", "Unsupported token serialization: \(serialization)")
            let body = object["Value"] as! Object
            let string = body["string"] as! String
            let attachments = body["attachmentsByRange"] as! Object
            // A lone variable carries its typed dictionary (or absent value).
            if string == "\u{fffc}", attachments.count == 1 {
                return try resolve(attachments.values.first)
            }
            let rendered = NSMutableString(string: string)
            for (range, token) in attachments.sorted(by: { NSRangeFromString($0.key).location > NSRangeFromString($1.key).location }) {
                let value = try resolve(token)
                let replacement: String
                if let dictionary = value as? Object {
                    replacement = String(data: try JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys]), encoding: .utf8)!
                } else { replacement = value.map { String(describing: $0) } ?? "" }
                rendered.replaceCharacters(in: NSRangeFromString(range), with: replacement)
            }
            return rendered as String
        }
        switch object["Type"] as? String {
        case "ActionOutput": return outputs[object["OutputUUID"] as! String]
        case "Variable":
            if let subject = object["Variable"] { return try resolve(subject) }
            return variables[object["VariableName"] as! String]
        default: throw Failure(description: "Unsupported variable in Safari graph: \(object)")
        }
    }

    func hasValue(_ value: Any?) -> Bool {
        guard let value else { return false }
        if let string = value as? String { return !string.isEmpty }
        if let list = value as? [Any] { return !list.isEmpty }
        return true
    }

    mutating func capture(_ fixture: SafariFixture, index: Int) throws -> Object {
        variables["Capture ID"] = "fixture-\(index)"
        variables["Captured at"] = "2026-09-18T12:00:00Z"
        variables["Repeat Item"] = fixture.url
        var conditions: [(group: String, parent: Bool, matches: Bool)] = []
        var active = true
        for action in graph {
            let p = parameters(action)
            if kind(action) == "conditional" {
                let group = p["GroupingIdentifier"] as! String
                switch p["WFControlFlowMode"] as! Int {
                case 0:
                    let subject = active ? try resolve(p["WFInput"]) : nil
                    let operation = p["WFCondition"] as! Int
                    try require(operation == 100 || operation == 4, "Unsupported If operation")
                    let matches = operation == 100 ? hasValue(subject)
                        : subject as? String == p["WFConditionalActionString"] as? String
                    conditions.append((group, active, matches))
                    active = active && matches
                case 1:
                    let condition = try conditions.last.unwrap("Unexpected Otherwise")
                    try require(condition.group == group, "Mismatched Otherwise")
                    active = condition.parent && !condition.matches
                case 2:
                    let condition = try conditions.popLast().unwrap("Unexpected End If")
                    try require(condition.group == group, "Mismatched End If")
                    active = condition.parent
                default: throw Failure(description: "Unsupported control-flow mode")
                }
                continue
            }
            guard active else { continue }
            var output: Any?
            switch kind(action) {
            case "gettext": output = try resolve(p["WFTextActionText"])
            case "detect.dictionary":
                let text = try (resolve(p["WFInput"]) as? String).unwrap("Dictionary input is not JSON text")
                output = try JSONSerialization.jsonObject(with: Data(text.utf8))
            case "setvariable": variables[p["WFVariableName"] as! String] = try resolve(p["WFInput"])
            case "setvalueforkey":
                var dictionary = try (resolve(p["WFDictionary"]) as? Object).unwrap("Missing dictionary")
                let key = p["WFDictionaryKey"] as! String
                let value = try resolve(p["WFDictionaryValue"])
                // This failure contract is the user's captured iOS error.
                try require(hasValue(value), "No Value Provided. No value was provided to the Set Dictionary Value action for the key “\(key)”.")
                dictionary[key] = value
                output = dictionary
            case "list": output = p["WFItems"] as! [Any]
            case "getitemtype":
                let input = try resolve(p["WFInput"]) as? String
                output = input == "downloaded-image" ? fixture.responseType : fixture.type
            case "text.match":
                let input = try resolve(p["text"]) as! String
                let regex = try NSRegularExpression(pattern: p["WFMatchTextPattern"] as! String)
                output = regex.matches(in: input, range: NSRange(input.startIndex..., in: input)).map { (input as NSString).substring(with: $0.range) }
            case "downloadurl":
                downloads.append(try resolve(p["WFURL"]) as! String)
                output = "downloaded-image"
            case "gettypeaction": output = try resolve(p["WFInput"])
            case "properties.files": output = p["WFContentItemPropertyName"] as? String == "Name" ? "shared.jpg" : "jpg"
            case "setitemname": output = try resolve(p["WFName"])
            case "appendvariable": payloads.append(try resolve(p["WFInput"]) as! String)
            case "hash": output = String(repeating: "a", count: 64)
            case "detect.text": output = try resolve(p["WFInput"])
            case "alert": break
            case "exit": throw Failure(description: "Capture stopped")
            case "properties.safariwebpage":
                switch p["WFContentItemPropertyName"] as! String {
                case "Page URL": output = fixture.url
                case "Name": output = fixture.title
                case "Page Selection": output = fixture.selection
                default: throw Failure(description: "Unexpected Safari property")
                }
            default: throw Failure(description: "Unexpected action in Safari graph: \(kind(action))")
            }
            // Clear absent outputs as well, so an earlier item's selection
            // cannot stand in for the current Page Selection result.
            outputs[p["UUID"] as! String] = output
        }
        try require(conditions.isEmpty,
                    "Safari branch did not finish its nested conditions")
        return try (variables["Manifest"] as? Object).unwrap("Missing manifest")
    }
}

let selectedText = "A \"quoted\" selection\nwith café and 🌱"
let cases: [(String, [String?])] = [
    ("whole page: absent selection", [nil]),
    ("whole page: empty selection", [""]),
    ("selected text preserved", [selectedText]),
    ("repeat items do not retain prior selection", [selectedText, nil, "", "A different selection"]),
]
var failures = 0
for (name, selections) in cases {
    do {
        var runner = SafariGraph()
        for (index, selection) in selections.enumerated() {
            let fixture = SafariFixture(url: "https://example.com/page/\(index)",
                                        title: "Page \(index)", selection: selection)
            let manifest = try runner.capture(fixture, index: index)
            let origin = manifest["origin"] as? Object
            try require(origin?["url"] as? String == fixture.url, "Source URL was lost or stale")
            try require(origin?["title"] as? String == fixture.title, "Source title was lost or stale")
            try require(manifest["version"] as? Int == 1 && manifest["capture_id"] as? String == "fixture-\(index)"
                        && manifest["captured_at"] as? String == "2026-09-18T12:00:00Z", "Capture metadata was lost or stale")
            if let selection, !selection.isEmpty {
                try require(manifest["text"] as? String == selection, "Selected quote text was lost or changed")
            } else {
                try require(manifest["text"] == nil, "Whole-page link retained a text field")
            }
        }
        print("PASS: \(name)")
    } catch {
        failures += 1
        print("FAIL: \(name): \(error)")
    }
}
do {
    for type in ["URL", "Text", "Safari Web Page"] {
        var runner = SafariGraph()
        let url = "https://www.instagram.com/p/DdlVpikk5Gj/?img_index=2&stkn=tracking"
        let manifest = try runner.capture(SafariFixture(url: url, title: "Post", selection: nil, type: type), index: 0)
        try require(manifest["version"] as? Int == 2 && manifest["instagram_url"] as? String == url,
                    "Instagram slide must survive as an explicit version-2 request: \(type)")
        try require(manifest["text"] == nil && manifest["origin"] == nil && manifest["attachments"] == nil && runner.downloads.isEmpty,
                    "Instagram must not download on iPhone or silently become a link")
    }
    print("PASS: Instagram URL, text and Safari shares queue the selected slide")
} catch { failures += 1; print("FAIL: Instagram request: \(error)") }
let urlCases: [(String, Bool)] = [
    ("https://media.houseandgarden.co.uk/photos/67879b979514423c41c6e4ea/master/w_1280,c_limit/11-13-24-HG-Anna-Hambro011.jpg", true),
    ("https://example.com/photo.PNG?width=1200#image", true),
    ("https://example.com/photo.webp", true),
    ("https://example.com/article", false),
    ("https://example.com/article?image=photo.jpg", false),
    ("https://example.com/photo.jpg/article", false),
    ("file:///tmp/photo.jpg", false),
]
do {
    var runner = SafariGraph()
    for (index, entry) in urlCases.enumerated() {
        let (url, isImage) = entry
        runner.downloads = []
        runner.payloads = []
        let manifest = try runner.capture(SafariFixture(url: url, title: "", selection: nil, type: "URL"), index: index)
        try require((manifest["origin"] as? Object)?["url"] as? String == url, "Shared URL was lost")
        try require(runner.downloads == (isImage ? [url] : []), "Wrong download decision: \(url)")
        try require(runner.payloads == (isImage ? ["payload.jpg"] : []), "Image bytes were not attached: \(url)")
        if isImage {
            let attachments = manifest["attachments"] as? [Object]
            try require(attachments?.count == 1 && attachments?.first?["path"] as? String == "payload.jpg", "Missing image attachment array")
            try require(attachments?.first?["sha256"] as? String == String(repeating: "a", count: 64), "Missing image checksum")
        } else { try require(manifest["attachments"] == nil, "Page URL retained a prior image") }
    }
    print("PASS: direct image URL and ordinary link capture (including House & Garden)")
    var rejected = false
    do {
        _ = try runner.capture(SafariFixture(url: "https://example.com/error.jpg", title: "", selection: nil, type: "URL", responseType: "Text"), index: 0)
    } catch { rejected = String(describing: error) == "Capture stopped" }
    try require(rejected, "A non-image response must stop instead of saving a link")
    print("PASS: non-image response stops capture")
    runner.downloads = []
    let local = try runner.capture(SafariFixture(url: "local-image", title: "", selection: nil, type: "Image"), index: 0)
    try require((local["attachments"] as? [Object])?.count == 1 && runner.downloads.isEmpty, "Local image capture regressed")
    print("PASS: local images retain attachments without downloading")
    try require(workflow["WFWorkflowName"] as? String == "Óia!", "Shortcut name is stale")
} catch {
    failures += 1
    print("FAIL: image URL regression: \(error)")
}
print("Action-graph regression checks: \(failures) failures (\(actions.count)-action workflow).")
print("This models missing-value/control-flow semantics; it is not a native or iPhone execution test.")
exit(failures == 0 ? 0 : 1)
