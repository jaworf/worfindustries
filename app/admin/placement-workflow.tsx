"use client";
import { useCallback, useEffect, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  type Profile,
  type Snapshot,
  type Person,
  personName,
  formatDate,
  todayISO,
  isCurrent,
  normalizeError,
} from "./admin-shared";
export type Opening = {
  id: string;
  role_id: string;
  sub_role_id: string | null;
  term_id: string | null;
  quantity: number;
  status: string;
  notes: string;
};
export type Candidate = {
  id: string;
  opening_id: string;
  person_id: string;
  assigned_to: string | null;
  response: string;
  follow_up: string | null;
  stage: string;
  nominated_on: string | null;
  first_reading: string | null;
  second_reading: string | null;
  decision_on: string | null;
  requires_vote: boolean | null;
};
export type ContactEntry = {
  id: string;
  person_id: string;
  candidate_id: string;
  kind: string;
  happened_on: string;
  response: string | null;
  notes: string;
  follow_up: string | null;
  caller_name: string | null;
  recorder_name: string;
  role_label: string;
};
export type Staff = { user_id: string; display_name: string; app_role: string };
export const responseLabels: Record<string, string> = {
  considering: "Considering",
  yes: "Yes / Willing",
  no: "No",
  maybe_later: "Maybe later",
  no_answer: "No answer",
  message_left: "Message left",
  other: "Other",
};
export const stageLabel = (value: string) =>
  value.replaceAll("_", " ").replace(/^./, (s) => s.toUpperCase());
