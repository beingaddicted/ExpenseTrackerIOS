const ImportDelta = require("../js/import-delta.js");

function mockQuickHash(text, len) {
  const sample = String(text).substring(0, len || 200);
  let h = 0;
  for (let i = 0; i < sample.length; i++) {
    h = ((h << 5) - h + sample.charCodeAt(i)) | 0;
  }
  return h;
}

describe("ImportDelta", () => {
  test("resolveDeltaStart returns 0 with no prior state", () => {
    const msgs = [{ body: "a" }, { body: "b" }];
    const fp = ImportDelta.smsMessagesHeadFingerprint(msgs, mockQuickHash);
    expect(ImportDelta.resolveDeltaStart(null, msgs.length, fp)).toBe(0);
    expect(ImportDelta.resolveDeltaStart(undefined, msgs.length, fp)).toBe(0);
  });

  test("resolveDeltaStart slices from prior count when head matches", () => {
    const msgs = [{ body: "same" }, { body: "tail" }];
    const fp = ImportDelta.smsMessagesHeadFingerprint(msgs, mockQuickHash);
    expect(
      ImportDelta.resolveDeltaStart({ count: 1, headFp: fp }, 2, fp),
    ).toBe(1);
  });

  test("resolveDeltaStart resets when first message changes (headFp)", () => {
    const v1 = [{ body: "old" }, { body: "x" }];
    const fp1 = ImportDelta.smsMessagesHeadFingerprint(v1, mockQuickHash);
    const v2 = [{ body: "new" }, { body: "x" }];
    const fp2 = ImportDelta.smsMessagesHeadFingerprint(v2, mockQuickHash);
    expect(fp1).not.toBe(fp2);
    expect(
      ImportDelta.resolveDeltaStart({ count: 2, headFp: fp1 }, 2, fp2),
    ).toBe(0);
  });

  test("head fingerprint stable when array grows but first row unchanged", () => {
    const a = ImportDelta.smsMessagesHeadFingerprint(
      [{ body: "head" }, { body: "mid" }],
      mockQuickHash,
    );
    const b = ImportDelta.smsMessagesHeadFingerprint(
      [{ body: "head" }, { body: "mid" }, { body: "new" }],
      mockQuickHash,
    );
    expect(a).toBe(b);
  });

  test("resolveDeltaStart resets when message count shrinks", () => {
    const msgs = [{ body: "a" }];
    const fp = ImportDelta.smsMessagesHeadFingerprint(msgs, mockQuickHash);
    expect(
      ImportDelta.resolveDeltaStart({ count: 100, headFp: fp }, 5, fp),
    ).toBe(0);
  });

  test("txnExportHeadFingerprint is stable when more rows are appended", () => {
    const u = ImportDelta.txnExportHeadFingerprint(
      [{ id: "1", date: "2026-01-01", amount: 10 }],
      mockQuickHash,
    );
    const v = ImportDelta.txnExportHeadFingerprint(
      [
        { id: "1", date: "2026-01-01", amount: 10 },
        { id: "2", date: "2026-01-02", amount: 20 },
      ],
      mockQuickHash,
    );
    expect(u).toBe(v);
  });

  test("jsonMessagesKey is namespaced", () => {
    expect(ImportDelta.jsonMessagesKey("SmsExtracts.json")).toBe(
      "json-msg:SmsExtracts.json",
    );
  });

  test("mixedImportHeadFingerprint prefers SMS row when first item has body", () => {
    const a = ImportDelta.mixedImportHeadFingerprint(
      [{ body: "head sms" }, { id: "1", amount: 10, date: "2026-01-01" }],
      mockQuickHash,
    );
    const b = ImportDelta.mixedImportHeadFingerprint(
      [
        { body: "head sms" },
        { id: "1", amount: 10, date: "2026-01-01" },
        { id: "2", amount: 20, date: "2026-01-02" },
      ],
      mockQuickHash,
    );
    expect(a).toBe(b);
  });

  test("mixedImportHeadFingerprint uses txn row when first item is txn-only", () => {
    const a = ImportDelta.mixedImportHeadFingerprint(
      [{ id: "x", amount: 5, date: "2026-01-01" }, { body: "sms" }],
      mockQuickHash,
    );
    const b = ImportDelta.mixedImportHeadFingerprint(
      [
        { id: "x", amount: 5, date: "2026-01-01" },
        { body: "sms" },
        { id: "y", amount: 6, date: "2026-01-02" },
      ],
      mockQuickHash,
    );
    expect(a).toBe(b);
  });

  test("jsonMixedArrayKey is namespaced", () => {
    expect(ImportDelta.jsonMixedArrayKey("a.json")).toBe("json-mixed:a.json");
  });
});
