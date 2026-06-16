#!/usr/bin/env bun
// scripts/bootstrap/configure-codex-config.mjs
//
// Merges the repo-tracked, shared OpenAI Codex settings in
// `codex-config.managed.toml` INTO the machine-local Codex config
// (`$CODEX_HOME/config.toml`, default `~/.codex/config.toml`) without
// disturbing machine-local state — most importantly the per-project trust
// table `[projects."<path>"]` that Codex writes back into that same file.
//
// Codex has no `include`/import directive and writes trust decisions into the
// user config.toml itself, so the file cannot be a dotbot symlink. This script
// is the alternative: it applies ONLY the keys declared in the managed file and
// preserves every other byte of the live config.
//
// RUNS ON BUN (not Node): the managed file is parsed with Bun's built-in
// `Bun.TOML.parse` — a full TOML parser, so the managed file may use any TOML
// syntax (array-of-tables like `[[hooks.Stop.hooks]]`, nested tables, inline
// arrays), not the old hand-rolled "simple TOML" subset. Bun parses TOML but
// has no serializer, and we deliberately do NOT re-serialize the whole live
// file (it is sensitive — it sits next to auth.json, and a full rewrite would
// drop comments and could reshuffle the machine-local `[projects]` table). So
// the merge stays surgical, with two complementary strategies:
//   * SCALAR keys (root scalars and scalar keys under plain `[table]` headers):
//     targeted, TOML-safe edits — update a key in place when it already exists,
//     or insert it (root keys before the first table header; sub-table keys
//     after the table header; a brand-new table appended at EOF). If updating a
//     key would require touching a multi-line value it cannot safely reason
//     about, it ABORTS without writing rather than risk corrupting the file.
//   * COMPLEX content (any subtree containing an array-of-tables, e.g. the
//     `hooks` lifecycle config): serialized to canonical TOML and written as a
//     single sentinel-delimited block (see BLOCK_BEGIN/BLOCK_END), replaced in
//     place on re-run or appended at EOF the first time. Array-of-tables are
//     self-delimiting and valid at EOF after the scalar/`[projects]` content,
//     which sidesteps TOML's "root keys must precede every table header" rule.
//
// Usage: configure-codex-config.mjs [--check] [--print] [--no-backup]
//   --check       Exit 1 if the live config would change; write nothing.
//   --print       Print the would-be result to stdout; write nothing.
//   --no-backup   Do not write a <config>.bak before changing the live file.
//   -h, --help    Show this help.

import { readFileSync, writeFileSync, chmodSync, mkdirSync, existsSync } from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, '../..');
const managedPath = path.join(repoRoot, 'codex', 'codex-config.managed.toml');

const codexHome =
  process.env.CODEX_HOME && process.env.CODEX_HOME.trim() !== ''
    ? process.env.CODEX_HOME
    : path.join(os.homedir(), '.codex');
const configPath = path.join(codexHome, 'config.toml');

// Sentinel markers that fence the managed "complex" block (array-of-tables and
// anything else that can't be expressed as a single `key = value` line) inside
// the live config. Kept ASCII and stable so the block is found and replaced
// byte-for-byte on every re-run.
const BLOCK_BEGIN =
  '# >>> managed by configure-codex-config (codex/codex-config.managed.toml) - do not edit below >>>';
const BLOCK_END = '# <<< managed by configure-codex-config <<<';
const OWNER_ONLY_DIR = 0o700;
const OWNER_ONLY_FILE = 0o600;
const isUnix = process.platform !== 'win32';

