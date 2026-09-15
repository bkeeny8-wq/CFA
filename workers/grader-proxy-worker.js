// grader-proxy-worker.js
// Cloudflare Worker: holds the Anthropic API key so the iOS app never does.
//
// THREAT MODEL — read this before changing anything.
//
// PROXY_TOKEN is hardcoded in the iOS app (CFAL3/Services/GraderConfig.swift)
// and that source file lives in a PUBLIC GitHub repo. The token is therefore
// PUBLIC INFORMATION. It is not a secret and must never be treated as one.
// Obfuscating it, moving it to an xcconfig, or injecting it at build time
// would change nothing: any shipped client secret is recoverable with
// `strings` on the binary.
//
// This worker is written on that premise. Its job is NOT to keep the token
// secret. Its job is to make holding the token nearly worthless:
//
//   * a hard daily and monthly USD ceiling on Anthropic spend,
//   * a daily request ceiling,
//   * a pinned model allowlist (four grading models, nothing else),
//   * a per-model max_tokens ceiling,
//   * a request body rebuilt from an allowlist, so the proxy cannot be used
//     as a general-purpose Anthropic endpoint (no tools, no agents, no
//     web search, no code execution, no 200k-token prompts),
//   * a structured log line per request,
//   * an instant kill switch that needs no redeploy.
//
// Worst case for a thief is therefore bounded at DAILY_USD per day and
// MONTHLY_USD per month of grading-shaped requests, and the owner can cut
// it to zero in about ten seconds. See workers/README.md.
//
// Secrets (wrangler secret put <NAME>):
//   ANTHROPIC_API_KEY  — the real Anthropic key
//   PROXY_TOKEN        — the value hardcoded in GraderConfig.swift
//   ADMIN_TOKEN        — a DIFFERENT long random string, never shipped in
//                        the app, used only for /usage and /panic

import { DurableObject } from "cloudflare:workers";

// ---------------------------------------------------------------------------
// Pinned model allowlist.
//
// Keys must match GraderModel.rawValue in CFAL3/Services/ClaudeGrader.swift.
// maxTokens must match GraderModel.maxTokens — the app sends exactly these
// values, so clamping never affects legitimate traffic and always defeats a
// caller asking for a 128k output.
//
// Prices are USD per million tokens, expressed as micro-dollars per token
// (they are numerically identical: $10/MTok == 10 micro-$/token).
// ---------------------------------------------------------------------------
const MODELS = {
  "claude-fable-5":              { maxTokens: 12000, in: 10, out: 50 },
  "claude-opus-4-8":             { maxTokens:  8000, in:  5, out: 25 },
  "claude-sonnet-4-6":           { maxTokens:  4000, in:  3, out: 15 },
  "claude-haiku-4-5":            { maxTokens:  2000, in:  1, out:  5 },
  // The app currently sends this date-suffixed spelling. Allowlisted so
  // pinning does not break Haiku grading; see workers/README.md.
  "claude-haiku-4-5-20251001":   { maxTokens:  2000, in:  1, out:  5 },
};

const MAX_SYSTEM_CHARS = 24000;
const MAX_MESSAGES = 2;
const MAX_CONTENT_CHARS = 40000;

// ---------------------------------------------------------------------------
// Ledger: one globally-consistent Durable Object holding the spend counters.
//
// A Durable Object (not KV) because a spend cap that can be raced by
// concurrent requests is not a cap. Every request serializes through this
// single instance, so N parallel requests cannot all read the same
// under-limit counter and all pass.
// ---------------------------------------------------------------------------
export class Ledger extends DurableObject {
  async #state() {
    const now = new Date();
    const day = now.toISOString().slice(0, 10);   // UTC YYYY-MM-DD
    const month = now.toISOString().slice(0, 7);  // UTC YYYY-MM

    let s = await this.ctx.storage.get("s");
    if (!s) s = { day, month, dayMicros: 0, monthMicros: 0, dayRequests: 0, disabled: false };

