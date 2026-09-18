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

// Evaluate only the existing per-item manifest initialization and Safari arm.
// Date/random/hash, non-Safari arms, ZIP creation, and saving are out of scope.
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
        && parameters(actions[$0])["WFControlFlowMode"] as? Int == 1
}.unwrap("Missing Safari branch boundary")
try require(start < safariIf, "Manifest initialization must precede the Safari branch")
let graph = Array(actions[start..<end])

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
}

struct SafariGraph {
    var variables: Object = [:]
    var outputs: Object = [:]

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
            try require(attachments.isEmpty, "Unexpected interpolated text in Safari graph")
            return string
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
            case "getitemtype": output = "Safari Web Page"
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
        try require(conditions.count == 1 && conditions[0].group == safariGroup,
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
print("Safari action-graph regression checks: \(cases.count - failures)/\(cases.count) passed (\(actions.count)-action workflow).")
print("This models missing-value/control-flow semantics; it is not a native or iPhone execution test.")
exit(failures == 0 ? 0 : 1)
