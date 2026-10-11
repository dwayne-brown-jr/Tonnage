// Offline checks for the Durable Object quota path in worker.js (the production path;
// proxy.test.mjs covers the KV fallback). The DO namespace is mocked: each object id gets
// one QuotaCounter, and calls to the same object run one at a time, as Cloudflare
// guarantees. Usage (from the proxy folder): node quota-do.test.mjs
import { pathToFileURL, fileURLToPath } from "node:url";
import path from "node:path";
import fs from "node:fs";
import os from "node:os";

const src = path.join(path.dirname(fileURLToPath(import.meta.url)), "worker.js");
const tmp = path.join(os.tmpdir(), "tonnage-worker-do-under-test.mjs");
fs.copyFileSync(src, tmp);
const mod = await import(pathToFileURL(tmp).href);
const worker = mod.default;
const { QuotaCounter } = mod;

function makeStorage() {
  const m = new Map();
  let alarm = null;
  return {
    _m: m,
    async get(k) { return m.get(k); },
    async put(k, v) { m.set(k, v); },
    async getAlarm() { return alarm; },
    async setAlarm(t) { alarm = t; },
    async deleteAll() { m.clear(); alarm = null; },
  };
}

function makeNamespace() {
  const objects = new Map();
  return {
    objects,
    idFromName(name) { return name; },
    get(id) {
      if (!objects.has(id)) {
        objects.set(id, { counter: new QuotaCounter({ storage: makeStorage() }), chain: Promise.resolve() });
      }
      const o = objects.get(id);
      return {
        fetch(url, init) {
          const run = o.chain.then(() => o.counter.fetch(new Request(url, init)));
          o.chain = run.catch(() => {});
          return run;
        },
      };
    },
  };
}

let upstreamOK = true;
let upstreamCalls = 0;
globalThis.fetch = async () => {
  upstreamCalls++;
  return upstreamOK
    ? new Response(JSON.stringify({ content: [{ type: "text", text: "hi" }] }), { status: 200, headers: { "content-type": "application/json" } })
    : new Response("{}", { status: 500 });
};

const TOKEN = "t";
const body = JSON.stringify({ model: "claude-haiku-4-5", max_tokens: 50, messages: [{ role: "user", content: "hi" }] });
const req = (ip = "203.0.113.7") => new Request("https://p.example/", {
  method: "POST", body,
  headers: { "content-type": "application/json", "x-app-token": TOKEN, "cf-connecting-ip": ip },
});
const kvTouched = { get: 0, put: 0 };
const env = () => ({
  ANTHROPIC_API_KEY: "k", APP_TOKEN: TOKEN, DAILY_LIMIT: "3", QUOTA_DO: makeNamespace(),
  QUOTA: { async get() { kvTouched.get++; return null; }, async put() { kvTouched.put++; } },
});

const results = [];
const check = (name, ok, detail = "") => results.push({ name, ok, detail });

{
  const e = env();
  const statuses = (await Promise.all(Array.from({ length: 10 }, () => worker.fetch(req(), e)))).map((r) => r.status);
  check("10 concurrent, limit 3 → exactly 3 succeed", statuses.filter((s) => s === 200).length === 3, statuses.join(","));
  check("KV untouched when the DO is bound", kvTouched.get === 0 && kvTouched.put === 0);
}
{
  const e = env();
  upstreamOK = false;
  const r = await worker.fetch(req(), e);
  upstreamOK = true;
  check("failed upstream is refunded", r.status === 502 && r.headers.get("x-quota-remaining") === "3");
  const ok = await worker.fetch(req(), e);
  check("next call still has the full allowance", ok.headers.get("x-quota-remaining") === "2");
}
{
  const e = env();
  for (let i = 0; i < 3; i++) await worker.fetch(req("2001:db8:1:2:aaaa::1"), e);
  const sameSlash64 = await worker.fetch(req("2001:db8:1:2:bbbb::9"), e);
  const otherNet = await worker.fetch(req("2001:db8:1:3::1"), e);
  check("IPv6 addresses in one /64 share a quota", sameSlash64.status === 429);
  check("a different network has its own quota", otherNet.status === 200);
}
{
  const storage = makeStorage();
  const counter = new QuotaCounter({ storage });
  await counter.fetch(new Request("https://q/", { method: "POST", body: JSON.stringify({ op: "consume", limit: 5, ttlMs: 1000 }) }));
  check("first use schedules expiry", (await storage.getAlarm()) !== null);
  await counter.alarm();
  check("expiry clears the counter", storage._m.size === 0);
}

for (const r of results) console.log(`[${r.ok ? "PASS" : "FAIL"}] ${r.name}${r.detail ? `  (${r.detail})` : ""}`);
console.log(`\n${results.filter((r) => r.ok).length}/${results.length} pass`);
process.exitCode = results.every((r) => r.ok) ? 0 : 1;
