/**
 * Behavioral tests for billing_web return.js (dependency-free fake DOM).
 */
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";
import vm from "node:vm";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const RETURN_JS = path.resolve(__dirname, "../src/assets/return.js");
const ATLAS_URI = "projectatlas://billing/return";

function loadReturnScript(options = {}) {
  const assignCalls = [];
  const closeCalls = [];
  const focusCalls = [];
  const state = { clickHandler: null };

  const opener =
    options.opener === undefined
      ? null
      : options.opener === null
        ? null
        : {
            closed: options.openerClosed === true,
            focus() {
              focusCalls.push(true);
              if (options.focusThrows) {
                throw new Error("focus blocked");
              }
            },
          };

  const elements = {
    "return-title": { textContent: "" },
    "return-body": { textContent: "" },
    "return-hint": { textContent: "" },
    "return-to-atlas": {
      addEventListener(type, handler) {
        if (type === "click") {
          state.clickHandler = handler;
        }
      },
    },
  };

  const documentListeners = {};
  const document = {
    readyState: options.readyState || "complete",
    getElementById(id) {
      return elements[id] || null;
    },
    addEventListener(type, handler) {
      documentListeners[type] = handler;
    },
  };

  const window = {
    opener,
    location: {
      assign(url) {
        assignCalls.push(url);
      },
    },
    close() {
      closeCalls.push(true);
    },
  };

  const context = { window, document };
  context.window.window = window;
  context.globalThis = context;

  const code = fs.readFileSync(RETURN_JS, "utf8");
  vm.runInNewContext(code, context, { filename: "return.js" });

  return {
    assignCalls,
    closeCalls,
    focusCalls,
    get clickHandler() {
      return state.clickHandler;
    },
    elements,
    documentListeners,
    fireClick() {
      assert.ok(state.clickHandler, "click handler not registered");
      state.clickHandler({ type: "click" });
    },
    fireDomContentLoaded() {
      assert.ok(
        documentListeners.DOMContentLoaded,
        "DOMContentLoaded handler missing",
      );
      documentListeners.DOMContentLoaded();
    },
  };
}

test("opener focus succeeds: close attempted, custom scheme not launched", () => {
  const env = loadReturnScript({
    opener: {},
    openerClosed: false,
  });
  assert.equal(env.assignCalls.length, 0);
  env.fireClick();
  assert.equal(env.focusCalls.length, 1);
  assert.equal(env.closeCalls.length, 1);
  assert.deepEqual(env.assignCalls, []);
});

test("opener absent: custom scheme launched only after click", () => {
  const env = loadReturnScript({ opener: null });
  assert.deepEqual(env.assignCalls, []);
  env.fireClick();
  assert.deepEqual(env.assignCalls, [ATLAS_URI]);
  assert.equal(env.closeCalls.length, 0);
});

test("opener focus throws: custom scheme fallback used", () => {
  const env = loadReturnScript({
    opener: {},
    openerClosed: false,
    focusThrows: true,
  });
  env.fireClick();
  assert.equal(env.focusCalls.length, 1);
  assert.deepEqual(env.assignCalls, [ATLAS_URI]);
  assert.equal(env.closeCalls.length, 0);
});

test("page init does not auto-launch custom scheme", () => {
  const ready = loadReturnScript({ opener: null, readyState: "complete" });
  assert.deepEqual(ready.assignCalls, []);

  const loading = loadReturnScript({ opener: null, readyState: "loading" });
  assert.deepEqual(loading.assignCalls, []);
  loading.fireDomContentLoaded();
  assert.deepEqual(loading.assignCalls, []);
  assert.ok(loading.clickHandler);
});

test("return copy remains non-authoritative about Premium", () => {
  const env = loadReturnScript({ opener: null });
  const title = env.elements["return-title"].textContent;
  const body = env.elements["return-body"].textContent;
  const hint = env.elements["return-hint"].textContent;
  assert.match(title, /Pagamento inviato/);
  assert.match(body, /riceve la conferma del pagamento/);
  assert.doesNotMatch(body, /Premium attivo/i);
  assert.doesNotMatch(body, /pagamento confermato/i);
  assert.match(
    hint,
    /Se Atlas non si apre automaticamente, torna manualmente all'app/,
  );
});
