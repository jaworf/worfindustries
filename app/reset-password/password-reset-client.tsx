"use client";

import { FormEvent, useEffect, useState } from "react";

type ResetState = "loading" | "ready" | "saving" | "complete" | "error";
type LinkKind = "recovery" | "invite";

type PasswordResetProps = {
  projectUrl?: string;
  publishableKey?: string;
};

function linkErrorMessage(errorCode: string | null, description: string | null) {
  if (errorCode === "otp_expired") {
    return (
      "This setup or recovery link has expired or was already used. Ask an administrator " +
      "to resend the setup email, then use the link in the newest message."
    );
  }

  return (
    description ??
    "This setup or recovery link is not valid. Return to the app and request a new email."
  );
}

export function PasswordReset({ projectUrl, publishableKey }: PasswordResetProps) {
  const [state, setState] = useState<ResetState>("loading");
  const [linkKind, setLinkKind] = useState<LinkKind>("recovery");
  const [accessToken, setAccessToken] = useState("");
  const [password, setPassword] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [message, setMessage] = useState("");

  useEffect(() => {
    let active = true;
    queueMicrotask(() => {
      if (!active) return;
      const parameters = new URLSearchParams(window.location.hash.replace(/^#/, ""));
      const errorCode = parameters.get("error_code");
      const error = parameters.get("error");

      if (error || errorCode) {
        setMessage(linkErrorMessage(errorCode, parameters.get("error_description")));
        setState("error");
        return;
      }

      const token = parameters.get("access_token");
      const type = parameters.get("type");
      if ((type !== "recovery" && type !== "invite") || !token) {
        setMessage(
          "Open this page from the newest setup or password recovery email sent by the app.",
        );
        setState("error");
        return;
      }

      setAccessToken(token);
      setLinkKind(type);
      setState("ready");
    });

    return () => {
      active = false;
    };
  }, []);

  async function updatePassword(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setMessage("");

    if (password.length < 8) {
      setMessage("Choose a password with at least 8 characters.");
      return;
    }
    if (password !== confirmation) {
      setMessage("The two passwords do not match.");
      return;
    }
    if (!projectUrl || !publishableKey) {
      setMessage("Password setup is not configured. Please contact the app administrator.");
      setState("error");
      return;
    }

    setState("saving");
    try {
      const response = await fetch(
        `${projectUrl.replace(/\/$/, "")}/auth/v1/user`,
        {
          method: "PUT",
          headers: {
            Accept: "application/json",
            apikey: publishableKey,
            Authorization: `Bearer ${accessToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ password }),
        },
      );

      if (!response.ok) {
        const details = (await response.json().catch(() => null)) as
          | { message?: string; error_description?: string }
          | null;
        throw new Error(
          details?.message ??
            details?.error_description ??
            "Supabase could not update the password.",
        );
      }

      window.history.replaceState(null, "", "/reset-password");
      setAccessToken("");
      setPassword("");
      setConfirmation("");
      setState("complete");
    } catch (error) {
      setMessage(
        error instanceof Error
          ? error.message
          : "Supabase could not update the password.",
      );
      setState("ready");
    }
  }

  return (
    <main className="auth-shell">
      <section className="auth-card" aria-live="polite">
        <img
          className="auth-mark"
          src="/ministry-logo.png"
          alt="Riverview Ministry Volunteers logo"
        />
        <p className="eyebrow">Pasco Riverview Adventist Church</p>
        <h1>
          {linkKind === "invite"
            ? "Set up your app password"
            : "Reset your app password"}
        </h1>
        <p className="auth-intro">
          {linkKind === "invite"
            ? "Choose a password for your new Riverview Ministry Volunteers account."
            : "Choose a new password for Riverview Ministry Volunteers."}{" "}
          This does not change the Supabase project or database password.
        </p>

        {state === "loading" && <p className="auth-status">Checking secure link…</p>}

        {state === "error" && (
          <div className="auth-status error" role="alert">
            <strong>We could not use this link.</strong>
            <span>{message}</span>
          </div>
        )}

        {(state === "ready" || state === "saving") && (
          <form className="auth-form" onSubmit={updatePassword}>
            <label>
              New password
              <input
                type="password"
                autoComplete="new-password"
                minLength={8}
                value={password}
                onChange={(event) => setPassword(event.target.value)}
                disabled={state === "saving"}
                required
              />
            </label>
            <label>
              Confirm new password
              <input
                type="password"
                autoComplete="new-password"
                minLength={8}
                value={confirmation}
                onChange={(event) => setConfirmation(event.target.value)}
                disabled={state === "saving"}
                required
              />
            </label>
            {message && (
              <p className="auth-validation" role="alert">
                {message}
              </p>
            )}
            <button className="button primary auth-submit" disabled={state === "saving"}>
              {state === "saving" ? "Updating password…" : "Update Password"}
            </button>
          </form>
        )}

        {state === "complete" && (
          <div className="auth-status success">
            <strong>Password updated.</strong>
            <span>You can close this page and sign in to Riverview Ministry Volunteers.</span>
          </div>
        )}
      </section>
    </main>
  );
}
