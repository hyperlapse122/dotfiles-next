import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as net from "node:net";
import * as os from "node:os";
import * as path from "node:path";
import { describe, test } from "node:test";

import { MXMaster4HapticPlugin } from "../src/index.ts";

// `sendCommand` resolves the daemon socket from XDG_RUNTIME_DIR at call time and
// flushes "<WAVEFORM>\n" to it, so a real Unix-socket server under a temp
// XDG_RUNTIME_DIR captures exactly what the plugin sent — no module mocking. The
// resolver and the listening socket are both POSIX-only (Windows uses a fixed
// named pipe and ignores XDG_RUNTIME_DIR), so the suite skips on win32.
const posixOnly =
  process.platform === "win32"
    ? { skip: "POSIX socket path; Windows uses a fixed named pipe" }
    : {};

type SocketLike = {
  end: () => void;
  on: {
    (event: "end", listener: () => void): void;
    (event: "data", listener: (chunk: string | Uint8Array) => void): void;
  };
  setEncoding: (encoding: "utf8") => void;
};

type HapticServer = {
  received: string[];
  connections: number;
  cleanup: () => Promise<void>;
};

// Stand up a daemon-shaped server on $XDG_RUNTIME_DIR/mxm4-haptic.sock that
// records each fully-received message (it ends its side on the client's
// half-close, which is what lets `sendCommand` resolve on flush).
async function startHapticServer(): Promise<HapticServer> {
  const originalXdg = process.env.XDG_RUNTIME_DIR;
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "mxm4-plugin-"));
  const socketPath = path.join(dir, "mxm4-haptic.sock");
  process.env.XDG_RUNTIME_DIR = dir;

  const received: string[] = [];
  let connections = 0;
  const server = net.createServer((socket: SocketLike) => {
    connections += 1;
    const chunks: string[] = [];
    socket.setEncoding("utf8");
    socket.on("data", (chunk) => chunks.push(String(chunk)));
    socket.on("end", () => {
      received.push(chunks.join(""));
      socket.end();
    });
  });

  await new Promise<void>((resolve) => server.listen(socketPath, resolve));

  return {
    received,
    get connections() {
      return connections;
    },
    async cleanup() {
      await new Promise<void>((resolve) => server.close(() => resolve()));
      restoreXdg(originalXdg);
      fs.rmSync(socketPath, { force: true });
      fs.rmSync(dir, { force: true, recursive: true });
    },
  };
}

// A runtime dir with NO server listening — exercises the daemon-absent path.
function startEmptyRuntimeDir(): { cleanup: () => void } {
  const originalXdg = process.env.XDG_RUNTIME_DIR;
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "mxm4-plugin-empty-"));
  process.env.XDG_RUNTIME_DIR = dir;
  return {
    cleanup() {
      restoreXdg(originalXdg);
      fs.rmSync(dir, { force: true, recursive: true });
    },
  };
}

function restoreXdg(value: string | undefined): void {
  if (value === undefined) {
    delete process.env.XDG_RUNTIME_DIR;
    return;
  }
  process.env.XDG_RUNTIME_DIR = value;
}

// Let any pending socket I/O callbacks drain before asserting.
function tick(): Promise<void> {
  return new Promise((resolve) => setImmediate(resolve));
}

type SessionStatus = { type: string };

type FakeClientOptions = {
  // Controls `client.session.get` — resolves a value, returns an `{ error }`
  // envelope, or throws, exactly as the call site distinguishes them.
  get?: () => Promise<unknown>;
  children?: Array<{ id: string }>;
  statuses?: Record<string, SessionStatus>;
};

type LogEntry = { body: { service: string; level: string; message: string; extra: unknown } };

type FakeClient = {
  client: unknown;
  logs: LogEntry[];
};

