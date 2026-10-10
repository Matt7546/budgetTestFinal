// Backend test process only. Intercepted Plaid adapters work without sockets.
// Allow only the disposable DB and ephemeral listeners created in this process.
const net = require("node:net");
const dns = require("node:dns");
const childProcess = require("node:child_process");
const path = require("node:path");
const allowedPorts = new Set();
function deny(message) {
  process.exitCode = 1; // A caught unexpected attempt must still fail the gate.
  throw new Error(message);
}
if (process.env.CALDERA_POSTGRES_TEST_CONFIRM === "disposable-loopback-cluster") {
  const target = new URL(process.env.DATABASE_URL);
  if (target.hostname !== "127.0.0.1" || Number(target.port) <= 1024 || target.port === "5432") {
    deny("Validation requires the disposable loopback database.");
  }
  allowedPorts.add(Number(target.port));
}
const listen = net.Server.prototype.listen;
net.Server.prototype.listen = function (...args) {
  const options = typeof args[0] === "object" ? args[0] : { port: args[0], host: args[1] };
  if (options.port !== 0 || options.host !== "127.0.0.1") {
    deny("Validation listeners must use ephemeral loopback ports.");
  }
  let port;
  this.once("listening", () => { port = this.address().port; allowedPorts.add(port); });
  this.once("close", () => { allowedPorts.delete(port); });
  return listen.apply(this, args);
};
// Existing real-index tests bind in their independently contained child. Only
// that exact instrumentation's IPC announcement may authorize its HTTP port.
const fork = childProcess.fork;
childProcess.fork = function (modulePath, args, options) {
  const child = fork.call(this, modulePath, args, options);
  const backend = path.resolve(__dirname, "../../plaid-backend");
  if (modulePath === path.join(backend, "index.js") &&
      options?.execArgv?.includes(path.join(backend, "scripts/startup-test-process.js"))) {
    let port;
    child.on("message", (message) => {
      if (message.kind === "listening" && Number.isInteger(message.port) && message.port > 1024 && message.port !== 5432) {
        port = message.port;
        allowedPorts.add(port);
      }
    });
    child.once("exit", () => { allowedPorts.delete(port); });
  }
  return child;
};
const connect = net.Socket.prototype.connect;
net.Socket.prototype.connect = function (...args) {
  const first = Array.isArray(args[0]) ? args[0][0] : args[0];
  const options = first && typeof first === "object" ? first : { port: first, host: args[1] };
  const port = Number(options.port);
  if (options.path || options.host !== "127.0.0.1" || !Number.isInteger(port) ||
      !allowedPorts.has(port)) {
    deny("Validation blocked an undeclared external/application connection.");
  }
  return connect.apply(this, args);
};
const lookup = dns.lookup;
dns.lookup = function (hostname, ...args) {
  if (hostname !== "127.0.0.1") deny("Validation blocked external DNS.");
  return lookup.call(this, hostname, ...args);
};
