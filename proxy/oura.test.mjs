// Offline checks for the Oura OAuth endpoints in worker.js. Oura's token endpoint is
// mocked; nothing touches the network. Usage (from the proxy folder): node oura.test.mjs
import { pathToFileURL, fileURLToPath } from "node:url";
import path from "node:path";
import fs from "node:fs";
import os from "node:os";

const src = path.join(path.dirname(fileURLToPath(import.meta.url)), "worker.js");
const tmp = path.join(os.tmpdir(), "tonnage-worker-oura-under-test.mjs");
fs.copyFileSync(src, tmp);
const worker = (await import(pathToFileURL(tmp).href)).default;

let mode = "ok";
const sent = [];
globalThis.fetch = async (url, init) => {
  sent.push({ url, init, form: new URLSearchParams(init.body) });
  switch (mode) {
    case "ok": return new Response(JSON.stringify({ access_token: "at", refresh_token: "rt2", expires_in: 86400,
      token_type: "bearer", scope: "daily personal", extra: "drop me" }), { status: 200, headers: { "content-type": "application/json" } });
    case "invalid_grant": return new Response(JSON.stringify({ error: "invalid_grant", error_description: "secret detail" }), { status: 400 });
    case "500": return new Response("oops internal", { status: 500 });
    case "throw": throw new TypeError("ECONNREFUSED");
  }
};

function makeKV() {
  const m = new Map();
  return { async get(k) { return m.get(k) ?? null; }, async put(k, v) { m.set(k, v); } };
}
const ORIGIN = "https://tonnage-coach.example.workers.dev";
const env = (extra = {}) => ({ APP_TOKEN: "t", OURA_CLIENT_ID: "cid", OURA_CLIENT_SECRET: "csecret",
  ANTHROPIC_API_KEY: "k", QUOTA: makeKV(), ...extra });
const post = (p, body, headers = {}) => new Request(ORIGIN + p, { method: "POST",
  headers: { "content-type": "application/json", "x-app-token": "t", ...headers },
  body: typeof body === "string" ? body : JSON.stringify(body) });

const results = [];
async function check(name, request, e, expect) {
  sent.length = 0;
  const res = await worker.fetch(request, e);
  const text = await res.text();
  let body = null; try { body = JSON.parse(text); } catch {}
  const ok = expect({ status: res.status, body, text, headers: res.headers, upstream: sent[0] });
  results.push({ name, ok, detail: `status=${res.status} ${text.slice(0, 100)}` });
}

// Callback
await check("callback bounces code + state to the app", new Request(ORIGIN + "/oura/callback?code=abc123&state=xyz&junk=1"), env(),
  (r) => r.status === 302 && r.headers.get("location") === "tonnage://oura?code=abc123&state=xyz");
await check("callback passes Oura's error through", new Request(ORIGIN + "/oura/callback?error=access_denied&state=xyz"), env(),
  (r) => r.status === 302 && r.headers.get("location") === "tonnage://oura?state=xyz&error=access_denied");
await check("callback with nothing → missing_code", new Request(ORIGIN + "/oura/callback"), env(),
  (r) => r.status === 302 && r.headers.get("location") === "tonnage://oura?error=missing_code");
await check("callback encodes hostile values", new Request(ORIGIN + "/oura/callback?code=a%26b%3Dc&state=%0Ax"), env(),
  (r) => r.status === 302 && !/[\n&]b=/.test(r.headers.get("location")) && r.headers.get("location").startsWith("tonnage://oura?code=a%26b%3Dc"));
await check("callback rejects POST", new Request(ORIGIN + "/oura/callback", { method: "POST" }), env(), (r) => r.status === 405);

