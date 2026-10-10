// Tonnage Coach proxy — a minimal Cloudflare Worker that holds the shared Anthropic key
// server-side so it never ships in the iOS app binary. It forwards Messages API requests
// to Anthropic, injecting the key, and enforces a daily free-message quota.
//
// Secrets/vars/bindings (set during deploy — see README.md):
//   ANTHROPIC_API_KEY  (secret)  the real key — `wrangler secret put ANTHROPIC_API_KEY`
//   APP_TOKEN          (secret)  shared token the app sends as `x-app-token`
//   DAILY_LIMIT        (var)     free messages per network per day (default 30)
//   RATE_LIMIT_PER_MINUTE (var)  burst cap per network (default 20)
//   QUOTA_DO           (Durable Object)  atomic counters — the production path
//   QUOTA              (KV)      fallback counters when QUOTA_DO isn't bound
//
// Every request is checked in this order: method, configuration, app token, content type,
// size, JSON shape, model/max_tokens/messages, per-network burst limit, daily quota. The
// forwarded body is rebuilt from an allowlist, and upstream failures map to a generic 502.

const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
// Model aliases the shared key may be used with. A pinned/dated id for one of these
// (e.g. "claude-haiku-4-5-20251001") is accepted too; the date suffix is the only thing
// allowed to differ, so this can't widen the set to another model. Opus is deliberately
// absent: the shared key is for the cheap model only. Users on their own key bypass the
// proxy and can use any model.
const ALLOWED_MODELS = ["claude-haiku-4-5"];
const DATE_SUFFIX = /^-\d{8}$/;
const MAX_TOKENS_CAP = 4096;
const MAX_BODY_BYTES = 1_000_000;
const MAX_MESSAGES = 40;
const DEFAULT_DAILY_LIMIT = 30;
const DEFAULT_RATE_PER_MINUTE = 20;
const DAY_MS = 86_400_000;

export default {
  async fetch(request, env) {
    if (request.method !== "POST") {
      return json({ error: { message: "Method not allowed" } }, 405);
    }
    if (!env.ANTHROPIC_API_KEY || !env.APP_TOKEN) {
      return json({ error: { message: "Proxy not configured" } }, 500);
    }
    if (!tokensMatch(request.headers.get("x-app-token"), env.APP_TOKEN)) {
      return json({ error: { message: "Unauthorized" } }, 401);
    }
    if (!(request.headers.get("content-type") || "").toLowerCase().includes("application/json")) {
      return json({ error: { message: "Content-Type must be application/json" } }, 415);
    }

    const declared = Number(request.headers.get("content-length"));
    if (Number.isFinite(declared) && declared > MAX_BODY_BYTES) {
      return json({ error: { message: "Request too large" } }, 413);
    }
    let raw;
    try {
      raw = await request.arrayBuffer();
    } catch {
      return json({ error: { message: "Bad request" } }, 400);
    }
    if (raw.byteLength > MAX_BODY_BYTES) {
      return json({ error: { message: "Request too large" } }, 413);
    }

    let parsed;
    try {
      parsed = JSON.parse(new TextDecoder().decode(raw));
    } catch {
      return json({ error: { message: "Bad request" } }, 400);
    }
    const checked = buildUpstreamBody(parsed);
    if (checked.error) {
      return json({ error: { message: checked.error } }, 400);
    }

    const network = networkKey(request);
    const now = Date.now();

    // Burst limit per network (not refunded — it limits attempts, not successes).
    const ratePerMinute = parseLimit(env.RATE_LIMIT_PER_MINUTE, DEFAULT_RATE_PER_MINUTE, DEFAULT_RATE_PER_MINUTE);
    const minute = Math.floor(now / 60_000);
    const rate = await consume(env, `rate:${network}:${minute}`, ratePerMinute, 120_000);
    if (!rate.allowed) {
      return json({ error: { message: "Too many requests — give it a minute, then try again." } }, 429,
        { "retry-after": "60" });
    }

    // Daily quota per network, counted BEFORE forwarding so concurrent requests can't all
    // slip under the limit. A failed upstream call is refunded below.
    // Unset → the default allowance. Set but unreadable → no shared messages (fail safe).
    const limit = parseLimit(env.DAILY_LIMIT, DEFAULT_DAILY_LIMIT, 0);
    const day = new Date(now).toISOString().slice(0, 10); // UTC YYYY-MM-DD
    const quotaKey = `quota:${network}:${day}`;
    const quota = await consume(env, quotaKey, limit, 2 * DAY_MS);
    if (!quota.allowed) {
      const message = limit > 0
        ? `You've used today's ${limit} free Coach messages on the shared key. ` +
          `Add your own Anthropic API key in Settings for unlimited chat — the free allowance resets tomorrow.`
        : "The shared Coach allowance isn't available right now. Add your own Anthropic API key in Settings to keep chatting.";
      return json({ error: { message } }, 429, { "x-quota-remaining": "0" });
    }

    let upstream;
    try {
      upstream = await fetch(ANTHROPIC_URL, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "anthropic-version": "2023-06-01",
          "x-api-key": env.ANTHROPIC_API_KEY,
        },
        body: JSON.stringify(checked.body),
      });
    } catch {
      const used = await refund(env, quotaKey);
      return json({ error: { message: "Upstream unavailable" } }, 502,
        { "x-quota-remaining": String(Math.max(0, limit - used)) });
    }

    if (!upstream.ok) {
      // Billing, key and rate-limit details stay server-side.
      const used = await refund(env, quotaKey);
      return json({ error: { message: "Upstream unavailable" } }, 502,
        { "x-quota-remaining": String(Math.max(0, limit - used)) });
    }

    const headers = new Headers();
    const type = upstream.headers.get("content-type");
    if (type) headers.set("content-type", type);
    headers.set("x-quota-remaining", String(Math.max(0, limit - quota.used)));
    return new Response(upstream.body, { status: upstream.status, headers });
  },
};

