"use client";
import { SearchSelect } from "./search-select";
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
  votesOnly = false,
}: {
  supabase: SupabaseClient;
  snapshot: Snapshot;
  profile: Profile;
  onChanged: () => Promise<void>;
  initialView?: string;
  votesOnly?: boolean;
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
      const { data: result, error } = await supabase.rpc("placement_command", {
        p_action: action,
        p_data: data,
      });
      if (error) throw error;
      await load();
      await onChanged();
      if (action === "opening") setSelected(result.id);
      if (
        ["cancel_opening", "finish_opening", "restore_opening"].includes(action)
      )
        setSelected("");
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
  const activeOpenings = openings.filter((o) => o.status === "open");
  const shownOpenings = openings.filter((o) =>
    view === "trash"
      ? o.status === "cancelled"
      : view === "completed"
        ? o.status === "filled"
        : o.status === "open",
  );
  return (
    <div className="placement-workflow">
      <h2>{votesOnly ? "Needing Votes" : "Placement Process"}</h2>
      <p>
        {votesOnly
          ? "Record bulletin readings and church votes for pending nominations."
          : "Choose an opening to work with its candidates, calls and nominations."}
      </p>
      <div className="placement-toolbar">
        {!votesOnly &&
          [
            ["openings", "Openings"],
            ["calls", "My Calls"],
            ["nominations", "Nominations & Votes"],
            ["completed", "Completed"],
            ["trash", "Trash"],
          ].map(([key, name]) => (
            <button
              className={"button " + (view === key ? "button-primary" : "")}
              key={key}
              onClick={() => {
                setView(key);
                setSelected("");
              }}
            >
              {name}
              {key === "openings" ? ` (${activeOpenings.length})` : ""}
            </button>
          ))}
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
      {["openings", "completed", "trash"].includes(view) && (
        <>
          {view === "openings" && canEdit && (
            <NewOpening
              key={openings.length}
              snapshot={snapshot}
              busy={busy}
              openings={openings}
              save={(data) => command("opening", data)}
            />
          )}
          <div className="opening-grid">
            {shownOpenings.map((o) => (
              <button
                key={o.id}
                className={
                  "opening-card " + (selected === o.id ? "selected" : "")
                }
                onClick={() => setSelected(selected === o.id ? "" : o.id)}
                aria-expanded={selected === o.id}
              >
                <strong>{label(o)}</strong>
                <span>
                  {
                    candidates.filter(
                      (c) =>
                        c.opening_id === o.id &&
                        !["withdrawn", "not_elected"].includes(c.stage),
                    ).length
                  }{" "}
                  candidates ·{" "}
                  {
                    candidates.filter(
                      (c) => c.opening_id === o.id && pending(c),
                    ).length
                  }{" "}
                  pending nominations
                </span>
                <small>
                  {selected === o.id ? "Close details" : "Open details →"}
                </small>
              </button>
            ))}
          </div>
          {!shownOpenings.length && loaded && (
            <p>
              {view === "trash"
                ? "Trash is empty."
                : "No openings in this view."}
            </p>
          )}
          {currentOpening && (
            <section className="admin-card">
              <div className="placement-section-heading">
                <h3>{label(currentOpening)}</h3>
                <button className="button" onClick={() => setSelected("")}>
                  Close
                </button>
              </div>
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
                  <div className="placement-actions">
                    <button
                      className="button"
                      disabled={busy}
                      onClick={() =>
                        void command("finish_opening", { opening_id: selected })
                      }
                    >
                      Finish Recruiting
                    </button>
                    <button
                      className="button"
                      disabled={busy}
                      onClick={() => {
                        if (
                          window.confirm(
                            "Move this opening to Trash? Candidate and call history will be kept.",
                          )
                        )
                          void command("cancel_opening", {
                            opening_id: selected,
                          });
                      }}
                    >
                      Move to Trash
                    </button>
                  </div>
                </>
              )}
              {canEdit && currentOpening.status !== "open" && (
                <button
                  className="button"
                  disabled={busy}
                  onClick={() =>
                    void command("restore_opening", { opening_id: selected })
                  }
                >
                  Reopen Recruitment
                </button>
              )}
            </section>
          )}
        </>
      )}
      {view === "calls" && <p>Calls assigned to you and follow-ups due.</p>}
      {view === "nominations" && (
        <details className="admin-card">
          <summary>Bulletin text</summary>
          {[
            ["nominated", "First reading"],
            ["first_reading", "Second reading"],
          ].map(([stage, heading]) => (
            <section key={stage}>
              <h3>{heading}</h3>
              <pre className="placement-notes">
                {candidates
                  .filter((c) => c.stage === stage)
                  .map(
                    (c) =>
                      `${personName(snapshot.people.find((p) => p.id === c.person_id)!)} — ${label(openings.find((o) => o.id === c.opening_id)!)}`,
                  )
                  .join("\n") || "None"}
              </pre>
            </section>
          ))}
        </details>
      )}
      {displayed.map((c) => {
        const person = snapshot.people.find((p) => p.id === c.person_id),
          o = openings.find((o) => o.id === c.opening_id);
        if (!person || !o) return null;
        return (
          <CandidateCard
            key={c.id}
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
  openings,
}: {
  snapshot: Snapshot;
  busy: boolean;
  save: (d: Record<string, unknown>) => Promise<boolean>;
  openings: Opening[];
}) {
  const [role, setRole] = useState(""),
    [position, setPosition] = useState("none"),
    [term, setTerm] = useState("none"),
    [notes, setNotes] = useState(""),
    [newRole, setNewRole] = useState(""),
    [newPosition, setNewPosition] = useState(""),
    [vote, setVote] = useState(false),
    [expanded, setExpanded] = useState(false),
    [newTerm, setNewTerm] = useState(""),
    [termStart, setTermStart] = useState(""),
    [termEnd, setTermEnd] = useState("");
  const duplicate = openings.some(
    (o) =>
      o.status === "open" &&
      o.role_id === role &&
      (o.sub_role_id ?? "none") === position &&
      (o.term_id ?? "none") === term,
  );
  const requirement =
    position !== "none" &&
    (snapshot.ministries.find((r) => r.id === role)?.requires_vote ||
      (position === "new"
        ? vote
        : snapshot.positions.find((p) => p.id === position)?.requires_vote));
  return (
    <section className="admin-card">
      <button
        type="button"
        className="opening-create-toggle"
        aria-expanded={expanded}
        onClick={() => setExpanded((v) => !v)}
      >
        ＋ Create Opening
      </button>
      {expanded && (
        <form
          className="admin-form-stack"
          onSubmit={async (e) => {
            e.preventDefault();
            if (duplicate) return;
            const ok = await save({
              role_id: role === "new" ? null : role,
              new_role_name: role === "new" ? newRole : null,
              sub_role_id: ["new", "none"].includes(position) ? null : position,
              new_position_name: position === "new" ? newPosition : null,
              new_position_vote: vote,
              term_id: ["none", "new"].includes(term) ? null : term,
              new_term_name: term === "new" ? newTerm : null,
              term_start: termStart || null,
              term_end: termEnd || null,
              notes,
            });
            if (ok) {
              setNotes("");
              setExpanded(false);
            }
          }}
        >
          <div className="admin-form-grid">
            <SearchSelect
              label="Ministry"
              value={role}
              required
              options={[
                ...snapshot.ministries
                  .filter((r) => r.is_active)
                  .map((r) => ({ value: r.id, label: r.name })),
                ...(role === "new" ? [{ value: "new", label: newRole }] : []),
              ]}
              onChange={(v) => {
                setRole(v);
                setPosition("none");
              }}
              onCreate={(name) => {
                setNewRole(name);
                setRole("new");
                setPosition("none");
              }}
              createLabel="Create a new ministry"
            />
            <SearchSelect
              label="Position"
              value={position}
              disabled={!role}
              options={[
                { value: "none", label: "Team member — no position" },
                ...snapshot.positions
                  .filter((p) => p.role_id === role && p.is_active)
                  .map((p) => ({ value: p.id, label: p.name })),
                ...(position === "new"
                  ? [{ value: "new", label: newPosition }]
                  : []),
              ]}
              onChange={setPosition}
              onCreate={(name) => {
                setNewPosition(name);
                setPosition("new");
              }}
              createLabel="Create a new position"
            />
            <SearchSelect
              label={requirement ? "Term (required)" : "Term"}
              value={term}
              options={[
                { value: "none", label: "No term" },
                ...snapshot.terms
                  .filter((t) => t.is_active)
                  .map((t) => ({ value: t.id, label: t.name })),
                ...(term === "new" ? [{ value: "new", label: newTerm }] : []),
              ]}
              onChange={setTerm}
              onCreate={(name) => {
                setNewTerm(name);
                setTerm("new");
              }}
              createLabel="Create a new term"
            />
          </div>
          {term === "new" && (
            <div className="admin-form-grid">
              <label>
                Term start
                <input
                  type="date"
                  required
                  value={termStart}
                  onChange={(e) => setTermStart(e.target.value)}
                />
              </label>
              <label>
                Term end
                <input
                  type="date"
                  required
                  min={termStart}
                  value={termEnd}
                  onChange={(e) => setTermEnd(e.target.value)}
                />
              </label>
            </div>
          )}
          {position === "new" && (
            <label className="admin-check-row">
              <input
                type="checkbox"
                checked={vote}
                onChange={(e) => setVote(e.target.checked)}
              />
              Position requires a church vote
            </label>
          )}
          {requirement && term === "none" && (
            <p>Choose a term for this voted position.</p>
          )}
          <label>
            Committee notes
            <textarea
              maxLength={10000}
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
            />
          </label>
          {duplicate && (
            <p role="alert">
              An open recruitment already exists for this ministry, position and
              term. Open its card below instead.
            </p>
          )}
          <button
            className="button button-primary"
            disabled={
              busy ||
              !role ||
              !position ||
              !term ||
              duplicate ||
              (requirement && term === "none")
            }
          >
            Create Opening
          </button>
        </form>
      )}
    </section>
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
  const [person, setPerson] = useState("");
  return (
    <form
      className="candidate-add"
      onSubmit={async (e) => {
        e.preventDefault();
        if (person && (await save(person))) setPerson("");
      }}
    >
      <SearchSelect
        label="Add a candidate"
        value={person}
        required
        options={people.map((p) => ({
          value: p.id,
          label: personName(p),
          detail: [p.email, p.mobile_phone].filter(Boolean).join(" · "),
        }))}
        onChange={setPerson}
      />
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
  defaultExpanded = false,
}: {
  defaultExpanded?: boolean;
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
  const [expanded, setExpanded] = useState(defaultExpanded);
  const [assignee, setAssignee] = useState(c.assigned_to ?? "none"),
    [caller, setCaller] = useState(
      admin ? (c.assigned_to ?? profile.user_id) : profile.user_id,
    ),
    [response, setResponse] = useState(""),
    [notes, setNotes] = useState(""),
    [actionNotes, setActionNotes] = useState(""),
    [date, setDate] = useState(todayISO()),
    [followUp, setFollowUp] = useState(c.follow_up ?? ""),
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
    command(action, { candidate_id: c.id, date, notes: actionNotes });
  return (
    <article className="admin-card placement-candidate">
      <button
        type="button"
        className="candidate-toggle"
        aria-expanded={expanded}
        onClick={() => setExpanded((v) => !v)}
      >
        <strong>{personName(person)}</strong>
        <span>
          {responseLabels[c.response]} · {stageLabel(c.stage)}
          {c.follow_up ? ` · Follow up ${formatDate(c.follow_up)}` : ""}
        </span>
        <span aria-hidden="true">{expanded ? "▴" : "▾"}</span>
      </button>
      <ContactLinks person={person} />
      <p className="candidate-commitments">
        Current positions:{" "}
        {snapshot.assignments
          .filter((a) => a.person_id === person.id && isCurrent(a))
          .map(
            (a) =>
              a.role_name + (a.sub_role_name ? ` · ${a.sub_role_name}` : ""),
          )
          .join("; ") || "None recorded"}
      </p>
      {expanded && (
        <div className="candidate-workspace">
          <div className="placement-section-heading">
            <h4>{title}</h4>
            <button className="button" onClick={() => setExpanded(false)}>
              Close
            </button>
          </div>
          <p>
            Assigned caller:{" "}
            {staff.find((s) => s.user_id === c.assigned_to)?.display_name ??
              "Unassigned"}
          </p>
          {otherCalls.length > 0 && (
            <p>Also being approached: {otherCalls.join("; ")}</p>
          )}
          {admin && !closed && (
            <section className="call-assignment-panel">
              <h4>Assign call</h4>
              <div className="call-assignment-grid">
                <SearchSelect
                  label="Assign caller"
                  value={assignee}
                  required
                  options={[
                    { value: "none", label: "Unassigned" },
                    ...staff.map((s) => ({
                      value: s.user_id,
                      label: s.display_name,
                      detail: s.app_role,
                    })),
                  ]}
                  onChange={setAssignee}
                />
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
                  disabled={busy || !assignee}
                  onClick={() =>
                    void command("assign_call", {
                      candidate_id: c.id,
                      caller_id: assignee === "none" ? null : assignee,
                      follow_up: followUp || null,
                    })
                  }
                >
                  Save Assignment
                </button>
              </div>
            </section>
          )}
          {canEdit && (
            <section className="call-result-panel">
              <h4>Record a call</h4>
              <form
                className="admin-form-stack call-result-grid"
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
                  <SearchSelect
                    label="Call made by"
                    value={caller}
                    required
                    options={staff.map((s) => ({
                      value: s.user_id,
                      label: s.display_name,
                    }))}
                    onChange={setCaller}
                  />
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
                    <option value="">Choose a response</option>
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
                <button
                  className="button button-primary"
                  disabled={busy || !caller || !response}
                >
                  Save Call to Person’s History
                </button>
              </form>
            </section>
          )}
          {canEdit && !closed && (
            <details
              open={
                c.response === "yes" ||
                [
                  "nominated",
                  "first_reading",
                  "second_reading",
                  "deferred",
                ].includes(c.stage)
              }
            >
              <summary>Selection and approval</summary>
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
                  value={actionNotes}
                  onChange={(e) => setActionNotes(e.target.value)}
                />
              </label>
              <div className="placement-actions">
                {c.stage === "considering" && c.response === "yes" && (
                  <button
                    className="button button-primary"
                    disabled={busy || !date}
                    onClick={() =>
                      void act(requirement ? "nominate" : "appoint")
                    }
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
            </details>
          )}
          <details>
            <summary>
              Person’s volunteer contact history ({history.length})
            </summary>
            <ContactHistory entries={history} />
          </details>
        </div>
      )}
    </article>
  );
}
