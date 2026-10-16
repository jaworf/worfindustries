import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.110.8";
import { corsHeaders } from "npm:@supabase/supabase-js@2.110.8/cors";

const jsonHeaders = {
  ...corsHeaders,
  "Content-Type": "application/json",
};

const defaultPasswordSetupURL =
  "https://ministryvolunteers.worf.app/reset-password";

type InvitationRole = "admin" | "editor" | "viewer";

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

async function findUserByEmail(
  admin: SupabaseClient,
  email: string,
) {
  for (let page = 1; page <= 10; page += 1) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage: 1000 });
    if (error) throw error;
    const match = data.users.find((user) => user.email?.toLowerCase() === email);
    if (match) return match;
    if (data.users.length < 1000) return null;
  }
  throw new Error("The user directory is too large to search safely.");
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

    const payload = (await request.json().catch(() => null)) as {
      action?: unknown;
      user_id?: unknown;
      disabled?: unknown;
      review_account?: unknown;
      email?: unknown;
      role?: unknown;
      church_id?: unknown;
      temporary_password?: unknown;
      confirmation?: unknown;
    } | null;

    // Self-deletion is available to every authenticated account, including
    // viewers and accounts whose church access has been removed.
    if (payload?.action === "delete_self") {
      if (payload.confirmation !== "DELETE") {
        return json(400, { error: "Confirm permanent account deletion." });
      }
      const { error } = await admin.auth.admin.deleteUser(user.id.toLowerCase());
      if (error) throw error;
      return json(200, { message: "Your account and sign-in profile have been permanently deleted." });
    }

    const { data: profile, error: profileError } = await admin
      .from("profiles")
      .select("app_role,church_id,is_platform_admin,access_disabled,must_change_password")
      .eq("user_id", user.id)
      .single();
    if (profileError || profile?.app_role !== "admin" || profile.access_disabled || profile.must_change_password || !profile.church_id) {
      return json(403, { error: "Only an active administrator can manage app users." });
    }

    if (payload?.action === "delete_user") {
      if (typeof payload.user_id !== "string" || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(payload.user_id) || payload.confirmation !== "DELETE") {
        return json(400, { error: "Choose a user and confirm permanent deletion." });
      }
      // Foundation UUID.uuidString uses uppercase; Auth's UUID validator only
      // accepts lowercase. Use one canonical ID for the guard and deletion.
      const targetUserId = payload.user_id.toLowerCase();
      const { data: target, error: lookupError } = await admin.from("profiles")
        .select("access_disabled").eq("user_id", targetUserId).single();
      if (lookupError) throw lookupError;
      // The same transactional guard protects church boundaries, platform
      // administrators, self-management, and the last active administrator.
      const { error: guardError } = await admin.rpc("manage_app_user_access", {
        p_actor_id: user.id, p_user_id: targetUserId, p_role: null, p_disabled: true,
      });
      if (guardError) return json(403, { error: "This account cannot be deleted by this administrator. Check church membership and administrator protections." });
      const { error: deleteError } = await admin.auth.admin.deleteUser(targetUserId);
      if (deleteError) {
        if (!target.access_disabled) {
          const { error: restoreError } = await admin.rpc("manage_app_user_access", {
            p_actor_id: user.id, p_user_id: targetUserId, p_role: null, p_disabled: false,
          });
          if (restoreError) console.error("Could not restore access after unsuccessful account deletion:", restoreError);
        }
        throw deleteError;
      }
      return json(200, { message: "User account permanently deleted. Church records are preserved." });
    }
    if (payload?.action === "list") {
      let query = admin.from("profiles").select("user_id,display_name,app_role,church_id,is_platform_admin,access_disabled,must_change_password").not("church_id", "is", null);
      if (!profile.is_platform_admin) query = query.eq("church_id", profile.church_id);
      const { data: profiles, error } = await query.order("display_name");
      if (error) throw error;
      const users = [];
      // Bound Auth API traffic even when a church has many accounts.
      const rows = profiles ?? [];
      for (let offset = 0; offset < rows.length; offset += 5) {
        users.push(...await Promise.all(rows.slice(offset, offset + 5).map(async p => {
        const { data, error } = await admin.auth.admin.getUserById(p.user_id);
        if (error) throw error;
        return { ...p, email: data.user.email, enrolled: Boolean(data.user.email_confirmed_at), last_sign_in_at: data.user.last_sign_in_at ?? null };
        })));
      }
      return json(200, { users });
    }
    if (["update_role", "remove_access", "restore_access"].includes(String(payload?.action))) {
      if (typeof payload?.user_id !== "string") return json(400, { error: "Choose an app user." });
      const { error } = await admin.rpc("manage_app_user_access", {
        p_actor_id: user.id, p_user_id: payload.user_id,
        p_role: payload.action === "update_role" ? payload.role : null,
        p_disabled: payload.action === "remove_access" ? true : payload.action === "restore_access" ? false : null,
      });
      if (error) return json(400, { error: error.message });
      return json(200, { message: "App access updated." });
    }
    if (payload?.action && payload.action !== "invite") return json(400, { error: "Unknown user-management action." });
    const email =
      typeof payload?.email === "string"
        ? payload.email.trim().toLowerCase()
        : "";
    const role = payload?.role;
    if (!/^\S+@\S+\.\S+$/.test(email)) {
      return json(400, { error: "Enter a valid email address." });
    }
    if (role !== "admin" && role !== "editor" && role !== "viewer") {
      return json(400, { error: "Choose Administrator, Editor, or Viewer access." });
    }
    const requestedChurchId =
      typeof payload?.church_id === "string" ? payload.church_id : null;
    const churchId = profile.is_platform_admin && requestedChurchId
      ? requestedChurchId
      : profile.church_id;
    if (!churchId) return json(400, { error: "Choose a church for this account." });
    if (role === "admin" && !profile.is_platform_admin) {
      return json(403, { error: "Only the platform administrator can create another administrator." });
    }
    const temporaryPassword =
      typeof payload?.temporary_password === "string"
        ? payload.temporary_password
        : "";
    const reviewAccount = payload?.review_account === true;
    if (reviewAccount && !profile.is_platform_admin) return json(403, { error: "Only the platform administrator can create review accounts." });
    if (temporaryPassword && temporaryPassword.length < 14) {
      return json(400, { error: "The temporary password must contain at least 14 characters." });
    }
    const { data: church, error: churchError } = await admin
      .from("churches")
      .select("id,name,is_active")
      .eq("id", churchId)
      .single();
    if (churchError || !church?.is_active) {
      return json(400, { error: "The selected church is not active." });
    }

    const redirectTo =
      Deno.env.get("APP_PASSWORD_RESET_URL") ?? defaultPasswordSetupURL;
    const existingUser = await findUserByEmail(admin, email);
    if (existingUser) {
      const { data: existingProfile, error: existingProfileError } = await admin.from("profiles").select("church_id,is_platform_admin,access_disabled,app_role").eq("user_id",existingUser.id).maybeSingle();
      // Fail closed before any email, password, or membership mutation.
      if (existingProfileError) throw existingProfileError;
      if (!existingProfile?.church_id) return json(409, { error: "This account has no church membership. A platform administrator must resolve it separately." });
      if (existingProfile?.church_id && (existingProfile.church_id !== churchId || existingProfile.app_role !== role)) return json(409, { error: "This account already exists. Change its permissions in Manage App Users; existing church membership is preserved." });
      if (existingUser.email_confirmed_at && temporaryPassword && !reviewAccount) return json(409, { error: "This account is already active. Use Manage App Users for permissions, or password recovery to change its password." });
      if (existingProfile?.access_disabled) return json(409, { error: "This user's app access was removed. Restore access from the user list first." });
      if (existingUser.id === user.id && temporaryPassword) return json(400, { error: "Change your own password through password recovery." });
      if (existingProfile?.is_platform_admin || (!profile.is_platform_admin && existingProfile && (existingProfile.church_id !== churchId || existingProfile.app_role === "admin"))) return json(403, { error: "You cannot change this account." });
    }
    let userId: string;
    let responseStatus = 201;
    let responseMessage = "Setup email sent.";

    if (existingUser && temporaryPassword) {
      return json(409, {
        error: "This account already exists. Use password recovery to change its password.",
      });
    } else if (existingUser) {
      if (existingUser.email_confirmed_at) {
        return json(409, { error: "That email already has an active app account." });
      }

      const { error: resendError } = await admin.auth.resetPasswordForEmail(email, {
        redirectTo,
      });
      if (resendError) return json(400, { error: resendError.message });
      userId = existingUser.id;
      responseStatus = 200;
      responseMessage = "A new setup email was sent. Use the link in the newest message.";
    } else if (temporaryPassword) {
      const { data: created, error: createError } = await admin.auth.admin.createUser({
        email,
        password: temporaryPassword,
        email_confirm: true,
        user_metadata: { full_name: reviewAccount ? "App Review" : email.split("@")[0] },
      });
      if (createError || !created.user) {
        return json(400, { error: createError?.message ?? "Supabase could not create the review user." });
      }
      userId = created.user.id;
      responseMessage = reviewAccount ? "Password-based review account created." : "Account created. The user must change the temporary password at first login.";
    } else {
      const { data: invitation, error: invitationError } =
        await admin.auth.admin.inviteUserByEmail(email, {
          redirectTo,
          data: { full_name: email.split("@")[0] },
        });
      if (invitationError || !invitation.user) {
        return json(400, {
          error: invitationError?.message ?? "Supabase could not create the user.",
        });
      }
      userId = invitation.user.id;
    }

    const { error: profileUpdateError } = existingUser
      ? temporaryPassword
        ? await admin.from("profiles").update({ must_change_password: !reviewAccount }).eq("user_id", userId).eq("church_id", churchId)
        : { error: null }
      : await admin
      .from("profiles")
      .upsert(
        {
          user_id: userId,
          ...(!existingUser ? { display_name: email.split("@")[0] } : {}),
          app_role: role as InvitationRole,
          church_id: churchId,
          ...(temporaryPassword ? { must_change_password: !reviewAccount } : {}),
        },
        { onConflict: "user_id" },
      );
    if (profileUpdateError) {
      if (!existingUser) await admin.auth.admin.deleteUser(userId);
      return json(500, {
        error: existingUser
          ? "The account role could not be updated."
          : "The account role could not be saved. No user was created.",
      });
    }

    return json(responseStatus, {
      user_id: userId,
      email,
      role,
      church_id: churchId,
      church_name: church.name,
      message: responseMessage,
    });
  } catch (error) {
    console.error("Admin user management failed:", error);
    return json(500, {
      error: "User management failed. Please try again.",
    });
  }
});