function main() {
  const args = new Set(process.argv.slice(2));

  if (args.has('--help') || args.has('-h')) {
    process.stdout.write(
      [
        'Usage: configure-codex-config.mjs [--check] [--print] [--no-backup]',
        '',
        `Applies the shared settings in ${path.relative(process.cwd(), managedPath)}`,
        `into the machine-local Codex config ${configPath}, preserving machine-local`,
        'state such as the [projects] trust table.',
        '',
        'Options:',
        '  --check       Exit 1 if the live config would change; write nothing.',
        '  --print       Print the would-be result to stdout; write nothing.',
        '  --no-backup   Do not write a <config>.bak before changing the live file.',
        '  -h, --help    Show this help.',
        '',
      ].join('\n'),
    );
    process.exit(0);
  }

  const knownFlags = new Set(['--check', '--print', '--no-backup']);
  const unknown = [...args].filter((a) => !knownFlags.has(a));
  if (unknown.length > 0) {
    fail(`unknown argument(s): ${unknown.join(', ')}`);
  }

  const checkOnly = args.has('--check');
  const printOnly = args.has('--print');
  const noBackup = args.has('--no-backup');

  if (!existsSync(managedPath)) {
    fail(`managed settings file not found: ${managedPath}`);
  }

  const { scalars, block } = parseManaged(readFileSync(managedPath, 'utf8'));

  const configExisted = existsSync(configPath);
  const original = configExisted ? readFileSync(configPath, 'utf8') : '';

  let result = original;
  for (const { table, key, value } of scalars) {
    result = applyAssignment(result, table, key, value);
  }
  if (block !== null) {
    result = applyManagedBlock(result, block);
  }

  if (printOnly) {
    process.stdout.write(result);
    process.exit(0);
  }

  if (result === original) {
    if (scalars.length === 0 && block === null) {
      log('no managed settings declared; nothing to do.');
    } else {
      log('config already up to date; no changes needed.');
    }
    process.exit(0);
  }

  if (checkOnly) {
    fail(
      `config is out of date. Run scripts/bootstrap/configure-codex-config.sh (or .ps1) to apply ${path.relative(
        process.cwd(),
        managedPath,
      )}.`,
    );
  }

  if (!existsSync(codexHome)) {
    mkdirSync(codexHome, { recursive: true, mode: OWNER_ONLY_DIR });
  }
  if (configExisted && !noBackup) {
    const backupPath = `${configPath}.bak`;
    writeFileSync(backupPath, original, { mode: OWNER_ONLY_FILE });
    if (isUnix) chmodSync(backupPath, OWNER_ONLY_FILE);
  }
  writeFileSync(configPath, result, configExisted ? undefined : { mode: OWNER_ONLY_FILE });
  // Preserve a user's explicit mode choice for existing configs; only make a
  // first-run create owner-only, and always harden the full backup copy above.
  if (isUnix && !configExisted) chmodSync(configPath, OWNER_ONLY_FILE);
  log(`${configExisted ? 'updated' : 'created'} ${configPath}.`);
  process.exit(0);
}

if (import.meta.main) {
  main();
}

// --------------------------------------------------------------------------
// Managed-file parsing (full TOML via Bun) + partitioning.
// --------------------------------------------------------------------------

/**
 * @typedef {{ table: string, key: string, value: string }} ScalarAssignment
 */

/**
 * Parse the managed settings file with Bun's TOML parser, reject the
 * machine-local `[projects]` namespace, and split the result into:
 *   - `scalars`: flat `{ table, key, value }` records for primitives and
 *     primitive arrays (applied with targeted edits).
 *   - `block`: canonical TOML text for every top-level subtree that contains an
 *     array-of-tables (applied as one sentinel-delimited block), or null when
 *     there is none.
 * @param {string} text
 * @returns {{ scalars: ScalarAssignment[], block: string | null }}
 */