async function allRows<T>(
  db: SupabaseClient,
  table: string,
  order: string,
  personId?: string,
): Promise<T[]> {
  const result: T[] = [];
  for (let offset = 0; ; offset += 1000) {
    let query = db
      .from(table)
      .select("*")
      .order(order)
      .order("id")
      .range(offset, offset + 999);
    if (personId) query = query.eq("person_id", personId);
    const { data, error } = await query;
    if (error) throw error;
    result.push(...(data as T[]));
    if (data.length < 1000) return result;
  }
}
export function ContactLinks({ person }: { person: Person }) {
  return (
    <div className="placement-contact">
      {person.mobile_phone && (
        <a href={`tel:${person.mobile_phone.replace(/[^+\d]/g, "")}`}>
          Mobile: {person.mobile_phone}
        </a>
      )}
      {person.home_phone && (
        <a href={`tel:${person.home_phone.replace(/[^+\d]/g, "")}`}>
          Home: {person.home_phone}
        </a>
      )}
      {person.email && <a href={`mailto:${person.email}`}>{person.email}</a>}
      {!person.mobile_phone && !person.home_phone && !person.email && (
        <span>No contact details recorded</span>
      )}
    </div>
  );
}
export function ContactHistory({ entries }: { entries: ContactEntry[] }) {
  return (
    <div>
      {!entries.length && <p>No volunteer contact history recorded.</p>}
      {entries.map((h) => (
        <article className="placement-history" key={h.id}>
          <strong>
            {formatDate(h.happened_on)} ·{" "}
            {h.kind === "call"
              ? (responseLabels[h.response ?? ""] ?? h.response)
              : stageLabel(h.kind)}
          </strong>
          <p>{h.role_label}</p>
          <small>
            {h.caller_name ? `Caller: ${h.caller_name} · ` : ""}Recorded by:{" "}
            {h.recorder_name}
          </small>
          {h.notes && <p className="placement-notes">{h.notes}</p>}
          {h.follow_up && <p>Follow up: {formatDate(h.follow_up)}</p>}
        </article>
      ))}
    </div>
  );
}
export function PersonContactHistory({
  supabase,
  personId,
}: {
  supabase: SupabaseClient;
  personId: string;
}) {
  const [entries, setEntries] = useState<ContactEntry[]>([]);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(true);
  useEffect(() => {
    let active = true;
    void allRows<ContactEntry>(
      supabase,
      "volunteer_contact_history",
      "created_at",
      personId,
    )
      .then((rows) => {
        if (active) setEntries(rows.reverse());
      })
      .catch((e) => {
        if (active) setError(normalizeError(e));
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [supabase, personId]);
  return (
    <section>
      <h3>Volunteer Contact History</h3>
      <p>
        Private church records. Responses apply to the opportunity discussed.
      </p>
      {loading ? (
        <p>Loading history…</p>
      ) : error ? (
        <p role="alert">{error}</p>
      ) : (
        <ContactHistory entries={entries} />
      )}
    </section>
  );
}
export function PlacementWorkflow({
  supabase,
  snapshot,
  profile,
  onChanged,
  initialView = "openings",
}: {
  supabase: SupabaseClient;
  snapshot: Snapshot;
  profile: Profile;
  onChanged: () => Promise<void>;
  initialView?: string;
}) {
  const [openings, setOpenings] = useState<Opening[]>([]),
    [candidates, setCandidates] = useState<Candidate[]>([]),
    [history, setHistory] = useState<ContactEntry[]>([]),
    [staff, setStaff] = useState<Staff[]>([]);
  const [view, setView] = useState(initialView),
    [selected, setSelected] = useState(""),
    [busy, setBusy] = useState(false),
    [error, setError] = useState(""),
    [notice, setNotice] = useState(""),
    [loaded, setLoaded] = useState(false);
  const canEdit = ["admin", "editor"].includes(profile.app_role);
  const admin = profile.app_role === "admin";
  const load = useCallback(async () => {
    const [o, c, h, s] = await Promise.all([
      allRows<Opening>(supabase, "placement_openings", "created_at"),
      allRows<Candidate>(supabase, "placement_candidates", "created_at"),
      allRows<ContactEntry>(
        supabase,
        "volunteer_contact_history",
        "created_at",
      ),
      supabase.rpc("placement_staff"),
    ]);
    if (s.error) throw s.error;
    setOpenings(o);
    setCandidates(c);
    setHistory(h.reverse());
    setStaff(s.data ?? []);
    setLoaded(true);
  }, [supabase]);
  useEffect(() => {
    let active = true;
    void Promise.all([
      allRows<Opening>(supabase, "placement_openings", "created_at"),
      allRows<Candidate>(supabase, "placement_candidates", "created_at"),
      allRows<ContactEntry>(
        supabase,
        "volunteer_contact_history",
        "created_at",
      ),
      supabase.rpc("placement_staff"),
    ])
      .then(([o, c, h, s]) => {
        if (!active) return;
        if (s.error) throw s.error;
        setOpenings(o);
        setCandidates(c);
        setHistory(h.reverse());
        setStaff(s.data ?? []);
        setLoaded(true);
      })
      .catch((e) => {
        if (active) setError(normalizeError(e));
      });
    return () => {
      active = false;
    };
  }, [supabase]);
  async function command(action: string, data: Record<string, unknown>) {
    setBusy(true);
    setError("");
    setNotice("");
    try {
      const { error } = await supabase.rpc("placement_command", {
        p_action: action,
        p_data: data,
      });
      if (error) throw error;
      await load();
      await onChanged();
      setNotice("Saved.");
      return true;
    } catch (e) {
      setError(normalizeError(e));
      return false;
    } finally {
      setBusy(false);
    }
  }
  const label = (o: Opening) =>
    [
      snapshot.ministries.find((r) => r.id === o.role_id)?.name,
      snapshot.positions.find((p) => p.id === o.sub_role_id)?.name,
      snapshot.terms.find((t) => t.id === o.term_id)?.name,
    ]
      .filter(Boolean)
      .join(" · ");
  const pending = (c: Candidate) =>
    ["nominated", "first_reading", "second_reading", "deferred"].includes(
      c.stage,
    );
  const currentOpening = openings.find((o) => o.id === selected);
  const displayed = candidates.filter((c) =>
    view === "calls"
      ? c.assigned_to === profile.user_id &&
        openings.some((o) => o.id === c.opening_id && o.status === "open") &&
        !["elected", "appointed", "withdrawn", "not_elected"].includes(
          c.stage,
        ) &&
        (!["yes", "no"].includes(c.response) || !!c.follow_up)
      : view === "nominations"
        ? pending(c)
        : c.opening_id === selected,
  );
  return (
    <div className="placement-workflow">
      <h2>Placement Process</h2>
      <p>
        Collect candidates, coordinate calls, and complete nominations or
        appointments.
      </p>
      <div className="placement-toolbar">
        <button className="button" onClick={() => setView("openings")}>
          Openings
        </button>
        <button className="button" onClick={() => setView("calls")}>
          My Calls
        </button>
        <button className="button" onClick={() => setView("nominations")}>
          Nominations & Votes
        </button>
        <button
          className="button"
          disabled={busy}
          onClick={() => void load().catch((e) => setError(normalizeError(e)))}
        >
          Refresh
        </button>
      </div>
      {error && (
        <p role="alert" className="admin-banner error">
          {error}
        </p>
      )}
      {notice && <p role="status">{notice}</p>}
      {!loaded && !error && <p>Loading placement process…</p>}
      {view === "openings" && (
        <>
          {canEdit && (
            <NewOpening
              snapshot={snapshot}
              busy={busy}
              save={(data) => command("opening", data)}
            />
          )}
          <label>
            Opening
            <select
              value={selected}
              onChange={(e) => setSelected(e.target.value)}
            >
              <option value="">Choose an opening</option>
              {openings.map((o) => (
                <option key={o.id} value={o.id}>
                  {label(o)} — {o.status} (
                  {
                    candidates.filter(
                      (c) =>
                        c.opening_id === o.id &&
                        ["elected", "appointed"].includes(c.stage),
                    ).length
                  }
                  /{o.quantity} filled)
                </option>
              ))}
            </select>
          </label>
          {currentOpening && (
            <section className="admin-card">
              <h3>{label(currentOpening)}</h3>
              <p>
                {currentOpening.quantity} needed ·{" "}
                {stageLabel(currentOpening.status)} ·{" "}
                {
                  candidates.filter(
                    (c) => c.opening_id === currentOpening.id && pending(c),
                  ).length
                }{" "}
                pending nominees
              </p>
              {currentOpening.notes && <p>{currentOpening.notes}</p>}
              {canEdit && currentOpening.status === "open" && (
                <>
                  <AddCandidate
                    people={snapshot.people.filter(
                      (p) =>
                        p.is_active &&
                        !candidates.some(
                          (c) =>
                            c.opening_id === selected && c.person_id === p.id,
                        ),
                    )}
                    busy={busy}
                    save={(person_id) =>
                      command("candidate", { opening_id: selected, person_id })
                    }
                  />
                  <button
                    className="button"
                    disabled={busy}
                    onClick={() => {
                      if (
                        window.confirm(
                          "Close this opening? Candidate and contact history will be retained.",
                        )
                      )
                        void command("cancel_opening", {
                          opening_id: selected,
                        });
                    }}
                  >
                    Close opening
                  </button>
                </>
              )}
            </section>
          )}
        </>
      )}
      {view === "calls" && (
        <p>
          Calls assigned to you, including follow-ups. A No or Yes response
          leaves this list unless another follow-up is scheduled.
        </p>
      )}
      {view === "nominations" && (
        <>
          <p>
            Pending nominees do not count as active volunteers. Actual reading
            and vote dates are recorded separately.
          </p>
          <details className="admin-card">
            <summary>Bulletin text</summary>
            <h3>First reading — pending publication</h3>
            <pre className="placement-notes">
              {candidates
                .filter((c) => c.stage === "nominated")
                .map(
                  (c) =>
                    `${personName(snapshot.people.find((p) => p.id === c.person_id)!)} — ${label(openings.find((o) => o.id === c.opening_id)!)}`,
                )
                .join("\n") || "None"}
            </pre>
            <h3>Second reading — pending publication and vote</h3>
            <pre className="placement-notes">
              {candidates
                .filter((c) => c.stage === "first_reading")
                .map(
                  (c) =>
                    `${personName(snapshot.people.find((p) => p.id === c.person_id)!)} — ${label(openings.find((o) => o.id === c.opening_id)!)}`,
                )
                .join("\n") || "None"}
            </pre>
          </details>
        </>
      )}
      {loaded && view !== "openings" && !displayed.length && (
        <p>Nothing in this list.</p>
      )}
      {displayed.map((c) => {
        const person = snapshot.people.find((p) => p.id === c.person_id),
          o = openings.find((o) => o.id === c.opening_id);
        if (!person || !o) return null;
        return (
          <CandidateCard
            key={`${c.id}:${c.assigned_to}`}
            candidate={c}
            person={person}
            opening={o}
            title={label(o)}
            snapshot={snapshot}
            staff={staff}
            history={history.filter((h) => h.person_id === person.id)}
            otherCalls={candidates
              .filter(
                (other) =>
                  other.person_id === person.id &&
                  other.id !== c.id &&
                  other.assigned_to &&
                  openings.some(
                    (x) => x.id === other.opening_id && x.status === "open",
                  ),
              )
              .map(
                (other) =>
                  `${label(openings.find((x) => x.id === other.opening_id)!)} (${staff.find((s) => s.user_id === other.assigned_to)?.display_name ?? "assigned caller"})`,
              )}
            profile={profile}
            busy={busy}
            canEdit={canEdit}
            admin={admin}
            command={command}
          />
        );
      })}
    </div>
  );
}
function NewOpening({
  snapshot,
  busy,
  save,
}: {
  snapshot: Snapshot;
  busy: boolean;
  save: (d: Record<string, unknown>) => Promise<boolean>;
}) {
  const [role, setRole] = useState(""),
    [position, setPosition] = useState(""),
    [term, setTerm] = useState(""),
    [quantity, setQuantity] = useState(1),
    [notes, setNotes] = useState("");
  return (
    <details className="admin-card">
      <summary>Create opening</summary>
      <form
        className="admin-form-stack"
        onSubmit={async (e) => {
          e.preventDefault();
          if (
            await save({
              role_id: role,
              sub_role_id: position || null,
              term_id: term || null,
              quantity,
              notes,
            })
          ) {
            setNotes("");
          }
        }}
      >
        <label>
          Ministry
          <select
            required
            value={role}
            onChange={(e) => {
              setRole(e.target.value);
              setPosition("");
            }}
          >
            <option value="">Choose ministry</option>
            {snapshot.ministries
              .filter((r) => r.is_active)
              .map((r) => (
                <option key={r.id} value={r.id}>
                  {r.name}
                </option>
              ))}
          </select>
        </label>
        <label>
          Position
          <select
            value={position}
            onChange={(e) => setPosition(e.target.value)}
          >
            <option value="">Team member (no church vote)</option>
            {snapshot.positions
              .filter((p) => p.role_id === role && p.is_active)
              .map((p) => (
                <option key={p.id} value={p.id}>
                  {p.name}
                </option>
              ))}
          </select>
        </label>
        <label>
          Term
          <select value={term} onChange={(e) => setTerm(e.target.value)}>
            <option value="">No term</option>
            {snapshot.terms
              .filter((t) => t.is_active)
              .map((t) => (
                <option key={t.id} value={t.id}>
                  {t.name}
                </option>
              ))}
          </select>
        </label>
        <label>
          People needed
          <input
            type="number"
            required
            min={1}
            max={100}
            value={quantity}
            onChange={(e) => setQuantity(Number(e.target.value))}
          />
        </label>
        <label>
          Committee notes
          <textarea
            maxLength={10000}
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
          />
        </label>
        <button className="button button-primary" disabled={busy || !role}>
          Create Opening
        </button>
      </form>
    </details>
  );
}
function AddCandidate({
  people,
  busy,
  save,
}: {
  people: Person[];
  busy: boolean;
  save: (id: string) => Promise<boolean>;
}) {
  const [query, setQuery] = useState(""),
    [person, setPerson] = useState("");
  return (
    <form
      className="admin-form-stack"
      onSubmit={async (e) => {
        e.preventDefault();
        if (await save(person)) setPerson("");
      }}
    >
      <label>
        Find a candidate
        <input
          type="search"
          value={query}
          onChange={(e) => {
            setQuery(e.target.value);
            setPerson("");
          }}
        />
      </label>
      <label>
        Candidate
        <select
          required
          value={person}
          onChange={(e) => setPerson(e.target.value)}
        >
          <option value="">Choose person</option>
          {people
            .filter((p) =>
              personName(p).toLowerCase().includes(query.toLowerCase()),
            )
            .map((p) => (
              <option value={p.id} key={p.id}>
                {personName(p)}
              </option>
            ))}
        </select>
      </label>
      <button className="button" disabled={busy || !person}>
        Add Candidate
      </button>
    </form>
  );
}
export function CandidateCard({
  candidate: c,
  person,
  opening: o,
  title,
  snapshot,
  staff,
  history,
  otherCalls,
  profile,
  busy,
  canEdit,
  admin,
  command,
}: {
  candidate: Candidate;
  person: Person;
  opening: Opening;
  title: string;
  snapshot: Snapshot;
  staff: Staff[];
  history: ContactEntry[];
  otherCalls: string[];
  profile: Profile;
  busy: boolean;
  canEdit: boolean;
  admin: boolean;
  command: (action: string, data: Record<string, unknown>) => Promise<boolean>;
}) {
  const [assignee, setAssignee] = useState(c.assigned_to ?? ""),
    [caller, setCaller] = useState(profile.user_id),
    [response, setResponse] = useState("considering"),
    [notes, setNotes] = useState(""),
    [date, setDate] = useState(todayISO()),
    [followUp, setFollowUp] = useState(""),
    [callDate, setCallDate] = useState(todayISO());
  const closed =
    ["elected", "appointed", "withdrawn", "not_elected"].includes(c.stage) ||
    o.status !== "open";
  const requirement =
    c.requires_vote ??
    (!!o.sub_role_id &&
      (snapshot.ministries.find((r) => r.id === o.role_id)?.requires_vote ||
        snapshot.positions.find((p) => p.id === o.sub_role_id)?.requires_vote));
  const act = (action: string) =>
    command(action, { candidate_id: c.id, date, notes });
  return (
    <article className="admin-card placement-candidate">
      <h3>{personName(person)}</h3>
      <p>{title}</p>
      <ContactLinks person={person} />
      <p>
        <strong>
          {responseLabels[c.response]} · {stageLabel(c.stage)}
        </strong>
      </p>
      <p>
        Caller:{" "}
        {staff.find((s) => s.user_id === c.assigned_to)?.display_name ??
          "Unassigned"}
        {c.follow_up &&
          ` · Follow up ${formatDate(c.follow_up)}${c.follow_up <= todayISO() ? " — due" : ""}`}
      </p>
      {otherCalls.length > 0 && (
        <p>Also being approached: {otherCalls.join("; ")}</p>
      )}
      <p>
        Current commitments:{" "}
        {snapshot.assignments
          .filter((a) => a.person_id === person.id && isCurrent(a))
          .map(
            (a) =>
              a.role_name + (a.sub_role_name ? ` · ${a.sub_role_name}` : ""),
          )
          .join("; ") || "None recorded"}
      </p>
      {admin && !closed && (
        <details>
          <summary>Assign call</summary>
          <label>
            Caller
            <select
              value={assignee}
              onChange={(e) => setAssignee(e.target.value)}
            >
              <option value="">Unassigned</option>
              {staff.map((s) => (
                <option key={s.user_id} value={s.user_id}>
                  {s.display_name} ({s.app_role})
                </option>
              ))}
            </select>
          </label>
          <label>
            Follow-up date
            <input
              type="date"
              value={followUp}
              onChange={(e) => setFollowUp(e.target.value)}
            />
          </label>
          <button
            className="button"
            disabled={busy}
            onClick={() =>
              void command("assign_call", {
                candidate_id: c.id,
                caller_id: assignee || null,
                follow_up: followUp || null,
              })
            }
          >
            Save Assignment
          </button>
        </details>
      )}
      {canEdit && (
        <details>
          <summary>Record a call</summary>
          <form
            className="admin-form-stack"
            onSubmit={async (e) => {
              e.preventDefault();
              if (
                await command("call", {
                  candidate_id: c.id,
                  caller_id: admin ? caller : profile.user_id,
                  response,
                  notes,
                  date: callDate,
                  follow_up: followUp || null,
                })
              )
                setNotes("");
            }}
          >
            {admin ? (
              <label>
                Call made by
                <select
                  value={caller}
                  onChange={(e) => setCaller(e.target.value)}
                >
                  {staff.map((s) => (
                    <option key={s.user_id} value={s.user_id}>
                      {s.display_name}
                    </option>
                  ))}
                </select>
              </label>
            ) : (
              <p>
                Call made by you. Only an admin can enter another caller’s
                results.
              </p>
            )}
            <label>
              Call date
              <input
                type="date"
                required
                max={todayISO()}
                value={callDate}
                onChange={(e) => setCallDate(e.target.value)}
              />
            </label>
            <label>
              Response
              <select
                value={response}
                onChange={(e) => setResponse(e.target.value)}
              >
                {Object.entries(responseLabels).map(([key, label]) => (
                  <option key={key} value={key}>
                    {label}
                  </option>
                ))}
              </select>
            </label>
            <label>
              Notes
              <textarea
                maxLength={10000}
                required={response === "other"}
                value={notes}
                onChange={(e) => setNotes(e.target.value)}
              />
            </label>
            <label>
              Follow-up date (optional)
              <input
                type="date"
                min={callDate}
                value={followUp}
                onChange={(e) => setFollowUp(e.target.value)}
              />
            </label>
            <button className="button button-primary" disabled={busy}>
              Save Call to Person’s History
            </button>
          </form>
        </details>
      )}
      {canEdit && !closed && (
        <section>
          <h4>Selection and approval</h4>
          <p>
            {requirement
              ? "Church vote required"
              : "Appointment — no church vote required"}
          </p>
          {c.nominated_on && <p>Nominated: {formatDate(c.nominated_on)}</p>}
          {c.first_reading && (
            <p>First reading: {formatDate(c.first_reading)}</p>
          )}
          {c.second_reading && (
            <p>Second reading: {formatDate(c.second_reading)}</p>
          )}
          <label>
            Actual action date
            <input
              type="date"
              required
              max={todayISO()}
              value={date}
              onChange={(e) => setDate(e.target.value)}
            />
          </label>
          <label>
            Action notes
            <textarea
              maxLength={10000}
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
            />
          </label>
          <div className="placement-actions">
            {c.stage === "considering" && c.response === "yes" && (
              <button
                className="button button-primary"
                disabled={busy || !date}
                onClick={() => void act(requirement ? "nominate" : "appoint")}
              >
                {requirement
                  ? "Nominate — Pending Church Vote"
                  : "Appoint Volunteer"}
              </button>
            )}
            {c.stage === "nominated" && (
              <button
                className="button"
                disabled={busy || !date}
                onClick={() => void act("first_reading")}
              >
                Record First Reading
              </button>
            )}
            {c.stage === "first_reading" && (
              <button
                className="button"
                disabled={busy || !date}
                onClick={() => void act("second_reading")}
              >
                Record Second Reading
              </button>
            )}
            {c.stage === "second_reading" && (
              <>
                <button
                  className="button button-primary"
                  disabled={busy || !date}
                  onClick={() => void act("vote_passed")}
                >
                  Vote Passed — Activate
                </button>
                <button
                  className="button"
                  disabled={busy || !date}
                  onClick={() => {
                    if (window.confirm("Record an unsuccessful vote?"))
                      void act("vote_failed");
                  }}
                >
                  Vote Did Not Pass
                </button>
              </>
            )}
            {["nominated", "first_reading", "second_reading"].includes(
              c.stage,
            ) && (
              <button
                className="button"
                disabled={busy || !date}
                onClick={() => void act("defer")}
              >
                Defer
              </button>
            )}
            {c.stage === "deferred" && (
              <button
                className="button"
                disabled={busy || !date}
                onClick={() => void act("resume")}
              >
                Resume Nomination
              </button>
            )}
            <button
              className="button"
              disabled={busy || !date}
              onClick={() => {
                if (
                  window.confirm(
                    "Withdraw this candidate? History will be retained.",
                  )
                )
                  void act("withdraw");
              }}
            >
              Withdraw Candidate
            </button>
          </div>
        </section>
      )}
      <details>
        <summary>Person’s volunteer contact history ({history.length})</summary>
        <ContactHistory entries={history} />
      </details>
    </article>
  );
}
