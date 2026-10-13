// Deliberately NOT a raw-log scrubber. Only recognized Node/TAP diagnostic
// fields are publishable; actual/expected values, objects, console output and
// environment dumps never enter the report. Unrecognized failures stay failed.
const path = require("node:path");

const COMMANDS = {
  static: "node scripts/validation/static-check.js",
  "backend-chain": "bash scripts/validation/disposable-postgres.sh chain (npm test)",
  "postgres-startup": "bash scripts/validation/disposable-postgres.sh startup (npm run test:startup-postgres)",
};
const ERROR_CLASSES = /^(AssertionError|Error|TypeError|SyntaxError|RangeError|ReferenceError|URIError|AggregateError)$/;
const UNAVAILABLE = "Safe failure detail unavailable; raw output was omitted, not treated as success.";
const FIELDS = ["name", "errorClass", "message", "sourceLocation"];
const REASONS = ["command-failed", "required-tests-skipped", "required-postgres-execution-marker-missing", "required-postgres-startup-marker-missing"];

function credentialIndicator(value, opaque = true) {
  // Do not attempt to infer the end of an unquoted/multi-word credential.
  // These indicators fence the COMPLETE field, including quoted and natural
  // language renderings. Pure subject words without a value are not a match.
  return /\b(?:authorization["']?\s*[:=]|bearer\s+\S|(?:session|access|refresh)[ _-]+token\s+\S|api[ _-]+key\s+\S|(?:plaid\s+)?client\s+(?:id|secret)\s+\S|database\s+password\s+\S|encryption\s+key\s+\S)/i.test(value) ||
    /\b(?:[A-Za-z0-9_-]*(?:password|passwd|secret|token|api[_-]?key|authorization|credential|encryption[_-]?key)[A-Za-z0-9_-]*|jwt|session(?:[_-]?id)?|database[_-]?url|(?:plaid[_-]?)?client[_-]?id|encryption\s+key)["']?\s*[:=]/i.test(value) ||
    /\b[A-Za-z][A-Za-z0-9+.-]*:\/\/|\b(?:access|public)-(?:sandbox|development|production)-|\b(?:gh[pousr]_|github_pat_)|\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+|\b[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\b/i.test(value) ||
    (opaque && /\b[A-Za-z0-9_+/=]{24,}\b/.test(value));
}

function diagnosticText(value) {
  if (typeof value !== "string" || value.length > 4096) return { value: null, status: "unavailable" };
  let safe = value.replace(/\x1b\[[0-9;]*m/g, "").trim();
  if (safe.startsWith('"') && safe.endsWith('"')) {
    try { safe = JSON.parse(safe); } catch { return { value: null, status: "unavailable" }; }
  } else if (safe.startsWith("'") && safe.endsWith("'")) safe = safe.slice(1, -1).replace(/''/g, "'");
  if (typeof safe !== "string" || /[^\x20-\x7e]/.test(safe)) return { value: null, status: "unavailable" };
  if (credentialIndicator(safe)) return { value: null, status: "redacted" };
  const valueAfterPolicy = text(safe);
  return { value: valueAfterPolicy, status: valueAfterPolicy === null ? "unavailable" : "available" };
}

function text(value) {
  if (typeof value !== "string" || value.length > 4096) return null;
  let safe = value.replace(/\x1b\[[0-9;]*m/g, "").trim();
  // Decode only ordinary quoted TAP scalars, not YAML documents/objects.
  if (safe.startsWith('"') && safe.endsWith('"')) {
    try { safe = JSON.parse(safe); } catch { return null; }
  } else if (safe.startsWith("'") && safe.endsWith("'")) safe = safe.slice(1, -1).replace(/''/g, "'");
  if (typeof safe !== "string" || /[^\x20-\x7e]/.test(safe)) return null;
  // assert.match prints the supplied regex and then an arbitrary input dump.
  // Preserve the recognized assertion fact, never that regex/input payload.
  if (/^The input (?:did not match|was expected to not match) the regular expression .*\. Input:$/.test(safe)) {
    if (safe === "The input did not match the regular expression /Validation blocked/. Input:") {
      return "The input did not match the regular expression /Validation blocked/. Input omitted.";
    }
    return safe.startsWith("The input did not match")
      ? "The input did not match the required regular expression; regex/input values omitted."
      : "The input unexpectedly matched the regular expression; regex/input values omitted.";
  }
  const classified = safe;
  // No raw payloads, money/account fields, arbitrary assignments, paths, .env
  // content or environment values. Ordinary diagnostic prose is retained.
  if (!/[A-Za-z]/.test(classified) || safe.length > 512 || /[{}\[\]<>\\]/.test(classified) ||
      /(?:^|\s)\/|\.env\b|\$\s*\d|\b\w+\s*=\s*[^=]|\b[A-Z][A-Z0-9_]{2,}\s*:/.test(classified) ||
      /\b(?:account_id|item_id|owner_id|user_id|balances?|amount|currency|transactions?|provider_payload|actual|expected)\b\s*[:=]/i.test(classified) ||
      /\b(?:balance|amount|protectedAmount|Cushion|Checking|Savings|SetAside|AvailableToSpend)\b[^;]*\d/i.test(classified)) return null;
  return safe;
}
function location(lines, repo) {
  for (const line of lines) {
    for (const match of line.matchAll(/((?:file:\/\/)?\/[^()\s'"]+|(?:scripts|plaid-backend)\/[A-Za-z0-9_./-]+):(\d+):(\d+)/g)) {
      const file = match[1].replace(/^file:\/\//, "");
      const relative = path.isAbsolute(file) ? path.relative(repo, file) : file;
      if (/^(?:scripts|plaid-backend)\/[A-Za-z0-9_./-]+\.(?:js|cjs|sh)$/.test(relative) &&
          !relative.split("/").includes("..") && !relative.includes("/node_modules/") && relative.length <= 200 &&
          !credentialIndicator(relative, false) &&
          [match[2], match[3]].every((n) => Number.isSafeInteger(Number(n)) && Number(n) > 0 && Number(n) < 10000000)) {
        return `${relative}:${match[2]}:${match[3]}`;
      }
    }
  }
  return null;
}
function diagnostic(lines, repo, name = null) {
  const indent = lines.find((line) => /^\s*---$/.test(line))?.match(/^\s*/)[0].length;
  const fieldPattern = (key) => new RegExp(`^ {${indent ?? 0}}${key}:\\s*`);
  const field = (key) => lines.find((line) => fieldPattern(key).test(line))?.replace(fieldPattern(key), "");
  const errorName = diagnosticText(field("name"));
  const code = diagnosticText(field("code"));
  const errorClass = ERROR_CLASSES.test(errorName.value || "") ? errorName.value : code.value === "ERR_ASSERTION" ? "AssertionError" : null;
  const error = field("error");
  let messageField = { value: null, status: "unavailable" };
  if (error?.startsWith("|")) {
    const start = lines.findIndex((line) => fieldPattern("error").test(line));
    for (const line of lines.slice(start + 1)) {
      if (line.trim() && line.match(/^\s*/)[0].length <= indent) break;
      // Continuations/diffs can contain unlabeled values. Retain only the
      // first diagnostic line, not arbitrary multiline assertion contents.
      if (line.trim()) { messageField = diagnosticText(line); break; }
    }
  } else messageField = diagnosticText(error);
  // Prefer the assertion stack frame over the test declaration's location.
  const stack = lines.findIndex((line) => fieldPattern("stack").test(line));
  const frames = [];
  if (stack >= 0) for (const line of lines.slice(stack + 1)) {
    if (line.trim() && line.match(/^\s*/)[0].length <= indent) break;
    frames.push(line);
  }
  const sourceLocation = location([...frames, field("location") || ""], repo);
  const nameField = diagnosticText(name);
  return { name: nameField.value, errorClass, message: messageField.value, sourceLocation,
    fieldAvailability: { name: nameField.status, errorClass: errorClass ? "available" :
      errorName.status === "redacted" || code.status === "redacted" ? "redacted" : "unavailable",
    message: messageField.status, sourceLocation: sourceLocation ? "available" : "unavailable" } };
}
function excerpt(details) {
  return details.map((d) => [d.name && `not ok: ${d.name}`, d.errorClass && `errorClass: ${d.errorClass}`,
    d.message && `message: ${d.message}`, d.sourceLocation && `sourceLocation: ${d.sourceLocation}`]
    .filter(Boolean).join("\n")).filter(Boolean);
}
function detailSummary(failingTests, root) {
  const missingDetails = [];
  if (!failingTests.some((d) => d.name)) missingDetails.push("failing test identity unavailable");
  if (!root.errorClass) missingDetails.push("error class unavailable");
  if (!root.message) missingDetails.push("safe assertion/message unavailable");
  if (!root.sourceLocation) missingDetails.push("source location unavailable");
  const details = [root, ...failingTests];
  const complete = missingDetails.length === 0 && details.every((d) => FIELDS.every((key) => d.fieldAvailability[key] === "available"));
  const some = details.some((d) => FIELDS.some((key) => d.fieldAvailability[key] === "available"));
  return { missingDetails, availability: complete ? "available" : some ? "partial" : "unavailable" };
}
function failureReport({ gate, exitCode, raw, repo, reason = "command-failed" }) {
  if (!COMMANDS[gate]) throw new Error("Unsupported backend failure gate.");
  const lines = raw.split(/\r?\n/);
  const failingTests = [];
  let omittedFailures = 0;
  for (let i = 0; i < lines.length; i++) {
    const match = lines[i].match(/^\s*not ok \d+\s*-\s*(.*)$/);
    if (!match) continue;
    if (failingTests.length === 20) { omittedFailures++; continue; }
    const block = [];
    for (const line of lines.slice(i + 1, i + 81)) {
      if (/^\s*(?:\.\.\.|(?:not ok|ok) \d+\s*-)/.test(line)) break;
      block.push(line);
    }
    failingTests.push(diagnostic(block, repo, match[1]));
  }
  // Plain check scripts throw outside node:test. Never retain their source
  // dump, actual/expected payload or arbitrary console output.
  let errorClass = null;
  let message = null;
  let sourceLocation = null;
  let fieldAvailability = Object.fromEntries(FIELDS.map((key) => [key, "unavailable"]));
  if (!failingTests.length) {
    for (let i = 0; i < lines.length; i++) {
      const match = lines[i].match(/^(AssertionError|Error|TypeError|SyntaxError|RangeError|ReferenceError|URIError|AggregateError)(?: \[ERR_[A-Z_]+\])?:\s*(.*)$/);
      if (!match) continue;
      errorClass = match[1];
      const messageField = diagnosticText(match[2]);
      message = messageField.value;
      sourceLocation = location(lines.slice(i + 1, i + 21), repo);
      fieldAvailability = { name: "unavailable", errorClass: "available", message: messageField.status,
        sourceLocation: sourceLocation ? "available" : "unavailable" };
      break;
    }
  } else ({ errorClass, message, sourceLocation, fieldAvailability } = failingTests[0]);
  const { missingDetails, availability } = detailSummary(failingTests, { errorClass, message, sourceLocation, fieldAvailability });
  // The excerpt reconstructs only recognized sanitized failure fields, not a
  // broad surrounding raw-log window (which may contain provider/account data).
  const sanitizedExcerpt = excerpt(failingTests.length ? failingTests : [{ errorClass, message, sourceLocation }]);
  return { version: 1, gate, command: COMMANDS[gate], exitCode, reason, availability, failingTests,
    errorClass, message, sourceLocation, fieldAvailability, sanitizedExcerpt, missingDetails, omittedFailures,
    ...(availability !== "available" ? { diagnosticNotice: UNAVAILABLE } : {}) };
}

function unavailableReport({ gate, exitCode, reason = "command-failed" }, notice) {
  if (!COMMANDS[gate] || !Number.isInteger(exitCode) || !REASONS.includes(reason)) throw new Error("Invalid failure context.");
  return { version: 1, gate, command: COMMANDS[gate], exitCode, reason, availability: "unavailable", failingTests: [],
    errorClass: null, message: null, sourceLocation: null,
    fieldAvailability: Object.fromEntries(FIELDS.map((key) => [key, "unavailable"])),
    sanitizedExcerpt: [], missingDetails: ["safe failure details unavailable"], omittedFailures: 0,
    diagnosticNotice: notice };
}

function prepareFailurePublication(report, context) {
  if (!COMMANDS[context.gate] || !Number.isInteger(context.exitCode) || !REASONS.includes(context.reason) ||
      typeof context.repo !== "string") throw new Error("Invalid failure publication context.");
  // Inspect the serialized candidate, not just the primary parser's inputs.
  // Round-trip eliminates getters/toJSON from the object we subsequently use.
  // Reject unknown payload fields; never attempt to rescue individual remnants.
  let value;
  let passed = false;
  try {
    value = JSON.parse(JSON.stringify(report));
    const keys = ["version", "gate", "command", "exitCode", "reason", "availability", "failingTests", "errorClass",
      "message", "sourceLocation", "fieldAvailability", "sanitizedExcerpt", "missingDetails", "omittedFailures", "diagnosticNotice"];
    const exactKeys = (object, allowed) => object && typeof object === "object" && !Array.isArray(object) &&
      Object.keys(object).every((key) => allowed.includes(key));
    const statuses = (data) => exactKeys(data, FIELDS) && FIELDS.every((key) => ["available", "redacted", "unavailable"].includes(data[key]));
    const detail = (data, withName) => {
      if (!exactKeys(data, [...FIELDS, "fieldAvailability"]) || !statuses(data.fieldAvailability)) return false;
      return FIELDS.filter((key) => withName || key !== "name").every((key) => {
        const entry = data[key];
        if (data.fieldAvailability[key] !== "available") return entry === null;
        if (typeof entry !== "string" || credentialIndicator(entry, key !== "sourceLocation")) return false;
        if (key === "sourceLocation") return entry === location([entry], context.repo);
        if (key === "errorClass") return ERROR_CLASSES.test(entry);
        // The known containment regex template has already omitted its input.
        if (entry === "The input did not match the regular expression /Validation blocked/. Input omitted.") return true;
        return entry === text(entry);
      });
    };
    passed = exactKeys(value, keys) && value.version === 1 && value.gate === context.gate &&
      value.command === COMMANDS[context.gate] && value.exitCode === context.exitCode && value.reason === context.reason &&
      ["available", "partial", "unavailable"].includes(value.availability) &&
      Array.isArray(value.failingTests) && value.failingTests.length <= 20 && value.failingTests.every((d) => detail(d, true)) &&
      detail({ errorClass: value.errorClass, message: value.message, sourceLocation: value.sourceLocation,
        fieldAvailability: value.fieldAvailability }, false) &&
      Number.isInteger(value.omittedFailures) && value.omittedFailures >= 0 &&
      Array.isArray(value.missingDetails) && value.missingDetails.every((s) => ["failing test identity unavailable", "error class unavailable",
        "safe assertion/message unavailable", "source location unavailable", "safe failure details unavailable"].includes(s)) &&
      (value.diagnosticNotice === undefined || [UNAVAILABLE, "Safe failure evidence generation failed; raw output was not published."].includes(value.diagnosticNotice)) &&
      JSON.stringify(value.sanitizedExcerpt) === JSON.stringify(excerpt(value.failingTests.length ? value.failingTests : [value]));
    if (passed) {
      const first = value.failingTests[0];
      const summary = detailSummary(value.failingTests, value);
      const extractorUnavailable = value.failingTests.length === 0 && summary.availability === "unavailable" &&
        JSON.stringify(value.missingDetails) === '["safe failure details unavailable"]';
      passed = (!first || ["errorClass", "message", "sourceLocation", "fieldAvailability"].every((key) =>
        JSON.stringify(value[key]) === JSON.stringify(first[key]))) && value.availability === summary.availability &&
        (extractorUnavailable || JSON.stringify(value.missingDetails) === JSON.stringify(summary.missingDetails));
    }
  } catch { /* Do not report the rejected object, JSON or exception. */ }
  if (!passed) value = unavailableReport(context, "Safe failure details unavailable due to publication redaction policy; raw content was not published.");
  value.publicationSafety = passed ? "passed" : "rejected";
  let serialized = JSON.stringify(value, null, 2) + "\n";
  const hasCredential = (node) => typeof node === "string" ? credentialIndicator(node, false) :
    node && typeof node === "object" ? Object.values(node).some(hasCredential) : false;
  // Scan the FINAL encoded record as well, including reconstructed excerpts
  // and metadata. Decode escapes before inspecting; these are the writer bytes.
  if (hasCredential(JSON.parse(serialized))) {
    value = unavailableReport(context, "Safe failure details unavailable due to publication redaction policy; raw content was not published.");
    value.publicationSafety = "rejected";
    serialized = JSON.stringify(value, null, 2) + "\n";
  }
  // These are the exact inspected, safe bytes that the writer must publish.
  return { report: value, serialized };
}

module.exports = { failureReport, unavailableReport, prepareFailurePublication };
