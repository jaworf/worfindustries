"use client";

import {useState} from "react";
import type {SupabaseClient} from "@supabase/supabase-js";
import {functionErrorMessage} from "./admin-shared";

export function DeleteAccountButton({supabase}: {supabase: SupabaseClient}) {
  const [confirming, setConfirming] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function remove() {
    setBusy(true);
    setError(null);
    try {
      const {error} = await supabase.functions.invoke("admin-users", {
        body: {action: "delete_self", confirmation: "DELETE"},
      });
      if (error) throw new Error(await functionErrorMessage(error));
      await supabase.auth.signOut({scope: "local"});
      window.location.assign("/admin");
    } catch (error) {
      setError(error instanceof Error ? error.message : "Account deletion failed. Please try again.");
      setBusy(false);
    }
  }

  return <div>
    <button type="button" className="button button-danger" disabled={busy} onClick={() => setConfirming(true)}>Delete My Account</button>
    {confirming && <section role="alertdialog" aria-modal="true" aria-labelledby="delete-account-title">
      <h3 id="delete-account-title">Permanently delete your account?</h3>
      <p>This deletes your login and account profile and signs you out. It cannot be undone. Church-owned volunteer records and assignments remain with the church; Planning Center records are not changed. If you are the only administrator, arrange another administrator first so your church can continue managing its records.</p>
      <button type="button" className="button button-danger" disabled={busy} onClick={() => void remove()}>{busy ? "Deleting…" : "Delete My Account Permanently"}</button>
      <button type="button" className="button" disabled={busy} onClick={() => setConfirming(false)}>Cancel</button>
    </section>}
    {error && <p role="alert">{error}</p>}
  </div>;
}