    if (s.day !== day) { s.day = day; s.dayMicros = 0; s.dayRequests = 0; }
    if (s.month !== month) { s.month = month; s.monthMicros = 0; }
    return s;
  }

  /**
   * Pessimistic pre-debit. Charges the WORST CASE cost of the request before
   * it is forwarded, so a caller who opens a request and disconnects (or
   * floods concurrently) cannot outrun the accounting. settle() refunds the
   * difference once real usage is known.
   */
  async reserve(worstCaseMicros, limits) {
    const s = await this.#state();

    if (s.disabled) {
      await this.ctx.storage.put("s", s);
      return { ok: false, reason: "disabled", ...s };
    }
    if (s.dayRequests + 1 > limits.dailyRequests) {
      await this.ctx.storage.put("s", s);
      return { ok: false, reason: "daily_requests", ...s };
    }
    if (s.dayMicros + worstCaseMicros > limits.dailyMicros) {
      await this.ctx.storage.put("s", s);
      return { ok: false, reason: "daily_spend", ...s };
    }
    if (s.monthMicros + worstCaseMicros > limits.monthlyMicros) {
      await this.ctx.storage.put("s", s);
      return { ok: false, reason: "monthly_spend", ...s };
    }

    s.dayRequests += 1;
    s.dayMicros += worstCaseMicros;
    s.monthMicros += worstCaseMicros;
    await this.ctx.storage.put("s", s);
    return { ok: true, ...s };
  }

  /** Adjust the pre-debit to actual usage. deltaMicros is normally negative. */
  async settle(deltaMicros) {
    const s = await this.#state();
    s.dayMicros = Math.max(0, s.dayMicros + deltaMicros);
    s.monthMicros = Math.max(0, s.monthMicros + deltaMicros);
    await this.ctx.storage.put("s", s);
    return s;
  }

  async usage() {
    const s = await this.#state();
    await this.ctx.storage.put("s", s);
    return s;
  }

  async setDisabled(disabled) {
    const s = await this.#state();
    s.disabled = !!disabled;
    await this.ctx.storage.put("s", s);
    return s;
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Anthropic-shaped error, so the app's existing parseAPIErrorMessage works. */
function apiError(status, type, message) {
  return new Response(
    JSON.stringify({ type: "error", error: { type, message } }),
    { status, headers: { "content-type": "application/json" } }
  );
}

/** Constant-time-ish string compare; avoids leaking length via early exit. */
function tokenEquals(a, b) {
  if (typeof a !== "string" || typeof b !== "string") return false;
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function limitsFrom(env) {
  return {
    dailyMicros: Math.round(Number(env.DAILY_USD ?? 5) * 1e6),
    monthlyMicros: Math.round(Number(env.MONTHLY_USD ?? 25) * 1e6),
    dailyRequests: Number(env.DAILY_REQUESTS ?? 40),
    maxBodyBytes: Number(env.MAX_BODY_BYTES ?? 65536),
  };
}

function ledger(env) {
  return env.LEDGER.get(env.LEDGER.idFromName("global"));
}

/**
 * Rebuild the upstream body from an allowlist. Nothing the caller sent is
 * forwarded verbatim. This is the control that stops the proxy being used as
 * a general Anthropic endpoint: unknown top-level fields (tools, thinking,
 * output_config, container, mcp_servers, betas, ...) are dropped on the floor.
 */
function buildUpstreamBody(raw) {
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
    return { error: "body must be a JSON object" };
  }

  const spec = MODELS[raw.model];
  if (!spec) return { error: `model not allowed: ${String(raw.model).slice(0, 64)}` };

  if (raw.stream !== true) return { error: "stream must be true" };

  const system = raw.system;
  if (typeof system !== "string" || system.length > MAX_SYSTEM_CHARS) {
    return { error: "system must be a string under 24000 characters" };
  }

  if (!Array.isArray(raw.messages) || raw.messages.length === 0 || raw.messages.length > MAX_MESSAGES) {
    return { error: `messages must be an array of 1-${MAX_MESSAGES} items` };
  }

  const messages = [];
  let contentChars = 0;
  for (const m of raw.messages) {
    if (typeof m !== "object" || m === null) return { error: "malformed message" };
    if (m.role !== "user" && m.role !== "assistant") return { error: "bad message role" };
    if (typeof m.content !== "string") return { error: "message content must be a string" };
    contentChars += m.content.length;
    if (contentChars > MAX_CONTENT_CHARS) return { error: "messages too long" };
    messages.push({ role: m.role, content: m.content });
  }

  const requested = Number.isInteger(raw.max_tokens) ? raw.max_tokens : spec.maxTokens;
  const maxTokens = Math.max(1, Math.min(requested, spec.maxTokens));

  return {
    spec,
    model: raw.model,
    maxTokens,
    body: JSON.stringify({
      model: raw.model,
      max_tokens: maxTokens,
      stream: true,
      system,
      messages,
    }),
  };
}

/** Pull real token usage out of the Anthropic SSE stream. */
async function meterStream(stream, spec, reservedMicros, env, logBase) {
  let inTok = 0, outTok = 0;
  try {
    const reader = stream.pipeThrough(new TextDecoderStream()).getReader();
    let buf = "";
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      buf += value;
      let nl;
      while ((nl = buf.indexOf("\n")) !== -1) {
        const line = buf.slice(0, nl);
        buf = buf.slice(nl + 1);
        if (!line.startsWith("data: ")) continue;
        let j;
        try { j = JSON.parse(line.slice(6)); } catch { continue; }
        if (j.type === "message_start" && j.message?.usage) {
          const u = j.message.usage;
          inTok = (u.input_tokens ?? 0)
                + (u.cache_creation_input_tokens ?? 0)
                + (u.cache_read_input_tokens ?? 0);
          outTok = u.output_tokens ?? 0;
        } else if (j.type === "message_delta" && j.usage?.output_tokens != null) {
          outTok = j.usage.output_tokens;
        }
      }
    }
  } catch (e) {
    // Metering failed — keep the pessimistic pre-debit rather than refunding.
    console.log(JSON.stringify({ ...logBase, event: "meter_error", error: String(e) }));
    return;
  }

  const actualMicros = inTok * spec.in + outTok * spec.out;
  const after = await ledger(env).settle(actualMicros - reservedMicros);
  console.log(JSON.stringify({
    ...logBase,
    event: "settled",
    inTok,
    outTok,
    actualUsd: +(actualMicros / 1e6).toFixed(4),
    dayUsd: +(after.dayMicros / 1e6).toFixed(4),
    monthUsd: +(after.monthMicros / 1e6).toFixed(4),
  }));
}

