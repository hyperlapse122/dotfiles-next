#!/usr/bin/env bun
// scripts/bootstrap/adopt-agent-of-empires-config.mjs
//
// Capture ("adopt") the live agent-of-empires config INTO the repo BEFORE
// dotbot re-links it.
//
// ~/.config/agent-of-empires/config.toml is a dotbot-managed symlink into
// home/.config/agent-of-empires/config.toml (linked by the ~/.config/**/* glob
// in install.linux.yaml). agent-of-empires saves its settings by writing a temp
// file and renaming it over the path — an atomic save that REPLACES the managed
// symlink with a brand-new REAL FILE holding the tool's latest config. On the
// next bootstrap, dotbot's `force: true` relink would delete that real file and
// recreate the symlink pointing at the OLD repo content, silently dropping the
// tool's changes.
//
// This script runs from install.linux.yaml BEFORE the relink (its `shell:` step
// is intentionally placed ahead of the `- link:` block): when the live path is
// a real file (the tool clobbered the symlink) its content is copied into the
// repo source so the following relink preserves it; when the live path is still
// the managed symlink, this is a no-op. You then commit the resulting repo
// change. It is the live->repo counterpart of configure-codex-config.mjs
// (which pushes repo->live).
//
// It runs through mise-managed Bun for consistency with the other bootstrap
// helpers; the logic itself is plain `node:fs` and would run on Node too.
// Always exits 0 (a bootstrap helper must never break the run), except under
// --check.
//
// Usage: adopt-agent-of-empires-config.mjs [--check]
//   --check     Exit 1 if the repo source WOULD change; copy nothing.
//   -h, --help  Show this help.

import { readFileSync, writeFileSync, mkdirSync, existsSync, lstatSync } from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, '../..');
// Same relative path under $HOME and under the repo's home/ mirror.
const RELATIVE = path.join('.config', 'agent-of-empires', 'config.toml');
const livePath = path.join(os.homedir(), RELATIVE);
const repoSource = path.join(repoRoot, 'home', RELATIVE);

function tildify(p) {
  const home = os.homedir();
  return p.startsWith(home + path.sep) ? '~' + p.slice(home.length) : p;
}

function log(msg) {
  process.stdout.write(`adopt-agent-of-empires-config: ${msg}\n`);
}

function main() {
  const args = new Set(process.argv.slice(2));

  if (args.has('-h') || args.has('--help')) {
    process.stdout.write(
      [
        'Usage: adopt-agent-of-empires-config.mjs [--check]',
        '',
        'Copies the live agent-of-empires config into the repo BEFORE dotbot',
        'relinks it, but only when the tool has replaced the managed symlink',
        'with a real file. A no-op while the live path is still the symlink.',
        '',
        `  live: ${livePath}`,
        `  repo: ${repoSource}`,
        '',
        'Options:',
        '  --check     Exit 1 if the repo source WOULD change; copy nothing.',
        '  -h, --help  Show this help.',
        '',
      ].join('\n'),
    );
    process.exit(0);
  }

  const checkOnly = args.has('--check');

  // No live file at all -> nothing to adopt (agent-of-empires not installed, or
  // never run on this machine).
  if (!existsSync(livePath)) {
    log(`skip: no live config at ${tildify(livePath)}`);
    process.exit(0);
  }

  // lstat does NOT follow the link: a symlink is the managed steady state, so
  // there is nothing to adopt. Only a REAL FILE means the tool clobbered the
  // symlink and we must capture it before the relink replaces it again.
  const st = lstatSync(livePath);
  if (st.isSymbolicLink()) {
    log('skip: live config is the managed symlink (nothing to adopt)');
    process.exit(0);
  }
  if (!st.isFile()) {
    log('skip: live config is not a regular file');
    process.exit(0);
  }

  const liveBuf = readFileSync(livePath);
  const repoBuf = existsSync(repoSource) ? readFileSync(repoSource) : null;
  if (repoBuf !== null && liveBuf.equals(repoBuf)) {
    log('up to date: live real file already matches the repo source');
    process.exit(0);
  }

  if (checkOnly) {
    log('check: repo source WOULD be updated from the live real file');
    process.exit(1);
  }

  mkdirSync(path.dirname(repoSource), { recursive: true });
  writeFileSync(repoSource, liveBuf);
  log(`adopted: copied live real file into ${path.relative(repoRoot, repoSource)}`);
  log('  commit it; dotbot will now relink the live path back to this source');
  process.exit(0);
}

main();
