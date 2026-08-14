"use client";

import { createClient, type Session, type SupabaseClient } from "@supabase/supabase-js";
import {
  type FormEvent,
  useCallback,
  useEffect,
  useMemo,
  useState,
} from "react";

type AppRole = "admin" | "editor" | "viewer";
type Tab =
  | "focus"
  | "assign"
  | "ministries"
  | "people"
  | "votes"
  | "manage"
  | "reports"
  | "settings";
type OrdinationKind = "deacon" | "deaconess" | "elder";

type Profile = {
  user_id: string;
  display_name: string | null;
  app_role: AppRole;
};

type Person = {
  id: string;
  first_name: string;
  middle_name: string | null;
  last_name: string;
  preferred_name: string | null;
  suffix: string | null;
  email: string | null;
  mobile_phone: string | null;
  home_phone: string | null;
  membership_status: string | null;
  is_active: boolean;
  is_public: boolean;
  is_ordained_deacon: boolean;
  is_ordained_deaconess: boolean;
  is_ordained_elder: boolean;
  source_created_at: string | null;
  created_at: string | null;
};

type Ministry = {
  id: string;
  name: string;
  description: string | null;
  requires_vote: boolean;
  is_active: boolean;
  is_public: boolean;
  display_order: number;
  archived_at: string | null;
};

type Position = {
  id: string;
  role_id: string | null;
  name: string;
  leadership_rank: number;
  requires_vote: boolean;
  is_active: boolean;
};

type Term = {
  id: string;
  name: string;
  start_date: string | null;
  end_date: string | null;
  term_type: string;
  is_active: boolean;
};

type Assignment = {
  id: string;
  person_id: string;
  first_name: string;
  preferred_name: string | null;
  last_name: string;
  person_name: string;
  email: string | null;
  mobile_phone: string | null;
  home_phone: string | null;
  role_id: string;
  role_name: string;
  sub_role_id: string | null;
  sub_role_name: string | null;
  leadership_rank: number;
  term_id: string | null;
  term_name: string | null;
  start_date: string | null;
  end_date: string | null;
  term_type: string | null;
  vote_date: string | null;
  ministry_requires_vote: boolean;
  position_requires_vote: boolean;
  requires_vote: boolean;
  vote_missing: boolean;
  status: string;
  is_public: boolean;
  notes: string | null;
  note_is_public: boolean;
  archived_at: string | null;
  ministry_is_active: boolean;
  ministry_archived_at: string | null;
};

type Snapshot = {
  people: Person[];
  ministries: Ministry[];
  positions: Position[];
  terms: Term[];
  assignments: Assignment[];
};

const emptySnapshot: Snapshot = {
  people: [],
  ministries: [],
  positions: [],
  terms: [],
  assignments: [],
};

const navItems: Array<{ id: Tab; label: string; short: string }> = [
  { id: "focus", label: "Focus", short: "Focus" },
  { id: "assign", label: "Assign", short: "Assign" },
  { id: "ministries", label: "Ministry Directory", short: "Ministries" },
  { id: "people", label: "People Directory", short: "People" },
  { id: "votes", label: "Awaiting Vote", short: "Votes" },
  { id: "manage", label: "Manage", short: "Manage" },
  { id: "reports", label: "Reports", short: "Reports" },
  { id: "settings", label: "Settings", short: "Settings" },
];

function personName(person: Person) {
  return [person.preferred_name || person.first_name, person.last_name, person.suffix]
    .filter(Boolean)
    .join(" ");
}

function ordinationKind(ministryName: string | undefined): OrdinationKind | null {
  const normalized = ministryName?.trim().toLowerCase();
  return normalized === "deacon" || normalized === "deaconess" || normalized === "elder"
    ? normalized
    : null;
}

function ordinationLabel(kind: OrdinationKind) {
  return `Ordained ${kind[0].toUpperCase()}${kind.slice(1)}`;
}

function ordinationLabels(person: Person) {
  const labels: string[] = [];
  if (person.is_ordained_deacon) labels.push("Ordained Deacon");
  if (person.is_ordained_deaconess) labels.push("Ordained Deaconess");
  if (person.is_ordained_elder) labels.push("Ordained Elder");
  return labels;
}

function ordinationField(kind: OrdinationKind) {
  return `is_ordained_${kind}` as
    | "is_ordained_deacon"
    | "is_ordained_deaconess"
    | "is_ordained_elder";
}

function todayISO() {
  const now = new Date();
  const local = new Date(now.getTime() - now.getTimezoneOffset() * 60_000);
  return local.toISOString().slice(0, 10);
}

function formatDate(value: string | null | undefined) {
  if (!value) return "No end date";
  return new Intl.DateTimeFormat("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
  }).format(new Date(`${value}T12:00:00`));
}

function isCurrent(assignment: Assignment) {
  return (
    assignment.status === "active" &&
    assignment.ministry_is_active &&
    (!assignment.end_date || assignment.end_date >= todayISO())
  );
}

function normalizeError(error: unknown) {
  if (error instanceof Error) return error.message;
  if (typeof error === "object" && error && "message" in error) {
    return String((error as { message: unknown }).message);
  }
  return "The request could not be completed.";
}

function membershipPriority(value: string | null) {
  const normalized = value?.trim().toLowerCase() ?? "";
  if (normalized === "riverview member") return 0;
  if (normalized.includes("riverview") && normalized.includes("member")) return 1;
  if (normalized.includes("member")) return 2;
  return 3;
}