// Build a structurally-typed stand-in for the OpenCode `client`, matching the
// call shapes the plugin uses: session.get / session.children / session.status
// and app.log.
function fakeClient(options: FakeClientOptions = {}): FakeClient {
  const logs: LogEntry[] = [];
  const get = options.get ?? (async () => ({ data: {} }));
  const children = options.children ?? [];
  const statuses = options.statuses ?? {};
  return {
    logs,
    client: {
      session: {
        get: () => get(),
        children: async () => ({ data: children }),
        status: async () => ({ data: statuses }),
      },
      app: {
        log: async (entry: LogEntry) => {
          logs.push(entry);
        },
      },
    },
  };
}

async function plugin(client: unknown) {
  return MXMaster4HapticPlugin({ client } as never);
}

function idleEvent(sessionID: string) {
  return { type: "session.idle", properties: { sessionID } };
}

function errorEvent(sessionID?: string) {
  return { type: "session.error", properties: sessionID ? { sessionID } : {} };
}

describe("MXMaster4HapticPlugin", posixOnly, () => {
  test("session.idle on a root session with no children buzzes COMPLETED", async () => {
    const server = await startHapticServer();
    const { client } = fakeClient({ get: async () => ({ data: {} }) });
    try {
      const hooks = await plugin(client);
      await hooks.event!({ event: idleEvent("root-1") } as never);
      await tick();
      assert.deepEqual(server.received, ["COMPLETED\n"]);
    } finally {
      await server.cleanup();
    }
  });

  test("session.idle on a child session (parentID) stays silent", async () => {
    const server = await startHapticServer();
    const { client } = fakeClient({ get: async () => ({ data: { parentID: "root-1" } }) });
    try {
      const hooks = await plugin(client);
      await hooks.event!({ event: idleEvent("child-1") } as never);
      await tick();
      assert.equal(server.connections, 0);
      assert.deepEqual(server.received, []);
    } finally {
      await server.cleanup();
    }
  });

  test("session.idle with a busy child stays silent — pins TODAY's drop-not-wait behavior", async () => {
    // NOTE: this deliberately characterizes the CURRENT behavior. When a child
    // session is still busy, the plugin drops the completion buzz outright
    // rather than deferring it until the child goes idle. If that is ever
    // changed to "wait and buzz later", THIS assertion should change with it.
    const server = await startHapticServer();
    const { client } = fakeClient({
      get: async () => ({ data: {} }),
      children: [{ id: "child-1" }],
      statuses: { "child-1": { type: "busy" } },
    });
    try {
      const hooks = await plugin(client);
      await hooks.event!({ event: idleEvent("root-1") } as never);
      await tick();
      assert.equal(server.connections, 0);
      assert.deepEqual(server.received, []);
    } finally {
      await server.cleanup();
    }
  });

  test("session.idle with a child that has no status entry buzzes COMPLETED (absent = idle)", async () => {
    const server = await startHapticServer();
    const { client } = fakeClient({
      get: async () => ({ data: {} }),
      children: [{ id: "child-1" }],
      statuses: {},
    });
    try {
      const hooks = await plugin(client);
      await hooks.event!({ event: idleEvent("root-1") } as never);
      await tick();
      assert.deepEqual(server.received, ["COMPLETED\n"]);
    } finally {
      await server.cleanup();
    }
  });

  test("session.get returning an { error } envelope still buzzes and logs a warning", async () => {
    const server = await startHapticServer();
    const { client, logs } = fakeClient({ get: async () => ({ error: { message: "boom" } }) });
    try {
      const hooks = await plugin(client);
      await hooks.event!({ event: idleEvent("root-1") } as never);
      await tick();
      assert.deepEqual(server.received, ["COMPLETED\n"]);
      assert.equal(logs.length, 1);
      assert.equal(logs[0]?.body.level, "warn");
    } finally {
      await server.cleanup();
    }
  });

  test("session.get throwing still buzzes COMPLETED (bias toward buzzing)", async () => {
    const server = await startHapticServer();
    const { client } = fakeClient({
      get: async () => {
        throw new Error("network down");
      },
    });
    try {
      const hooks = await plugin(client);
      await hooks.event!({ event: idleEvent("root-1") } as never);
      await tick();
      assert.deepEqual(server.received, ["COMPLETED\n"]);
    } finally {
      await server.cleanup();
    }
  });

  test("session.error on a child session stays silent", async () => {
    const server = await startHapticServer();
    const { client } = fakeClient({ get: async () => ({ data: { parentID: "root-1" } }) });
    try {
      const hooks = await plugin(client);
      await hooks.event!({ event: errorEvent("child-1") } as never);
      await tick();
      assert.equal(server.connections, 0);
      assert.deepEqual(server.received, []);
    } finally {
      await server.cleanup();
    }
  });

  test("session.error on a root session buzzes MAD", async () => {
    const server = await startHapticServer();
    const { client } = fakeClient({ get: async () => ({ data: {} }) });
    try {
      const hooks = await plugin(client);
      await hooks.event!({ event: errorEvent("root-1") } as never);
      await tick();
      assert.deepEqual(server.received, ["MAD\n"]);
    } finally {
      await server.cleanup();
    }
  });

  test("session.error with no sessionID buzzes MAD (can't resolve → bias toward buzzing)", async () => {
    const server = await startHapticServer();
    // get should never be consulted when sessionID is absent.
    const { client } = fakeClient({
      get: async () => {
        throw new Error("session.get must not be called");
      },
    });
    try {
      const hooks = await plugin(client);
      await hooks.event!({ event: errorEvent() } as never);
      await tick();
      assert.deepEqual(server.received, ["MAD\n"]);
    } finally {
      await server.cleanup();
    }
  });

  test("permission.updated buzzes RINGING", async () => {
    const server = await startHapticServer();
    const { client } = fakeClient();
    try {
      const hooks = await plugin(client);
      await hooks.event!({ event: { type: "permission.updated", properties: {} } } as never);
      await tick();
      assert.deepEqual(server.received, ["RINGING\n"]);
    } finally {
      await server.cleanup();
    }
  });

  test("tool.execute.before for the Question tool buzzes RINGING (case-insensitive)", async () => {
    const server = await startHapticServer();
    const { client } = fakeClient();
    try {
      const hooks = await plugin(client);
      await hooks["tool.execute.before"]!({ tool: "Question" } as never, {} as never);
      await tick();
      assert.deepEqual(server.received, ["RINGING\n"]);
    } finally {
      await server.cleanup();
    }
  });

  test("tool.execute.before for a non-question tool stays silent", async () => {
    const server = await startHapticServer();
    const { client } = fakeClient();
    try {
      const hooks = await plugin(client);
      await hooks["tool.execute.before"]!({ tool: "bash" } as never, {} as never);
      await tick();
      assert.equal(server.connections, 0);
      assert.deepEqual(server.received, []);
    } finally {
      await server.cleanup();
    }
  });

  test("daemon socket absent — the event hook resolves and logs a skipped pulse", async () => {
    const runtime = startEmptyRuntimeDir();
    const { client, logs } = fakeClient({ get: async () => ({ data: {} }) });
    try {
      const hooks = await plugin(client);
      await hooks.event!({ event: idleEvent("root-1") } as never);
      assert.ok(
        logs.some(
          (log) =>
            log.body.level === "warn" && log.body.message === "haptic pulse COMPLETED skipped",
        ),
      );
    } finally {
      runtime.cleanup();
    }
  });

  test("daemon socket absent — the question hook resolves and logs a skipped pulse", async () => {
    const runtime = startEmptyRuntimeDir();
    const { client, logs } = fakeClient();
    try {
      const hooks = await plugin(client);
      await hooks["tool.execute.before"]!({ tool: "Question" } as never, {} as never);
      assert.equal(logs.length, 1);
      assert.equal(logs[0]?.body.level, "warn");
      assert.equal(logs[0]?.body.message, "haptic pulse RINGING skipped");
    } finally {
      runtime.cleanup();
    }
  });
});