// ---------------------------------------------------------------------------
// Worker
// ---------------------------------------------------------------------------
export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const limits = limitsFrom(env);

    // --- admin surface (ADMIN_TOKEN, never shipped in the app) -------------
    if (url.pathname === "/usage" || url.pathname === "/panic") {
      if (!env.ADMIN_TOKEN || !tokenEquals(request.headers.get("X-Admin-Token") || "", env.ADMIN_TOKEN)) {
        return new Response("unauthorized", { status: 401 });
      }
      if (url.pathname === "/usage") {
        const s = await ledger(env).usage();
        return Response.json({
          ...s,
          dayUsd: +(s.dayMicros / 1e6).toFixed(4),
          monthUsd: +(s.monthMicros / 1e6).toFixed(4),
          limits: {
            dailyUsd: limits.dailyMicros / 1e6,
            monthlyUsd: limits.monthlyMicros / 1e6,
            dailyRequests: limits.dailyRequests,
          },
        });
      }
      // /panic?on=1 kills grading instantly, worldwide, with no redeploy and
      // no app change. /panic?on=0 restores it.
      const on = url.searchParams.get("on") !== "0";
      const s = await ledger(env).setDisabled(on);
      return Response.json({ disabled: s.disabled });
    }

    // --- grading path ------------------------------------------------------
    if (request.method !== "POST") {
      return new Response("method not allowed", { status: 405 });
    }

    const auth = request.headers.get("Authorization") || "";
    if (!auth.startsWith("Bearer ") || !tokenEquals(auth.slice(7), env.PROXY_TOKEN || "")) {
      console.log(JSON.stringify({
        event: "unauthorized",
        ip: request.headers.get("cf-connecting-ip"),
        country: request.cf?.country,
        asn: request.cf?.asn,
      }));
      return new Response("unauthorized", { status: 401 });
    }

    const declared = Number(request.headers.get("content-length") || 0);
    if (declared > limits.maxBodyBytes) {
      return apiError(400, "invalid_request_error", "request too large");
    }

    let text;
    try {
      text = await request.text();
    } catch {
      return apiError(400, "invalid_request_error", "unreadable body");
    }
    if (new TextEncoder().encode(text).length > limits.maxBodyBytes) {
      return apiError(400, "invalid_request_error", "request too large");
    }

    let parsed;
    try { parsed = JSON.parse(text); } catch {
      return apiError(400, "invalid_request_error", "body is not JSON");
    }

    const built = buildUpstreamBody(parsed);
    if (built.error) {
      return apiError(400, "invalid_request_error", built.error);
    }

    const logBase = {
      ts: new Date().toISOString(),
      ip: request.headers.get("cf-connecting-ip"),
      country: request.cf?.country,
      asn: request.cf?.asn,
      model: built.model,
      maxTokens: built.maxTokens,
      bodyBytes: text.length,
    };

    // Pessimistic worst case: full output budget, plus a deliberately
    // generous input estimate (bytes / 3 is well under real tokens-per-byte).
    const estInTok = Math.ceil(text.length / 3);
    const worstCaseMicros = built.maxTokens * built.spec.out + estInTok * built.spec.in;

    const res = await ledger(env).reserve(worstCaseMicros, limits);
    if (!res.ok) {
      console.log(JSON.stringify({ ...logBase, event: "capped", reason: res.reason }));
      if (res.reason === "disabled") {
        return apiError(503, "api_error", "Grading is disabled by the owner.");
      }
      return apiError(429, "rate_limit_error",
        `Grading budget reached (${res.reason}). Resets at 00:00 UTC.`);
    }

    let upstream;
    try {
      upstream = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-api-key": env.ANTHROPIC_API_KEY,
          "anthropic-version": "2023-06-01",
        },
        body: built.body,
      });
    } catch (e) {
      ctx.waitUntil(ledger(env).settle(-worstCaseMicros));
      console.log(JSON.stringify({ ...logBase, event: "upstream_error", error: String(e) }));
      return apiError(502, "api_error", "Upstream request failed.");
    }

    if (!upstream.ok || !upstream.body) {
      // Nothing was generated; refund the whole reservation.
      ctx.waitUntil(ledger(env).settle(-worstCaseMicros));
      const errBody = await upstream.text();
      console.log(JSON.stringify({ ...logBase, event: "upstream_status", status: upstream.status }));
      return new Response(errBody, {
        status: upstream.status,
        headers: { "content-type": "application/json" },
      });
    }

    // Tee: one branch to the app, one branch metered under waitUntil. The
    // metering branch keeps pulling even if the app disconnects, so a
    // connect-and-drop flood is still billed against the ledger.
    const [toClient, toMeter] = upstream.body.tee();
    ctx.waitUntil(meterStream(toMeter, built.spec, worstCaseMicros, env, logBase));

    // Header shape deliberately unchanged from the original worker: the app
    // reads raw bytes and never inspects content-type.
    return new Response(toClient, {
      status: upstream.status,
      headers: { "content-type": "application/json" },
    });
  },
};
