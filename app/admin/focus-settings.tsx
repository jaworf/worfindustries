"use client";
import { useEffect, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
export function FocusMembershipSettings({
  supabase,
  connected,
}: {
  supabase: SupabaseClient;
  connected: boolean;
}) {
  const [options, setOptions] = useState<string[]>([]),
    [selected, setSelected] = useState<string[]>([]),
    [error, setError] = useState(""),
    [busy, setBusy] = useState(false),
    [notice, setNotice] = useState("");
  useEffect(() => {
    let live = true;
    void supabase.rpc("focus_preferences").then(({ data, error }) => {
      if (!live) return;
      if (error) setError(error.message);
      else {
        setOptions(data.options);
        setSelected(data.selected);
      }
    });
    if (connected)
      void supabase.functions
        .invoke("planning-center-sync", {
          body: { action: "membership_types" },
        })
        .then(({ data, error }) => {
          if (live && !error && data?.membership_types)
            setOptions(data.membership_types);
        });
    return () => {
      live = false;
    };
  }, [supabase, connected]);
  return (
    <section className="focus-membership-settings">
      <h4>Volunteer Activation membership types</h4>
      <p>
        Show the 100 newest Planning Center people in these membership types who
        are not currently volunteering.
      </p>
      <details>
        <summary>
          {selected.length ? selected.join(", ") : "All membership types"} ▾
        </summary>
        {options.map((option) => (
          <label className="admin-check-row" key={option}>
            <input
              type="checkbox"
              checked={selected.some(
                (s) => s.toLowerCase() === option.toLowerCase(),
              )}
              onChange={(e) =>
                setSelected((s) =>
                  e.target.checked
                    ? [
                        ...s.filter(
                          (v) => v.toLowerCase() !== option.toLowerCase(),
                        ),
                        option,
                      ]
                    : s.filter((v) => v.toLowerCase() !== option.toLowerCase()),
                )
              }
            />
            {option}
          </label>
        ))}
        {!options.length && (
          <p>
            Refresh membership types from Planning Center to choose options.
          </p>
        )}
        <button className="button" onClick={() => setSelected([])}>
          Use all types
        </button>
      </details>
      <div className="placement-actions">
        <button
          className="button"
          disabled={busy}
          onClick={async () => {
            setBusy(true);
            const { error } = await supabase.rpc("save_focus_memberships", {
              p_statuses: selected,
            });
            setError(error?.message ?? "");
            setNotice(error ? "" : "Focus membership types saved.");
            setBusy(false);
          }}
        >
          Save Focus Membership Types
        </button>
        <button
          className="button"
          disabled={busy || !connected}
          onClick={async () => {
            setBusy(true);
            const { data, error } = await supabase.functions.invoke(
              "planning-center-sync",
              { body: { action: "membership_types" } },
            );
            if (error) setError(error.message);
            else {
              setOptions(data.membership_types);
              setNotice("Membership types refreshed from Planning Center.");
            }
            setBusy(false);
          }}
        >
          Refresh Membership Types
        </button>
      </div>
      {notice && <p role="status">{notice}</p>}
      {error && <p role="alert">{error}</p>}
    </section>
  );
}
