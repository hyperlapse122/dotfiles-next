import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { describe, test } from 'node:test';

import {
  applyAssignment,
  applyManagedBlock,
  findHeaderLines,
  parseManaged,
  parseHeaderLine,
  serializeToml,
} from './configure-codex-config.mjs';

const repoRoot = path.resolve(import.meta.dirname, '../..');
const scriptPath = path.join(repoRoot, 'scripts/bootstrap/configure-codex-config.mjs');

function runScript(args = [], env = {}) {
  return spawnSync('bun', [scriptPath, ...args], {
    cwd: repoRoot,
    env: { ...process.env, ...env },
    encoding: 'utf8',
  });
}

function runInline(source) {
  return spawnSync('bun', ['--eval', source], {
    cwd: repoRoot,
    encoding: 'utf8',
  });
}

describe('configure-codex-config helpers', () => {
  test('applyAssignment inserts and updates root scalars', () => {
    assert.equal(applyAssignment('', '', 'model', '"gpt-5.5"'), 'model = "gpt-5.5"\n');
    assert.equal(
      applyAssignment('model = "old"\n', '', 'model', '"gpt-5.5"'),
      'model = "gpt-5.5"\n',
    );
  });

  test('applyAssignment inserts root keys before the first real table header', () => {
    const input = 'matrix = [\n  [1, 2],\n]\n[projects."/tmp/example"]\ntrust_level = "trusted"\n';
    const output = applyAssignment(input, '', 'model', '"gpt-5.5"');
    assert.equal(
      output,
      'matrix = [\n  [1, 2],\n]\nmodel = "gpt-5.5"\n[projects."/tmp/example"]\ntrust_level = "trusted"\n',
    );
  });

  test('applyAssignment edits existing tables and appends missing tables', () => {
    assert.equal(
      applyAssignment('[tools]\nfoo = false\n', 'tools', 'bar', 'true'),
      '[tools]\nfoo = false\nbar = true\n',
    );
    assert.equal(
      applyAssignment('model = "gpt"\n', 'tools', 'web_search', 'true'),
      'model = "gpt"\n\n[tools]\nweb_search = true\n',
    );
  });

  test('applyManagedBlock appends and replaces the sentinel block idempotently', () => {
    const first = applyManagedBlock('model = "gpt"\n', '[[hooks.Stop]]\ncommand = "mxm4"');
    assert.match(first, /# >>> managed by configure-codex-config/);
    assert.equal(applyManagedBlock(first, '[[hooks.Stop]]\ncommand = "mxm4"'), first);
    assert.equal(
      applyManagedBlock(first, '[[hooks.Stop]]\ncommand = "other"').includes('command = "other"'),
      true,
    );
  });

  test('serializeToml emits canonical hooks-shaped array-of-tables', () => {
    assert.equal(
      serializeToml({
        hooks: {
          Stop: [{ hooks: [{ command: 'mxm4-haptic COMPLETED' }] }],
        },
      }),
      '[[hooks.Stop]]\n\n[[hooks.Stop.hooks]]\ncommand = "mxm4-haptic COMPLETED"',
    );
  });

  test('parseManaged splits scalars from array-of-tables block', () => {
    const parsed = parseManaged('model = "gpt-5.5"\n[tools]\nweb_search = true\n[[hooks.Stop]]\n[[hooks.Stop.hooks]]\ncommand = "mxm4"\n');
    assert.deepEqual(parsed.scalars, [
      { table: '', key: 'model', value: '"gpt-5.5"' },
      { table: 'tools', key: 'web_search', value: 'true' },
    ]);
    assert.equal(parsed.block, '[[hooks.Stop]]\n\n[[hooks.Stop.hooks]]\ncommand = "mxm4"');
  });

  test('findHeaderLines only accepts complete TOML table boundaries', () => {
    const headers = findHeaderLines('matrix = [\n  [1, 2],\n]\n[tools] # ok\nname = "[not a header]"\n[[hooks.Stop]]\n');
    assert.deepEqual(headers.map((header) => header.name), ['tools', null]);
    assert.deepEqual(parseHeaderLine('  [1, 2],'), { accepted: false, name: null });
  });
});

describe('configure-codex-config failure paths', () => {
  test('applyAssignment aborts on ambiguous multi-line existing values', () => {
    const child = runInline(
      `import { applyAssignment } from './scripts/bootstrap/configure-codex-config.mjs';\n` +
      `applyAssignment('model = [\\n  "old",\\n]\\n', '', 'model', '"new"');`,
    );
    assert.notEqual(child.status, 0);
    assert.match(child.stderr, /existing value is multi-line\/ambiguous/);
  });

  test('applyManagedBlock aborts on a missing end marker', () => {
    const child = runInline(
      `import { applyManagedBlock } from './scripts/bootstrap/configure-codex-config.mjs';\n` +
      `applyManagedBlock('# >>> managed by configure-codex-config (codex/codex-config.managed.toml) - do not edit below >>>\\n', 'body');`,
    );
    assert.notEqual(child.status, 0);
    assert.match(child.stderr, /without a matching end marker/);
  });

  test('parseManaged refuses the machine-local projects table', () => {
    const child = runInline(
      `import { parseManaged } from './scripts/bootstrap/configure-codex-config.mjs';\n` +
      `parseManaged('[projects]\\nfoo = "bar"\\n');`,
    );
    assert.notEqual(child.status, 0);
    assert.match(child.stderr, /refusing to manage/);
  });
});

describe('configure-codex-config CLI writes', () => {
  test('fresh config is owner-only', () => {
    const codexHome = mkdtempSync(path.join(os.tmpdir(), 'codex-config-test-'));
    try {
      const result = runScript([], { CODEX_HOME: codexHome });
      assert.equal(result.status, 0, result.stderr);
      const mode = statSync(path.join(codexHome, 'config.toml')).mode & 0o777;
      assert.equal(mode, process.platform === 'win32' ? mode : 0o600);
    } finally {
      rmSync(codexHome, { recursive: true, force: true });
    }
  });

  test('backup is owner-only while existing config mode is preserved', () => {
    if (process.platform === 'win32') return;
    const codexHome = mkdtempSync(path.join(os.tmpdir(), 'codex-config-test-'));
    const configPath = path.join(codexHome, 'config.toml');
    try {
      writeFileSync(configPath, 'model = "old"\n', { mode: 0o644 });
      const result = runScript([], { CODEX_HOME: codexHome });
      assert.equal(result.status, 0, result.stderr);
      assert.equal(statSync(configPath).mode & 0o777, 0o644);
      assert.equal(statSync(`${configPath}.bak`).mode & 0o777, 0o600);
      assert.equal(readFileSync(`${configPath}.bak`, 'utf8'), 'model = "old"\n');
    } finally {
      rmSync(codexHome, { recursive: true, force: true });
    }
  });
});
