// SPDX-License-Identifier: MIT
// Builds the reviewable, unsigned source for the Save to Cuttings Shortcut.
// Run from the repository root: swift shortcuts/build-shortcut.swift
import Foundation

typealias Object = [String: Any]
var actions: [Object] = []
var sequence = 0

func identifier() -> String {
    sequence += 1
    return String(format: "C0771000-0000-4000-8000-%012d", sequence)
}

func variable(_ name: String) -> Object {
    ["Type": "Variable", "VariableName": name]
}

func attachment(_ value: Object) -> Object {
    ["Value": value, "WFSerializationType": "WFTextTokenAttachment"]
}

func text(_ parts: Any...) -> Object {
    var value = ""
    var ranges: Object = [:]
    for part in parts {
        if let token = part as? Object {
            ranges["{\(value.utf16.count), 1}"] = token
            value += "\u{fffc}"
        } else {
            value += String(describing: part)
        }
    }
    return ["Value": ["string": value, "attachmentsByRange": ranges],
            "WFSerializationType": "WFTextTokenString"]
}

@discardableResult
func action(_ name: String, _ parameters: Object = [:]) -> Object {
    let uuid = identifier()
    var parameters = parameters
    parameters["UUID"] = uuid
    actions.append(["WFWorkflowActionIdentifier": "is.workflow.actions.\(name)",
                    "WFWorkflowActionParameters": parameters])
    return ["Type": "ActionOutput", "OutputUUID": uuid, "OutputName": name]
}

func set(_ name: String, _ value: Object) {
    action("setvariable", ["WFVariableName": name, "WFInput": attachment(value)])
}

func field(_ name: String, _ value: Object, in dictionary: String = "Manifest") {
    let updated = action("setvalueforkey", ["WFDictionary": attachment(variable(dictionary)),
                                           "WFDictionaryKey": name,
                                           "WFDictionaryValue": text(value)])
    set(dictionary, updated)
}

func json(_ value: Object, named name: String) {
    let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    let string = action("gettext", ["WFTextActionText": String(data: data, encoding: .utf8)!])
    set(name, action("detect.dictionary", ["WFInput": attachment(string)]))
}

// Unlike ordinary action inputs, If wraps its variable in a typed subject.
// This representation round-trips through Apple's native action serializer.
func beginIf(_ subject: Object, equals value: String? = nil) -> String {
    let group = identifier()
    var parameters: Object = ["GroupingIdentifier": group, "WFControlFlowMode": 0,
                               "WFCondition": value == nil ? 100 : 4,
                               "WFInput": ["Type": "Variable", "Variable": attachment(subject)]]
    if let value { parameters["WFConditionalActionString"] = value }
    action("conditional", parameters)
    return group
}

func otherwise(_ group: String) {
    action("conditional", ["GroupingIdentifier": group, "WFControlFlowMode": 1])
}

func endIf(_ group: String) {
    action("conditional", ["GroupingIdentifier": group, "WFControlFlowMode": 2])
}

let shortcutInput: Object = ["Type": "ExtensionInput"]
let repeatItem = variable("Repeat Item")
action("comment", ["WFCommentActionText": "Share an image, video, text or link to Save to Cuttings. Choose the inbox folder inside your iCloud Cuttings library during setup. Each item is saved as a complete archive; Cuttings imports it on your Mac. No network requests or accounts."])
let hasInput = beginIf(shortcutInput)
let repeatGroup = identifier()
action("repeat.each", ["GroupingIdentifier": repeatGroup, "WFControlFlowMode": 0,
                       "WFInput": attachment(shortcutInput)])
let now = action("date", ["WFDateActionMode": "Current Date"])
let date = action("format.date", ["WFDate": text(now), "WFDateFormatStyle": "ISO 8601",
                                  "WFISO8601IncludeTime": true])
set("Captured at", date)
let random = action("number.random", ["WFRandomNumberMinimum": 1, "WFRandomNumberMaximum": 999999999999])
let seed = action("gettext", ["WFTextActionText": text(date, "-", random, "-", variable("Repeat Index"))])
set("Capture ID", action("hash", ["WFInput": attachment(seed), "WFHashType": "SHA256"]))
json(["version": 1], named: "Manifest")
field("capture_id", variable("Capture ID"))
field("captured_at", variable("Captured at"))
set("Capture files", action("list", ["WFItems": [Any]()]))

let itemType = action("getitemtype", ["WFInput": attachment(repeatItem)])
let safari = beginIf(itemType, equals: "Safari Web Page")
json([:], named: "Origin")
field("url", action("properties.safariwebpage", ["WFInput": attachment(repeatItem),
                                                "WFContentItemPropertyName": "Page URL"]), in: "Origin")
field("title", action("properties.safariwebpage", ["WFInput": attachment(repeatItem),
                                                  "WFContentItemPropertyName": "Name"]), in: "Origin")
field("origin", variable("Origin"))
field("text", action("properties.safariwebpage", ["WFInput": attachment(repeatItem),
                                                 "WFContentItemPropertyName": "Page Selection"]))