// Token exchange
await check("token: exchanges the code with the secret and a fixed redirect URI", post("/oura/token", { code: "abc123", redirect_uri: "https://evil.example/cb" }), env(),
  (r) => r.status === 200 && r.upstream?.url === "https://api.ouraring.com/oauth/token"
    && r.upstream.form.get("grant_type") === "authorization_code" && r.upstream.form.get("code") === "abc123"
    && r.upstream.form.get("client_secret") === "csecret" && r.upstream.form.get("client_id") === "cid"
    && r.upstream.form.get("redirect_uri") === ORIGIN + "/oura/callback");
await check("token: response keeps only token fields and isn't cached", post("/oura/token", { code: "abc123" }), env(),
  (r) => r.body?.access_token === "at" && r.body.refresh_token === "rt2" && r.body.extra === undefined
    && !JSON.stringify(r.body).includes("csecret") && r.headers.get("cache-control") === "no-store");
await check("token: PKCE verifier is forwarded when sent", post("/oura/token", { code: "abc", code_verifier: "v-123_x.y~z" }), env(),
  (r) => r.upstream?.form.get("code_verifier") === "v-123_x.y~z");
await check("token: missing code → 400, no upstream call", post("/oura/token", {}), env(), (r) => r.status === 400 && !r.upstream);
await check("token: code with odd characters → 400", post("/oura/token", { code: "a b<script>" }), env(), (r) => r.status === 400 && !r.upstream);

// Refresh
await check("refresh: uses the refresh grant", post("/oura/refresh", { refresh_token: "rt1" }), env(),
  (r) => r.status === 200 && r.upstream?.form.get("grant_type") === "refresh_token" && r.upstream.form.get("refresh_token") === "rt1");
mode = "invalid_grant";
await check("refresh: rejected token → 401 reconnect, Oura's detail hidden", post("/oura/refresh", { refresh_token: "old" }), env(),
  (r) => r.status === 401 && r.body?.error?.code === "reconnect" && !r.text.includes("secret detail"));
mode = "500";
await check("refresh: Oura 500 → generic 502", post("/oura/refresh", { refresh_token: "rt1" }), env(),
  (r) => r.status === 502 && !r.text.includes("oops"));
mode = "throw";
await check("refresh: network failure → 502", post("/oura/refresh", { refresh_token: "rt1" }), env(), (r) => r.status === 502);
mode = "ok";

// Gatekeeping
await check("no app token → 401", post("/oura/token", { code: "abc" }, { "x-app-token": "" }), env(), (r) => r.status === 401 && !r.upstream);
await check("wrong app token → 401", post("/oura/token", { code: "abc" }, { "x-app-token": "nope" }), env(), (r) => r.status === 401);
await check("not configured → 500", post("/oura/token", { code: "abc" }), env({ OURA_CLIENT_SECRET: undefined }),
  (r) => r.status === 500 && r.body?.error?.message === "Oura not configured");
await check("text/plain → 415", post("/oura/token", '{"code":"abc"}', { "content-type": "text/plain" }), env(), (r) => r.status === 415);
await check("oversized body → 413", post("/oura/token", { code: "a".repeat(10_000) }), env(), (r) => r.status === 413);
await check("unknown Oura path → 404", post("/oura/whatever", {}), env(), (r) => r.status === 404);
await check("GET on token → 405", new Request(ORIGIN + "/oura/token"), env(), (r) => r.status === 405);
{
  const e = env({ RATE_LIMIT_PER_MINUTE: "2" });
  for (let i = 0; i < 2; i++) await worker.fetch(post("/oura/refresh", { refresh_token: "rt1" }), e);
  await check("burst limit applies", post("/oura/refresh", { refresh_token: "rt1" }), e, (r) => r.status === 429);
}
await check("Anthropic path still requires a POST to /", new Request(ORIGIN + "/"), env(), (r) => r.status === 405);

for (const r of results) console.log(`[${r.ok ? "PASS" : "FAIL"}] ${r.name}${r.ok ? "" : "  (" + r.detail + ")"}`);
console.log(`\n${results.filter((r) => r.ok).length}/${results.length} pass`);
process.exitCode = results.every((r) => r.ok) ? 0 : 1;
