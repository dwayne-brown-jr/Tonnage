// Offline pen-test harness for proxy/worker.js. Never touches the network:
// global fetch is mocked, KV is an in-memory Map, the clock is controllable.
// Usage (from the proxy folder): node proxy.test.mjs
// Written during the October 2026 independent audit. 23 of 37 passed at the time;
// each FAIL line names the gap. Some FAILs are strict judgment calls (e.g. text/plain
// content type, missing max_tokens), see the audit write-up for which ones matter.
//
// Fixture update (audit fixes, Oct 2026): the worker now requires an app token, so the
// env carries APP_TOKEN and every request sends it unless a test overrides the header.
// A header given as `undefined` is omitted rather than sent as the string "undefined".
// Three quota assertions now expect 429 (see the comment above them).
import { pathToFileURL, fileURLToPath } from "node:url";
import path from "node:path";
import fs from "node:fs";
import os from "node:os";

let workerPath = path.resolve(process.argv[2] || path.join(path.dirname(fileURLToPath(import.meta.url)), "worker.js"));
if (workerPath.endsWith(".js")) {
  // worker.js is an ES module but package.json has no "type": "module", so load a .mjs copy.
  const tmp = path.join(os.tmpdir(), "tonnage-worker-under-test.mjs");
  fs.copyFileSync(workerPath, tmp);
  workerPath = tmp;
}
const worker = (await import(pathToFileURL(workerPath).href)).default;

// ---- controllable clock (for day rollover) ----
const RealDate = Date;
let nowOffsetMs = 0;
globalThis.Date = class extends RealDate {
  constructor(...a) { a.length ? super(...a) : super(RealDate.now() + nowOffsetMs); }
  static now() { return RealDate.now() + nowOffsetMs; }
};

// ---- in-memory KV ----
function makeKV() {
  const m = new Map();
  return { _m: m,
    async get(k) { return m.has(k) ? m.get(k).v : null; },
    async put(k, v, o) { m.set(k, { v, o }); } };
}

// ---- mocked upstream ----
let upstreamMode = "ok";
const sent = [];
globalThis.fetch = async (url, init) => {
  sent.push({ url, headers: init.headers, body: JSON.parse(init.body) });
  switch (upstreamMode) {
    case "ok": return new Response(JSON.stringify({ content: [{ type: "text", text: "hi" }] }),
      { status: 200, headers: { "content-type": "application/json", "anthropic-ratelimit-requests-remaining": "999", "request-id": "req_upstream_123" } });
    case "500": return new Response(JSON.stringify({ type: "error", error: { type: "api_error", message: "Internal upstream detail: org org_ABC billing account suspended" } }),
      { status: 500, headers: { "content-type": "application/json" } });
    case "401": return new Response(JSON.stringify({ error: { message: "invalid x-api-key" } }), { status: 401 });
    case "html": return new Response("<html>Bad Gateway from cf-edge-xyz</html>", { status: 200, headers: { "content-type": "text/html" } });
    case "throw": throw new TypeError("connect ECONNREFUSED");
  }
};

const URL_ = "https://proxy.example.workers.dev/";
const good = (o = {}) => JSON.stringify({ model: "claude-haiku-4-5", max_tokens: 100, messages: [{ role: "user", content: "hi" }], ...o });
const APP_TOKEN = "test-app-token";
function req({ method = "POST", body = good(), headers = {} } = {}) {
  const merged = { "content-type": "application/json", "x-device-id": "dev-A", "x-app-token": APP_TOKEN, ...headers };
  const h = Object.fromEntries(Object.entries(merged).filter(([, v]) => v !== undefined));
  return new Request(URL_, { method, headers: h, body: method === "GET" || method === "HEAD" ? undefined : body });
}

let env;
function freshEnv(extra = {}) { env = { ANTHROPIC_API_KEY: "test-placeholder-not-a-key", APP_TOKEN, DAILY_LIMIT: "3", QUOTA: makeKV(), ...extra }; }

