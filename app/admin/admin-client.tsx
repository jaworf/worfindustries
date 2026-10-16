"use client";

import { createClient, type Session, type SupabaseClient } from "@supabase/supabase-js";
import {
  type FormEvent,
  useCallback,
  useEffect,
  useMemo,
  useState,
} from "react";

import { type AppRole, type Tab, type AssignmentRoute, type OrdinationKind, type Profile, type Church, type Person, type Ministry, type Position, type Term, type Assignment, type Snapshot, emptySnapshot, navItems, personName, ordinationKind, ordinationLabels, ordinationField, todayISO, formatDate, isCurrent, normalizeError, loadAllPeople, functionErrorMessage, isFutureJwtError, adminErrorMessage, wait, membershipPriority, type MutationRunner } from "./admin-shared";
import { AssignView } from "./assign-view";
import { SectionHeading } from "./section-heading";
import { DeleteAccountButton } from "./delete-account";

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
  const [assignmentRoute, setAssignmentRoute] = useState<AssignmentRoute>({});
  const openAssign = (route: AssignmentRoute) => { setAssignmentRoute(route); setActiveTab("assign"); };
  const [booting, setBooting] = useState(Boolean(supabase));
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
        for (let attempt = 0; attempt < 3; attempt += 1) {
          try {
            const [profileResult, peopleResult, ministryResult, positionResult, termResult, assignmentResult] =
              await Promise.all([
                supabase
                  .from("profiles")
                  .select("user_id,display_name,app_role,church_id,is_platform_admin,access_disabled,must_change_password,churches(name,slug,support_email)")
                  .eq("user_id", userId)
                  .single(),
                loadAllPeople(supabase),
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

            const profileData = profileResult.data;
            setProfile({ ...profileData, churches: Array.isArray(profileData.churches) ? profileData.churches[0] : profileData.churches } as Profile);
            setSnapshot({
              people: (peopleResult.data ?? []) as Person[],
              ministries: (ministryResult.data ?? []) as Ministry[],
              positions: (positionResult.data ?? []) as Position[],
              terms: (termResult.data ?? []) as Term[],
              assignments: (assignmentResult.data ?? []) as Assignment[],
            });
            setError(null);
            return;
          } catch (caught) {
            if (isFutureJwtError(caught) && attempt < 2) {
              setError(null);
              await wait((attempt + 1) * 1_200);
              continue;
            }
            throw caught;
          }
        }
      } catch (caught) {
        setError(adminErrorMessage(caught));
      } finally {
        if (!quiet) setLoading(false);
      }
    },
    [supabase],
  );

  useEffect(() => {
    if (!supabase) return;
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
    return <AdminLogin supabase={supabase} notice={notice} setNotice={setNotice} />;
  }

  if (profile?.access_disabled) return <main className="admin-login-shell"><section className="admin-login-card"><h1>App access removed</h1><p>Contact your administrator to restore access.</p><DeleteAccountButton supabase={supabase} /><button className="button" onClick={() => void supabase.auth.signOut()}>Sign Out</button></section></main>;
  if (profile?.must_change_password) return <InitialPasswordChange supabase={supabase} complete={() => loadData(session.user.id)} />;

  return (
    <div className="admin-app-shell">
      <header className="admin-header">
        <div className="admin-brand">
          <img src="/ministry-logo.png" alt="Riverview Ministry Volunteers logo" />
          <div>
            <p>{profile?.churches?.name ?? "Ministry Volunteers"}</p>
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
          {!loading && !profile && (
            <section className="admin-card admin-session-recovery" aria-live="polite">
              <p className="eyebrow">Secure session</p>
              <h2>Reconnect to ministry data</h2>
              <p>
                The login succeeded, but the secure data session has not finished synchronizing.
              </p>
              <button
                className="button button-primary"
                onClick={() => void loadData(session.user.id)}
                disabled={working}
              >
                Try Again
              </button>
            </section>
          )}
          {!loading && profile && (
            <>
              {activeTab === "focus" && (
                <FocusView
                  onAssign={openAssign}
                  supabase={supabase}
                  snapshot={snapshot}
                  canEdit={canEdit}
                  working={working}
                  mutate={mutate}
                />
              )}
              {activeTab === "assign" && (
                <AssignView
                  initialRoute={assignmentRoute}
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

function InitialPasswordChange({supabase,complete}:{supabase:SupabaseClient;complete:()=>Promise<void>}) {
  const [password,setPassword]=useState(""); const [confirmation,setConfirmation]=useState(""); const [busy,setBusy]=useState(false); const [error,setError]=useState<string|null>(null);
  return <main className="admin-login-shell"><section className="admin-login-card"><DeleteAccountButton supabase={supabase} /><h1>Change your temporary password</h1><p>Choose a new password before using the app. Use at least 14 characters.</p><form className="admin-form-stack" onSubmit={async event=>{event.preventDefault(); if(password.length<14 || password!==confirmation){setError("Enter matching passwords with at least 14 characters.");return;} setBusy(true); const {error}=await supabase.auth.updateUser({password}); if(error)setError(error.message); else await complete(); setBusy(false);}}><label>New password<input type="password" autoComplete="new-password" minLength={14} value={password} onChange={e=>setPassword(e.target.value)} required /></label><label>Confirm new password<input type="password" autoComplete="new-password" value={confirmation} onChange={e=>setConfirmation(e.target.value)} required /></label>{error&&<p role="alert">{error}</p>}<button className="button button-primary" disabled={busy}>Save New Password</button><button type="button" className="button" onClick={()=>void supabase.auth.signOut()}>Sign Out</button></form></section></main>;
}

type ManagedAppUser = {user_id:string;email:string;app_role:AppRole;church_id:string;is_platform_admin:boolean;access_disabled:boolean;must_change_password:boolean;enrolled:boolean};
function AppUserManagement({supabase,profile,session,working,mutate}:{supabase:SupabaseClient;profile:Profile;session:Session;working:boolean;mutate:MutationRunner}) {
 const [users,setUsers]=useState<ManagedAppUser[]>([]); const [error,setError]=useState<string|null>(null);
 const load=useCallback(async()=>{const {data,error}=await supabase.functions.invoke("admin-users",{body:{action:"list"}}); if(error)setError(await functionErrorMessage(error)); else{setUsers(data.users);setError(null);}},[supabase]);
 useEffect(() => {
   let active = true;
   void supabase.functions.invoke("admin-users", {body: {action: "list"}}).then(async ({data, error}) => {
     const message = error ? await functionErrorMessage(error) : null;
     if (!active) return;
     setError(message);
     if (!error) setUsers(data.users);
   });
   return () => {active = false;};
 }, [supabase, profile]);
 async function change(user:ManagedAppUser,action:string,role?:AppRole){if(await mutate("App access updated.",async()=>{const {error}=await supabase.functions.invoke("admin-users",{body:{action,user_id:user.user_id,role,...(action==="delete_user"?{confirmation:"DELETE"}:{})}});if(error)throw new Error(await functionErrorMessage(error));}))await load();}
 return <section className="admin-card full-panel"><h3>Manage App Users</h3><p>Changes apply to existing accounts. Remove access keeps records and can be reversed.</p><button className="button" onClick={()=>void load()}>Refresh Users</button>{error&&<p role="alert">{error}</p>}<ul className="admin-focus-list">{users.map(user=>{const protectedUser=user.user_id===session.user.id||user.is_platform_admin||(!profile.is_platform_admin&&user.app_role==="admin");return <li key={user.user_id}><strong>{user.email}</strong><p>{user.access_disabled?"Access removed":user.must_change_password?"Password change required":user.enrolled?"Active":"Invitation pending"}</p><label>Permissions for {user.email}<select value={user.app_role} disabled={working||protectedUser||user.access_disabled} onChange={e=>void change(user,"update_role",e.target.value as AppRole)}>{profile.is_platform_admin&&<option value="admin">Administrator</option>}<option value="editor">Editor</option><option value="viewer">Viewer</option></select></label><button className="button" disabled={working||protectedUser} onClick={()=>void change(user,user.access_disabled?"restore_access":"remove_access")}>{user.access_disabled?"Restore Access":"Remove Access"}</button>{!user.enrolled&&!user.access_disabled&&<button className="button" disabled={working} onClick={async()=>{await mutate("New setup email sent.",async()=>{const {error}=await supabase.functions.invoke("admin-users",{body:{email:user.email,role:user.app_role,church_id:user.church_id}});if(error)throw new Error(await functionErrorMessage(error));});}}>Resend Setup Email</button>}<button className="button button-danger" disabled={working||protectedUser} onClick={()=>{if(window.confirm(`Permanently delete ${user.email}? This deletes their login and account profile. Church-owned volunteer records and assignments are preserved. This cannot be undone.`))void change(user,"delete_user");}}>Delete User Permanently</button></li>;})}</ul></section>;
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
  notice,
  setNotice,
}: {
  supabase: SupabaseClient;
  notice: string | null;
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
          {notice && <p role="status">{notice}</p>}
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

function FocusView({ supabase, snapshot, canEdit, working, mutate, onAssign }: {
  supabase: SupabaseClient; snapshot: Snapshot; canEdit: boolean; working: boolean;
  mutate: MutationRunner; onAssign: (route: AssignmentRoute) => void;
}) {
  const current = snapshot.assignments.filter(isCurrent);
  const needingVotes = current.filter(a => a.vote_missing);
  const cutoff = new Date(); cutoff.setMonth(cutoff.getMonth() + 6);
  const ending = current.filter(a => a.end_date && a.end_date >= todayISO() && a.end_date <= cutoff.toISOString().slice(0,10));
  const assigned = new Set(current.map(a => a.person_id));
  const unassigned = snapshot.people.filter(p => p.is_active && !assigned.has(p.id)).sort((a,b) => membershipPriority(a.membership_status)-membershipPriority(b.membership_status) || a.last_name.localeCompare(b.last_name));
  const occupied = new Set(current.map(a => a.role_id));
  const empty = snapshot.ministries.filter(m => m.is_active && !occupied.has(m.id));
  const people = new Map(snapshot.people.map(p => [p.id,p]));
  const needs = new Map<string,{person:Person;kind:OrdinationKind;assignment:Assignment}>();
  for (const assignment of current) { const kind = ordinationKind(assignment.role_name); const person = people.get(assignment.person_id); if (kind && person?.is_active && !person[ordinationField(kind)]) needs.set(person.id+kind,{person,kind,assignment}); }
  return <>
    <SectionHeading title="Placement Focus" detail="Choose a person or action to resolve the items below." />
    <section className="admin-card"><h3>Needing Votes</h3>
      {!needingVotes.length && <p>No placements are waiting for a vote.</p>}
      {needingVotes.map(assignment => <VoteRow key={assignment.id} assignment={assignment} canEdit={canEdit} working={working} save={async date => { await mutate("Church vote recorded.",async () => { const {error}=await supabase.from("assignments").update({vote_date:date}).eq("id",assignment.id); if(error) throw error; }); }} />)}
    </section>
    <FocusList title="Ordination Actions" empty="Every current Deacon, Deaconess, and Elder is marked ordained." items={[...needs.values()].map(({person,kind,assignment}) => ({title:personName(person),detail:assignment.role_name,actionLabel:canEdit ? "Mark ordained" : undefined,actionDisabled:working,onAction:() => { void mutate("Ordination record updated.",async () => { const {error}=await supabase.from("people").update({[ordinationField(kind)]:true}).eq("id",person.id); if(error) throw error; }); }}))} />
    <FocusList title="Terms ending in the next 6 months" empty="No current terms end in the next 6 months." items={ending.map(a => ({title:a.person_name,detail:a.role_name+" · ends "+formatDate(a.end_date),actionLabel:canEdit ? "Assign ministry" : undefined,onAction:() => onAssign({personId:a.person_id,ministryId:a.role_id})}))} />
    <FocusList title="Ministries Needing Volunteers" empty="Every active ministry has a current volunteer." items={empty.map(m => ({title:m.name,detail:"No active placement",actionLabel:canEdit ? "Assign volunteer" : undefined,onAction:() => onAssign({ministryId:m.id})}))} />
    <FocusList title="Volunteer Activation" empty="Every active person has a current role." items={unassigned.map(p => ({title:personName(p),detail:p.membership_status || "Membership not recorded",emphasized:membershipPriority(p.membership_status)===0,actionLabel:canEdit ? "Assign ministry" : undefined,onAction:() => onAssign({personId:p.id})}))} />
  </>;
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
              {item.onAction && item.actionLabel ? <button type="button" className="button button-link" disabled={item.actionDisabled} onClick={item.onAction}>{item.title}</button> : <strong>{item.title}</strong>}
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
  const requiresVote = Boolean(positionId && (assignment.ministry_requires_vote || selectedPosition?.requires_vote));

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
            <select value={positionId} onChange={(event) => {
              setPositionId(event.target.value);
              if (!event.target.value) { setTermId(""); setVoteDate(""); }
            }}>
              <option value="">No position — team member</option>
              {positions.map((position) => <option key={position.id} value={position.id}>{position.name}</option>)}
            </select>
          </label>
          <label>
            Term {requiresVote ? "(required)" : "(optional)"}
            <select value={termId} onChange={(event) => setTermId(event.target.value)} disabled={!positionId}>
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
                  term_id: positionId ? termId || null : null,
                  vote_date: positionId ? voteDate || null : null,
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
                  if (error) throw new Error(await functionErrorMessage(error));
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
          <a className="button button-primary" href="/directory" target="_blank" rel="noreferrer">Open Full Report</a>
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
  const [inviteRole, setInviteRole] = useState<AppRole>("editor");
  const [churches, setChurches] = useState<Church[]>([]);
  const [inviteChurchId, setInviteChurchId] = useState(profile.church_id);
  const [temporaryPassword, setTemporaryPassword] = useState("");
  const [reviewAccount,setReviewAccount]=useState(false);
  const [pcoApplicationId, setPcoApplicationId] = useState("");
  const [pcoSecret, setPcoSecret] = useState("");
  const [pcoConnected, setPcoConnected] = useState<boolean | null>(null);

  useEffect(() => {
    void supabase.rpc("planning_center_connection_status").then(({ data }) => {
      const status = data as { connected?: boolean } | null;
      setPcoConnected(Boolean(status?.connected));
    });
    if (profile.is_platform_admin) {
      void supabase.from("churches").select("id,name,slug").order("name").then(({ data }) => {
        setChurches((data ?? []) as Church[]);
      });
    }
  }, [profile.is_platform_admin, supabase]);
  return (
    <>
      <SectionHeading title="Settings" detail="Account, Planning Center sync, and administrator-only user access." />
      <div className="admin-two-column">
        <section className="admin-card admin-settings-card">
          <h3>Your account</h3>
          <dl><dt>Email</dt><dd>{session.user.email}</dd><dt>Access</dt><dd>{profile.app_role}</dd></dl>
          <button className="button" onClick={() => void supabase.auth.signOut()}>Sign Out</button>
          <DeleteAccountButton supabase={supabase} />
        </section>
        <section className="admin-card admin-settings-card">
          <h3>Planning Center People</h3>
          <p>Planning Center remains the source of truth for contact and membership information. This sync is read-only and uses this church&apos;s own Personal Access Token.</p>
          <p><strong>{pcoConnected === null ? "Checking connection…" : pcoConnected ? "Connected" : "Not connected"}</strong></p>
          {profile.app_role === "admin" && (
            <div className="admin-form-grid">
              <label>Personal Access Token application ID<input type="password" autoComplete="off" value={pcoApplicationId} onChange={(event) => setPcoApplicationId(event.target.value)} /></label>
              <label>Personal Access Token secret<input type="password" autoComplete="off" value={pcoSecret} onChange={(event) => setPcoSecret(event.target.value)} /></label>
              <button className="button admin-connection-save" disabled={working || !pcoApplicationId.trim() || !pcoSecret.trim()} onClick={async () => {
                const succeeded = await mutate("Planning Center connection saved securely.", async () => {
                  const { error } = await supabase.rpc("configure_planning_center", { p_application_id: pcoApplicationId.trim(), p_secret: pcoSecret.trim() });
                  if (error) throw error;
                });
                if (succeeded) { setPcoApplicationId(""); setPcoSecret(""); setPcoConnected(true); }
              }}>Save Connection</button>
            </div>
          )}
          <p><a href="https://api.planningcenteronline.com/docs/overview/authentication" target="_blank" rel="noreferrer">Where to create a Planning Center Personal Access Token</a></p>
          <button className="button button-primary" disabled={!canEdit || working} onClick={() => mutate("Planning Center sync completed.", async () => {
            const { error } = await supabase.functions.invoke("planning-center-sync", { body: {} });
            if (error) throw error;
          })}>Sync Planning Center</button>
        </section>
        {profile.app_role === "admin" && (
          <section className="admin-card admin-settings-card full-panel">
            <h3>Create or resend an app user</h3>
            <p>Leave the temporary password blank to email a setup link valid for 24 hours. Enter a temporary password to create an account that requires a password change at first login. Provide that password to the user separately.</p>
            <div className="admin-form-grid invite-grid">
              <label>Email<input type="email" value={inviteEmail} onChange={(event) => setInviteEmail(event.target.value)} /></label>
              <label>Access<select value={inviteRole} onChange={(event) => setInviteRole(event.target.value as AppRole)}>{profile.is_platform_admin && <option value="admin">Administrator</option>}<option value="editor">Editor</option><option value="viewer">Viewer</option></select></label>
              {profile.is_platform_admin && <label>Church<select value={inviteChurchId} onChange={(event) => setInviteChurchId(event.target.value)}>{churches.map((church) => <option key={church.id} value={church.id}>{church.name}</option>)}</select></label>}
              {<label>Temporary password (optional; change required at first login)<input type="password" autoComplete="new-password" value={temporaryPassword} onChange={(event) => setTemporaryPassword(event.target.value)} /></label>}
              {profile.is_platform_admin && <label><input type="checkbox" checked={reviewAccount} onChange={e=>setReviewAccount(e.target.checked)} />App Store review account (fixed password)</label>}
              <button className="button button-primary admin-check-bottom" disabled={working || !inviteEmail.trim()} onClick={async () => {
                const succeeded = await mutate(temporaryPassword ? (reviewAccount ? "Review account password saved." : "Temporary password saved. Password change is required at first login.") : "Setup email sent. Use the newest message.", async () => {
                  const { error } = await supabase.functions.invoke("admin-users", { body: { email: inviteEmail.trim(), role: inviteRole, church_id: inviteChurchId, temporary_password: temporaryPassword || undefined, review_account: reviewAccount } });
                  if (error) throw new Error(await functionErrorMessage(error));
                });
                if (succeeded) { setInviteEmail(""); setTemporaryPassword(""); }
              }}>{temporaryPassword ? "Create with Temporary Password" : "Create or Resend Setup Email"}</button>
            </div>
          </section>
        )}
        {profile.app_role === "admin" && <AppUserManagement supabase={supabase} profile={profile} session={session} working={working} mutate={mutate} />}
      </div>
    </>
  );
}