export function MinistryAdmin({
  projectUrl,
  publishableKey,
}: {
  projectUrl?: string;
  publishableKey?: string;
}) {
  const supabase = useMemo<SupabaseClient | null>(() => {
    if (!projectUrl || !publishableKey) return null;
    return createClient(projectUrl, publishableKey, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true,
      },
    });
  }, [projectUrl, publishableKey]);

  const [session, setSession] = useState<Session | null>(null);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [snapshot, setSnapshot] = useState<Snapshot>(emptySnapshot);
  const [activeTab, setActiveTab] = useState<Tab>("focus");
  const [booting, setBooting] = useState(true);
  const [loading, setLoading] = useState(false);
  const [working, setWorking] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const canEdit = profile?.app_role === "admin" || profile?.app_role === "editor";

  const loadData = useCallback(
    async (userId: string, quiet = false) => {
      if (!supabase) return;
      if (!quiet) setLoading(true);
      try {
        const [profileResult, peopleResult, ministryResult, positionResult, termResult, assignmentResult] =
          await Promise.all([
            supabase
              .from("profiles")
              .select("user_id,display_name,app_role")
              .eq("user_id", userId)
              .single(),
            supabase.from("people").select("*").order("last_name").order("first_name"),
            supabase.from("roles").select("*").order("display_order").order("name"),
            supabase.from("sub_roles").select("*").order("leadership_rank").order("name"),
            supabase.from("terms").select("*").order("end_date", { ascending: false }),
            supabase
              .from("assignment_details")
              .select("*")
              .order("role_name")
              .order("last_name")
              .order("first_name"),
          ]);

        const firstError = [
          profileResult,
          peopleResult,
          ministryResult,
          positionResult,
          termResult,
          assignmentResult,
        ].find((result) => result.error)?.error;
        if (firstError) throw firstError;
        if (!profileResult.data) {
          throw new Error("This login has not been assigned an app access role.");
        }

        setProfile(profileResult.data as Profile);
        setSnapshot({
          people: (peopleResult.data ?? []) as Person[],
          ministries: (ministryResult.data ?? []) as Ministry[],
          positions: (positionResult.data ?? []) as Position[],
          terms: (termResult.data ?? []) as Term[],
          assignments: (assignmentResult.data ?? []) as Assignment[],
        });
        setError(null);
      } catch (caught) {
        setError(normalizeError(caught));
      } finally {
        if (!quiet) setLoading(false);
      }
    },
    [supabase],
  );

  useEffect(() => {
    if (!supabase) {
      setBooting(false);
      return;
    }
    let active = true;
    void supabase.auth.getSession().then(({ data }) => {
      if (!active) return;
      setSession(data.session);
      if (data.session) void loadData(data.session.user.id);
      setBooting(false);
    });
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      if (!active) return;
      setSession(nextSession);
      if (nextSession) void loadData(nextSession.user.id, true);
      else {
        setProfile(null);
        setSnapshot(emptySnapshot);
      }
    });
    return () => {
      active = false;
      subscription.unsubscribe();
    };
  }, [loadData, supabase]);

  useEffect(() => {
    if (!notice) return;
    const timer = window.setTimeout(() => setNotice(null), 4_000);
    return () => window.clearTimeout(timer);
  }, [notice]);

  const mutate = useCallback(
    async (successMessage: string, action: () => Promise<void>) => {
      if (!session) return false;
      setWorking(true);
      setError(null);
      try {
        await action();
        await loadData(session.user.id, true);
        setNotice(successMessage);
        return true;
      } catch (caught) {
        setError(normalizeError(caught));
        return false;
      } finally {
        setWorking(false);
      }
    },
    [loadData, session],
  );

  if (!supabase) {
    return (
      <main className="admin-login-shell">
        <section className="admin-login-card">
          <img
            src="/ministry-logo.png"
            alt="Riverview Ministry Volunteers logo"
            className="admin-login-mark"
          />
          <h1>Riverview Ministry Volunteers</h1>
          <p>The secure database connection is not configured on this host.</p>
        </section>
      </main>
    );
  }

  if (booting) {
    return <AdminLoading label="Opening Riverview Ministry Volunteers…" />;
  }

  if (!session) {
    return <AdminLogin supabase={supabase} setNotice={setNotice} />;
  }

  return (
    <div className="admin-app-shell">
      <header className="admin-header">
        <div className="admin-brand">
          <img src="/ministry-logo.png" alt="Riverview Ministry Volunteers logo" />
          <div>
            <p>Pasco Riverview Adventist Church</p>
            <h1>Ministry Volunteers</h1>
          </div>
        </div>
        <div className="admin-header-actions">
          <span className="admin-role-badge">{profile?.app_role ?? "loading"}</span>
          <button
            className="button button-quiet"
            onClick={() => void loadData(session.user.id)}
            disabled={loading || working}
          >
            Refresh
          </button>
        </div>
      </header>

      {(notice || error) && (
        <div className={`admin-banner ${error ? "error" : "success"}`} role="status">
          <span>{error ?? notice}</span>
          <button onClick={() => (error ? setError(null) : setNotice(null))} aria-label="Dismiss">
            ×
          </button>
        </div>
      )}

      <div className="admin-workspace">
        <nav className="admin-nav" aria-label="Admin sections">
          {navItems.map((item) => (
            <button
              key={item.id}
              className={activeTab === item.id ? "active" : ""}
              onClick={() => setActiveTab(item.id)}
              aria-current={activeTab === item.id ? "page" : undefined}
            >
              <span className="admin-nav-full">{item.label}</span>
              <span className="admin-nav-short">{item.short}</span>
            </button>
          ))}
        </nav>

        <main className="admin-main">
          {loading && <AdminLoading label="Loading ministry data…" compact />}
          {!loading && profile && (
            <>
              {activeTab === "focus" && (
                <FocusView
                  supabase={supabase}
                  snapshot={snapshot}
                  canEdit={canEdit}
                  working={working}
                  mutate={mutate}
                />
              )}
              {activeTab === "assign" && (
                <AssignView
                  supabase={supabase}
                  snapshot={snapshot}
                  canEdit={canEdit}
                  working={working}
                  mutate={mutate}
                />
              )}
              {activeTab === "ministries" && (
                <MinistryDirectoryView
                  supabase={supabase}
                  snapshot={snapshot}
                  canEdit={canEdit}
                  working={working}
                  mutate={mutate}
                />
              )}
              {activeTab === "people" && (
                <PeopleView
                  supabase={supabase}
                  snapshot={snapshot}
                  canEdit={canEdit}
                  working={working}
                  mutate={mutate}
                />
              )}
              {activeTab === "votes" && (
                <VoteView
                  supabase={supabase}
                  assignments={snapshot.assignments}
                  canEdit={canEdit}
                  working={working}
                  mutate={mutate}
                />
              )}
              {activeTab === "manage" && (
                <ManageView
                  supabase={supabase}
                  snapshot={snapshot}
                  canEdit={canEdit}
                  working={working}
                  mutate={mutate}
                />
              )}
              {activeTab === "reports" && <ReportsView />}
              {activeTab === "settings" && (
                <SettingsView
                  supabase={supabase}
                  session={session}
                  profile={profile}
                  canEdit={canEdit}
                  working={working}
                  mutate={mutate}
                />
              )}
            </>
          )}
        </main>
      </div>
    </div>
  );
}

function AdminLoading({ label, compact = false }: { label: string; compact?: boolean }) {
  return (
    <main className={compact ? "admin-inline-loading" : "admin-login-shell"} aria-busy="true">
      <div className="admin-spinner" />
      <p>{label}</p>
    </main>
  );
}

function AdminLogin({
  supabase,
  setNotice,
}: {
  supabase: SupabaseClient;
  setNotice: (message: string | null) => void;
}) {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function signIn(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    const { error: signInError } = await supabase.auth.signInWithPassword({ email, password });
    if (signInError) {
      setError(
        signInError.code === "invalid_credentials"
          ? "Email or password is incorrect."
          : `Login failed: ${signInError.message}`,
      );
    }
    setBusy(false);
  }

  async function forgotPassword() {
    if (!email.trim()) {
      setError("Enter your email address first.");
      return;
    }
    setBusy(true);
    setError(null);
    const { error: resetError } = await supabase.auth.resetPasswordForEmail(email.trim(), {
      redirectTo: `${window.location.origin}/reset-password`,
    });
    if (resetError) setError(resetError.message);
    else setNotice("Password recovery email sent. Use the newest message in your inbox.");
    setBusy(false);
  }

  return (
    <main className="admin-login-shell">
      <section className="admin-login-card">
        <img
          src="/ministry-logo.png"
          alt="Riverview Ministry Volunteers logo"
          className="admin-login-mark"
        />
        <p className="eyebrow">Pasco Riverview Adventist Church</p>
        <h1>Riverview Ministry Volunteers</h1>
        <p className="admin-login-intro">
          Secure mobile access for ministry placement team members.
        </p>
        <form onSubmit={signIn} className="admin-form-stack">
          <label>
            Email
            <input
              type="email"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              autoComplete="username"
              required
            />
          </label>
          <label>
            Password
            <input
              type="password"
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              autoComplete="current-password"
              required
            />
          </label>
          {error && <p className="admin-form-error">{error}</p>}
          <button className="button button-primary" disabled={busy}>
            {busy ? "Signing in…" : "Sign In"}
          </button>
          <button type="button" className="button button-link" onClick={forgotPassword} disabled={busy}>
            Forgot password?
          </button>
        </form>
        <p className="admin-security-note">
          The public report remains separate and does not expose contact or ordination records.
        </p>
      </section>
    </main>
  );
}

