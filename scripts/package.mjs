// Packages the built extension into a store-ready zip.
//
// Run via `npm run package`, which builds first, then invokes this script. It
// zips only what the manifest references — no src/, node_modules/, or signing
// keys — into artifacts/readcontrol-extension-<version>.zip, ready to upload to
// the Chrome Web Store, Edge Add-ons, or AMO.

import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, rmSync } from "node:fs";
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

const { version } = JSON.parse(
  readFileSync(join(root, "manifest.json"), "utf8"),
);

const outDir = join(root, "artifacts");
mkdirSync(outDir, { recursive: true });

const outFile = join(outDir, `readcontrol-extension-${version}.zip`);
rmSync(outFile, { force: true }); // a stale zip would be merged into, not replaced

// -r recurse, -X drop extra file attributes, -x skip cruft. Run from the
// extension root so paths inside the zip are relative to the manifest.
execFileSync("zip", ["-r", "-X", outFile, ...CONTENTS, "-x", "*.DS_Store"], {
  cwd: root,
  stdio: "inherit",
});

console.log(`\n✓ Packaged v${version} → ${outFile}`);
