// No names, messages, paths, stdout/stderr, credentials, or arbitrary event data
// enter this report. Human diagnostics use the separate TAP reporter.
const { summarizeEvents } = require("./backend-suite-result");
module.exports = async function* report(source) {
  const context = { suite: process.env.CALDERA_SUITE_ID,
    runID: process.env.CALDERA_SUITE_RUN_ID,
    operation: process.env.CALDERA_SUITE_OPERATION,
    pid: process.pid, nodeVersion: process.version };
  yield JSON.stringify(await summarizeEvents(source, context)) + "\n";
};
