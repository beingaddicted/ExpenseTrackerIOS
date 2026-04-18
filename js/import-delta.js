// ═══════════════════════════════════════════════════
// JSON import delta — slice growing exports (Scriptable SMS JSON, etc.)
// Browser: global ImportDelta. Node: require("./import-delta")
// ═══════════════════════════════════════════════════

(function (root, factory) {
  const exp = factory();
  if (typeof module === "object" && module.exports) {
    module.exports = exp;
  }
  if (typeof root !== "undefined") {
    root.ImportDelta = exp;
  }
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  function smsItemBody(item) {
    if (!item || typeof item !== "object") return "";
    return String(
      item.originalSms || item.body || item.message || item.text || "",
    );
  }

  /**
   * Fingerprint the leading SMS body (only). Using a single stable head keeps
   * delta imports correct when the file grows from 1–2 rows to many (min(3,n)
   * would change the fingerprint as soon as a third row appears).
   */
  function smsMessagesHeadFingerprint(messages, quickHash) {
    if (!messages || !messages.length) return 0;
    const sample = smsItemBody(messages[0]);
    const len = Math.max(200, Math.min(1200, sample.length + 80));
    return quickHash(sample, len);
  }

  function txnExportHeadFingerprint(transactions, quickHash) {
    if (!transactions || !transactions.length) return 0;
    const sample = transactions
      .slice(0, 1)
      .map(
        (t) =>
          `${t && t.id != null ? t.id : ""}|${t && t.date != null ? t.date : ""}|${t && t.amount != null ? t.amount : ""}`,
      )
      .join("\n");
    return quickHash(sample, 500);
  }

  /**
   * @param {{ count: number, headFp: number }|null|undefined} prev
   * @returns {number} start index for Array#slice (only process messages.slice(start))
   */
  function resolveDeltaStart(prev, totalLen, headFp) {
    if (!totalLen) return 0;
    if (!prev || typeof prev.count !== "number") return 0;
    if (totalLen < prev.count) return 0;
    if (prev.headFp !== headFp) return 0;
    return Math.min(prev.count, totalLen);
  }

  function jsonMessagesKey(fileName) {
    return `json-msg:${fileName || "unknown"}`;
  }

  function jsonTxnsKey(fileName) {
    return `json-txn:${fileName || "unknown"}`;
  }

  function jsonMixedArrayKey(fileName) {
    return `json-mixed:${fileName || "unknown"}`;
  }

  /**
   * Stable head fingerprint for a top-level array that may contain both
   * SMS-shaped rows and transaction-shaped rows (order preserved).
   */
  function mixedImportHeadFingerprint(arr, quickHash) {
    if (!arr || !arr.length) return 0;
    const first = arr[0];
    if (!first || typeof first !== "object") return 0;
    if (first.message || first.text || first.body || first.originalSms) {
      return smsMessagesHeadFingerprint([first], quickHash);
    }
    if (first.id != null && first.amount != null) {
      return txnExportHeadFingerprint([first], quickHash);
    }
    const ser = JSON.stringify(first);
    return quickHash(ser, Math.min(500, ser.length + 40));
  }

  return {
    smsItemBody,
    smsMessagesHeadFingerprint,
    txnExportHeadFingerprint,
    resolveDeltaStart,
    jsonMessagesKey,
    jsonTxnsKey,
    jsonMixedArrayKey,
    mixedImportHeadFingerprint,
  };
});
