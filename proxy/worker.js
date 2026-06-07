// Tonnage Coach proxy — a minimal Cloudflare Worker that holds the shared Anthropic key
// server-side so it never ships in the iOS app binary. It forwards Messages API requests
// to Anthropic, injecting the key, and enforces a per-device daily free-message quota.
//
// Secrets/vars (set during deploy — see README.md):
//   ANTHROPIC_API_KEY  (secret)  the real key — `wrangler secret put ANTHROPIC_API_KEY`
//   DAILY_LIMIT        (var)     free messages per device per day (default 30)
//   QUOTA              (KV)      namespace binding for the per-device counters

const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
const ALLOWED_MODELS = new Set(["claude-haiku-4-5", "claude-opus-4-8"]);
const MAX_TOKENS_CAP = 4096;

export default {
  async fetch(request, env) {
    if (request.method !== "POST") {
      return json({ error: { message: "Method not allowed" } }, 405);
    }
    if (!env.ANTHROPIC_API_KEY) {
      return json({ error: { message: "Proxy not configured" } }, 500);
    }

    const deviceId = (request.headers.get("x-device-id") || "anon").slice(0, 128);
    const limit = parseInt(env.DAILY_LIMIT || "30", 10);

    // Validate the body — this endpoint is reachable by anyone who finds the URL, so cap
    // the model + token budget to bound abuse (the real backstop is your Anthropic spend cap).
    let body;
    try {
      body = await request.json();
    } catch {
      return json({ error: { message: "Bad request" } }, 400);
    }
    if (!ALLOWED_MODELS.has(body?.model)) {
      return json({ error: { message: "Unsupported model" } }, 400);
    }
    if (typeof body.max_tokens === "number") {
      body.max_tokens = Math.min(body.max_tokens, MAX_TOKENS_CAP);
    }

    // Per-device daily quota (KV). Keys auto-expire after 2 days.
    const day = new Date().toISOString().slice(0, 10); // UTC YYYY-MM-DD
    const quotaKey = `quota:${deviceId}:${day}`;
    const used = parseInt((await env.QUOTA.get(quotaKey)) || "0", 10);
    if (used >= limit) {
      return json(
        {
          error: {
            message:
              `You've used today's ${limit} free Coach messages on the shared key. ` +
              `Add your own Anthropic API key in Settings for unlimited chat — the free allowance resets tomorrow.`,
          },
        },
        429,
        { "x-quota-remaining": "0" }
      );
    }

    // Forward to Anthropic with the server-held key.
    let upstream;
    try {
      upstream = await fetch(ANTHROPIC_URL, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "anthropic-version": "2023-06-01",
          "x-api-key": env.ANTHROPIC_API_KEY,
        },
        body: JSON.stringify(body),
      });
    } catch {
      return json({ error: { message: "Upstream unreachable" } }, 502);
    }

    // Count only successful calls against the allowance.
    let remaining = limit - used;
    if (upstream.ok) {
      const newUsed = used + 1;
      remaining = Math.max(0, limit - newUsed);
      await env.QUOTA.put(quotaKey, String(newUsed), { expirationTtl: 172800 });
    }

    const headers = new Headers(upstream.headers);
    headers.set("x-quota-remaining", String(remaining));
    return new Response(upstream.body, { status: upstream.status, headers });
  },
};

function json(obj, status, extraHeaders = {}) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "content-type": "application/json", ...extraHeaders },
  });
}