// MARK: - Request validation

/// The body we forward, rebuilt from an allowlist, or `{ error }` describing what's wrong.
export function buildUpstreamBody(body) {
  if (body === null || typeof body !== "object" || Array.isArray(body)) {
    return { error: "Bad request" };
  }
  if (!isAllowedModel(body.model)) {
    return { error: "Unsupported model" };
  }
  if (!Number.isInteger(body.max_tokens) || body.max_tokens < 1) {
    return { error: "max_tokens must be a positive integer" };
  }
  const messages = body.messages;
  if (!Array.isArray(messages) || messages.length === 0 || messages.length > MAX_MESSAGES) {
    return { error: `messages must be a list of 1 to ${MAX_MESSAGES} turns` };
  }
  for (const m of messages) {
    if (m === null || typeof m !== "object" || (m.role !== "user" && m.role !== "assistant")) {
      return { error: "Each message needs a user or assistant role" };
    }
    if (typeof m.content !== "string" && !Array.isArray(m.content)) {
      return { error: "Each message needs content" };
    }
  }
  if (body.system !== undefined && typeof body.system !== "string" && !Array.isArray(body.system)) {
    return { error: "system must be text" };
  }

  const out = {
    model: body.model,
    max_tokens: Math.min(body.max_tokens, MAX_TOKENS_CAP),
    messages: messages.map((m) => ({ role: m.role, content: m.content })),
  };
  if (body.system !== undefined) out.system = body.system;
  return { body: out };
}

/// True for an allowed model alias, or that alias pinned to a release date.
function isAllowedModel(model) {
  if (typeof model !== "string") return false;
  return ALLOWED_MODELS.some((allowed) => {
    if (model === allowed) return true;
    if (!model.startsWith(allowed)) return false;
    return DATE_SUFFIX.test(model.slice(allowed.length));
  });
}

/// Constant-time comparison so the token can't be guessed byte by byte from timing.
function tokensMatch(given, expected) {
  if (typeof given !== "string" || typeof expected !== "string") return false;
  const a = new TextEncoder().encode(given);
  const b = new TextEncoder().encode(expected);
  let diff = a.length ^ b.length;
  for (let i = 0; i < b.length; i++) diff |= (a[i] ?? 0) ^ b[i];
  return diff === 0;
}

