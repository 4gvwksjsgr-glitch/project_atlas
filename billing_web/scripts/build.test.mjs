import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import test from "node:test";
import {
  build,
  buildRuntimeConfigSource,
  validateSandboxClientToken,
  SANDBOX_CLIENT_TOKEN_RE,
} from "../scripts/build.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const BILLING_WEB = path.resolve(__dirname, "..");
const REPO_ROOT = path.resolve(BILLING_WEB, "..");

/** Synthetic exact-format sandbox client token (not real). */
const VALID_TOKEN = "test_" + "a".repeat(27);
assert.equal(VALID_TOKEN.length, 5 + 27);
assert.equal(SANDBOX_CLIENT_TOKEN_RE.test(VALID_TOKEN), true);

const VALID_TXN = "txn_" + "b".repeat(26);
assert.equal(VALID_TXN.length, 4 + 26);

function read(p) {
  return fs.readFileSync(p, "utf8");
}

function withTempRoot(fn) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "billing-web-"));
  const root = path.join(tmp, "billing_web");
  fs.cpSync(path.join(BILLING_WEB, "src"), path.join(root, "src"), {
    recursive: true,
  });
  fs.mkdirSync(path.join(root, "scripts"), { recursive: true });
  try {
    return fn(root, tmp);
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

function loadCheckoutJsSource() {
  return read(path.join(BILLING_WEB, "src", "assets", "checkout.js"));
}

function extractCheckoutRegex(source, varName) {
  const re = new RegExp(
    "var\\s+" + varName + "\\s*=\\s*/(.+)/([a-z]*);",
  );
  const m = source.match(re);
  assert.ok(m, `missing ${varName}`);
  return new RegExp(m[1], m[2] || "");
}

test("SANDBOX_CLIENT_TOKEN_RE is exact Paddle sandbox format", () => {
  assert.equal(SANDBOX_CLIENT_TOKEN_RE.source, "^test_[a-zA-Z0-9]{27}$");
});

test("validateSandboxClientToken accepts exact valid token", () => {
  assert.equal(validateSandboxClientToken(VALID_TOKEN), true);
});

test("validateSandboxClientToken rejects missing/empty", () => {
  assert.equal(validateSandboxClientToken(""), false);
  assert.equal(validateSandboxClientToken(null), false);
  assert.equal(validateSandboxClientToken(undefined), false);
});

test("validateSandboxClientToken rejects length variants", () => {
  assert.equal(validateSandboxClientToken("test_" + "a".repeat(26)), false);
  assert.equal(validateSandboxClientToken("test_" + "a".repeat(28)), false);
  assert.equal(validateSandboxClientToken("test_short"), false);
});

test("validateSandboxClientToken rejects live_ and whitespace and punctuation", () => {
  assert.equal(validateSandboxClientToken("live_" + "a".repeat(27)), false);
  assert.equal(validateSandboxClientToken(" " + VALID_TOKEN), false);
  assert.equal(validateSandboxClientToken(VALID_TOKEN + " "), false);
  assert.equal(
    validateSandboxClientToken("test_" + "a".repeat(13) + " " + "b".repeat(13)),
    false,
  );
  assert.equal(validateSandboxClientToken("test_" + "a".repeat(26) + "!"), false);
});

test("production build rejects missing token", () => {
  withTempRoot((root) => {
    assert.throws(() => build({ root, env: {} }), /required/);
  });
});

test("production build rejects whitespace-padded token without silent trim", () => {
  withTempRoot((root) => {
    assert.throws(
      () =>
        build({
          root,
          env: { PADDLE_SANDBOX_CLIENT_TOKEN: " " + VALID_TOKEN },
        }),
      /exact|format|required/i,
    );
    assert.throws(
      () =>
        build({
          root,
          env: { PADDLE_SANDBOX_CLIENT_TOKEN: VALID_TOKEN + " " },
        }),
      /exact|format/i,
    );
  });
});

test("production build rejects live_ and wrong lengths", () => {
  withTempRoot((root) => {
    assert.throws(
      () =>
        build({
          root,
          env: { PADDLE_SANDBOX_CLIENT_TOKEN: "live_" + "a".repeat(27) },
        }),
      /format|exact|live_/i,
    );
    assert.throws(
      () =>
        build({
          root,
          env: { PADDLE_SANDBOX_CLIENT_TOKEN: "test_" + "a".repeat(26) },
        }),
      /format|exact/i,
    );
    assert.throws(
      () =>
        build({
          root,
          env: { PADDLE_SANDBOX_CLIENT_TOKEN: "test_" + "a".repeat(28) },
        }),
      /format|exact/i,
    );
  });
});

test("production build rejects forbidden secret env vars", () => {
  withTempRoot((root) => {
    assert.throws(
      () =>
        build({
          root,
          env: {
            PADDLE_SANDBOX_CLIENT_TOKEN: VALID_TOKEN,
            PADDLE_SANDBOX_API_KEY: "should-not-be-here",
          },
        }),
      /PADDLE_SANDBOX_API_KEY/,
    );
    assert.throws(
      () =>
        build({
          root,
          env: {
            PADDLE_SANDBOX_CLIENT_TOKEN: VALID_TOKEN,
            SUPABASE_SERVICE_ROLE_KEY: "should-not-be-here",
          },
        }),
      /SUPABASE_SERVICE_ROLE_KEY/,
    );
  });
});

test("production build accepts exact token and emits public config only", () => {
  withTempRoot((root) => {
    const result = build({
      root,
      env: { PADDLE_SANDBOX_CLIENT_TOKEN: VALID_TOKEN },
    });
    assert.equal(result.checkoutEnabled, true);
    const runtime = read(result.runtimePath);
    assert.match(runtime, /AtlasBillingRuntime/);
    assert.match(runtime, /"checkoutEnabled":true/);
    assert.match(
      runtime,
      new RegExp(`"paddleSandboxClientToken":"${VALID_TOKEN}"`),
    );
    assert.doesNotMatch(runtime, /PADDLE_SANDBOX_API_KEY/);
    assert.doesNotMatch(runtime, /SUPABASE_SERVICE_ROLE_KEY/);
    assert.ok(fs.existsSync(path.join(result.dist, "billing", "checkout.html")));
    assert.ok(fs.existsSync(path.join(result.dist, "billing", "return.html")));
  });
});

test("dev build produces disabled checkout without token", () => {
  withTempRoot((root) => {
    const result = build({ root, dev: true, env: {} });
    assert.equal(result.checkoutEnabled, false);
    const runtime = read(result.runtimePath);
    assert.match(runtime, /"checkoutEnabled":false/);
    assert.match(runtime, /"paddleSandboxClientToken":null/);
  });
});

test("build writes only under billing_web/dist and cleans previous dist", () => {
  withTempRoot((root) => {
    const first = build({
      root,
      env: { PADDLE_SANDBOX_CLIENT_TOKEN: VALID_TOKEN },
    });
    const marker = path.join(first.dist, "stale-marker.txt");
    fs.writeFileSync(marker, "stale");
    assert.ok(fs.existsSync(marker));

    const second = build({
      root,
      env: { PADDLE_SANDBOX_CLIENT_TOKEN: VALID_TOKEN },
    });
    assert.equal(second.dist, first.dist);
    assert.ok(!fs.existsSync(marker));
    assert.ok(second.dist.endsWith(`${path.sep}dist`));
  });
});

test("dist symlink is rejected fail-closed", (t) => {
  withTempRoot((root, tmp) => {
    const dist = path.join(root, "dist");
    const outside = path.join(tmp, "outside-target");
    fs.mkdirSync(outside, { recursive: true });
    fs.writeFileSync(path.join(outside, "owned.txt"), "do-not-delete");

    try {
      fs.symlinkSync(outside, dist, "junction");
    } catch (err) {
      t.skip(
        `symlink/junction unavailable in this environment: ${
          err instanceof Error ? err.message : String(err)
        }`,
      );
      return;
    }

    assert.throws(
      () =>
        build({
          root,
          env: { PADDLE_SANDBOX_CLIENT_TOKEN: VALID_TOKEN },
        }),
      /symbolic link|fail closed/i,
    );
    assert.ok(fs.existsSync(path.join(outside, "owned.txt")));
  });
});

test("exact route files are checkout.html and return.html", () => {
  assert.ok(
    fs.existsSync(path.join(BILLING_WEB, "src", "billing", "checkout.html")),
  );
  assert.ok(
    fs.existsSync(path.join(BILLING_WEB, "src", "billing", "return.html")),
  );
  assert.ok(
    !fs.existsSync(
      path.join(BILLING_WEB, "src", "billing", "checkout", "index.html"),
    ),
  );
  assert.ok(
    !fs.existsSync(
      path.join(BILLING_WEB, "src", "billing", "return", "index.html"),
    ),
  );
});

test("checkout.js uses exact txn regex and does not open Checkout", () => {
  const js = loadCheckoutJsSource();
  const txnRe = extractCheckoutRegex(js, "TXN_RE");
  assert.equal(txnRe.source, "^txn_[a-z\\d]{26}$");
  assert.equal(txnRe.flags.includes("i"), false);

  assert.equal(txnRe.test(VALID_TXN), true);
  assert.equal(txnRe.test("txn_" + "b".repeat(25)), false);
  assert.equal(txnRe.test("txn_" + "b".repeat(27)), false);
  assert.equal(txnRe.test("txn_" + "B".repeat(26)), false);
  assert.equal(txnRe.test("txn_" + "b".repeat(25) + "!"), false);
  assert.equal(txnRe.test("txn_abc"), false);
  assert.equal(txnRe.test(""), false);
  assert.equal(txnRe.test(null), false);

  const tokenRe = extractCheckoutRegex(js, "CLIENT_TOKEN_RE");
  assert.equal(tokenRe.source, "^test_[a-zA-Z0-9]{27}$");
  assert.equal(tokenRe.test(VALID_TOKEN), true);
  assert.equal(tokenRe.test("test_" + "a".repeat(26)), false);

  assert.doesNotMatch(js, /Paddle\.Checkout\.open\s*\(/);
  assert.doesNotMatch(js, /\.Checkout\.open\s*\(/);
  const sandboxIdx = js.indexOf('Environment.set("sandbox")');
  const initIdx = js.indexOf("Initialize(");
  assert.ok(sandboxIdx >= 0);
  assert.ok(initIdx > sandboxIdx);
});

test("return page wording is non-authoritative", () => {
  const js = read(path.join(BILLING_WEB, "src", "assets", "return.js"));
  assert.match(js, /Stiamo verificando il pagamento/);
  assert.match(js, /aggiornato dopo la conferma/);
  assert.doesNotMatch(js, /Pagamento ricevuto/);
  assert.doesNotMatch(js, /Premium attivo/i);
  assert.doesNotMatch(js, /abbonamento attivo/i);
  assert.doesNotMatch(js, /acquisto completato/i);
  assert.doesNotMatch(js, /pagamento confermato/i);
});

test("payment-page JS has no entitlement mutation or server credential usage", () => {
  const files = [
    path.join(BILLING_WEB, "src", "assets", "checkout.js"),
    path.join(BILLING_WEB, "src", "assets", "return.js"),
  ];
  for (const file of files) {
    const text = read(file);
    assert.doesNotMatch(text, /PADDLE_SANDBOX_API_KEY/);
    assert.doesNotMatch(text, /SUPABASE_SERVICE_ROLE_KEY/);
    assert.doesNotMatch(text, /service_role/i);
    assert.doesNotMatch(text, /company_billing/);
    assert.doesNotMatch(text, /entitlement/i);
    assert.doesNotMatch(text, /fetch\s*\(/);
    assert.doesNotMatch(text, /XMLHttpRequest/);
    assert.doesNotMatch(text, /console\.(log|debug|info|warn|error)/);
    assert.doesNotMatch(text, /localStorage|sessionStorage/);
  }
});

test("checkout CSP is sandbox-only without live Paddle hosts", () => {
  const html = read(path.join(BILLING_WEB, "src", "billing", "checkout.html"));
  assert.doesNotMatch(html, /https:\/\/api\.paddle\.com/);
  assert.doesNotMatch(html, /https:\/\/buy\.paddle\.com/);
  assert.doesNotMatch(html, /https:\/\/checkout\.paddle\.com(?!-)/);
  assert.match(html, /https:\/\/cdn\.paddle\.com/);
  assert.match(html, /https:\/\/sandbox-api\.paddle\.com/);
  assert.match(html, /https:\/\/sandbox-buy\.paddle\.com/);
  assert.match(html, /https:\/\/sandbox-checkout\.paddle\.com/);
  assert.doesNotMatch(html, /unsafe-eval/);
  const cspMatch = html.match(
    /http-equiv="Content-Security-Policy" content="([^"]+)"/,
  );
  assert.ok(cspMatch, "CSP meta missing");
  assert.doesNotMatch(cspMatch[1], /\*/);
});

function assertCloudflareHeadersPolicy(headersText) {
  assert.match(headersText, /^\/\*\s*$/m);
  assert.match(headersText, /Content-Security-Policy:/);
  assert.match(headersText, /frame-ancestors 'none'/);
  assert.match(headersText, /X-Frame-Options:\s*DENY/);
  assert.match(headersText, /X-Content-Type-Options:\s*nosniff/);
  assert.match(
    headersText,
    /Referrer-Policy:\s*strict-origin-when-cross-origin/,
  );
  assert.match(
    headersText,
    /Permissions-Policy:\s*camera=\(\),\s*microphone=\(\),\s*geolocation=\(\)/,
  );

  const cspLine = headersText
    .split(/\r?\n/)
    .find((line) => /Content-Security-Policy:/i.test(line));
  assert.ok(cspLine, "Content-Security-Policy line missing");
  assert.match(cspLine, /frame-ancestors 'none'/);
  assert.match(cspLine, /https:\/\/cdn\.paddle\.com/);
  assert.match(cspLine, /https:\/\/sandbox-cdn\.paddle\.com/);
  assert.match(cspLine, /https:\/\/sandbox-api\.paddle\.com/);
  assert.match(cspLine, /https:\/\/sandbox-buy\.paddle\.com/);
  assert.match(cspLine, /https:\/\/sandbox-checkout\.paddle\.com/);
  assert.doesNotMatch(cspLine, /https:\/\/api\.paddle\.com/);
  assert.doesNotMatch(cspLine, /https:\/\/buy\.paddle\.com/);
  assert.doesNotMatch(cspLine, /https:\/\/checkout\.paddle\.com(?!-)/);
  assert.doesNotMatch(cspLine, /\*/);
  assert.doesNotMatch(cspLine, /unsafe-eval/);

  assert.doesNotMatch(headersText, /PADDLE_SANDBOX_API_KEY/);
  assert.doesNotMatch(headersText, /SUPABASE_SERVICE_ROLE_KEY/);
  assert.doesNotMatch(headersText, /eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]+\./);
  assert.doesNotMatch(headersText, /test_[a-zA-Z0-9]{27}/);
}

test("src/_headers exists with required Cloudflare security policy", () => {
  const headersPath = path.join(BILLING_WEB, "src", "_headers");
  assert.ok(fs.existsSync(headersPath), "billing_web/src/_headers missing");
  assertCloudflareHeadersPolicy(read(headersPath));
});

test("production build copies _headers to dist/_headers", () => {
  withTempRoot((root) => {
    const result = build({
      root,
      env: { PADDLE_SANDBOX_CLIENT_TOKEN: VALID_TOKEN },
    });
    const distHeaders = path.join(result.dist, "_headers");
    assert.ok(fs.existsSync(distHeaders), "dist/_headers missing after production build");
    assertCloudflareHeadersPolicy(read(distHeaders));
  });
});

test("dev build copies _headers to dist/_headers", () => {
  withTempRoot((root) => {
    const result = build({ root, dev: true, env: {} });
    const distHeaders = path.join(result.dist, "_headers");
    assert.ok(fs.existsSync(distHeaders), "dist/_headers missing after dev build");
    assertCloudflareHeadersPolicy(read(distHeaders));
  });
});

test("source and docs do not contain forbidden secret assignments", () => {
  const roots = [
    path.join(BILLING_WEB, "src"),
    path.join(BILLING_WEB, "scripts", "build.mjs"),
    path.join(BILLING_WEB, "README.md"),
  ];
  const checkFile = (full) => {
    const text = read(full);
    assert.doesNotMatch(text, /PADDLE_SANDBOX_API_KEY\s*=/);
    assert.doesNotMatch(text, /SUPABASE_SERVICE_ROLE_KEY\s*=/);
    assert.doesNotMatch(text, /eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]+\./);
  };
  const walk = (dir) => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (entry.isFile()) checkFile(full);
    }
  };
  for (const root of roots) {
    if (fs.statSync(root).isDirectory()) walk(root);
    else checkFile(root);
  }
});

test("buildRuntimeConfigSource exposes only expected public fields", () => {
  const src = buildRuntimeConfigSource({
    checkoutEnabled: true,
    token: VALID_TOKEN,
  });
  assert.match(src, /checkoutEnabled/);
  assert.match(src, /paddleSandboxClientToken/);
  assert.doesNotMatch(src, /apiKey/i);
  assert.doesNotMatch(src, /serviceRole/i);
});

test("repo gitignore covers billing_web/dist", () => {
  const gi = read(path.join(REPO_ROOT, ".gitignore"));
  assert.match(gi, /billing_web\/dist\//);
});

// Keep import used for potential dynamic checks on Windows path URLs.
void pathToFileURL;