export function parseManaged(text) {
  let parsed;
  try {
    parsed = Bun.TOML.parse(text);
  } catch (err) {
    fail(`could not parse managed settings as TOML: ${err instanceof Error ? err.message : err}`);
  }
  if (!isPlainObject(parsed)) {
    fail('managed settings did not parse to a table.');
  }
  if (Object.prototype.hasOwnProperty.call(parsed, 'projects')) {
    fail('refusing to manage the machine-local [projects] table.');
  }

  /** @type {ScalarAssignment[]} */
  const scalars = [];
  /** @type {Record<string, unknown>} */
  const blockObject = {};

  for (const [key, value] of Object.entries(parsed)) {
    if (containsArrayOfTables(value)) {
      blockObject[key] = value;
    } else {
      flattenScalars(value, [key], scalars);
    }
  }

  const block = Object.keys(blockObject).length > 0 ? serializeToml(blockObject) : null;
  return { scalars, block };
}

/**
 * Flatten a primitive, primitive array, or array-of-tables-free plain object
 * into `{ table, key, value }` scalar assignments. `pathSegments` is the dotted
 * path to `value`; its last element is the key and the rest form the table.
 * @param {unknown} value
 * @param {string[]} pathSegments
 * @param {ScalarAssignment[]} out
 */
export function flattenScalars(value, pathSegments, out) {
  if (isScalar(value)) {
    const key = pathSegments[pathSegments.length - 1];
    const table = pathSegments.slice(0, -1).join('.');
    out.push({ table, key, value: serializeValue(value) });
    return;
  }
  if (isPlainObject(value)) {
    // TOML requires a table's own scalar keys before any nested table header.
    for (const [k, v] of Object.entries(value)) {
      if (isScalar(v)) {
        out.push({ table: pathSegments.join('.'), key: k, value: serializeValue(v) });
      }
    }
    for (const [k, v] of Object.entries(value)) {
      if (isPlainObject(v)) {
        flattenScalars(v, [...pathSegments, k], out);
      }
    }
    return;
  }
  // Unreachable: array-of-tables subtrees are routed to the block instead.
  fail(`internal: cannot flatten non-scalar value at ${pathSegments.join('.')}`);
}

// --------------------------------------------------------------------------
// Minimal TOML serializer (only what the managed file can contain: scalars,
// primitive arrays, nested tables, and arrays-of-tables).
// --------------------------------------------------------------------------

/**
 * Serialize a plain object to canonical TOML text.
 * @param {Record<string, unknown>} obj
 * @returns {string}
 */
export function serializeToml(obj) {
  /** @type {string[]} */
  const lines = [];
  emitTable(obj, [], lines);
  // Drop the leading blank line emitted before the first table header.
  return lines.join('\n').replace(/^\n+/, '').trimEnd();
}

/**
 * Emit `obj`'s body — direct scalar keys first, then nested tables, then
 * arrays-of-tables — appending to `lines`. Intermediate tables with no direct
 * scalar keys emit no header (e.g. `[hooks]` / `[hooks.Stop]` are elided when
 * only `[[hooks.Stop.hooks]]` carries data).
 * @param {Record<string, unknown>} obj
 * @param {string[]} pathSegments
 * @param {string[]} lines
 */
export function emitTable(obj, pathSegments, lines) {
  const entries = Object.entries(obj);

  for (const [k, v] of entries) {
    if (isScalar(v)) {
      lines.push(`${formatKey(k)} = ${serializeValue(v)}`);
    }
  }
  for (const [k, v] of entries) {
    if (isPlainObject(v)) {
      const childPath = [...pathSegments, k];
      if (Object.values(v).some(isScalar)) {
        lines.push('', `[${formatPath(childPath)}]`);
      }
      emitTable(v, childPath, lines);
    }
  }
  for (const [k, v] of entries) {
    if (isArrayOfTables(v)) {
      const childPath = [...pathSegments, k];
      for (const element of v) {
        lines.push('', `[[${formatPath(childPath)}]]`);
        emitTable(element, childPath, lines);
      }
    }
  }
}

/**
 * Serialize a primitive or primitive array to its single-line TOML form.
 * @param {unknown} value
 * @returns {string}
 */
