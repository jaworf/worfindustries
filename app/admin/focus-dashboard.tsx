"use client";
import { useEffect, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  type Snapshot,
  type Person,
  type AssignmentRoute,
  type MutationRunner,
  personName,
  isCurrent,
  todayISO,
  formatDate,
  ordinationKind,
  ordinationField,
} from "./admin-shared";
type FocusKey = "ordination" | "ending" | "ministries" | "activation";
export function FocusDashboard({
  supabase,
  snapshot,
  canEdit,
  working,
  mutate,
  onAssign,
  onVotes,
}: {
  supabase: SupabaseClient;
  snapshot: Snapshot;
  canEdit: boolean;
  working: boolean;
  mutate: MutationRunner;
  onAssign: (r: AssignmentRoute) => void;
  onVotes: () => void;
}) {
  const [expanded, setExpanded] = useState<FocusKey | null>(null),
    [activation, setActivation] = useState<Person[]>([]),
    [error, setError] = useState(""),
    [pendingVotes, setPendingVotes] = useState(0);
  useEffect(() => {
    let live = true;
    void Promise.all([
      supabase.rpc("volunteer_activation"),
      supabase
        .from("placement_candidates")
        .select("id")
        .in("stage", [
          "nominated",
          "first_reading",
          "second_reading",
          "deferred",
        ]),
    ]).then(([activation, nominations]) => {
      if (!live) return;
      if (activation.error) setError(activation.error.message);
      else setActivation(activation.data ?? []);
      setPendingVotes(nominations.data?.length ?? 0);
    });
    return () => {
      live = false;
    };
  }, [supabase, snapshot]);
  const current = snapshot.assignments.filter(isCurrent),
    votes = current.filter((a) => a.vote_missing);
  const cutoff = new Date();
  cutoff.setMonth(cutoff.getMonth() + 6);
  const ending = current.filter(
    (a) =>
      a.end_date &&
      a.end_date >= todayISO() &&
      a.end_date <= cutoff.toISOString().slice(0, 10),
  );
  const occupied = new Set(current.map((a) => a.role_id));
  const empty = snapshot.ministries.filter(
    (m) => m.is_active && !occupied.has(m.id),
  );
  const ordinations = [
    ...new Map(
      current.flatMap((a) => {
        const kind = ordinationKind(a.role_name),
          person = snapshot.people.find((p) => p.id === a.person_id);
        return kind && person?.is_active && !person[ordinationField(kind)]
          ? [[person.id + kind, { kind, person, assignment: a }] as const]
          : [];
      }),
    ).values(),
  ];
  const groups = [
    {
      key: "votes",
      title: "Needing Votes",
      count: votes.length + pendingVotes,
      description: "Open the church-vote action page.",
    },
    {
      key: "ordination",
      title: "Ordination Actions",
      count: ordinations.length,
      description: "Record permanent ordination status.",
    },
    {
      key: "ending",
      title: "Terms ending in next 6 months",
      count: ending.length,
      description: "Plan upcoming transitions.",
    },
    {
      key: "ministries",
      title: "Ministries needing volunteers",
      count: empty.length,
      description: "Find ministries with no active volunteer.",
    },
    {
      key: "activation",
      title: "Volunteer Activation",
      count: activation.length,
      description: "The 100 newest eligible Planning Center contacts.",
    },
  ];
  const group = groups.find((g) => g.key === expanded);
  return (
    <>
      <div className="admin-section-heading">
        <h2>Placement Focus</h2>
        <p>
          Choose a card to work on one area. Highlighted cards need attention.
        </p>
      </div>
      {!expanded ? (
        <div className="focus-card-grid">
          {groups.map((g) => (
            <button
              id={"focus-card-" + g.key}
              className={
                "focus-summary-card " + (g.count ? "needs-attention" : "clear")
              }
              key={g.key}
              onClick={() =>
                g.key === "votes" ? onVotes() : setExpanded(g.key as FocusKey)
              }
            >
              <span>{g.title}</span>
              <strong>{g.count}</strong>
              <small>{g.description}</small>
            </button>
          ))}
        </div>
      ) : (
        <section className="admin-card focus-expanded">
          <header>
            <button
              className="focus-expanded-title"
              onClick={() => setExpanded(null)}
            >
              <h3>{group?.title}</h3>
              <span>{group?.count} items</span>
            </button>
            <button className="button" onClick={() => setExpanded(null)}>
              Close
            </button>
          </header>
          {expanded === "activation" && (
            <p>
              Newest Planning Center creation dates first, limited to 100 people
              who are not currently volunteering. Administrators choose eligible
              membership types in Settings → Planning Center.
            </p>
          )}
          {expanded === "activation" && error && <p role="alert">{error}</p>}
          <ul className="admin-focus-list">
            {expanded === "activation" &&
              activation.map((p) => (
                <li key={p.id}>
                  <div>
                    <strong>{personName(p)}</strong>
                    <p>
                      {p.membership_status ?? "No membership type"} · Added{" "}
                      {p.source_created_at
                        ? formatDate(p.source_created_at.slice(0, 10))
                        : "date unavailable"}
                    </p>
                  </div>
                  {canEdit && (
                    <button
                      className="button"
                      onClick={() => onAssign({ personId: p.id })}
                    >
                      Assign ministry
                    </button>
                  )}
                </li>
              ))}
            {expanded === "ministries" &&
              empty.map((m) => (
                <li key={m.id}>
                  <strong>{m.name}</strong>
                  {canEdit && (
                    <button
                      className="button"
                      onClick={() => onAssign({ ministryId: m.id })}
                    >
                      Assign volunteer
                    </button>
                  )}
                </li>
              ))}
            {expanded === "ending" &&
              ending.map((a) => (
                <li key={a.id}>
                  <div>
                    <strong>{a.person_name}</strong>
                    <p>
                      {a.role_name} · Ends {formatDate(a.end_date)}
                    </p>
                  </div>
                  {canEdit && (
                    <button
                      className="button"
                      onClick={() =>
                        onAssign({
                          personId: a.person_id,
                          ministryId: a.role_id,
                        })
                      }
                    >
                      Plan placement
                    </button>
                  )}
                </li>
              ))}
            {expanded === "ordination" &&
              ordinations.map(({ person, kind, assignment }) => (
                <li key={person.id + kind}>
                  <div>
                    <strong>{personName(person)}</strong>
                    <p>{assignment.role_name}</p>
                  </div>
                  {canEdit && (
                    <button
                      className="button"
                      disabled={working}
                      onClick={() =>
                        void mutate("Ordination record updated.", async () => {
                          const { error } = await supabase
                            .from("people")
                            .update({ [ordinationField(kind)]: true })
                            .eq("id", person.id);
                          if (error) throw error;
                        })
                      }
                    >
                      Mark ordained
                    </button>
                  )}
                </li>
              ))}
          </ul>
          {group?.count === 0 && (
            <p>Nothing needs attention in this section.</p>
          )}
        </section>
      )}
    </>
  );
}
