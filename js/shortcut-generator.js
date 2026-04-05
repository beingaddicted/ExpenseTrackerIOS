// ═══════════════════════════════════════════════════════════
// iOS Shortcut Generator — Builds downloadable .shortcut files
// Creates Apple Shortcut XML plist for SMS-to-file automation
// ═══════════════════════════════════════════════════════════

const ShortcutGenerator = (() => {
  // ─── XML Plist Helpers ───
  function escapeXml(str) {
    return String(str)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function toXml(value, indent) {
    indent = indent || "";
    const ni = indent + "\t";
    if (value === true) return indent + "<true/>";
    if (value === false) return indent + "<false/>";
    if (typeof value === "number") {
      return Number.isInteger(value)
        ? indent + "<integer>" + value + "</integer>"
        : indent + "<real>" + value + "</real>";
    }
    if (typeof value === "string")
      return indent + "<string>" + escapeXml(value) + "</string>";
    if (Array.isArray(value)) {
      if (!value.length) return indent + "<array/>";
      var lines = [indent + "<array>"];
      for (var i = 0; i < value.length; i++) lines.push(toXml(value[i], ni));
      lines.push(indent + "</array>");
      return lines.join("\n");
    }
    if (value && typeof value === "object") {
      var keys = Object.keys(value);
      if (!keys.length) return indent + "<dict/>";
      var lines = [indent + "<dict>"];
      for (var i = 0; i < keys.length; i++) {
        lines.push(ni + "<key>" + escapeXml(keys[i]) + "</key>");
        lines.push(toXml(value[keys[i]], ni));
      }
      lines.push(indent + "</dict>");
      return lines.join("\n");
    }
    return indent + "<string></string>";
  }

  function toPlist(obj) {
    return [
      '<?xml version="1.0" encoding="UTF-8"?>',
      '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">',
      '<plist version="1.0">',
      toXml(obj, ""),
      "</plist>",
    ].join("\n");
  }

  // ─── Shortcut Wrapper ───
  function wrapShortcut(name, actions, icon) {
    return {
      WFWorkflowMinimumClientVersionString: "900",
      WFWorkflowMinimumClientVersion: 900,
      WFWorkflowIcon: icon || {
        WFWorkflowIconStartColor: 4274264076,
        WFWorkflowIconGlyphNumber: 59749,
      },
      WFWorkflowClientVersion: "2302.0.4",
      WFWorkflowOutputContentItemClasses: [],
      WFWorkflowHasOutputFallback: false,
      WFWorkflowActions: actions,
      WFWorkflowInputContentItemClasses: ["WFStringContentItem"],
      WFWorkflowImportQuestions: [],
      WFWorkflowTypes: ["AutomationTrigger"],
      WFQuickActionSurfaces: [],
      WFWorkflowHasShortcutInputVariables: true,
      WFWorkflowName: name,
    };
  }

  // ═══════════════════════════════════════════════════════════
  // Option A: Simple Text Append (.txt)
  //   - One action: append SMS text to bank_sms.txt
  //   - Simplest to install, works great with the parser
  // ═══════════════════════════════════════════════════════════
  function buildSimpleShortcut() {
    var actions = [
      {
        WFWorkflowActionIdentifier: "is.workflow.actions.appendfile",
        WFWorkflowActionParameters: {
          WFInput: {
            Type: "Variable",
            VariableName: "Shortcut Input",
          },
          WFFilePath: "Shortcuts/bank_sms.txt",
          WFAppendOnNewLine: true,
        },
      },
    ];
    return wrapShortcut("Save Bank SMS", actions, {
      WFWorkflowIconStartColor: 4274264076,
      WFWorkflowIconGlyphNumber: 59749,
    });
  }

  // ═══════════════════════════════════════════════════════════
  // Option B: JSON Format (Recommended)
  //   - Builds JSON entry with message, sender, timestamp
  //   - Appends to bank_sms.json, creates file if missing
  // ═══════════════════════════════════════════════════════════
  function buildJSONShortcut() {
    var groupId = "EXPENSE-TRACKER-IF-1";

    // UUIDs for linking action outputs
    var UUID_ENTRY = "E7A1B2C3-0001-4000-8000-000000000001";
    var UUID_GETFILE = "E7A1B2C3-0002-4000-8000-000000000002";
    var UUID_GETTEXT = "E7A1B2C3-0003-4000-8000-000000000003";
    var UUID_REPLACE = "E7A1B2C3-0004-4000-8000-000000000004";
    var UUID_INIT = "E7A1B2C3-0005-4000-8000-000000000005";

    // Magic variable references
    function actionOutput(name, uuid) {
      return {
        Value: { Type: "ActionOutput", OutputName: name, OutputUUID: uuid },
        WFSerializationType: "WFTextTokenAttachment",
      };
    }

    // Token string with embedded variables
    function tokenString(template, attachments) {
      return {
        Value: { attachmentsByRange: attachments, string: template },
        WFSerializationType: "WFTextTokenString",
      };
    }

    var shortcutInput = {
      Type: "Variable",
      VariableName: "Shortcut Input",
    };

    var actions = [
      // ── 1. Build JSON entry text ──
      // {"message":"<MSG>","sender":"<SENDER>","timestamp":"<DATE>"}
      {
        WFWorkflowActionIdentifier: "is.workflow.actions.gettext",
        WFWorkflowActionParameters: {
          WFTextActionText: tokenString(
            '{"message":"\uFFFC","sender":"unknown","timestamp":"\uFFFC"}',
            {
              "{12, 1}": shortcutInput,
              "{36, 1}": { Type: "CurrentDate" },
            },
          ),
          UUID: UUID_ENTRY,
        },
      },

      // ── 2. Get existing file (don't error if missing) ──
      {
        WFWorkflowActionIdentifier: "is.workflow.actions.documentpicker.open",
        WFWorkflowActionParameters: {
          WFGetFilePath: "Shortcuts/bank_sms.json",
          WFFileErrorIfNotFound: false,
          UUID: UUID_GETFILE,
        },
      },

      // ── 3. IF file exists ──
      {
        WFWorkflowActionIdentifier: "is.workflow.actions.conditional",
        WFWorkflowActionParameters: {
          GroupingIdentifier: groupId,
          WFControlFlowMode: 0,
          WFCondition: 100,
          WFConditionalActionString: "",
        },
      },

      // ── 3a. Get text from file ──
      {
        WFWorkflowActionIdentifier: "is.workflow.actions.detect.text",
        WFWorkflowActionParameters: {
          UUID: UUID_GETTEXT,
        },
      },

      // ── 3b. Replace ]} with ,<newEntry>]} ──
      {
        WFWorkflowActionIdentifier: "is.workflow.actions.text.replace",
        WFWorkflowActionParameters: {
          WFReplaceTextFind: "]}",
          WFReplaceTextReplace: tokenString(",\uFFFC]}", {
            "{1, 1}": {
              Type: "ActionOutput",
              OutputName: "Text",
              OutputUUID: UUID_ENTRY,
            },
          }),
          WFInput: actionOutput("Text", UUID_GETTEXT),
          UUID: UUID_REPLACE,
        },
      },

      // ── 3c. Save updated file ──
      {
        WFWorkflowActionIdentifier: "is.workflow.actions.documentpicker.save",
        WFWorkflowActionParameters: {
          WFFileDestinationPath: "Shortcuts/bank_sms.json",
          WFSaveFileOverwrite: true,
          WFAskWhereToSave: false,
          WFInput: actionOutput("Updated Text", UUID_REPLACE),
        },
      },

      // ── 4. OTHERWISE (first time) ──
      {
        WFWorkflowActionIdentifier: "is.workflow.actions.conditional",
        WFWorkflowActionParameters: {
          GroupingIdentifier: groupId,
          WFControlFlowMode: 1,
        },
      },

      // ── 4a. Create initial JSON ──
      {
        WFWorkflowActionIdentifier: "is.workflow.actions.gettext",
        WFWorkflowActionParameters: {
          WFTextActionText: tokenString('{"messages":[\uFFFC]}', {
            "{13, 1}": {
              Type: "ActionOutput",
              OutputName: "Text",
              OutputUUID: UUID_ENTRY,
            },
          }),
          UUID: UUID_INIT,
        },
      },

      // ── 4b. Save new file ──
      {
        WFWorkflowActionIdentifier: "is.workflow.actions.documentpicker.save",
        WFWorkflowActionParameters: {
          WFFileDestinationPath: "Shortcuts/bank_sms.json",
          WFSaveFileOverwrite: false,
          WFAskWhereToSave: false,
          WFInput: actionOutput("Text", UUID_INIT),
        },
      },

      // ── End If ──
      {
        WFWorkflowActionIdentifier: "is.workflow.actions.conditional",
        WFWorkflowActionParameters: {
          GroupingIdentifier: groupId,
          WFControlFlowMode: 2,
        },
      },
    ];

    return wrapShortcut("Save Bank SMS (JSON)", actions, {
      WFWorkflowIconStartColor: 255303167,
      WFWorkflowIconGlyphNumber: 59749,
    });
  }

  // ─── Download Helper ───
  function download(shortcutObj, filename) {
    var xml = toPlist(shortcutObj);
    var blob = new Blob([xml], { type: "application/octet-stream" });
    var url = URL.createObjectURL(blob);
    var a = document.createElement("a");
    a.href = url;
    a.download =
      filename ||
      shortcutObj.WFWorkflowName.replace(/[^a-zA-Z0-9 ]/g, "") + ".shortcut";
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    setTimeout(function () {
      URL.revokeObjectURL(url);
    }, 5000);
  }

  return {
    buildSimpleShortcut: buildSimpleShortcut,
    buildJSONShortcut: buildJSONShortcut,
    download: download,
    toPlist: toPlist,
  };
})();

if (typeof module !== "undefined" && module.exports) {
  module.exports = ShortcutGenerator;
}
