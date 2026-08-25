// Packages the built extension into a store-ready zip.
//
// Run via `npm run package`, which builds first, then invokes this script. It
// stages only what the manifest references — no src/, node_modules/, or signing
// keys — into a stable unpacked/ directory for local browser loading and
// artifacts/cuttings-extension-<version>.zip for store upload.
//
// The staged manifest drops the `key` field: it pins a stable extension ID for
// local unpacked development, but the Chrome Web Store manages signing itself
// and rejects any upload that carries `key`. The source manifest.json keeps it.

import { execFileSync } from "node:child_process";
import { cpSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");

// Everything the packaged extension loads at runtime. Anything not listed here
// (src/, node_modules/, package files, *.pem) stays out of the zip.
const CONTENTS = ["manifest.json", "dist", "icons", "popup.html", "options.html", "install.html"];

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

// Keep one stable, clean path that Dia/Chrome can load once and retain across
// rebuilds. Its manifest keeps `key`, which pins the development extension ID
// expected by the native-host manifest.
const unpackedDir = join(root, "unpacked");
rmSync(unpackedDir, { recursive: true, force: true });
mkdirSync(unpackedDir, { recursive: true });
for (const entry of CONTENTS) {
  cpSync(join(root, entry), join(unpackedDir, entry), { recursive: true });
}

// Stage the unpacked files so stores receive a manifest without `key` while
// the local development copy retains its stable extension ID.
const stageDir = join(outDir, "stage");
rmSync(stageDir, { recursive: true, force: true });
mkdirSync(stageDir, { recursive: true });
for (const entry of CONTENTS) {
  cpSync(join(unpackedDir, entry), join(stageDir, entry), { recursive: true });
}

delete manifest.key; // rejected by the Chrome Web Store; only used for local dev
writeFileSync(join(stageDir, "manifest.json"), JSON.stringify(manifest, null, 2) + "\n");

const outFile = join(outDir, `cuttings-extension-${version}.zip`);
rmSync(outFile, { force: true }); // a stale zip would be merged into, not replaced

// -r recurse, -X drop extra file attributes, -x skip cruft. Run from the stage
// dir so paths inside the zip are relative to the manifest.
execFileSync("zip", ["-r", "-X", outFile, ...CONTENTS, "-x", "*.DS_Store"], {
  cwd: stageDir,
  stdio: "inherit",
});

rmSync(stageDir, { recursive: true, force: true });

console.log(`\n✓ Unpacked v${version} → ${unpackedDir}`);
console.log(`✓ Packaged v${version} → ${outFile}`);