otherwise(safari)
let url = beginIf(itemType, equals: "URL")
json([:], named: "Origin")
field("url", repeatItem, in: "Origin")
field("origin", variable("Origin"))
otherwise(url)
let plain = beginIf(itemType, equals: "Text")
field("text", repeatItem)
otherwise(plain)
let rich = beginIf(itemType, equals: "Rich Text")
field("text", action("detect.text", ["WFInput": attachment(repeatItem)]))
otherwise(rich)

// Media and regular files keep their bytes; a safe fixed basename prevents
// original filenames from colliding with the transport manifest.
let originalFile = action("gettypeaction", ["WFInput": attachment(repeatItem), "WFFileType": "public.data"])
json([:], named: "Origin")
field("title", action("properties.files", ["WFInput": attachment(originalFile),
                                           "WFContentItemPropertyName": "Name"]), in: "Origin")
let fileExtension = action("properties.files", ["WFInput": attachment(originalFile),
                                                "WFContentItemPropertyName": "File Extension"])
let payloadName = action("gettext", ["WFTextActionText": text("payload.", fileExtension)])
let payload = action("setitemname", ["WFInput": attachment(originalFile),
                                     "WFName": text(payloadName), "WFDontIncludeFileExtension": false])
action("appendvariable", ["WFVariableName": "Capture files", "WFInput": attachment(payload)])
let digest = action("hash", ["WFInput": attachment(payload), "WFHashType": "SHA256"])
// The filename is put into a Dictionary before JSON serialization; filenames
// never get interpolated into JSON source.
json([:], named: "Attachment")
field("path", payloadName, in: "Attachment")
field("sha256", digest, in: "Attachment")
// Set Dictionary Value unwraps a one-item List into its single object. Parse
// the array from JSON instead, then add the other fields without touching it.
// Attachment itself is serialized by Shortcuts, so its values remain escaped.
let mediaManifest = action("gettext", ["WFTextActionText": text(
    "{\"version\":1,\"attachments\":[", variable("Attachment"), "]}")])
set("Manifest", action("detect.dictionary", ["WFInput": attachment(mediaManifest)]))
field("capture_id", variable("Capture ID"))
field("captured_at", variable("Captured at"))
field("origin", variable("Origin"))
endIf(rich)
endIf(plain)
endIf(url)
endIf(safari)

let manifestText = action("gettext", ["WFTextActionText": text(variable("Manifest"))])
let manifestFile = action("setitemname", ["WFInput": attachment(manifestText),
                                          "WFName": "manifest.json", "WFDontIncludeFileExtension": false])
action("appendvariable", ["WFVariableName": "Capture files", "WFInput": attachment(manifestFile)])
let archive = action("makezip", ["WFInput": attachment(variable("Capture files")),
                                 "WFArchiveFormat": "zip"])
// Make Archive's name field is ignored in some native execution paths. Rename
// the resulting file explicitly, as we do for manifest.json and payload files.
let captureFile = action("setitemname", ["WFInput": attachment(archive),
    "WFName": text(variable("Capture ID"), ".cuttingscapture.zip"),
    "WFDontIncludeFileExtension": false])
let saveActionIndex = actions.count
action("documentpicker.save", ["WFInput": attachment(captureFile), "WFAskWhereToSave": false,
                                "WFSaveFileOverwrite": false])
action("repeat.each", ["GroupingIdentifier": repeatGroup, "WFControlFlowMode": 2])
action("notification", ["WFNotificationActionTitle": "Cuttings",
                         "WFNotificationActionBody": "Saved to Inbox",
                         "WFNotificationActionSound": false])
otherwise(hasInput)
action("alert", ["WFAlertActionTitle": "Save to Cuttings",
                  "WFAlertActionMessage": "Open an image, video, text or link. Tap Share, then Save to Cuttings.",
                  "WFAlertActionCancelButtonShown": false])
endIf(hasInput)

let workflow: Object = [
    "WFWorkflowName": "Save to Cuttings",
    "WFWorkflowClientVersion": "2302.0.4",
    "WFWorkflowMinimumClientVersion": 900,
    "WFWorkflowMinimumClientVersionString": "900",
    "WFWorkflowIcon": ["WFWorkflowIconStartColor": 4251333119, "WFWorkflowIconGlyphNumber": 59511],
    "WFWorkflowTypes": ["ActionExtension"],
    "WFQuickActionSurfaces": [String](),
    "WFWorkflowHasShortcutInputVariables": true,
    "WFWorkflowHasOutputFallback": false,
    "WFWorkflowInputContentItemClasses": ["WFSafariWebPageContentItem", "WFURLContentItem",
        "WFStringContentItem", "WFRichTextContentItem", "WFImageContentItem", "WFAVAssetContentItem",
        "WFGenericFileContentItem"],
    "WFWorkflowOutputContentItemClasses": [String](),
    "WFWorkflowImportQuestions": [["ActionIndex": saveActionIndex, "Category": "Parameter",
        "ParameterKey": "WFFolder", "Text": "Choose the inbox folder inside your iCloud Cuttings library."]],
    "WFWorkflowActions": actions,
]
let destination = CommandLine.arguments.dropFirst().first ?? "shortcuts/Save to Cuttings.unsigned.shortcut"
let bytes = try PropertyListSerialization.data(fromPropertyList: workflow, format: .xml, options: 0)
try bytes.write(to: URL(fileURLWithPath: destination), options: .atomic)
print("Built \(actions.count) actions: \(destination)")