/// A whole, non-negative number from a var: `whenUnset` if it isn't set, `whenInvalid` if
/// it's set to something that isn't one. A misconfigured value never means "unlimited".
function parseLimit(value, whenUnset, whenInvalid) {
  if (value === undefined || value === null || String(value).trim() === "") return whenUnset;
  const n = Number(value);
  return Number.isInteger(n) && n >= 0 ? n : whenInvalid;
}

/// Who the quota belongs to: the client's network, which a caller can't rotate the way it
/// can rotate a header. IPv4 by address; IPv6 by /64, since one device can hold many
/// addresses in its prefix.
function networkKey(request) {
  const ip = (request.headers.get("cf-connecting-ip") || "").trim();
  if (!ip) return "unknown";
  if (ip.includes(":")) {
    return ip.toLowerCase().split(":").slice(0, 4).join(":") + "::/64";
  }
  return ip;
}

// MARK: - Counters

/// Atomically adds one to `key` unless it's already at `limit`.
/// Returns `{ allowed, used }`, where `used` includes this request when allowed.
async function consume(env, key, limit, ttlMs) {
  if (env.QUOTA_DO) {
    return doCall(env, key, { op: "consume", limit, ttlMs });
  }
  return withLock(key, async () => {
    const used = parseInt((await env.QUOTA.get(key)) || "0", 10) || 0;
    if (used >= limit) return { allowed: false, used };
    await env.QUOTA.put(key, String(used + 1), { expirationTtl: Math.ceil(ttlMs / 1000) });
    return { allowed: true, used: used + 1 };
  });
}

/// Gives back one unit after a failed upstream call. Returns the new count.
async function refund(env, key) {
  if (env.QUOTA_DO) {
    return (await doCall(env, key, { op: "refund" })).used;
  }
  return withLock(key, async () => {
    const used = Math.max(0, (parseInt((await env.QUOTA.get(key)) || "0", 10) || 0) - 1);
    await env.QUOTA.put(key, String(used), { expirationTtl: 2 * 86_400 });
    return used;
  });
}

async function doCall(env, key, payload) {
  const stub = env.QUOTA_DO.get(env.QUOTA_DO.idFromName(key));
  const res = await stub.fetch("https://quota/", { method: "POST", body: JSON.stringify(payload) });
  return res.json();
}

/// KV has no atomic increment. Without the Durable Object this serializes counter updates
/// within one isolate — enough for local runs, NOT a guarantee across Cloudflare's
/// isolates. Bind QUOTA_DO in production.
const locks = new Map();
function withLock(key, fn) {
  const prev = locks.get(key) || Promise.resolve();
  const run = prev.then(fn, fn);
  const tail = run.catch(() => {});
  locks.set(key, tail);
  tail.then(() => { if (locks.get(key) === tail) locks.delete(key); });
  return run;
}

/// One counter per key. A Durable Object handles one event at a time and storage calls
/// can't interleave, so check-and-increment is atomic across every isolate and colo.
export class QuotaCounter {
  constructor(state) {
    this.state = state;
  }

  async fetch(request) {
    const { op, limit, ttlMs } = await request.json();
    const storage = this.state.storage;
    const used = (await storage.get("used")) || 0;
    if (op === "refund") {
      const next = Math.max(0, used - 1);
      await storage.put("used", next);
      return Response.json({ used: next });
    }
    if (used >= limit) {
      return Response.json({ allowed: false, used });
    }
    await storage.put("used", used + 1);
    if ((await storage.getAlarm()) === null) {
      await storage.setAlarm(Date.now() + (ttlMs || 2 * DAY_MS));
    }
    return Response.json({ allowed: true, used: used + 1 });
  }

  /// The counter's window is over — drop it.
  async alarm() {
    await this.state.storage.deleteAll();
  }
}

function json(obj, status, extraHeaders = {}) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "content-type": "application/json", ...extraHeaders },
  });
}
