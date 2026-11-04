"use client";
import { useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Profile } from "./admin-shared";
export function StaffProfileSetup({
  supabase,
  profile,
  onComplete,
}: {
  supabase: SupabaseClient;
  profile: Profile;
  onComplete: () => Promise<void>;
}) {
  const [first, setFirst] = useState(profile.first_name ?? ""),
    [last, setLast] = useState(profile.last_name ?? ""),
    [phone, setPhone] = useState(profile.phone ?? ""),
    [busy, setBusy] = useState(false),
    [error, setError] = useState("");
  return (
    <main className="admin-login-shell">
      <section className="admin-login-card">
        <h1>Complete your account</h1>
        <p>
          Add your name and phone number so your team knows who is making each
          call.
        </p>
        <form
          className="admin-form-stack"
          onSubmit={async (e) => {
            e.preventDefault();
            setBusy(true);
            const { error } = await supabase.rpc("complete_staff_profile", {
              p_first_name: first.trim(),
              p_last_name: last.trim(),
              p_phone: phone.trim(),
            });
            if (error) setError(error.message);
            else await onComplete();
            setBusy(false);
          }}
        >
          <label>
            First name
            <input
              autoComplete="given-name"
              required
              maxLength={100}
              value={first}
              onChange={(e) => setFirst(e.target.value)}
            />
          </label>
          <label>
            Last name
            <input
              autoComplete="family-name"
              required
              maxLength={100}
              value={last}
              onChange={(e) => setLast(e.target.value)}
            />
          </label>
          <label>
            Phone number
            <input
              type="tel"
              autoComplete="tel"
              required={!profile.person_id}
              minLength={5}
              maxLength={50}
              value={phone}
              onChange={(e) => setPhone(e.target.value)}
            />
          </label>
          {error && <p role="alert">{error}</p>}
          <button className="button button-primary" disabled={busy}>
            Save and Continue
          </button>
        </form>
        <button className="button" onClick={() => void supabase.auth.signOut()}>
          Sign Out
        </button>
      </section>
    </main>
  );
}
