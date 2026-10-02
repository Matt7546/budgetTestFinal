// Test-only instrumentation around the REAL index.js / Express / store code.
const assert = require("node:assert/strict");
const { fork } = require("node:child_process");
const fs = require("node:fs");
const http = require("node:http");
const os = require("node:os");
const path = require("node:path");

if (process.env.CALDERA_STARTUP_TEST_HARNESS === "contained") {
  const Module = require("node:module");
  const net = require("node:net");
  const originalConnect = net.Socket.prototype.connect;
  net.Socket.prototype.connect = function (...args) {
    const options = typeof args[0] === "object"
      ? args[0] : { port: args[0], host: args[1] };
    if (!options || typeof options !== "object" ||
        options.host !== "127.0.0.1" ||
        String(options.port) !== process.env.CALDERA_STARTUP_TEST_DB_PORT) {
      process.send?.({ kind: "unexpected-network" });
      throw new Error("Contained startup test blocked an outbound connection.");
    }
    return originalConnect.apply(this, args);
  };
  global.fetch = async () => {
    process.send?.({ kind: "unexpected-network" });
    throw new Error("Contained startup test blocked fetch.");
  };

  const express = require("express");
  const originalListen = express.application.listen;
  express.application.listen = function (...args) {
    process.send?.({ kind: "listen-attempt" });
    const callback = args.find((argument) => typeof argument === "function");
    // Never expose this diagnostic process on the LAN or configured PORT.
    return originalListen.call(this, 0, "127.0.0.1", function () {
      callback?.call(this);
      process.send?.({ kind: "listening", port: this.address().port });
    });
  };
  const expressProxy = new Proxy(express, {
    apply(target, receiver, args) {
      process.send?.({ kind: "app-created" });
      return Reflect.apply(target, receiver, args);
    },
  });
  const originalLoad = Module._load;
  Module._load = function (request, parent, isMain) {
    if (request === "express") return expressProxy;
    const loaded = originalLoad.call(this, request, parent, isMain);
    if (request === "./plaidItemStore") {
      return { ...loaded, createPlaidItemStore(...args) {
        process.send?.({ kind: "item-store-created" });
        const store = loaded.createPlaidItemStore(...args);
        if (process.env.CALDERA_STARTUP_TEST_FAIL_SCHEMA === "true") {
          store.ensureSchema = async () => {
            throw new Error("synthetic-database-password");
          };
        }
        return store;
      } };
    }
    if (request === "./sessionStore") {
      return { ...loaded, createSessionStore(...args) {
        process.send?.({ kind: "session-store-created" });
        return loaded.createSessionStore(...args);
      } };
    }
    if (request === "plaid") {
      return { ...loaded, PlaidApi: new Proxy(loaded.PlaidApi, {
        construct(target, args) {
          process.send?.({ kind: "provider-client-created" });
          return Reflect.construct(target, args);
        },
      }) };
    }
    return loaded;
  };
}

async function launchBackend(env, { databasePort = "" } = {}) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "caldera-startup-test-"));
  const events = [];
  let output = "";
  let child;
  try {
    child = fork(path.join(__dirname, "..", "index.js"), [], {
      cwd: directory, // No application .env is read.
      execArgv: ["--require", __filename],
      env: {
        // Only module lookup is inherited; no application credentials/config.
        ...(process.env.NODE_PATH ? { NODE_PATH: process.env.NODE_PATH } : {}),
        // Default local DB role is the OS owner, never an inherited PGUSER.
        // A role explicitly named in DATABASE_URL still takes precedence.
        USER: os.userInfo().username,
        ...env,
        PORT: "0",
        PLAID_TOKEN_STORE_PATH: path.join(directory, "items.json"),
        CALDERA_STARTUP_TEST_HARNESS: "contained",
        CALDERA_STARTUP_TEST_DB_PORT: String(databasePort),
      },
      stdio: ["ignore", "pipe", "pipe", "ipc"],
    });
    child.stdout.on("data", (data) => { output += data.toString(); });
    child.stderr.on("data", (data) => { output += data.toString(); });
    const outcome = await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        reject(new Error("Contained backend did not finish startup within the test bound."));
      }, 10_000);
      child.on("message", (message) => {
        events.push(message);
        if (message.kind === "listening") {
          clearTimeout(timeout);
          resolve({ port: message.port, exitCode: null });
        }
      });
      child.once("error", (error) => { clearTimeout(timeout); reject(error); });
      child.once("close", (code) => {
        clearTimeout(timeout);
        resolve({ port: null, exitCode: code });
      });
    });
    return { child, directory, events, output: () => output, ...outcome };
  } catch (error) {
    await stopBackend({ child, directory });
    throw error;
  }
}

async function stopBackend({ child, directory }) {
  try {
    if (child && child.exitCode === null && child.signalCode === null) {
      await new Promise((resolve) => {
        const timeout = setTimeout(() => child.kill("SIGKILL"), 3_000);
        child.once("exit", () => { clearTimeout(timeout); resolve(); });
        child.kill("SIGTERM");
      });
    }
  } finally {
    // Exact directory created above; never an application store or database.
    fs.rmSync(directory, { recursive: true, force: true });
  }
}

async function requestJSON(backend, route, { method = "GET", headers = {} } = {}) {
  assert.ok(backend.port);
  return new Promise((resolve, reject) => {
    const request = http.request({
      hostname: "127.0.0.1", port: backend.port, path: route, method, headers,
    }, (response) => {
      let body = "";
      response.on("data", (data) => { body += data.toString(); });
      response.on("end", () => {
        try { resolve({ status: response.statusCode, body: JSON.parse(body) }); }
        catch { reject(new Error("Contained backend returned invalid JSON.")); }
      });
    });
    request.setTimeout(5_000, () => request.destroy(new Error("Contained request timed out.")));
    request.on("error", reject);
    request.end();
  });
}

async function waitForEvent(backend, kind) {
  if (backend.events.some((event) => event.kind === kind)) return;
  await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      backend.child.off("message", received);
      reject(new Error("Contained backend event did not arrive."));
    }, 5_000);
    function received(event) {
      if (event.kind !== kind) return;
      clearTimeout(timeout);
      backend.child.off("message", received);
      resolve();
    }
    backend.child.on("message", received);
  });
}

module.exports = { launchBackend, stopBackend, requestJSON, waitForEvent };
