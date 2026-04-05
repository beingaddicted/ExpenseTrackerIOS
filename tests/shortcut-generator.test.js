const ShortcutGenerator = require("../js/shortcut-generator");

describe("ShortcutGenerator", () => {
  // ─── Module API ───
  describe("Module exports", () => {
    test("exposes buildSimpleShortcut", () => {
      expect(typeof ShortcutGenerator.buildSimpleShortcut).toBe("function");
    });
    test("exposes buildJSONShortcut", () => {
      expect(typeof ShortcutGenerator.buildJSONShortcut).toBe("function");
    });
    test("exposes download", () => {
      expect(typeof ShortcutGenerator.download).toBe("function");
    });
    test("exposes toPlist", () => {
      expect(typeof ShortcutGenerator.toPlist).toBe("function");
    });
  });

  // ─── toPlist XML generation ───
  describe("toPlist", () => {
    test("generates valid XML plist header", () => {
      const xml = ShortcutGenerator.toPlist({ key: "value" });
      expect(xml).toContain('<?xml version="1.0"');
      expect(xml).toContain("<!DOCTYPE plist");
      expect(xml).toContain('<plist version="1.0">');
      expect(xml).toContain("</plist>");
    });

    test("serializes strings", () => {
      const xml = ShortcutGenerator.toPlist({ name: "Test" });
      expect(xml).toContain("<key>name</key>");
      expect(xml).toContain("<string>Test</string>");
    });

    test("serializes integers", () => {
      const xml = ShortcutGenerator.toPlist({ count: 42 });
      expect(xml).toContain("<integer>42</integer>");
    });

    test("serializes booleans", () => {
      const xml = ShortcutGenerator.toPlist({ enabled: true, disabled: false });
      expect(xml).toContain("<true/>");
      expect(xml).toContain("<false/>");
    });

    test("serializes arrays", () => {
      const xml = ShortcutGenerator.toPlist({ items: ["a", "b"] });
      expect(xml).toContain("<array>");
      expect(xml).toContain("<string>a</string>");
      expect(xml).toContain("<string>b</string>");
      expect(xml).toContain("</array>");
    });

    test("serializes nested dicts", () => {
      const xml = ShortcutGenerator.toPlist({
        outer: { inner: "value" },
      });
      expect(xml).toContain("<key>outer</key>");
      expect(xml).toContain("<key>inner</key>");
      expect(xml).toContain("<string>value</string>");
    });

    test("serializes empty arrays", () => {
      const xml = ShortcutGenerator.toPlist({ items: [] });
      expect(xml).toContain("<array/>");
    });

    test("serializes empty dicts", () => {
      const xml = ShortcutGenerator.toPlist({ obj: {} });
      expect(xml).toContain("<dict/>");
    });

    test("escapes XML special characters", () => {
      const xml = ShortcutGenerator.toPlist({ text: 'a < b & "c"' });
      expect(xml).toContain("&lt;");
      expect(xml).toContain("&amp;");
      expect(xml).toContain("&quot;");
      expect(xml).not.toContain('a < b & "c"');
    });

    test("serializes real/float numbers", () => {
      const xml = ShortcutGenerator.toPlist({ val: 3.14 });
      expect(xml).toContain("<real>3.14</real>");
    });
  });

  // ─── Simple Shortcut ───
  describe("buildSimpleShortcut", () => {
    let shortcut;
    beforeAll(() => {
      shortcut = ShortcutGenerator.buildSimpleShortcut();
    });

    test("returns object with WFWorkflowName", () => {
      expect(shortcut.WFWorkflowName).toBe("Save Bank SMS");
    });

    test("has WFWorkflowActions array", () => {
      expect(Array.isArray(shortcut.WFWorkflowActions)).toBe(true);
      expect(shortcut.WFWorkflowActions.length).toBeGreaterThan(0);
    });

    test("uses append file action", () => {
      const action = shortcut.WFWorkflowActions[0];
      expect(action.WFWorkflowActionIdentifier).toBe(
        "is.workflow.actions.appendfile",
      );
    });

    test("appends to bank_sms.txt", () => {
      const params = shortcut.WFWorkflowActions[0].WFWorkflowActionParameters;
      expect(params.WFFilePath).toContain("bank_sms.txt");
    });

    test("uses Shortcut Input variable", () => {
      const params = shortcut.WFWorkflowActions[0].WFWorkflowActionParameters;
      expect(params.WFInput.VariableName).toBe("Shortcut Input");
    });

    test("appends on new line", () => {
      const params = shortcut.WFWorkflowActions[0].WFWorkflowActionParameters;
      expect(params.WFAppendOnNewLine).toBe(true);
    });

    test("has AutomationTrigger type", () => {
      expect(shortcut.WFWorkflowTypes).toContain("AutomationTrigger");
    });

    test("has icon configuration", () => {
      expect(shortcut.WFWorkflowIcon).toBeDefined();
      expect(shortcut.WFWorkflowIcon.WFWorkflowIconGlyphNumber).toBeDefined();
      expect(shortcut.WFWorkflowIcon.WFWorkflowIconStartColor).toBeDefined();
    });

    test("generates valid XML plist", () => {
      const xml = ShortcutGenerator.toPlist(shortcut);
      expect(xml).toContain("is.workflow.actions.appendfile");
      expect(xml).toContain("bank_sms.txt");
      expect(xml).toContain("Shortcut Input");
    });

    test("accepts string content item class", () => {
      expect(shortcut.WFWorkflowInputContentItemClasses).toContain(
        "WFStringContentItem",
      );
    });
  });

  // ─── JSON Shortcut ───
  describe("buildJSONShortcut", () => {
    let shortcut;
    beforeAll(() => {
      shortcut = ShortcutGenerator.buildJSONShortcut();
    });

    test("returns object with WFWorkflowName", () => {
      expect(shortcut.WFWorkflowName).toBe("Save Bank SMS (JSON)");
    });

    test("has multiple actions", () => {
      expect(shortcut.WFWorkflowActions.length).toBeGreaterThan(3);
    });

    test("includes get text action for JSON template", () => {
      const actions = shortcut.WFWorkflowActions;
      const getTextActions = actions.filter(
        (a) => a.WFWorkflowActionIdentifier === "is.workflow.actions.gettext",
      );
      expect(getTextActions.length).toBeGreaterThan(0);
    });

    test("includes conditional (if/else) for file existence", () => {
      const actions = shortcut.WFWorkflowActions;
      const conditionals = actions.filter(
        (a) =>
          a.WFWorkflowActionIdentifier === "is.workflow.actions.conditional",
      );
      // Should have If (mode 0), Otherwise (mode 1), End If (mode 2)
      expect(conditionals.length).toBe(3);
      expect(conditionals[0].WFWorkflowActionParameters.WFControlFlowMode).toBe(
        0,
      );
      expect(conditionals[1].WFWorkflowActionParameters.WFControlFlowMode).toBe(
        1,
      );
      expect(conditionals[2].WFWorkflowActionParameters.WFControlFlowMode).toBe(
        2,
      );
    });

    test("includes file open action for bank_sms.json", () => {
      const actions = shortcut.WFWorkflowActions;
      const openAction = actions.find(
        (a) =>
          a.WFWorkflowActionIdentifier ===
          "is.workflow.actions.documentpicker.open",
      );
      expect(openAction).toBeDefined();
      expect(openAction.WFWorkflowActionParameters.WFGetFilePath).toContain(
        "bank_sms.json",
      );
    });

    test("includes file save actions", () => {
      const actions = shortcut.WFWorkflowActions;
      const saveActions = actions.filter(
        (a) =>
          a.WFWorkflowActionIdentifier ===
          "is.workflow.actions.documentpicker.save",
      );
      expect(saveActions.length).toBeGreaterThanOrEqual(2);
    });

    test("includes text replace action for appending", () => {
      const actions = shortcut.WFWorkflowActions;
      const replaceAction = actions.find(
        (a) =>
          a.WFWorkflowActionIdentifier === "is.workflow.actions.text.replace",
      );
      expect(replaceAction).toBeDefined();
      expect(replaceAction.WFWorkflowActionParameters.WFReplaceTextFind).toBe(
        "]}",
      );
    });

    test("has AutomationTrigger type", () => {
      expect(shortcut.WFWorkflowTypes).toContain("AutomationTrigger");
    });

    test("generates valid XML plist", () => {
      const xml = ShortcutGenerator.toPlist(shortcut);
      expect(xml).toContain("bank_sms.json");
      expect(xml).toContain("is.workflow.actions.conditional");
      expect(xml).toContain("is.workflow.actions.documentpicker.save");
      expect(xml).toContain('<?xml version="1.0"');
    });

    test("all conditionals share same grouping identifier", () => {
      const actions = shortcut.WFWorkflowActions;
      const conditionals = actions.filter(
        (a) =>
          a.WFWorkflowActionIdentifier === "is.workflow.actions.conditional",
      );
      const groupIds = conditionals.map(
        (c) => c.WFWorkflowActionParameters.GroupingIdentifier,
      );
      expect(new Set(groupIds).size).toBe(1);
    });
  });

  // ─── XML Plist Completeness ──
  describe("Full plist output validation", () => {
    test("Simple shortcut plist is valid structure", () => {
      const shortcut = ShortcutGenerator.buildSimpleShortcut();
      const xml = ShortcutGenerator.toPlist(shortcut);

      // Should have proper open/close tags
      const openDicts = (xml.match(/<dict>/g) || []).length;
      const closeDicts = (xml.match(/<\/dict>/g) || []).length;
      const emptyDicts = (xml.match(/<dict\/>/g) || []).length;
      // open + empty should roughly balance with close (empty are self-closing)
      expect(openDicts).toBe(closeDicts);

      const openArrays = (xml.match(/<array>/g) || []).length;
      const closeArrays = (xml.match(/<\/array>/g) || []).length;
      expect(openArrays).toBe(closeArrays);
    });

    test("JSON shortcut plist is valid structure", () => {
      const shortcut = ShortcutGenerator.buildJSONShortcut();
      const xml = ShortcutGenerator.toPlist(shortcut);

      const openDicts = (xml.match(/<dict>/g) || []).length;
      const closeDicts = (xml.match(/<\/dict>/g) || []).length;
      expect(openDicts).toBe(closeDicts);
    });
  });
});