export function serializeValue(value) {
  if (typeof value === 'string') {
    return tomlBasicString(value);
  }
  if (typeof value === 'boolean') {
    return value ? 'true' : 'false';
  }
  if (typeof value === 'number') {
    if (!Number.isFinite(value)) {
      fail(`cannot serialize non-finite number: ${value}`);
    }
    return String(value);
  }
  if (typeof value === 'bigint') {
    return value.toString();
  }
  if (Array.isArray(value)) {
    return `[${value.map((v) => serializeValue(v)).join(', ')}]`;
  }
  fail(`cannot serialize value of type ${typeof value} as a single-line TOML value.`);
}

/**
 * Quote a string as a TOML basic string with the required escapes.
 * @param {string} s
 * @returns {string}
 */
export function tomlBasicString(s) {
  let out = '"';
  for (const ch of s) {
    const code = ch.codePointAt(0) ?? 0;
    if (ch === '\\') out += '\\\\';
    else if (ch === '"') out += '\\"';
    else if (ch === '\n') out += '\\n';
    else if (ch === '\t') out += '\\t';
    else if (ch === '\r') out += '\\r';
    else if (ch === '\b') out += '\\b';
    else if (ch === '\f') out += '\\f';
    else if (code < 0x20 || code === 0x7f) out += `\\u${code.toString(16).padStart(4, '0')}`;
    else out += ch;
  }
  return `${out}"`;
}

/**
 * Render one path segment as a bare key when safe, else a quoted key.
 * @param {string} key
 * @returns {string}
 */
export function formatKey(key) {
  return /^[A-Za-z0-9_-]+$/.test(key) ? key : tomlBasicString(key);
}

/**
 * Render a dotted table path, quoting each segment as needed.
 * @param {string[]} segments
 * @returns {string}
 */
export function formatPath(segments) {
  return segments.map(formatKey).join('.');
}

// --------------------------------------------------------------------------
// Value-shape predicates.
// --------------------------------------------------------------------------

/** @param {unknown} v @returns {boolean} */
export function isPlainObject(v) {
  return typeof v === 'object' && v !== null && !Array.isArray(v);
}

/** @param {unknown} v @returns {boolean} */
export function isScalar(v) {
  if (
    typeof v === 'string' ||
    typeof v === 'boolean' ||
    typeof v === 'number' ||
    typeof v === 'bigint'
  ) {
    return true;
  }
  if (Array.isArray(v)) {
    return v.every(isScalar);
  }
  return false;
}

/** @param {unknown} v @returns {boolean} */
export function isArrayOfTables(v) {
  return Array.isArray(v) && v.length > 0 && v.every(isPlainObject);
}

/**
 * Does `v`, anywhere in its subtree, hold an array-of-tables? Such subtrees
 * cannot be expressed as single-line assignments and go to the block instead.
 * @param {unknown} v
 * @returns {boolean}
 */
export function containsArrayOfTables(v) {
  if (isArrayOfTables(v)) {
    return true;
  }
  if (Array.isArray(v)) {
    return v.some(containsArrayOfTables);
  }
  if (isPlainObject(v)) {
    return Object.values(v).some(containsArrayOfTables);
  }
  return false;
}

// --------------------------------------------------------------------------
// Sentinel-block editing of the live config.
// --------------------------------------------------------------------------

/**
 * Replace the managed block in `text` (between BLOCK_BEGIN/BLOCK_END) with
 * `body`, or append a fresh block at EOF when no markers are present.
 * @param {string} text
 * @param {string} body
 * @returns {string}
 */