function SectionHeading({ title, detail }: { title: string; detail: string }) {
  return (
    <header className="admin-section-heading">
      <div>
        <p className="eyebrow">Riverview Ministry Volunteers</p>
        <h2>{title}</h2>
      </div>
      <p>{detail}</p>
    </header>
  );
}

function FocusView({
  supabase,
  snapshot,
  canEdit,
  working,
  mutate,
}: {
  supabase: SupabaseClient;
  snapshot: Snapshot;
  canEdit: boolean;
  working: boolean;
  mutate: MutationRunner;
}) {
  const currentAssignments = snapshot.assignments.filter(isCurrent);
  const occupiedMinistries = new Set(currentAssignments.map((item) => item.role_id));
  const emptyMinistries = snapshot.ministries
    .filter((ministry) => ministry.is_active && !occupiedMinistries.has(ministry.id))
    .sort((a, b) => a.name.localeCompare(b.name));
  const assignedPeople = new Set(currentAssignments.map((item) => item.person_id));
  const unassigned = snapshot.people
    .filter((person) => person.is_active && !assignedPeople.has(person.id))
    .sort((a, b) => {
      const priority = membershipPriority(a.membership_status) - membershipPriority(b.membership_status);
      return priority || a.last_name.localeCompare(b.last_name) || a.first_name.localeCompare(b.first_name);
    });
  const awaitingVotes = currentAssignments.filter((item) => item.vote_missing);
  const oneYear = new Date();
  oneYear.setFullYear(oneYear.getFullYear() + 1);
  const oneYearISO = oneYear.toISOString().slice(0, 10);
  const endingSoon = currentAssignments.filter(
    (item) => item.end_date && item.end_date >= todayISO() && item.end_date <= oneYearISO,
  );
  const peopleById = new Map(snapshot.people.map((person) => [person.id, person]));
  const ordinationNeedMap = new Map<
    string,
    { person: Person; kind: OrdinationKind; assignment: Assignment }
  >();
  for (const assignment of currentAssignments) {
    const kind = ordinationKind(assignment.role_name);
    const person = peopleById.get(assignment.person_id);
    if (!kind || !person?.is_active || person[ordinationField(kind)]) continue;
    ordinationNeedMap.set(`${person.id}-${kind}`, { person, kind, assignment });
  }
  const ordinationNeeds = [...ordinationNeedMap.values()].sort(
    (a, b) =>
      a.assignment.role_name.localeCompare(b.assignment.role_name) ||
      a.person.last_name.localeCompare(b.person.last_name) ||
      a.person.first_name.localeCompare(b.person.first_name),
  );

  return (
    <>
      <SectionHeading
        title="Placement Focus"
        detail="A prioritized view of ministries and people that need attention."
      />
      <div className="admin-stat-grid">
        <StatCard value={emptyMinistries.length} label="Empty ministries" tone="urgent" />
        <StatCard value={awaitingVotes.length} label="Awaiting church vote" tone="gold" />
        <StatCard value={endingSoon.length} label="Terms ending within a year" tone="blue" />
        <StatCard value={unassigned.length} label="People without a role" tone="green" />
        <StatCard value={ordinationNeeds.length} label="Awaiting ordination" tone="urgent" />
      </div>
      <div className="admin-two-column">
        <FocusList
          title="Ministries needing a volunteer"
          empty="Every active ministry has at least one current volunteer."
          items={emptyMinistries.map((ministry) => ({
            title: ministry.name,
            detail: "No active placement",
          }))}
        />
        <FocusList
          title="Awaiting church vote"
          empty="No active placements are waiting for a vote."
          items={awaitingVotes.map((assignment) => ({
            title: assignment.person_name,
            detail: `${assignment.role_name}${assignment.sub_role_name ? ` · ${assignment.sub_role_name}` : ""}`,
          }))}
        />
        <FocusList
          title="Ordination action"
          empty="Every current Deacon, Deaconess, and Elder is marked ordained."
          items={ordinationNeeds.map(({ person, kind, assignment }) => ({
            title: personName(person),
            detail: `${assignment.role_name} · ${ordinationLabel(kind)} is not checked`,
            actionLabel: canEdit ? `Mark ${ordinationLabel(kind)}` : undefined,
            actionDisabled: working,
            onAction: canEdit
              ? () => {
                  void mutate("Ordination record updated.", async () => {
                    const { error } = await supabase
                      .from("people")
                      .update({ [ordinationField(kind)]: true })
                      .eq("id", person.id);
                    if (error) throw error;
                  });
                }
              : undefined,
          }))}
        />
        <FocusList
          title="Terms ending within one year"
          empty="No current terms end within the next year."
          items={endingSoon.map((assignment) => ({
            title: assignment.person_name,
            detail: `${assignment.role_name} · ends ${formatDate(assignment.end_date)}`,
          }))}
        />
        <FocusList
          title="Volunteer activation"
          empty="Every active person has a current role."
          items={unassigned.slice(0, 80).map((person) => ({
            title: personName(person),
            detail: person.membership_status || "Membership status not recorded",
            emphasized: membershipPriority(person.membership_status) === 0,
          }))}
        />
      </div>
    </>
  );
}

function StatCard({
  value,
  label,
  tone,
}: {
  value: number;
  label: string;
  tone: "urgent" | "gold" | "blue" | "green";
}) {
  return (
    <article className={`admin-stat-card ${tone}`}>
      <strong>{value}</strong>
      <span>{label}</span>
    </article>
  );
}

