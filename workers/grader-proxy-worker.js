// grader-proxy-worker.js
// Cloudflare Worker: holds the Anthropic API key so the iOS app never does.
//
// THREAT MODEL — read this before changing anything.
//
// PROXY_TOKEN is shipped inside the iOS app, so it reaches every install and
// is recoverable from any build. It is not a secret and must not be treated as
// one. An earlier version of it was also committed to this PUBLIC repository
// and sat readable for eight weeks; it has since been rotated.
//
// This worker does not try to keep the token secret. It makes holding the
// token useless for anything except grading an essay:
//
//   * a pinned model allowlist,
//   * a per-model max_tokens ceiling,
//   * a request body rebuilt from an allowlist, so this cannot be used as a
//     general-purpose Anthropic endpoint — no tools, no agents, no web search,
//     no code execution, no 200k-token prompts,
//   * a request size cap.
//
// Deliberately NOT here: spend metering and a kill-switch endpoint. Both need
// durable state, and both duplicate controls that already exist for free and
// hold even if this file is wrong:
//
//   * the SPEND CEILING belongs on the Anthropic workspace, where Anthropic
//     enforces it regardless of what this worker does;
//   * the KILL SWITCH is `wrangler secret put PROXY_TOKEN` with a fresh
//     value, which revokes every client instantly and needs no code.
//
// Secrets (wrangler secret put <NAME>):
//   ANTHROPIC_API_KEY  — the real Anthropic key
//   PROXY_TOKEN        — the value the app sends as a bearer token

// Keys must match GraderModel.rawValue, and maxTokens must match
// GraderModel.maxTokens, in CFAL3/Services/ClaudeGrader.swift. The app sends
// exactly these values, so clamping never affects real traffic — it only
// stops a caller asking for a 128k output.
const MODELS = {
  "claude-fable-5": { maxTokens: 12000 },
  "claude-opus-4-8": { maxTokens: 8000 },
  "claude-sonnet-4-6": { maxTokens: 4000 },
  "claude-haiku-4-5": { maxTokens: 2000 },
  // The date-suffixed spelling the app actually sends for Haiku.
  "claude-haiku-4-5-20251001": { maxTokens: 2000 },
};

// Measured against the bundled content: the largest real grading request is
// ~12,200 characters of content and ~18 KB of body, so these sit at roughly
// three times the worst legitimate case.
const MAX_BODY_BYTES = 65536;
const MAX_SYSTEM_CHARS = 24000;
const MAX_CONTENT_CHARS = 40000;
const MAX_MESSAGES = 2;

/** Anthropic-shaped error, so the app's existing parseAPIErrorMessage works. */
function apiError(status, type, message) {
  return new Response(
    JSON.stringify({ type: "error", error: { type, message } }),
    { status, headers: { "content-type": "application/json" } }
  );
}

/** Length-independent compare, so a wrong token leaks nothing by timing. */
function tokenEquals(a, b) {
  if (typeof a !== "string" || typeof b !== "string") return false;
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/**
 * Rebuild the upstream body from an allowlist. Nothing the caller sent is
 * forwarded verbatim — this is the control that stops the proxy being a
 * general Anthropic endpoint. Unknown top-level fields (tools, thinking,
 * mcp_servers, container, betas, ...) are dropped on the floor.
 */
function buildUpstreamBody(raw) {
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
    return { error: "body must be a JSON object" };
  }

  const spec = MODELS[raw.model];
  if (!spec) return { error: `model not allowed: ${String(raw.model).slice(0, 64)}` };

  // The app always streams; refusing non-streaming keeps the surface to one shape.
  if (raw.stream !== true) return { error: "stream must be true" };

  const system = raw.system;
  if (typeof system !== "string" || system.length > MAX_SYSTEM_CHARS) {
    return { error: `system must be a string under ${MAX_SYSTEM_CHARS} characters` };
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
    body: JSON.stringify({
      model: raw.model,
      max_tokens: maxTokens,
      stream: true,
      system,
      messages,
    }),
  };
}

export default {
  async fetch(request, env) {
    if (request.method !== "POST") {
      return new Response("method not allowed", { status: 405 });
    }

    const auth = request.headers.get("Authorization") || "";
    if (!auth.startsWith("Bearer ") || !tokenEquals(auth.slice(7), env.PROXY_TOKEN || "")) {
      console.log(JSON.stringify({
        event: "unauthorized",
        ip: request.headers.get("cf-connecting-ip"),
        country: request.cf?.country,
      }));
      return new Response("unauthorized", { status: 401 });
    }

    if (Number(request.headers.get("content-length") || 0) > MAX_BODY_BYTES) {
      return apiError(400, "invalid_request_error", "request too large");
    }

    let text;
    try {
      text = await request.text();
    } catch {
      return apiError(400, "invalid_request_error", "unreadable body");
    }
    if (new TextEncoder().encode(text).length > MAX_BODY_BYTES) {
      return apiError(400, "invalid_request_error", "request too large");
    }

    let parsed;
    try {
      parsed = JSON.parse(text);
    } catch {
      return apiError(400, "invalid_request_error", "body is not JSON");
    }

    const built = buildUpstreamBody(parsed);
    if (built.error) {
      return apiError(400, "invalid_request_error", built.error);
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
      console.log(JSON.stringify({ event: "upstream_error", error: String(e) }));
      return apiError(502, "api_error", "Upstream request failed.");
    }

    // Stream straight through. The app reads SSE via URLSession.bytes, so
    // buffering here would break every grade.
    return new Response(upstream.body, {
      status: upstream.status,
      headers: { "content-type": "application/json" },
    });
  },
};