export function applyManagedBlock(text, body) {
  const fenced = `${BLOCK_BEGIN}\n${body}\n${BLOCK_END}\n`;

  const beginIdx = text.indexOf(BLOCK_BEGIN);
  if (beginIdx !== -1) {
    const endIdx = text.indexOf(BLOCK_END, beginIdx);
    if (endIdx === -1) {
      fail(`found ${BLOCK_BEGIN} without a matching end marker in ${configPath}; resolve by hand.`);
    }
    const nl = text.indexOf('\n', endIdx);
    const replaceEnd = nl === -1 ? text.length : nl + 1;
    return `${text.slice(0, beginIdx)}${fenced}${text.slice(replaceEnd)}`;
  }

  let prefix = text;
  if (prefix !== '' && !prefix.endsWith('\n')) {
    prefix += '\n';
  }
  const sep = prefix === '' || prefix.endsWith('\n\n') ? '' : '\n';
  return `${prefix}${sep}${fenced}`;
}

// --------------------------------------------------------------------------
// Targeted, TOML-safe editing of the live config (scalar keys).
// --------------------------------------------------------------------------

/**
 * Ensure `<key> = <value>` exists under `table` ('' = root) in `text`,
 * updating in place when present and inserting safely otherwise.
 * @param {string} text
 * @param {string} table
 * @param {string} key
 * @param {string} value
 * @returns {string}
 */
export function applyAssignment(text, table, key, value) {
  const line = `${key} = ${value}`;
  const region = findTableRegion(text, table);

  if (region === null) {
    // Named table absent: append a fresh, well-formed table block at EOF.
    // (The root table always resolves to a region, so `table` is non-empty here.)
    let prefix = text;
    if (prefix !== '' && !prefix.endsWith('\n')) {
      prefix += '\n';
    }
    const sep = prefix === '' || prefix.endsWith('\n\n') ? '' : '\n';
    return `${prefix}${sep}[${table}]\n${line}\n`;
  }

  const existing = findKeyInRegion(text, region, key);
  if (existing) {
    if (!isSingleLineValue(text.slice(existing.valueStart, existing.lineEnd).trim())) {
      fail(
        `refusing to overwrite '${key}'${
          table ? ` in [${table}]` : ''
        }: existing value is multi-line/ambiguous in ${configPath}. ` +
          'Resolve it by hand, then re-run.',
      );
    }
    return `${text.slice(0, existing.lineStart)}${line}${text.slice(existing.lineEnd)}`;
  }

  // Key absent in an existing table region: insert at the end of the region so
  // declaration order is preserved. For the root table this lands just before
  // the first table header (or EOF); for a named table, just before the next
  // header (or EOF). Inserting at a region boundary keeps root keys ahead of
  // every table header, which is what TOML requires.
  const insertAt = region.end;
  const needsLeadingNl = insertAt > 0 && text[insertAt - 1] !== '\n';
  const insertion = `${needsLeadingNl ? '\n' : ''}${line}\n`;
  return `${text.slice(0, insertAt)}${insertion}${text.slice(insertAt)}`;
}

/**
 * Locate the byte region of `table` in `text`.
 * For the root table ('') returns { start: 0, headerEnd: 0, end } where end is
 * the start of the first table header (or text length). For a named table,
 * returns the body between its header and the next header (or EOF), with
 * `headerEnd` pointing just past the header line. Returns null if not found.
 * @param {string} text
 * @param {string} table
 * @returns {{ start: number, headerEnd: number, end: number } | null}
 */
export function findTableRegion(text, table) {
  const headers = findHeaderLines(text);
  if (table === '') {
    const end = headers.length > 0 ? headers[0].start : text.length;
    return { start: 0, headerEnd: 0, end };
  }
  for (let i = 0; i < headers.length; i += 1) {
    if (headers[i].name === table) {
      const end = i + 1 < headers.length ? headers[i + 1].start : text.length;
      return { start: headers[i].end, headerEnd: headers[i].end, end };
    }
  }
  return null;
}

/**
 * Find every table/array-of-tables header line. `name` is the standard table
 * name, or null for array-of-tables headers (which only act as boundaries).
 * @param {string} text
 * @returns {{ start: number, end: number, name: string | null }[]}
 */
