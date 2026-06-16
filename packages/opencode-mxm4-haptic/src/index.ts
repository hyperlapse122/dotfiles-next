import type { Plugin, PluginInput, Hooks } from "@opencode-ai/plugin";
import { sendCommand, type WaveformName } from "@h82/mxm4-haptic";
import { match, P } from "ts-pattern";

type Client = PluginInput["client"];
type Event = Parameters<NonNullable<Hooks["event"]>>[0]["event"];

const serviceName = "mxm4-haptic" as const;

/**
 * Map of OpenCode event types to the waveform pulsed when they fire.
 *
 * `session.idle` and `session.error` are handled separately (they need
 * parent/child gating, see below), so they are intentionally absent here.
 */
const EVENT_WAVEFORMS: Partial<Record<Event["type"], WaveformName>> = {
  // The agent is waiting on you to decide (a permission / approval request) —
  // ring for attention, like a phone waiting to be answered.
  "permission.updated": "RINGING",
} as const;

/**
 * Tool names that present a blocking question for the user to decide. The
 * `Question` tool is registered (lowercased) as one of these by the agent
 * runtime; it does not emit `permission.updated`, so it is caught via the
 * `tool.execute.before` hook instead.
 */
const QUESTION_TOOLS = new Set(["question", "ask_user_question", "askuserquestion"]);

/**
 * A session spawned by another session (e.g. a sub-agent `task()` run) carries
 * a `parentID`. Root/top-level sessions do not.
 *
 * On any failure to resolve the session we assume it is a root session, so a
 * transient API hiccup biases toward still delivering the completion buzz
 * rather than silently dropping it.
 */
async function isChildSession(client: Client, sessionID: string): Promise<boolean> {
  try {
    return match(await client.session.get({ path: { id: sessionID } }))
      .with({ data: { parentID: P.string } }, () => true)
      .otherwise(async ({ error }) => {
        await client.app.log({
          body: {
            service: serviceName,
            level: "warn",
            message: `Failed to resolve session ${sessionID} to check if it's a child session — assuming it's a root session and buzzing accordingly.`,
            extra: { error },
          },
        });
        return false;
      });
  } catch {
    return false;
  }
}

/**
 * True when every child (sub-agent) session of `sessionID` is idle — i.e. no
 * sub-agent is still `busy` or retrying.
 *
 * A root session can briefly report idle while a sub-agent is still wrapping
 * up, so the completion buzz waits until everything underneath has gone idle
 * too. On any failure we assume all children are idle (bias toward buzzing).
 */
async function allChildrenIdle(client: Client, sessionID: string): Promise<boolean> {
  try {
    const [children, statuses] = await Promise.all([
      client.session.children({ path: { id: sessionID } }),
      client.session.status(),
    ]);
    const statusMap = statuses.data ?? {};
    for (const child of children.data ?? []) {
      const status = statusMap[child.id];
      // An absent status means the session is not actively running → idle.
      if (status && status.type !== "idle") return false;
    }
    return true;
  } catch {
    return true;
  }
}

async function pulse(client: Client, waveform: WaveformName): Promise<void> {
  try {
    await sendCommand(waveform);
  } catch (error) {
    await client.app
      .log({
        body: {
          service: serviceName,
          level: "warn",
          message: `haptic pulse ${waveform} skipped`,
          extra: { error },
        },
      })
      .catch(() => {});
  }
}

export const MXMaster4HapticPlugin: Plugin = async ({ client }: PluginInput) => {
  return {
    event: async ({ event }) => {
      await match(event)
        .with({ type: "session.idle" }, async (event) => {
          const { sessionID } = event.properties;
          // Sub-agent (child) sessions finishing shouldn't buzz — only the
          // top-level session's completion is worth a pulse.
          if (await isChildSession(client, sessionID)) return;
          // Only buzz once the root session AND all of its sub-agents are idle.
          if (!(await allChildrenIdle(client, sessionID))) return;
          await pulse(client, "COMPLETED");
        })
        .with({ type: "session.error" }, async (event) => {
          const { sessionID } = event.properties;
          // Sub-agent (child) errors shouldn't buzz — only the top-level
          // session's failure is worth a pulse. An absent sessionID can't be
          // resolved, so it biases toward still buzzing.
          if (sessionID && (await isChildSession(client, sessionID))) return;
          await pulse(client, "MAD");
        })
        .otherwise(async (event) => {
          if (event.type in EVENT_WAVEFORMS) {
            const waveform = EVENT_WAVEFORMS[event.type];
            if (waveform) await pulse(client, waveform);
          }
        });
    },
    "tool.execute.before": async ({ tool }) => {
      if (QUESTION_TOOLS.has(tool.toLowerCase())) await pulse(client, "RINGING");
    },
  };
};
