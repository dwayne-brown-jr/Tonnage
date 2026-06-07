# Tonnage Coach Proxy

A minimal [Cloudflare Worker](https://workers.cloudflare.com) that lets TestFlight testers
use the AI Coach **without the Anthropic key ever shipping in the app binary**.

- The real key lives only as a Worker **secret** (set via CLI, never in code or git).
- The Worker forwards Messages API requests to Anthropic and injects the key.
- It enforces a **per-device daily free-message quota** server-side (so it can't be
  bypassed by reinstalling the app) and returns the remaining count in `x-quota-remaining`.
- It caps the model + `max_tokens` to bound abuse of the public endpoint.

Users who enter **their own** Anthropic key in Settings bypass the proxy entirely — those
calls go straight to Anthropic on their own dime.

---

## ⚠️ First: rotate the old key

The previously-bundled key shipped in builds 7–13 and is compromised. In the
[Anthropic Console](https://console.anthropic.com/settings/keys):

1. **Revoke** the old key.
2. **Create a new key**, and set a **monthly spend limit** on it (Console → Limits). This
   is your real backstop against abuse — do not skip it.
3. Use the new key as the Worker secret below. It never goes in the app.

## Deploy (one time, ~5 minutes)

Prereqs: a free Cloudflare account and Node installed. All commands run from this `proxy/`
folder. (`npx wrangler …` works without a global install.)

```bash
cd proxy

# 1. Log in to Cloudflare
npx wrangler login

# 2. Create the KV namespace for the quota counters, then paste the printed id
#    into wrangler.toml ([[kv_namespaces]] id = "...").
npx wrangler kv namespace create QUOTA

# 3. Store the NEW Anthropic key as a secret (prompts for the value; not echoed/committed)
npx wrangler secret put ANTHROPIC_API_KEY

# 4. Deploy
npx wrangler deploy
```

`deploy` prints your Worker URL, e.g. `https://tonnage-coach.<your-subdomain>.workers.dev`.

## Point the app at it

In `Tonnage/Secrets.swift` (gitignored) set:

```swift
enum BundledSecrets {
    static let proxyBaseURL = "https://tonnage-coach.<your-subdomain>.workers.dev"
}
```

Rebuild + archive. Testers without their own key now reach the coach through the proxy; the
binary contains only this URL (not a secret).

> Ship order matters: **deploy the proxy first**, then ship the build. Until `proxyBaseURL`
> is set, shared-key testers will be asked to add their own key (the app degrades gracefully,
> it doesn't break).

## Rotating the key later

```bash
npx wrangler secret put ANTHROPIC_API_KEY   # paste the new value
```
No app update needed — the app never holds the key.

## Tuning the quota

- Per-device/day limit: edit `DAILY_LIMIT` in `wrangler.toml` and redeploy, or
  `npx wrangler deploy --var DAILY_LIMIT:50`.
- Counters live in KV under `quota:<deviceId>:<UTC-date>` and auto-expire after 2 days.

## How the app calls it

`POST <proxyBaseURL>` with the standard Anthropic Messages API JSON body and an
`x-device-id` header. The Worker adds `x-api-key` + `anthropic-version`, forwards to
`https://api.anthropic.com/v1/messages`, and relays the response plus `x-quota-remaining`.
Both text chat and the vision (photo body-scan) calls use this same endpoint.

## Optional hardening (later)

- Add an `APP_TOKEN` secret + check `x-app-token` to filter drive-by use of the public URL
  (still extractable from the binary, but rotatable without touching Anthropic).
- Add per-IP rate limiting (Cloudflare Rules / Turnstile) if abuse appears.
- The definitive cost ceiling is always the **Anthropic spend limit** on the key.

## Alternative hosts

The app only needs a URL that accepts the Messages API body and injects the key, so the
same ~70-line handler ports directly to a Vercel/Netlify function, Deno Deploy, Fly.io, or
a tiny Express server. Swap KV for that platform's store (Vercel KV, Upstash Redis, etc.).