const results = [];
async function run(name, request, expect, after) {
  sent.length = 0;
  let res, text;
  try { res = await worker.fetch(request, env); text = await res.text(); }
  catch (e) { results.push({ name, verdict: "CRASH", detail: String(e) }); return; }
  const info = { status: res.status, quota: res.headers.get("x-quota-remaining"),
    cors: res.headers.get("access-control-allow-origin"), body: text.slice(0, 140),
    upstreamCalls: sent.length, fwdMaxTokens: sent[0]?.body?.max_tokens, fwdKeys: sent[0] ? Object.keys(sent[0].body).join(",") : "" };
  const extra = after ? after(res, info) : "";
  const pass = expect(info);
  results.push({ name, verdict: pass ? "PASS" : "FAIL", ...info, extra });
}

freshEnv();
await run("GET -> 405", req({ method: "GET" }), i => i.status === 405);
await run("OPTIONS preflight", req({ method: "OPTIONS", body: undefined }), i => i.status === 405);
await run("PUT -> 405", req({ method: "PUT" }), i => i.status === 405);
await run("text/plain content-type w/ valid JSON body (should be 415/400?)", req({ headers: { "content-type": "text/plain" } }), i => i.status === 400 || i.status === 415);
await run("invalid JSON -> 400", req({ body: "{not json" }), i => i.status === 400 && i.upstreamCalls === 0);
await run("JSON null body -> 400", req({ body: "null" }), i => i.status === 400);
await run("JSON array body -> 400", req({ body: "[]" }), i => i.status === 400);
await run("disallowed model opus-4-1 -> 400", req({ body: good({ model: "claude-opus-4-1" }) }), i => i.status === 400);
await run("model prefix trick 'claude-haiku-4-5-20251001x'", req({ body: good({ model: "claude-haiku-4-5-20251001x" }) }), i => i.status === 400);
await run("pinned model 'claude-haiku-4-5-20251001' allowed", req({ body: good({ model: "claude-haiku-4-5-20251001" }) }), i => i.status === 200);
freshEnv();
await run("max_tokens 100000 -> capped 4096", req({ body: good({ max_tokens: 100000 }) }), i => i.fwdMaxTokens === 4096);
await run("max_tokens as string '100000' (cap bypass?)", req({ body: good({ max_tokens: "100000" }) }), i => i.upstreamCalls === 0 || (typeof i.fwdMaxTokens === "number" && i.fwdMaxTokens <= 4096));
await run("max_tokens negative -1", req({ body: good({ max_tokens: -1 }) }), i => i.upstreamCalls === 0);
freshEnv({ DAILY_LIMIT: "1000" });
await run("max_tokens missing", req({ body: JSON.stringify({ model: "claude-haiku-4-5", messages: [{ role: "user", content: "x" }] }) }), i => i.upstreamCalls === 0);
await run("extra fields passthrough (tools/stream/metadata)", req({ body: good({ stream: true, tools: [{ name: "web_search", type: "web_search_20250305" }], metadata: { user_id: "x" } }) }), i => !/tools|stream/.test(i.fwdKeys));
const big = "A".repeat(5 * 1024 * 1024);
await run("5 MB body -> 400/413", req({ body: good({ messages: [{ role: "user", content: big }] }) }), i => i.status === 400 || i.status === 413);
await run("200 messages in one request", req({ body: good({ messages: Array.from({ length: 200 }, (_, k) => ({ role: k % 2 ? "assistant" : "user", content: "x" })) }) }), i => i.upstreamCalls === 0);
await run("no auth header at all (anyone with URL)", req({ headers: { "x-app-token": undefined } }), i => i.status === 401 || i.status === 403);
await run("forged x-app-token / Authorization", req({ headers: { authorization: "Bearer forged", "x-app-token": "forged" } }), i => i.status === 401 || i.status === 403);

