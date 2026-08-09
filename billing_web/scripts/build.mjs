/**
 * billing_web build — copies src -> dist and emits runtime-config.js.
 *
 * Production / Cloudflare:
 *   PADDLE_SANDBOX_CLIENT_TOKEN=test_... node scripts/build.mjs
 *
 * Local disabled-checkout placeholder:
 *   node scripts/build.mjs --dev
 *
 * Never accepts PADDLE_SANDBOX_API_KEY or SUPABASE_SERVICE_ROLE_KEY.
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const DEFAULT_ROOT = path.resolve(__dirname, "..");

const FORBIDDEN_ENV = [
  "PADDLE_SANDBOX_API_KEY",
  "SUPABASE_SERVICE_ROLE_KEY",
];

/** Exact Paddle sandbox client-side token (docs: ^(test|live)_[a-zA-Z0-9]{27}$). */
export const SANDBOX_CLIENT_TOKEN_RE = /^test_[a-zA-Z0-9]{27}$/;

export function validateSandboxClientToken(raw) {
  if (typeof raw !== "string") return false;
  // Reject whitespace by requiring exact equality with trim (no silent trim-accept).
  if (raw !== raw.trim()) return false;
  if (raw.startsWith("live_")) return false;
  return SANDBOX_CLIENT_TOKEN_RE.test(raw);
}

export function buildRuntimeConfigSource({ checkoutEnabled, token }) {
  const payload = {
    checkoutEnabled: Boolean(checkoutEnabled),
    paddleSandboxClientToken: checkoutEnabled && token ? token : null,
  };
  return (
    "/* generated - do not edit */\n" +
    "Object.defineProperty(window, \"AtlasBillingRuntime\", {\n" +
    "  value: Object.freeze(" +
    JSON.stringify(payload) +
    "),\n" +
    "  writable: false,\n" +
    "  configurable: false,\n" +
    "});\n"
  );
}

function assertInsideDist(distRoot, targetPath) {
  const resolved = path.resolve(targetPath);
  const distResolved = path.resolve(distRoot);
  const prefix = distResolved.endsWith(path.sep)
    ? distResolved
    : distResolved + path.sep;
  if (resolved !== distResolved && !resolved.startsWith(prefix)) {
    throw new Error(`Refusing write outside billing_web/dist: ${resolved}`);
  }
}

function rejectForbiddenEnv(env) {
  for (const key of FORBIDDEN_ENV) {
    if (env[key] !== undefined && String(env[key]).length > 0) {
      throw new Error(
        `${key} must never be supplied to billing_web build`,
      );
    }
  }
}

/**
 * Resolve a path and ensure it stays under an allowed root (canonical).
 * Uses realpath where the path exists; otherwise resolve + prefix check.
 */
function assertPathUnderRoot(rootCanonical, candidatePath, label) {
  const rootWithSep = rootCanonical.endsWith(path.sep)
    ? rootCanonical
    : rootCanonical + path.sep;
  let resolved;
  try {
    if (fs.existsSync(candidatePath)) {
      resolved = fs.realpathSync(candidatePath);
    } else {
      resolved = path.resolve(candidatePath);
    }
  } catch {
    throw new Error(`Unable to resolve ${label}`);
  }
  if (resolved !== rootCanonical && !resolved.startsWith(rootWithSep)) {
    throw new Error(`${label} escaped billing_web boundary`);
  }
  return resolved;
}

function removeDistSafely(distPath, rootCanonical) {
  if (!fs.existsSync(distPath)) return;

  let st;
  try {
    st = fs.lstatSync(distPath);
  } catch {
    throw new Error("Unable to lstat dist before cleanup");
  }

  if (st.isSymbolicLink()) {
    throw new Error(
      "Refusing to delete dist: path is a symbolic link (fail closed)",
    );
  }

  // Ensure the existing dist node resolves inside billing_web.
  assertPathUnderRoot(rootCanonical, distPath, "dist");

  const intended = path.join(rootCanonical, "dist");
  const intendedResolved = path.resolve(intended);
  if (path.resolve(distPath) !== intendedResolved) {
    throw new Error("Unexpected dist path; refusing cleanup");
  }

  fs.rmSync(distPath, { recursive: true, force: true });
}