export function findHeaderLines(text) {
  /** @type {{ start: number, end: number, name: string | null }[]} */
  const headers = [];
  let offset = 0;
  for (const raw of text.split('\n')) {
    const start = offset;
    const end = offset + raw.length + 1; // include the trailing '\n'
    offset = end;
    const header = parseHeaderLine(raw.trim());
    if (header.accepted) {
      headers.push({ start, end, name: header.name });
    }
  }
  return headers;
}

/**
 * Return the inside-bracket name of a standard `[table]` header, or null for
 * anything else (array-of-tables `[[x]]`, malformed, etc.).
 * @param {string} line
 * @returns {string | null}
 */
export function parseTableHeader(line) {
  const m = /^\[([^[\]]+)\]$/.exec(line);
  return m ? m[1].trim() : null;
}

/**
 * Return a parsed TOML table boundary if `line` is a complete standard table or
 * array-of-tables header. Array-of-tables boundaries have no scalar-editable
 * table name, so they return `name: null`.
 * @param {string} line
 * @returns {{ accepted: boolean, name: string | null }}
 */
export function parseHeaderLine(line) {
  const table = /^\[([^\[\]]+)\](?:\s+#.*)?$/.exec(line);
  if (table) {
    return { accepted: true, name: table[1].trim() };
  }
  if (/^\[\[([^\[\]]+)\]\](?:\s+#.*)?$/.test(line)) {
    return { accepted: true, name: null };
  }
  return { accepted: false, name: null };
}

/**
 * Find an assignment for `key` within a region. Returns line/value offsets, or
 * null. Matches the key as the first token before `=` on a non-comment line.
 * @param {string} text
 * @param {{ start: number, end: number }} region
 * @param {string} key
 * @returns {{ lineStart: number, lineEnd: number, valueStart: number } | null}
 */
export function findKeyInRegion(text, region, key) {
  let offset = region.start;
  const slice = text.slice(region.start, region.end);
  for (const raw of slice.split('\n')) {
    const lineStart = offset;
    const lineEnd = offset + raw.length; // excludes '\n'
    offset = lineEnd + 1;
    const trimmed = raw.trim();
    if (trimmed === '' || trimmed.startsWith('#')) {
      continue;
    }
    const eq = raw.indexOf('=');
    if (eq === -1) {
      continue;
    }
    if (raw.slice(0, eq).trim() === key) {
      return { lineStart, lineEnd, valueStart: lineStart + eq + 1 };
    }
  }
  return null;
}

/**
 * Heuristic: is `value` a complete single-line TOML value (balanced quotes,
 * brackets and braces, not opening a multi-line string)? Used to refuse
 * overwriting an ambiguous existing value in the live config.
 * @param {string} value
 * @returns {boolean}
 */
export function isSingleLineValue(value) {
  if (value.includes('"""') || value.includes("'''")) {
    return false;
  }
  let inBasic = false; // "..."
  let inLiteral = false; // '...'
  let escaped = false;
  let square = 0;
  let curly = 0;
  for (const ch of value) {
    if (inBasic) {
      if (escaped) escaped = false;
      else if (ch === '\\') escaped = true;
      else if (ch === '"') inBasic = false;
      continue;
    }
    if (inLiteral) {
      if (ch === "'") inLiteral = false;
      continue;
    }
    if (ch === '#') break; // start of a comment: rest is not value
    if (ch === '"') inBasic = true;
    else if (ch === "'") inLiteral = true;
    else if (ch === '[') square += 1;
    else if (ch === ']') square -= 1;
    else if (ch === '{') curly += 1;
    else if (ch === '}') curly -= 1;
    if (square < 0 || curly < 0) return false;
  }
  return !inBasic && !inLiteral && square === 0 && curly === 0;
}

/**
 * @param {string} message
 * @returns {never}
 */
function fail(message) {
  process.stderr.write(`configure-codex-config: ${message}\n`);
  process.exit(1);
}

/** @param {string} message */
function log(message) {
  process.stdout.write(`configure-codex-config: ${message}\n`);
}