// quota
freshEnv({ DAILY_LIMIT: "3" });
for (let k = 1; k <= 3; k++) await run(`quota call ${k}/3`, req(), i => i.status === 200 && i.quota === String(3 - k));
await run("quota call 4/3 -> 429", req(), i => i.status === 429 && i.quota === "0" && i.upstreamCalls === 0);
await run("same device, rotated x-device-id -> bypass?", req({ headers: { "x-device-id": "dev-A-2" } }), i => i.status === 429);
// The quota belongs to the network, not the client-chosen x-device-id, so none of these
// header variations buys a fresh allowance once the network's is spent (changed from 200
// with the audit fixes; see AUDIT-2026-10.md).
await run("missing x-device-id -> no fresh allowance", req({ headers: { "x-device-id": "" } }), i => i.status === 429 && i.upstreamCalls === 0, () => `anon key used: ${[...env.QUOTA._m.keys()].some(k => k.startsWith("quota:anon:"))}`);
await run("x-device-id 300 chars -> no fresh allowance", req({ headers: { "x-device-id": "Z".repeat(300) } }), i => i.status === 429 && i.upstreamCalls === 0, () => `key len: ${[...env.QUOTA._m.keys()].find(k => k.includes("ZZZ"))?.length ?? "no device-keyed entry"}`);
await run("x-device-id with ':' delimiter injection -> no fresh allowance", req({ headers: { "x-device-id": "dev-A:2099-01-01" } }), i => i.status === 429 && i.upstreamCalls === 0, () => [...env.QUOTA._m.keys()].join(" | "));
nowOffsetMs = 24 * 3600 * 1000;
await run("day rollover (+24h) dev-A resets", req(), i => i.status === 200 && i.quota === "2");
nowOffsetMs = 0;
freshEnv({ DAILY_LIMIT: "abc" });
await run("DAILY_LIMIT misconfigured 'abc' (NaN)", req(), i => i.status === 429 || i.status === 500);
freshEnv({ DAILY_LIMIT: "3" });
// concurrency race: 10 parallel requests with limit 3
{
  const ps = Array.from({ length: 10 }, () => worker.fetch(req({ headers: { "x-device-id": "racer" } }), env));
  const st = (await Promise.all(ps)).map(r => r.status);
  results.push({ name: "10 concurrent requests, limit 3 (KV race)", verdict: st.filter(s => s === 200).length <= 3 ? "PASS" : "FAIL", status: st.join(","), extra: `stored=${await env.QUOTA.get("quota:racer:" + new Date().toISOString().slice(0, 10))}` });
}

// upstream failures
freshEnv();
upstreamMode = "500";
await run("upstream 500 -> body leaked?", req(), i => !i.body.includes("billing") && i.quota === "3");
upstreamMode = "401";
await run("upstream 401 (bad server key) relayed as 401", req(), i => i.status !== 401);
upstreamMode = "html";
await run("upstream 200 non-JSON", req(), i => true);
upstreamMode = "throw";
await run("upstream network error -> 502", req(), i => i.status === 502 && !i.body.includes("ECONNREFUSED"));
upstreamMode = "ok";
await run("upstream headers relayed (request-id, ratelimit)", req(), i => true, r => `request-id=${r.headers.get("request-id")} ratelimit=${r.headers.get("anthropic-ratelimit-requests-remaining")}`);
await run("server key forwarded only to api.anthropic.com", req(), i => sent[0]?.url === "https://api.anthropic.com/v1/messages");
freshEnv({ ANTHROPIC_API_KEY: "" });
await run("no key configured -> 500 generic", req(), i => i.status === 500 && i.body.includes("Proxy not configured"));

for (const r of results) {
  console.log(`[${r.verdict}] ${r.name}\n    status=${r.status} quota=${r.quota ?? "-"} cors=${r.cors ?? "-"} upstream=${r.upstreamCalls ?? "-"} fwdMax=${r.fwdMaxTokens ?? "-"} keys=${r.fwdKeys ?? ""}\n    body=${(r.body || "").replace(/\s+/g, " ")}${r.extra ? "\n    note=" + r.extra : ""}`);
}
console.log(`\n${results.filter(r => r.verdict === "PASS").length}/${results.length} pass`);