function copyRecursive(fromDir, toDir, distRoot, srcRootCanonical) {
  assertInsideDist(distRoot, toDir);
  fs.mkdirSync(toDir, { recursive: true });

  for (const entry of fs.readdirSync(fromDir, { withFileTypes: true })) {
    const srcPath = path.join(fromDir, entry.name);
    const destPath = path.join(toDir, entry.name);

    let srcStat;
    try {
      srcStat = fs.lstatSync(srcPath);
    } catch {
      throw new Error(`Unable to lstat source entry: ${entry.name}`);
    }

    if (srcStat.isSymbolicLink()) {
      throw new Error(
        `Refusing to copy source symlink (fail closed): ${entry.name}`,
      );
    }

    // Keep every copied source path under canonical src.
    assertPathUnderRoot(srcRootCanonical, srcPath, "source entry");

    if (srcStat.isDirectory()) {
      copyRecursive(srcPath, destPath, distRoot, srcRootCanonical);
    } else if (srcStat.isFile()) {
      assertInsideDist(distRoot, destPath);
      fs.copyFileSync(srcPath, destPath);
    } else {
      throw new Error(`Unsupported source entry type: ${entry.name}`);
    }
  }
}

/**
 * @param {{ dev?: boolean, env?: NodeJS.ProcessEnv, root?: string }} [opts]
 */
export function build(opts = {}) {
  const dev = Boolean(opts.dev);
  const env = opts.env ?? process.env;
  const root = opts.root ?? DEFAULT_ROOT;

  rejectForbiddenEnv(env);

  const rootResolved = path.resolve(root);
  let rootCanonical;
  try {
    rootCanonical = fs.realpathSync(rootResolved);
  } catch {
    throw new Error("Unable to resolve billing_web root");
  }

  const src = path.join(rootCanonical, "src");
  const dist = path.join(rootCanonical, "dist");

  if (!fs.existsSync(src)) {
    throw new Error(`Missing source directory: ${src}`);
  }

  let srcCanonical;
  try {
    const srcStat = fs.lstatSync(src);
    if (srcStat.isSymbolicLink()) {
      throw new Error("Refusing build: src is a symbolic link (fail closed)");
    }
    srcCanonical = fs.realpathSync(src);
  } catch (err) {
    if (err instanceof Error && /symbolic link/.test(err.message)) throw err;
    throw new Error("Unable to resolve billing_web/src");
  }

  assertPathUnderRoot(rootCanonical, srcCanonical, "src");

  // dist must be exactly root/dist
  const distResolved = path.resolve(dist);
  if (distResolved !== path.join(rootCanonical, "dist")) {
    throw new Error("dist path escaped billing_web root");
  }

  removeDistSafely(dist, rootCanonical);

  fs.mkdirSync(dist, { recursive: true });
  assertInsideDist(dist, dist);

  copyRecursive(srcCanonical, dist, dist, srcCanonical);

  let checkoutEnabled = false;
  let token = null;

  if (dev) {
    checkoutEnabled = false;
    token = null;
  } else {
    const raw = env.PADDLE_SANDBOX_CLIENT_TOKEN;
    if (raw === undefined || raw === null || String(raw) === "") {
      throw new Error(
        "PADDLE_SANDBOX_CLIENT_TOKEN is required for production billing_web build",
      );
    }
    if (typeof raw !== "string") {
      throw new Error("PADDLE_SANDBOX_CLIENT_TOKEN must be a string");
    }
    if (!validateSandboxClientToken(raw)) {
      throw new Error(
        "PADDLE_SANDBOX_CLIENT_TOKEN must exactly match sandbox client-token format",
      );
    }
    checkoutEnabled = true;
    token = raw;
  }

  const runtimePath = path.join(dist, "assets", "runtime-config.js");
  assertInsideDist(dist, runtimePath);
  fs.mkdirSync(path.dirname(runtimePath), { recursive: true });
  fs.writeFileSync(
    runtimePath,
    buildRuntimeConfigSource({ checkoutEnabled, token }),
    "utf8",
  );

  return { dist, checkoutEnabled, runtimePath };
}

function isMain() {
  const entry = process.argv[1];
  if (!entry) return false;
  return path.resolve(entry) === path.resolve(__filename);
}

if (isMain()) {
  try {
    const dev = process.argv.slice(2).includes("--dev");
    const result = build({ dev });
    console.log(
      `billing_web build ok (checkoutEnabled=${result.checkoutEnabled})`,
    );
  } catch (err) {
    console.error(err instanceof Error ? err.message : String(err));
    process.exit(1);
  }
}
