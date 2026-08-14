import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.110.8";
import { corsHeaders } from "npm:@supabase/supabase-js@2.110.8/cors";

const jsonHeaders = {
  ...corsHeaders,
  "Content-Type": "application/json",
};

const defaultPasswordSetupURL =
  "https://riverview-ministry-directory.jaworf.chatgpt.site/reset-password";

type InvitationRole = "editor" | "viewer";

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

function requiredSecret(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing required secret: ${name}`);
  return value;
}

function serviceKey(): string {
  const single =
    Deno.env.get("SUPABASE_SECRET_KEY") ??
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (single) return single;

  const encoded = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (!encoded) {
    throw new Error(
      "Missing SUPABASE_SECRET_KEYS or SUPABASE_SERVICE_ROLE_KEY.",
    );
  }
  const keys = JSON.parse(encoded) as Record<string, string>;
  const key = keys.default ?? Object.values(keys)[0];
  if (!key) throw new Error("SUPABASE_SECRET_KEYS has no usable key.");
  return key;
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: jsonHeaders });
  }
  if (request.method !== "POST") {
    return json(405, { error: "Method not allowed." });
  }

  try {
    const authorization = request.headers.get("Authorization");
    const token = authorization?.replace(/^Bearer\s+/i, "").trim();
    if (!token) return json(401, { error: "Authentication is required." });

    const admin = createClient(requiredSecret("SUPABASE_URL"), serviceKey(), {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const {
      data: { user },
      error: userError,
    } = await admin.auth.getUser(token);
    if (userError || !user) {
      return json(401, { error: "The Supabase session is invalid." });
    }

    const { data: profile, error: profileError } = await admin
      .from("profiles")
      .select("app_role")
      .eq("user_id", user.id)
      .single();
    if (profileError || profile?.app_role !== "admin") {
      return json(403, { error: "Only an administrator can create app users." });
    }

    const payload = (await request.json().catch(() => null)) as {
      email?: unknown;
      role?: unknown;
    } | null;
    const email =
      typeof payload?.email === "string"
        ? payload.email.trim().toLowerCase()
        : "";
    const role = payload?.role;
    if (!/^\S+@\S+\.\S+$/.test(email)) {
      return json(400, { error: "Enter a valid email address." });
    }
    if (role !== "editor" && role !== "viewer") {
      return json(400, { error: "Access level must be Editor or Viewer." });
    }

    const redirectTo =
      Deno.env.get("APP_PASSWORD_RESET_URL") ?? defaultPasswordSetupURL;
    const { data: invitation, error: invitationError } =
      await admin.auth.admin.inviteUserByEmail(email, {
        redirectTo,
        data: { full_name: email.split("@")[0] },
      });
    if (invitationError || !invitation.user) {
      const message = invitationError?.message ?? "Supabase could not create the user.";
      const friendly = /already|registered|exists/i.test(message)
        ? "That email already has an app account."
        : message;
      return json(409, { error: friendly });
    }

    const { error: profileUpdateError } = await admin
      .from("profiles")
      .upsert(
        {
          user_id: invitation.user.id,
          display_name: email.split("@")[0],
          app_role: role as InvitationRole,
        },
        { onConflict: "user_id" },
      );
    if (profileUpdateError) {
      await admin.auth.admin.deleteUser(invitation.user.id);
      return json(500, {
        error: "The account role could not be saved. No user was created.",
      });
    }

    return json(201, {
      user_id: invitation.user.id,
      email,
      role,
      message: "Setup email sent.",
    });
  } catch (error) {
    return json(500, {
      error: error instanceof Error ? error.message : "Unexpected server error.",
    });
  }
});
