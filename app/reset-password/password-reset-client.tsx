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
  const [needsProfile,setNeedsProfile]=useState(false);
  const [firstName,setFirstName]=useState("");
  const [lastName,setLastName]=useState("");
  const [phone,setPhone]=useState("");

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
      if (!projectUrl || !publishableKey) { setState("error"); setMessage("Account setup is not configured."); return; }
      const headers={apikey:publishableKey,Authorization:`Bearer ${token}`};
      void fetch(`${projectUrl}/auth/v1/user`,{headers}).then(async response=>{if(!response.ok)throw Error("This link is unavailable. Use the newest setup email.");const user=await response.json();const profileResponse=await fetch(`${projectUrl}/rest/v1/profiles?user_id=eq.${encodeURIComponent(user.id)}&select=first_name,last_name,phone,person_id,church_id`,{headers});if(!profileResponse.ok)throw Error("Your account details could not be loaded. Please try the newest link.");const rows=await profileResponse.json();const profile=rows[0];if(!active)return;setFirstName(profile?.first_name??'');setLastName(profile?.last_name??'');setPhone(profile?.phone??'');setNeedsProfile(!!profile?.church_id&&(!profile.first_name||!profile.last_name||(!profile.person_id&&!profile.phone)));setState("ready");}).catch(error=>{if(active){setState("error");setMessage(error.message);}});
    });

    return () => {
      active = false;
    };
  }, [projectUrl,publishableKey]);

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
      if(needsProfile){
        const profileResponse=await fetch(`${projectUrl.replace(/\/$/, "")}/rest/v1/rpc/complete_staff_profile`,{method:'POST',headers:{apikey:publishableKey,Authorization:`Bearer ${accessToken}`,'Content-Type':'application/json'},body:JSON.stringify({p_first_name:firstName.trim(),p_last_name:lastName.trim(),p_phone:phone.trim()})});
        if(!profileResponse.ok){const details=await profileResponse.json().catch(()=>null);throw new Error(details?.message??'Your name and phone number could not be saved.');}
      }
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
          Use this password to sign in to the Ministry Volunteers app.
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
            {needsProfile&&<><p>Tell your team who you are.</p><label>First name<input required maxLength={100} autoComplete="given-name" disabled={state==='saving'} value={firstName} onChange={e=>setFirstName(e.target.value)}/></label><label>Last name<input required maxLength={100} autoComplete="family-name" disabled={state==='saving'} value={lastName} onChange={e=>setLastName(e.target.value)}/></label><label>Phone number<input type="tel" required minLength={5} maxLength={50} autoComplete="tel" disabled={state==='saving'} value={phone} onChange={e=>setPhone(e.target.value)}/></label></>}

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
            <span>Choose where you would like to sign in.</span>
            <div className="auth-success-actions">
              <a className="button primary" href="riverviewministry://open">
                Open iPhone or iPad App
              </a>
              <a className="button secondary" href="/admin">
                Open Web App
              </a>
            </div>
            <small>If the mobile app is not installed, use the web app instead.</small>
          </div>
        )}
      </section>
    </main>
  );
}
