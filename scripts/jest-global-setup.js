/**
 * Ensures tests/.generated/bank-sms-lib.cjs exists before any suite runs
 * (works for `npx jest` as well as `npm test`).
 */
const { spawnSync } = require("child_process");
const path = require("path");

const extract = path.join(__dirname, "extract-bank-sms-lib-for-jest.js");
const r = spawnSync(process.execPath, [extract], {
  stdio: "inherit",
  cwd: path.join(__dirname, ".."),
});
if (r.error) throw r.error;
if (r.status !== 0) {
  throw new Error("extract-bank-sms-lib-for-jest.js exited with " + r.status);
}

module.exports = async function globalSetup() {};
