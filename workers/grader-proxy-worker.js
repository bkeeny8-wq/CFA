// grader-proxy-worker.js
// Cloudflare Worker: holds the Anthropic API key so the iOS app never does.
//
// One-time setup (Cloudflare dashboard or wrangler CLI):
//   1. Create a Worker, paste this file.
//   2. Add secrets (Settings > Variables > Secrets):
//        ANTHROPIC_API_KEY  = <your Anthropic key>
//        PROXY_TOKEN        = <any long random string you invent>
//   3. Note the worker URL, e.g. https://cfal3-grader.<account>.workers.dev
//
// The app sends the normal /v1/messages JSON body with
//   Authorization: Bearer <PROXY_TOKEN>
// and this worker injects the real key server-side.

export default {
  async fetch(request, env) {
    if (request.method !== "POST") {
      return new Response("method not allowed", { status: 405 });
    }

    const auth = request.headers.get("Authorization") || "";
    if (auth !== `Bearer ${env.PROXY_TOKEN}`) {
      return new Response("unauthorized", { status: 401 });
    }

    let body;
    try {
      body = await request.text();
      JSON.parse(body); // must be JSON; contents passed through verbatim
    } catch {
      return new Response("bad request", { status: 400 });
    }

    const upstream = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": env.ANTHROPIC_API_KEY,
        "anthropic-version": "2023-06-01",
      },
      body,
    });

    // pass status + body through so the app's existing error
    // handling (rate limits, overloaded, invalid request) still works
    return new Response(upstream.body, {
      status: upstream.status,
      headers: { "content-type": "application/json" },
    });
  },
};
