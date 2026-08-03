// Packages the built extension into a store-ready zip.
//
// Run via `npm run package`, which builds first, then invokes this script. It
// stages only what the manifest references — no src/, node_modules/, or signing
// keys — into artifacts/readcontrol-extension-<version>.zip, ready to upload to
// the Chrome Web Store, Edge Add-ons, or AMO.
//
// The staged manifest drops the `key` field: it pins a stable extension ID for
// local unpacked development, but the Chrome Web Store manages signing itself
// and rejects any upload that carries `key`. The source manifest.json keeps it.

import { execFileSync } from "node:child_process";
import {
  cpSync,
  existsSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");

// Everything the packaged extension loads at runtime. Anything not listed here
// (src/, node_modules/, package files, *.pem) stays out of the zip.
const CONTENTS = [
  "manifest.json",
  "dist",
  "icons",
  "options.html",
  "install.html",
];

function fail(message) {
  console.error(`✗ ${message}`);
  process.exit(1);
}

// `zip` ships with macOS but not every environment; fail with a clear hint.
try {
  execFileSync("zip", ["--version"], { stdio: "ignore" });
} catch {
  fail(
    "`zip` was not found on PATH. It is preinstalled on macOS; on Debian/Ubuntu run `sudo apt-get install zip`.",
  );
}

const missing = CONTENTS.filter((entry) => !existsSync(join(root, entry)));
if (missing.length > 0) {
  fail(
    `missing build output: ${missing.join(", ")}. Run \`npm run build\` first (\`npm run package\` does this for you).`,
  );
}

const manifest = JSON.parse(readFileSync(join(root, "manifest.json"), "utf8"));
const { version } = manifest;

const outDir = join(root, "artifacts");
mkdirSync(outDir, { recursive: true });

// Stage the shipped files so we can hand the store a manifest without `key`
// while leaving the source manifest untouched.
const stageDir = join(outDir, "stage");
rmSync(stageDir, { recursive: true, force: true });
mkdirSync(stageDir, { recursive: true });
for (const entry of CONTENTS) {
  cpSync(join(root, entry), join(stageDir, entry), { recursive: true });
}

delete manifest.key; // rejected by the Chrome Web Store; only used for local dev
writeFileSync(
  join(stageDir, "manifest.json"),
  JSON.stringify(manifest, null, 2) + "\n",
);

const outFile = join(outDir, `readcontrol-extension-${version}.zip`);
rmSync(outFile, { force: true }); // a stale zip would be merged into, not replaced

// -r recurse, -X drop extra file attributes, -x skip cruft. Run from the stage
// dir so paths inside the zip are relative to the manifest.
execFileSync("zip", ["-r", "-X", outFile, ...CONTENTS, "-x", "*.DS_Store"], {
  cwd: stageDir,
  stdio: "inherit",
});

rmSync(stageDir, { recursive: true, force: true });

console.log(`\n✓ Packaged v${version} → ${outFile}`);