function FocusList({
  title,
  empty,
  items,
}: {
  title: string;
  empty: string;
  items: Array<{
    title: string;
    detail: string;
    emphasized?: boolean;
    actionLabel?: string;
    actionDisabled?: boolean;
    onAction?: () => void;
  }>;
}) {
  return (
    <section className="admin-card admin-focus-list">
      <h3>{title}</h3>
      {items.length === 0 ? (
        <p className="admin-empty">{empty}</p>
      ) : (
        <ul>
          {items.map((item, index) => (
            <li key={`${item.title}-${item.detail}-${index}`} className={item.emphasized ? "priority" : ""}>
              <strong>{item.title}</strong>
              <span>{item.detail}</span>
              {item.actionLabel && item.onAction && (
                <button
                  className="button button-small admin-focus-action"
                  disabled={item.actionDisabled}
                  onClick={item.onAction}
                >
                  {item.actionLabel}
                </button>
              )}
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

type MutationRunner = (successMessage: string, action: () => Promise<void>) => Promise<boolean>;

function AssignView({
  supabase,
  snapshot,
  canEdit,
  working,
  mutate,
}: {
  supabase: SupabaseClient;
  snapshot: Snapshot;
  canEdit: boolean;
  working: boolean;
  mutate: MutationRunner;
}) {
  const [newPerson, setNewPerson] = useState(false);
  const [personQuery, setPersonQuery] = useState("");
  const [personId, setPersonId] = useState("");
  const [firstName, setFirstName] = useState("");
  const [lastName, setLastName] = useState("");
  const [email, setEmail] = useState("");
  const [phone, setPhone] = useState("");
  const [ministryId, setMinistryId] = useState("");
  const [positionId, setPositionId] = useState("");
  const [termId, setTermId] = useState("");
  const [voteDate, setVoteDate] = useState("");
  const [notes, setNotes] = useState("");
  const [notePublic, setNotePublic] = useState(false);
  const [assignmentPublic, setAssignmentPublic] = useState(true);
  const [personPublic, setPersonPublic] = useState(true);
  const [newPositionName, setNewPositionName] = useState("");
  const [newPositionVote, setNewPositionVote] = useState(false);
  const [ordained, setOrdained] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);

  const activeMinistries = snapshot.ministries.filter((item) => item.is_active);
  const selectedMinistry = activeMinistries.find((item) => item.id === ministryId);
  const selectedPerson = snapshot.people.find((item) => item.id === personId);
  const availablePositions = snapshot.positions.filter(
    (item) => item.is_active && item.role_id === ministryId,
  );
  const selectedPosition = availablePositions.find((item) => item.id === positionId);
  const kind = ordinationKind(selectedMinistry?.name);
  const requiresVote = Boolean(
    selectedMinistry?.requires_vote ||
      selectedPosition?.requires_vote ||
      (positionId === "add" && newPositionVote),
  );
  const people = snapshot.people.filter((person) => {
    if (!person.is_active) return false;
    const query = personQuery.trim().toLowerCase();
    if (!query) return true;
    return [personName(person), person.email, person.mobile_phone, person.membership_status]
      .filter(Boolean)
      .some((value) => value!.toLowerCase().includes(query));
  });

  useEffect(() => {
    setPositionId("");
    setNewPositionName("");
    setNewPositionVote(false);
  }, [ministryId]);

  useEffect(() => {
    if (!kind || newPerson) {
      setOrdained(false);
      return;
    }
    setOrdained(Boolean(selectedPerson?.[ordinationField(kind)]));
  }, [kind, newPerson, selectedPerson]);

  async function submit(event: FormEvent) {
    event.preventDefault();
    setFormError(null);
    if (!canEdit) return setFormError("Your account has view-only access.");
    if (!ministryId) return setFormError("Choose a ministry.");
    if (!positionId) return setFormError("Choose a position.");
    if (newPerson && (!firstName.trim() || !lastName.trim())) {
      return setFormError("Enter the new person's first and last name.");
    }
    if (!newPerson && !personId) return setFormError("Choose a person.");
    if (positionId === "add" && !newPositionName.trim()) {
      return setFormError("Enter the new position name.");
    }
    if (requiresVote && !termId) return setFormError("A term is required for a voted role.");
    if (requiresVote && !voteDate) return setFormError("Enter the church vote date.");

    const succeeded = await mutate("Volunteer assignment saved.", async () => {
      let savedPersonId = personId;
      if (newPerson) {
        const { data, error } = await supabase
          .from("people")
          .insert({
            first_name: firstName.trim(),
            last_name: lastName.trim(),
            email: email.trim() || null,
            mobile_phone: phone.trim() || null,
            is_active: true,
            is_public: personPublic,
            is_ordained_deacon: kind === "deacon" ? ordained : false,
            is_ordained_deaconess: kind === "deaconess" ? ordained : false,
            is_ordained_elder: kind === "elder" ? ordained : false,
          })
          .select("id")
          .single();
        if (error) throw error;
        savedPersonId = data.id;
      } else if (kind) {
        const { error } = await supabase
          .from("people")
          .update({ [ordinationField(kind)]: ordained })
          .eq("id", savedPersonId);
        if (error) throw error;
      }

      let savedPositionId = positionId;
      if (positionId === "add") {
        const { data, error } = await supabase
          .from("sub_roles")
          .insert({
            role_id: ministryId,
            name: newPositionName.trim(),
            leadership_rank: 100,
            requires_vote: newPositionVote,
            is_active: true,
          })
          .select("id")
          .single();
        if (error) throw error;
        savedPositionId = data.id;
      }

      const { error } = await supabase.from("assignments").insert({
        person_id: savedPersonId,
        role_id: ministryId,
        sub_role_id: savedPositionId,
        term_id: termId || null,
        vote_date: voteDate || null,
        notes: notes.trim() || null,
        note_is_public: Boolean(notes.trim()) && notePublic,
        status: "active",
        is_public: assignmentPublic,
      });
      if (error) throw error;
    });

    if (succeeded) {
      setPersonId("");
      setPersonQuery("");
      setFirstName("");
      setLastName("");
      setEmail("");
      setPhone("");
      setMinistryId("");
      setPositionId("");
      setTermId("");
      setVoteDate("");
      setNotes("");
      setNotePublic(false);
      setOrdained(false);
    }
  }

  return (
    <>
      <SectionHeading
        title="Assign a Volunteer"
        detail="Choose an existing person or create a new person, then record the placement."
      />
      <form className="admin-card admin-editor-form" onSubmit={submit}>
        <fieldset disabled={!canEdit || working}>
          <legend>Volunteer</legend>
          <label className="admin-check-row">
            <input type="checkbox" checked={newPerson} onChange={(event) => setNewPerson(event.target.checked)} />
            Enter a new person
          </label>
          {newPerson ? (
            <div className="admin-form-grid">
              <label>
                First name
                <input value={firstName} onChange={(event) => setFirstName(event.target.value)} required />
              </label>
              <label>
                Last name
                <input value={lastName} onChange={(event) => setLastName(event.target.value)} required />
              </label>
              <label>
                Email
                <input type="email" value={email} onChange={(event) => setEmail(event.target.value)} />
              </label>
              <label>
                Mobile phone
                <input type="tel" value={phone} onChange={(event) => setPhone(event.target.value)} />
              </label>
              <label className="admin-check-row full">
                <input type="checkbox" checked={personPublic} onChange={(event) => setPersonPublic(event.target.checked)} />
                Allow this person's name in the public directory
              </label>
            </div>
          ) : (
            <div className="admin-form-grid">
              <label>
                Find a person
                <input
                  type="search"
                  placeholder="Name, email, phone, or membership"
                  value={personQuery}
                  onChange={(event) => setPersonQuery(event.target.value)}
                />
              </label>
              <label>
                Person
                <select value={personId} onChange={(event) => setPersonId(event.target.value)} required>
                  <option value="">Choose a person</option>
                  {people.slice(0, 200).map((person) => (
                    <option key={person.id} value={person.id}>
                      {personName(person)}{person.membership_status ? ` — ${person.membership_status}` : ""}
                    </option>
                  ))}
                </select>
              </label>
            </div>
          )}
        </fieldset>

        <fieldset disabled={!canEdit || working}>
          <legend>Ministry placement</legend>
          <div className="admin-form-grid">
            <label>
              Ministry
              <select value={ministryId} onChange={(event) => setMinistryId(event.target.value)} required>
                <option value="">Choose a ministry</option>
                {activeMinistries.map((ministry) => (
                  <option key={ministry.id} value={ministry.id}>{ministry.name}</option>
                ))}
              </select>
            </label>
            <label>
              Position
              <select value={positionId} onChange={(event) => setPositionId(event.target.value)} required disabled={!ministryId}>
                <option value="">Choose a position</option>
                {availablePositions.map((position) => (
                  <option key={position.id} value={position.id}>{position.name}</option>
                ))}
                <option value="add">＋ Add a position…</option>
              </select>
            </label>
            {positionId === "add" && (
              <>
                <label>
                  New position name
                  <input value={newPositionName} onChange={(event) => setNewPositionName(event.target.value)} required />
                </label>
                <label className="admin-check-row admin-check-bottom">
                  <input type="checkbox" checked={newPositionVote} onChange={(event) => setNewPositionVote(event.target.checked)} />
                  Position requires church vote
                </label>
              </>
            )}
            <label>
              Term {requiresVote ? "(required)" : "(optional)"}
              <select value={termId} onChange={(event) => setTermId(event.target.value)} required={requiresVote}>
                <option value="">{requiresVote ? "Choose a term" : "No term"}</option>
                {snapshot.terms.filter((term) => term.is_active).map((term) => (
                  <option key={term.id} value={term.id}>
                    {term.name}{term.end_date ? ` — ends ${formatDate(term.end_date)}` : ""}
                  </option>
                ))}
              </select>
            </label>
            {(requiresVote || voteDate) && (
              <label>
                Church vote date {requiresVote ? "(required)" : ""}
                <input type="date" value={voteDate} onChange={(event) => setVoteDate(event.target.value)} required={requiresVote} />
              </label>
            )}
          </div>
          {!requiresVote && (
            <button type="button" className="button button-link align-left" onClick={() => setVoteDate(voteDate ? "" : todayISO())}>
              {voteDate ? "Remove optional vote date" : "Add an optional vote date"}
            </button>
          )}
        </fieldset>

        {kind && (
          <fieldset disabled={!canEdit || working} className="admin-ordination-fieldset">
            <legend>Ordination</legend>
            <label className="admin-check-row">
              <input type="checkbox" checked={ordained} onChange={(event) => setOrdained(event.target.checked)} />
              {ordinationLabel(kind)}
            </label>
            <p>This permanent person record remains after the placement is archived.</p>
          </fieldset>
        )}

        <fieldset disabled={!canEdit || working}>
          <legend>Assignment details</legend>
          <label>
            Note
            <textarea value={notes} onChange={(event) => setNotes(event.target.value)} rows={4} placeholder="Optional staff note" />
          </label>
          <label className="admin-check-row">
            <input type="checkbox" checked={notePublic} onChange={(event) => setNotePublic(event.target.checked)} disabled={!notes.trim()} />
            Include this note in reports and the public web directory
          </label>
          <label className="admin-check-row">
            <input type="checkbox" checked={assignmentPublic} onChange={(event) => setAssignmentPublic(event.target.checked)} />
            Show this assignment in the public directory
          </label>
        </fieldset>

        {formError && <p className="admin-form-error">{formError}</p>}
        {!canEdit && <p className="admin-readonly">Your viewer account cannot save changes.</p>}
        <button className="button button-primary button-wide" disabled={!canEdit || working}>
          {working ? "Saving…" : "Save Assignment"}
        </button>
      </form>
    </>
  );
}

function MinistryDirectoryView({
  supabase,
  snapshot,
  canEdit,
  working,
  mutate,
}: {
  supabase: SupabaseClient;
  snapshot: Snapshot;
  canEdit: boolean;
  working: boolean;
  mutate: MutationRunner;
}) {
  const [query, setQuery] = useState("");
  const [editing, setEditing] = useState<Assignment | null>(null);
  const normalized = query.trim().toLowerCase();
  const ministries = snapshot.ministries
    .filter((item) => item.is_active)
    .map((ministry) => ({
      ministry,
      assignments: snapshot.assignments.filter(
        (assignment) =>
          assignment.role_id === ministry.id &&
          isCurrent(assignment) &&
          (!normalized ||
            [assignment.person_name, assignment.role_name, assignment.sub_role_name]
              .filter(Boolean)
              .some((value) => value!.toLowerCase().includes(normalized))),
      ),
    }))
    .filter(({ ministry, assignments }) =>
      normalized ? ministry.name.toLowerCase().includes(normalized) || assignments.length > 0 : true,
    );

  return (
    <>
      <SectionHeading
        title="Ministry Directory"
        detail="Current placements only. Archived history remains available in People Directory."
      />
      <div className="admin-search-row">
        <input type="search" placeholder="Search ministry, person, or position" value={query} onChange={(event) => setQuery(event.target.value)} />
      </div>
      <div className="admin-ministry-grid">
        {ministries.map(({ ministry, assignments }) => (
          <section className="admin-card admin-ministry-card" key={ministry.id}>
            <header>
              <h3>{ministry.name}</h3>
              <span>{assignments.length}</span>
            </header>
            {assignments.length === 0 ? (
              <p className="admin-empty">No active placements</p>
            ) : (
              <ul className="admin-assignment-list">
                {assignments
                  .sort(
                    (a, b) =>
                      a.leadership_rank - b.leadership_rank ||
                      a.last_name.localeCompare(b.last_name) ||
                      a.first_name.localeCompare(b.first_name),
                  )
                  .map((assignment) => (
                    <li key={assignment.id}>
                      <div>
                        <strong>{assignment.person_name}</strong>
                        <span>{assignment.sub_role_name || "Volunteer"}</span>
                        <small>
                          {assignment.end_date ? `Ends ${formatDate(assignment.end_date)}` : "No term end"}
                          {assignment.requires_vote
                            ? assignment.vote_date
                              ? ` · Voted ${formatDate(assignment.vote_date)}`
                              : " · Vote missing"
                            : ""}
                        </small>
                      </div>
                      {canEdit && (
                        <button className="button button-small" onClick={() => setEditing(assignment)}>Edit</button>
                      )}
                    </li>
                  ))}
              </ul>
            )}
          </section>
        ))}
      </div>
      {editing && (
        <AssignmentEditor
          assignment={editing}
          positions={snapshot.positions.filter((item) => item.role_id === editing.role_id && item.is_active)}
          terms={snapshot.terms.filter((item) => item.is_active)}
          working={working}
          onClose={() => setEditing(null)}
          onSave={async (update) => {
            const succeeded = await mutate("Assignment details updated.", async () => {
              const { error } = await supabase.from("assignments").update(update).eq("id", editing.id);
              if (error) throw error;
            });
            if (succeeded) setEditing(null);
          }}
        />
      )}
    </>
  );
}

function AssignmentEditor({
  assignment,
  positions,
  terms,
  working,
  onClose,
  onSave,
}: {
  assignment: Assignment;
  positions: Position[];
  terms: Term[];
  working: boolean;
  onClose: () => void;
  onSave: (update: Record<string, unknown>) => Promise<void>;
}) {
  const [positionId, setPositionId] = useState(assignment.sub_role_id ?? "");
  const [termId, setTermId] = useState(assignment.term_id ?? "");
  const [voteDate, setVoteDate] = useState(assignment.vote_date ?? "");
  const [notes, setNotes] = useState(assignment.notes ?? "");
  const [notePublic, setNotePublic] = useState(assignment.note_is_public);
  const selectedPosition = positions.find((item) => item.id === positionId);
  const requiresVote = assignment.ministry_requires_vote || selectedPosition?.requires_vote;

  return (
    <div className="admin-modal-backdrop" role="presentation" onMouseDown={onClose}>
      <section className="admin-modal" role="dialog" aria-modal="true" aria-labelledby="assignment-editor-title" onMouseDown={(event) => event.stopPropagation()}>
        <header>
          <div>
            <p className="eyebrow">{assignment.role_name}</p>
            <h3 id="assignment-editor-title">Edit {assignment.person_name}</h3>
          </div>
          <button onClick={onClose} aria-label="Close">×</button>
        </header>
        <div className="admin-form-stack">
          <label>
            Position
            <select value={positionId} onChange={(event) => setPositionId(event.target.value)}>
              <option value="">No position</option>
              {positions.map((position) => <option key={position.id} value={position.id}>{position.name}</option>)}
            </select>
          </label>
          <label>
            Term {requiresVote ? "(required)" : "(optional)"}
            <select value={termId} onChange={(event) => setTermId(event.target.value)}>
              <option value="">No term</option>
              {terms.map((term) => <option key={term.id} value={term.id}>{term.name}</option>)}
            </select>
          </label>
          {requiresVote && (
            <label>
              Church vote date
              <input type="date" value={voteDate} onChange={(event) => setVoteDate(event.target.value)} />
            </label>
          )}
          <label>
            Note
            <textarea rows={4} value={notes} onChange={(event) => setNotes(event.target.value)} />
          </label>
          <label className="admin-check-row">
            <input type="checkbox" checked={notePublic} onChange={(event) => setNotePublic(event.target.checked)} disabled={!notes.trim()} />
            Include note in reports and public directory
          </label>
          <div className="admin-modal-actions">
            <button
              className="button button-danger"
              disabled={working}
              onClick={() => onSave({ status: "completed" })}
            >
              Archive Role
            </button>
            <button
              className="button button-primary"
              disabled={working || Boolean(requiresVote && (!termId || !voteDate))}
              onClick={() =>
                onSave({
                  sub_role_id: positionId || null,
                  term_id: termId || null,
                  vote_date: voteDate || null,
                  notes: notes.trim() || null,
                  note_is_public: Boolean(notes.trim()) && notePublic,
                })
              }
            >
              Save Changes
            </button>
          </div>
        </div>
      </section>
    </div>
  );
}

function PeopleView({
  supabase,
  snapshot,
  canEdit,
  working,
  mutate,
}: {
  supabase: SupabaseClient;
  snapshot: Snapshot;
  canEdit: boolean;
  working: boolean;
  mutate: MutationRunner;
}) {
  const [query, setQuery] = useState("");
  const [filter, setFilter] = useState("all");
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const selected = snapshot.people.find((person) => person.id === selectedId) ?? null;
  const normalized = query.trim().toLowerCase();
  const people = snapshot.people
    .filter((person) => {
      const ordained = ordinationLabels(person);
      if (filter === "deacon" && !person.is_ordained_deacon) return false;
      if (filter === "deaconess" && !person.is_ordained_deaconess) return false;
      if (filter === "elder" && !person.is_ordained_elder) return false;
      if (filter === "none" && ordained.length > 0) return false;
      if (!normalized) return true;
      return [
        personName(person),
        person.email,
        person.mobile_phone,
        person.home_phone,
        person.membership_status,
        ...ordained,
      ]
        .filter(Boolean)
        .some((value) => value!.toLowerCase().includes(normalized));
    })
    .sort((a, b) => a.last_name.localeCompare(b.last_name) || a.first_name.localeCompare(b.first_name));

  return (
    <>
      <SectionHeading
        title="People Directory"
        detail="Search contact details, ministry history, membership, and permanent ordination status."
      />
      <div className="admin-search-row two">
        <input type="search" placeholder="Search people or ordination status" value={query} onChange={(event) => setQuery(event.target.value)} />
        <select value={filter} onChange={(event) => setFilter(event.target.value)} aria-label="Filter by ordination">
          <option value="all">All people</option>
          <option value="deacon">Ordained Deacons</option>
          <option value="deaconess">Ordained Deaconesses</option>
          <option value="elder">Ordained Elders</option>
          <option value="none">Not ordained</option>
        </select>
      </div>
      <p className="admin-result-count">{people.length} people</p>
      <div className="admin-people-grid">
        {people.map((person) => {
          const assignments = snapshot.assignments.filter((item) => item.person_id === person.id);
          const currentCount = assignments.filter(isCurrent).length;
          const historyCount = assignments.length - currentCount;
          return (
            <button className="admin-card admin-person-card" key={person.id} onClick={() => setSelectedId(person.id)}>
              <span className="admin-avatar">{(person.preferred_name || person.first_name)[0]}{person.last_name[0]}</span>
              <span className="admin-person-summary">
                <strong>{personName(person)}</strong>
                <small>{person.membership_status || "Membership status not recorded"}</small>
                <span className="admin-badges">
                  {ordinationLabels(person).map((label) => <em key={label}>{label}</em>)}
                </span>
              </span>
              <span className="admin-person-counts">
                <b>{currentCount} current</b>
                {historyCount > 0 && <small>{historyCount} history</small>}
              </span>
            </button>
          );
        })}
      </div>
      {selected && (
        <PersonEditor
          person={selected}
          assignments={snapshot.assignments.filter((item) => item.person_id === selected.id)}
          canEdit={canEdit}
          working={working}
          onClose={() => setSelectedId(null)}
          onSaveOrdination={async (values) => {
            await mutate("Ordination record updated.", async () => {
              const { error } = await supabase.from("people").update(values).eq("id", selected.id);
              if (error) throw error;
            });
          }}
          onArchive={async (assignment, archived) => {
            await mutate(archived ? "Assignment archived." : "Assignment restored.", async () => {
              const { error } = await supabase
                .from("assignments")
                .update({ status: archived ? "completed" : "active" })
                .eq("id", assignment.id);
              if (error) throw error;
            });
          }}
        />
      )}
    </>
  );
}

function PersonEditor({
  person,
  assignments,
  canEdit,
  working,
  onClose,
  onSaveOrdination,
  onArchive,
}: {
  person: Person;
  assignments: Assignment[];
  canEdit: boolean;
  working: boolean;
  onClose: () => void;
  onSaveOrdination: (values: Record<string, boolean>) => Promise<void>;
  onArchive: (assignment: Assignment, archived: boolean) => Promise<void>;
}) {
  const [deacon, setDeacon] = useState(person.is_ordained_deacon);
  const [deaconess, setDeaconess] = useState(person.is_ordained_deaconess);
  const [elder, setElder] = useState(person.is_ordained_elder);
  const current = assignments.filter(isCurrent);
  const history = assignments.filter((item) => !isCurrent(item));

  return (
    <div className="admin-modal-backdrop" role="presentation" onMouseDown={onClose}>
      <section className="admin-modal admin-person-modal" role="dialog" aria-modal="true" aria-labelledby="person-editor-title" onMouseDown={(event) => event.stopPropagation()}>
        <header>
          <div>
            <p className="eyebrow">People Directory</p>
            <h3 id="person-editor-title">{personName(person)}</h3>
          </div>
          <button onClick={onClose} aria-label="Close">×</button>
        </header>
        <div className="admin-person-contact">
          {person.membership_status && <span>{person.membership_status}</span>}
          {person.email && <a href={`mailto:${person.email}`}>{person.email}</a>}
          {(person.mobile_phone || person.home_phone) && <a href={`tel:${person.mobile_phone || person.home_phone}`}>{person.mobile_phone || person.home_phone}</a>}
        </div>
        <section className="admin-modal-section admin-ordination-box">
          <h4>Permanent ordination status</h4>
          <p>These records stay with the person when ministry assignments are archived.</p>
          <label className="admin-check-row"><input type="checkbox" checked={deacon} onChange={(event) => setDeacon(event.target.checked)} disabled={!canEdit} />Ordained Deacon</label>
          <label className="admin-check-row"><input type="checkbox" checked={deaconess} onChange={(event) => setDeaconess(event.target.checked)} disabled={!canEdit} />Ordained Deaconess</label>
          <label className="admin-check-row"><input type="checkbox" checked={elder} onChange={(event) => setElder(event.target.checked)} disabled={!canEdit} />Ordained Elder</label>
          {canEdit && (
            <button
              className="button button-primary"
              disabled={working}
              onClick={() => onSaveOrdination({
                is_ordained_deacon: deacon,
                is_ordained_deaconess: deaconess,
                is_ordained_elder: elder,
              })}
            >
              Save Ordination Status
            </button>
          )}
        </section>
        <AssignmentHistory title="Current ministries" assignments={current} canEdit={canEdit} working={working} onArchive={onArchive} />
        <AssignmentHistory title="Archived & historical ministries" assignments={history} canEdit={canEdit} working={working} onArchive={onArchive} />
      </section>
    </div>
  );
}

function AssignmentHistory({
  title,
  assignments,
  canEdit,
  working,
  onArchive,
}: {
  title: string;
  assignments: Assignment[];
  canEdit: boolean;
  working: boolean;
  onArchive: (assignment: Assignment, archived: boolean) => Promise<void>;
}) {
  return (
    <section className="admin-modal-section">
      <h4>{title}</h4>
      {assignments.length === 0 ? (
        <p className="admin-empty">None</p>
      ) : (
        <ul className="admin-history-list">
          {assignments.map((assignment) => (
            <li key={assignment.id}>
              <div>
                <strong>{assignment.role_name}</strong>
                <span>{assignment.sub_role_name || "Volunteer"}{assignment.end_date ? ` · ends ${formatDate(assignment.end_date)}` : ""}</span>
              </div>
              {canEdit && (
                <button className="button button-small" disabled={working} onClick={() => onArchive(assignment, isCurrent(assignment))}>
                  {isCurrent(assignment) ? "Archive" : "Restore"}
                </button>
              )}
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

function VoteView({
  supabase,
  assignments,
  canEdit,
  working,
  mutate,
}: {
  supabase: SupabaseClient;
  assignments: Assignment[];
  canEdit: boolean;
  working: boolean;
  mutate: MutationRunner;
}) {
  const [query, setQuery] = useState("");
  const normalized = query.trim().toLowerCase();
  const awaiting = assignments
    .filter((item) => isCurrent(item) && item.vote_missing)
    .filter((item) =>
      !normalized || [item.person_name, item.role_name, item.sub_role_name]
        .filter(Boolean)
        .some((value) => value!.toLowerCase().includes(normalized)),
    );

  return (
    <>
      <SectionHeading title="Awaiting Church Vote" detail="Quickly complete missing vote records for active placements." />
      <div className="admin-search-row">
        <input type="search" placeholder="Search person or ministry" value={query} onChange={(event) => setQuery(event.target.value)} />
      </div>
      {awaiting.length === 0 ? (
        <section className="admin-card admin-empty-state"><h3>Nothing is waiting</h3><p>All current voted roles have a recorded vote date.</p></section>
      ) : (
        <div className="admin-vote-list">
          {awaiting.map((assignment) => (
            <VoteRow
              key={assignment.id}
              assignment={assignment}
              canEdit={canEdit}
              working={working}
              save={async (voteDate) => {
                await mutate("Church vote recorded.", async () => {
                  const { error } = await supabase.from("assignments").update({ vote_date: voteDate }).eq("id", assignment.id);
                  if (error) throw error;
                });
              }}
            />
          ))}
        </div>
      )}
    </>
  );
}

function VoteRow({ assignment, canEdit, working, save }: { assignment: Assignment; canEdit: boolean; working: boolean; save: (date: string) => Promise<void> }) {
  const [date, setDate] = useState(todayISO());
  return (
    <article className="admin-card admin-vote-row">
      <div><strong>{assignment.person_name}</strong><span>{assignment.role_name}{assignment.sub_role_name ? ` · ${assignment.sub_role_name}` : ""}</span><small>{assignment.term_name || "Term required"}</small></div>
      <label>Vote date<input type="date" value={date} onChange={(event) => setDate(event.target.value)} disabled={!canEdit || working} /></label>
      <button className="button button-primary" disabled={!canEdit || working || !date} onClick={() => save(date)}>Record Vote</button>
    </article>
  );
}

function ManageView({
  supabase,
  snapshot,
  canEdit,
  working,
  mutate,
}: {
  supabase: SupabaseClient;
  snapshot: Snapshot;
  canEdit: boolean;
  working: boolean;
  mutate: MutationRunner;
}) {
  const [selectedMinistryId, setSelectedMinistryId] = useState(snapshot.ministries.find((item) => item.is_active)?.id ?? "");
  const [newMinistry, setNewMinistry] = useState("");
  const [newPosition, setNewPosition] = useState("");
  const [newPositionVote, setNewPositionVote] = useState(false);
  const [newTerm, setNewTerm] = useState("");
  const [termStart, setTermStart] = useState("");
  const [termEnd, setTermEnd] = useState("");
  const selected = snapshot.ministries.find((item) => item.id === selectedMinistryId);

  return (
    <>
      <SectionHeading title="Manage" detail="Configure ministries, their positions, and reusable terms." />
      {!canEdit && <p className="admin-readonly">Your viewer account can inspect these settings but cannot change them.</p>}
      <div className="admin-two-column manage-columns">
        <section className="admin-card admin-manage-panel">
          <h3>Ministries</h3>
          <div className="admin-form-inline">
            <input placeholder="New ministry name" value={newMinistry} onChange={(event) => setNewMinistry(event.target.value)} disabled={!canEdit || working} />
            <button className="button button-primary" disabled={!canEdit || working || !newMinistry.trim()} onClick={async () => {
              const succeeded = await mutate("Ministry added.", async () => {
                const nextOrder = Math.max(0, ...snapshot.ministries.map((item) => item.display_order)) + 10;
                const { error } = await supabase.from("roles").insert({ name: newMinistry.trim(), requires_vote: false, is_active: true, is_public: true, display_order: nextOrder });
                if (error) throw error;
              });
              if (succeeded) setNewMinistry("");
            }}>Add</button>
          </div>
          <div className="admin-manage-list">
            {snapshot.ministries.map((ministry) => (
              <EditableMinistry key={ministry.id} ministry={ministry} selected={ministry.id === selectedMinistryId} canEdit={canEdit} working={working} onSelect={() => setSelectedMinistryId(ministry.id)} onSave={(values) => mutate("Ministry updated everywhere it is assigned.", async () => {
                const { error } = await supabase.from("roles").update(values).eq("id", ministry.id);
                if (error) throw error;
              })} />
            ))}
          </div>
        </section>

        <section className="admin-card admin-manage-panel">
          <h3>Positions {selected ? `for ${selected.name}` : ""}</h3>
          {selected ? (
            <>
              <div className="admin-form-stack compact">
                <input placeholder="New position name" value={newPosition} onChange={(event) => setNewPosition(event.target.value)} disabled={!canEdit || working} />
                <label className="admin-check-row"><input type="checkbox" checked={newPositionVote} onChange={(event) => setNewPositionVote(event.target.checked)} disabled={!canEdit || working} />Requires church vote</label>
                <button className="button button-primary" disabled={!canEdit || working || !newPosition.trim()} onClick={async () => {
                  const succeeded = await mutate("Position added.", async () => {
                    const { error } = await supabase.from("sub_roles").insert({ role_id: selected.id, name: newPosition.trim(), leadership_rank: 100, requires_vote: newPositionVote, is_active: true });
                    if (error) throw error;
                  });
                  if (succeeded) { setNewPosition(""); setNewPositionVote(false); }
                }}>Add Position</button>
              </div>
              <div className="admin-manage-list">
                {snapshot.positions.filter((item) => item.role_id === selected.id).map((position) => (
                  <EditablePosition key={position.id} position={position} canEdit={canEdit} working={working} onSave={(values) => mutate("Position updated.", async () => {
                    const { error } = await supabase.from("sub_roles").update(values).eq("id", position.id);
                    if (error) throw error;
                  })} />
                ))}
              </div>
            </>
          ) : <p className="admin-empty">Choose a ministry first.</p>}
        </section>

        <section className="admin-card admin-manage-panel full-panel">
          <h3>Terms</h3>
          <div className="admin-form-grid term-create">
            <label>Term name<input value={newTerm} onChange={(event) => setNewTerm(event.target.value)} disabled={!canEdit || working} /></label>
            <label>Starts<input type="date" value={termStart} onChange={(event) => setTermStart(event.target.value)} disabled={!canEdit || working} /></label>
            <label>Ends<input type="date" value={termEnd} onChange={(event) => setTermEnd(event.target.value)} disabled={!canEdit || working} /></label>
            <button className="button button-primary admin-check-bottom" disabled={!canEdit || working || !newTerm.trim() || !termStart || !termEnd} onClick={async () => {
              const succeeded = await mutate("Term added.", async () => {
                const { error } = await supabase.from("terms").insert({ name: newTerm.trim(), start_date: termStart, end_date: termEnd, term_type: "custom", is_active: true });
                if (error) throw error;
              });
              if (succeeded) { setNewTerm(""); setTermStart(""); setTermEnd(""); }
            }}>Add Term</button>
          </div>
          <div className="admin-term-grid">
            {snapshot.terms.map((term) => (
              <article key={term.id} className={term.is_active ? "" : "archived"}>
                <strong>{term.name}</strong>
                <span>{term.start_date ? formatDate(term.start_date) : "Ongoing"} — {term.end_date ? formatDate(term.end_date) : "No end"}</span>
                {!term.is_active && <em>Archived</em>}
              </article>
            ))}
          </div>
        </section>
      </div>
    </>
  );
}

function EditableMinistry({ ministry, selected, canEdit, working, onSelect, onSave }: { ministry: Ministry; selected: boolean; canEdit: boolean; working: boolean; onSelect: () => void; onSave: (values: Record<string, unknown>) => Promise<boolean> }) {
  const [name, setName] = useState(ministry.name);
  const [requiresVote, setRequiresVote] = useState(ministry.requires_vote);
  return (
    <article className={`admin-manage-item ${selected ? "selected" : ""}`}>
      <button className="admin-manage-select" onClick={onSelect}>{ministry.name}<small>{ministry.is_active ? "Active" : "Archived"}</small></button>
      <details>
        <summary>Edit</summary>
        <div className="admin-form-stack compact">
          <label>Name<input value={name} onChange={(event) => setName(event.target.value)} disabled={!canEdit || working} /></label>
          <label className="admin-check-row"><input type="checkbox" checked={requiresVote} onChange={(event) => setRequiresVote(event.target.checked)} disabled={!canEdit || working} />Ministry requires church vote</label>
          <div className="admin-inline-actions">
            <button className="button button-primary" disabled={!canEdit || working || !name.trim()} onClick={() => onSave({ name: name.trim(), requires_vote: requiresVote })}>Save</button>
            <button className={ministry.is_active ? "button button-danger" : "button"} disabled={!canEdit || working} onClick={() => onSave({ is_active: !ministry.is_active })}>{ministry.is_active ? "Archive" : "Restore"}</button>
          </div>
        </div>
      </details>
    </article>
  );
}

function EditablePosition({ position, canEdit, working, onSave }: { position: Position; canEdit: boolean; working: boolean; onSave: (values: Record<string, unknown>) => Promise<boolean> }) {
  const [name, setName] = useState(position.name);
  const [requiresVote, setRequiresVote] = useState(position.requires_vote);
  return (
    <details className="admin-manage-item">
      <summary>{position.name}<small>{position.is_active ? "Active" : "Archived"}</small></summary>
      <div className="admin-form-stack compact">
        <label>Name<input value={name} onChange={(event) => setName(event.target.value)} disabled={!canEdit || working} /></label>
        <label className="admin-check-row"><input type="checkbox" checked={requiresVote} onChange={(event) => setRequiresVote(event.target.checked)} disabled={!canEdit || working} />Requires church vote</label>
        <div className="admin-inline-actions">
          <button className="button button-primary" disabled={!canEdit || working || !name.trim()} onClick={() => onSave({ name: name.trim(), requires_vote: requiresVote })}>Save</button>
          <button className={position.is_active ? "button button-danger" : "button"} disabled={!canEdit || working} onClick={() => onSave({ is_active: !position.is_active })}>{position.is_active ? "Archive" : "Restore"}</button>
        </div>
      </div>
    </details>
  );
}

function ReportsView() {
  return (
    <>
      <SectionHeading title="Reports" detail="Preview, filter, print, or save the current public ministry report as a PDF." />
      <section className="admin-card admin-report-card">
        <div>
          <h3>Printable Ministry Directory</h3>
          <p>The report includes current public placements and approved notes. Contact details and ordination status are intentionally excluded.</p>
          <a className="button button-primary" href="/" target="_blank" rel="noreferrer">Open Full Report</a>
        </div>
        <iframe className="admin-report-frame" src="/embed" title="Printable ministry directory report preview" />
      </section>
    </>
  );
}

function SettingsView({
  supabase,
  session,
  profile,
  canEdit,
  working,
  mutate,
}: {
  supabase: SupabaseClient;
  session: Session;
  profile: Profile;
  canEdit: boolean;
  working: boolean;
  mutate: MutationRunner;
}) {
  const [inviteEmail, setInviteEmail] = useState("");
  const [inviteRole, setInviteRole] = useState<"editor" | "viewer">("editor");
  return (
    <>
      <SectionHeading title="Settings" detail="Account, Planning Center sync, and administrator-only user access." />
      <div className="admin-two-column">
        <section className="admin-card admin-settings-card">
          <h3>Your account</h3>
          <dl><dt>Email</dt><dd>{session.user.email}</dd><dt>Access</dt><dd>{profile.app_role}</dd></dl>
          <button className="button" onClick={() => void supabase.auth.signOut()}>Sign Out</button>
        </section>
        <section className="admin-card admin-settings-card">
          <h3>Planning Center People</h3>
          <p>Planning Center remains the source of truth for contact and membership information. This sync is read-only.</p>
          <button className="button button-primary" disabled={!canEdit || working} onClick={() => mutate("Planning Center sync completed.", async () => {
            const { error } = await supabase.functions.invoke("planning-center-sync", { body: {} });
            if (error) throw error;
          })}>Sync Planning Center</button>
        </section>
        {profile.app_role === "admin" && (
          <section className="admin-card admin-settings-card full-panel">
            <h3>Create an app user</h3>
            <p>The new user receives an email to set a password. This section is visible only to administrators.</p>
            <div className="admin-form-grid invite-grid">
              <label>Email<input type="email" value={inviteEmail} onChange={(event) => setInviteEmail(event.target.value)} /></label>
              <label>Access<select value={inviteRole} onChange={(event) => setInviteRole(event.target.value as "editor" | "viewer")}><option value="editor">Editor</option><option value="viewer">Viewer</option></select></label>
              <button className="button button-primary admin-check-bottom" disabled={working || !inviteEmail.trim()} onClick={async () => {
                const succeeded = await mutate("Setup email sent to the new app user.", async () => {
                  const { error } = await supabase.functions.invoke("admin-users", { body: { email: inviteEmail.trim(), role: inviteRole } });
                  if (error) throw error;
                });
                if (succeeded) setInviteEmail("");
              }}>Create User & Send Setup Email</button>
            </div>
          </section>
        )}
      </div>
    </>
  );
}
