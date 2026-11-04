/** Cloudflare Worker entry point for the Riverview directory. */
import { handleImageOptimization, DEFAULT_DEVICE_SIZES, DEFAULT_IMAGE_SIZES } from "vinext/server/image-optimization";
import {loadEmbedConfig} from "../app/embed/config";
import handler from "vinext/server/app-router-entry";

interface Env {
  EMBED_ALLOWED_ORIGINS?: string;
  SUPABASE_URL?: string;
  SUPABASE_PUBLISHABLE_KEY?: string;
  ASSETS: Fetcher;
  DB: D1Database;
  IMAGES: {
    input(stream: ReadableStream): {
      transform(options: Record<string, unknown>): {
        output(options: { format: string; quality: number }): Promise<{ response(): Response }>;
      };
    };
  };
}

interface ExecutionContext {
  waitUntil(promise: Promise<unknown>): void;
  passThroughOnException(): void;
}

// Image security config. SVG sources with .svg extension auto-skip the
// optimization endpoint on the client side (served directly, no proxy).
// To route SVGs through the optimizer (with security headers), set
// dangerouslyAllowSVG: true in next.config.js and uncomment below:
// const imageConfig: ImageConfig = { dangerouslyAllowSVG: true };

const worker = {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);

    if (url.hostname === "ministryvolunteers.worf.app" && url.pathname === "/") {
      url.pathname = "/admin";
      return new Response(null, {
        status: 302,
        headers: { Location: url.toString(), "Cache-Control": "no-store" },
      });
    }

    if (url.pathname === "/_vinext/image") {
      const allowedWidths = [...DEFAULT_DEVICE_SIZES, ...DEFAULT_IMAGE_SIZES];
      return handleImageOptimization(request, {
        fetchAsset: (path) => env.ASSETS.fetch(new Request(new URL(path, request.url))),
        transformImage: async (body, { width, format, quality }) => {
          const result = await env.IMAGES.input(body).transform(width > 0 ? { width } : {}).output({ format, quality });
          return result.response();
        },
      }, allowedWidths);
    }

    const response = await handler.fetch(request, env, ctx);
    const headers = new Headers(response.headers);
    headers.set("X-Content-Type-Options", "nosniff");
    headers.set("Referrer-Policy", "strict-origin-when-cross-origin");

    const churchEmbed = url.pathname.match(/^\/embed\/(app|directory)\/([a-z0-9][a-z0-9-]{0,79})\/?$/);
    let origins: string[] = [];
    if (churchEmbed) {
      const config = await loadEmbedConfig(churchEmbed[2], churchEmbed[1] as "app"|"directory", env.SUPABASE_URL, env.SUPABASE_PUBLISHABLE_KEY);
      origins = config ? embedOrigins(config.allowed_origins.join(" ")) : [];
      headers.set("Cache-Control", "private, no-store");
    } else if (url.pathname === "/embed") origins = embedOrigins(env.EMBED_ALLOWED_ORIGINS);
    if (origins.length) headers.delete("X-Frame-Options");
    headers.set("Content-Security-Policy", `frame-ancestors 'self'${origins.length ? " " + origins.join(" ") : ""}`);

    return new Response(response.body, {
      status: response.status,
      statusText: response.statusText,
      headers,
    });
  },
};

export default worker;

function embedOrigins(configured?: string): string[] {
  const origins = configured ?? "https://riverviewadventist.org https://www.riverviewadventist.org";
  return origins.split(/[\s,]+/).filter(value => {
    try {
      const url = new URL(value);
      return url.protocol === "https:" && !url.hostname.includes("*") && url.origin === value;
    } catch {
      return false;
    }
  });
}
