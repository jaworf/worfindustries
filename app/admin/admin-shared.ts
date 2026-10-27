import type { SupabaseClient } from "@supabase/supabase-js";
export type AppRole = "admin" | "editor" | "viewer";
export type Tab =
  | "focus"
  | "assign"
  | "ministries"
  | "people"
  | "votes"
  | "manage"
  | "reports"
  | "users"
  | "settings";
export type AssignmentRoute = { personId?: string; ministryId?: string };
export type OrdinationKind = "deacon" | "deaconess" | "elder";

export type Profile = {
  user_id: string;
  display_name: string | null;
  app_role: AppRole;
  church_id: string;
  is_platform_admin: boolean;
  access_disabled?: boolean;
  must_change_password?: boolean;
  churches: { name: string; slug: string; support_email: string | null } | null;
};

export type Church = { id: string; name: string; slug: string };

export type Person = {
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

export type Ministry = {
  id: string;
  name: string;
  description: string | null;
  requires_vote: boolean;
  is_active: boolean;
  is_public: boolean;
  display_order: number;
  archived_at: string | null;
};

export type Position = {
  id: string;
  role_id: string | null;
  name: string;
  leadership_rank: number;
  requires_vote: boolean;
  is_active: boolean;
};

export type Term = {
  id: string;
  name: string;
  start_date: string | null;
  end_date: string | null;
  term_type: string;
  is_active: boolean;
};

export type Assignment = {
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

export type Snapshot = {
  people: Person[];
  ministries: Ministry[];
  positions: Position[];
  terms: Term[];
  assignments: Assignment[];
};

export const emptySnapshot: Snapshot = {
  people: [],
  ministries: [],
  positions: [],
  terms: [],
  assignments: [],
};

export const navItems: Array<{ id: Tab; label: string; short: string }> = [
  { id: "focus", label: "Focus", short: "Focus" },
  { id: "assign", label: "Assign", short: "Assign" },
  { id: "ministries", label: "Ministry Directory", short: "Ministries" },
  { id: "people", label: "People Directory", short: "People" },
  { id: "votes", label: "Awaiting Vote", short: "Votes" },
  { id: "manage", label: "Manage", short: "Manage" },
  { id: "reports", label: "Reports", short: "Reports" },
  { id: "users", label: "Users", short: "Users" },
  { id: "settings", label: "Settings", short: "Settings" },
];

export function personName(person: Person) {
  return [person.preferred_name || person.first_name, person.last_name, person.suffix]
    .filter(Boolean)
    .join(" ");
}

export function ordinationKind(ministryName: string | undefined): OrdinationKind | null {
  const normalized = ministryName?.trim().toLowerCase();
  return normalized === "deacon" || normalized === "deaconess" || normalized === "elder"
    ? normalized
    : null;
}

export function ordinationLabel(kind: OrdinationKind) {
  return `Ordained ${kind[0].toUpperCase()}${kind.slice(1)}`;
}

export function ordinationLabels(person: Person) {
  const labels: string[] = [];
  if (person.is_ordained_deacon) labels.push("Ordained Deacon");
  if (person.is_ordained_deaconess) labels.push("Ordained Deaconess");
  if (person.is_ordained_elder) labels.push("Ordained Elder");
  return labels;
}

export function ordinationField(kind: OrdinationKind) {
  return `is_ordained_${kind}` as
    | "is_ordained_deacon"
    | "is_ordained_deaconess"
    | "is_ordained_elder";
}

export function todayISO() {
  const now = new Date();
  const local = new Date(now.getTime() - now.getTimezoneOffset() * 60_000);
  return local.toISOString().slice(0, 10);
}

export function formatDate(value: string | null | undefined) {
  if (!value) return "No end date";
  return new Intl.DateTimeFormat("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
  }).format(new Date(`${value}T12:00:00`));
}

export function isCurrent(assignment: Assignment) {
  return (
    assignment.status === "active" &&
    assignment.ministry_is_active &&
    (!assignment.end_date || assignment.end_date >= todayISO())
  );
}

export function normalizeError(error: unknown) {
  if (error instanceof Error) return error.message;
  if (typeof error === "object" && error && "message" in error) {
    return String((error as { message: unknown }).message);
  }
  return "The request could not be completed.";
}

export async function loadAllPeople(supabase: SupabaseClient) {
  const people: Person[] = [];
  for (let offset = 0; ; offset += 1000) {
    const { data, error } = await supabase.from("people").select("*")
      .order("last_name").order("first_name").order("id").range(offset, offset + 999);
    if (error) return { data: null, error };
    people.push(...(data as Person[]));
    if (data.length < 1000) return { data: people, error: null };
  }
}

export async function functionErrorMessage(error: unknown) {
  if (typeof error === "object" && error && "context" in error) {
    const context = (error as { context?: unknown }).context;
    if (context instanceof Response) {
      try {
        const body = await context.clone().json();
        const message = body.error ?? body.message;
        if (typeof message === "string" && message.trim()) return message;
      } catch {
        // Keep the SDK message if the response is not JSON.
      }
    }
  }
  return normalizeError(error);
}

export function isFutureJwtError(error: unknown) {
  return normalizeError(error).toLowerCase().includes("jwt issued at future");
}

export function adminErrorMessage(error: unknown) {
  if (isFutureJwtError(error)) {
    return "The secure session is still synchronizing. Check that this device sets its date and time automatically, then try again.";
  }
  return normalizeError(error);
}

export function wait(milliseconds: number) {
  return new Promise<void>((resolve) => window.setTimeout(resolve, milliseconds));
}

export function membershipPriority(value: string | null) {
  const normalized = value?.trim().toLowerCase() ?? "";
  if (normalized === "riverview member") return 0;
  if (normalized.includes("riverview") && normalized.includes("member")) return 1;
  if (normalized.includes("member")) return 2;
  return 3;
}


export type MutationRunner = (successMessage: string, action: () => Promise<void>) => Promise<boolean>;
