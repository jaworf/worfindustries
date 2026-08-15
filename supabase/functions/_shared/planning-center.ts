import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.110.8";

export const planningCenterApiVersion =
  Deno.env.get("PCO_API_VERSION") ?? "2026-06-04";

type JsonApiIdentifier = {
  type: string;
  id: string;
};

type JsonApiResource = JsonApiIdentifier & {
  attributes: Record<string, unknown>;
  relationships?: Record<
    string,
    { data: JsonApiIdentifier | JsonApiIdentifier[] | null }
  >;
};

type PlanningCenterResponse = {
  data: JsonApiResource | JsonApiResource[];
  included?: JsonApiResource[];
  links?: {
    next?: string | null;
  };
};

export type MinistryPersonRecord = {
  first_name: string;
  middle_name?: string | null;
  last_name: string;
  preferred_name?: string | null;
  suffix?: string | null;
  email?: string | null;
  mobile_phone?: string | null;
  home_phone?: string | null;
  address_line_1?: string | null;
  address_line_2?: string | null;
  city?: string | null;
  state_region?: string | null;
  postal_code?: string | null;
  country_code?: string | null;
  membership_status?: string | null;
  is_active: boolean;
  source_created_at?: string | null;
  source_updated_at?: string | null;
};

function requiredSecret(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`Missing required secret: ${name}`);
  }
  return value;
}

function serviceKey(): string {
  const single =
    Deno.env.get("SUPABASE_SECRET_KEY") ??
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (single) return single;

  const encoded = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (!encoded) {
    throw new Error(
      "Missing SUPABASE_SECRET_KEYS or SUPABASE_SERVICE_ROLE_KEY.",
    );
  }

  const keys = JSON.parse(encoded) as Record<string, string>;
  const firstKey = keys.default ?? Object.values(keys)[0];
  if (!firstKey) {
    throw new Error("SUPABASE_SECRET_KEYS does not contain a usable key.");
  }
  return firstKey;
}

function publishableKey(): string {
  const single =
    Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ??
    Deno.env.get("SUPABASE_ANON_KEY");
  if (single) return single;

  const encoded = Deno.env.get("SUPABASE_PUBLISHABLE_KEYS");
  if (!encoded) {
    throw new Error(
      "Missing SUPABASE_PUBLISHABLE_KEYS, SUPABASE_PUBLISHABLE_KEY, or SUPABASE_ANON_KEY.",
    );
  }
  const keys = JSON.parse(encoded) as Record<string, string>;
  const firstKey = keys.default ?? Object.values(keys)[0];
  if (!firstKey) {
    throw new Error("SUPABASE_PUBLISHABLE_KEYS does not contain a usable key.");
  }
  return firstKey;
}

export function adminClient(): SupabaseClient {
  return createClient(requiredSecret("SUPABASE_URL"), serviceKey(), {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}

export async function requireEditor(
  request: Request,
): Promise<{ userId: string; churchId: string }> {
  const authorization = request.headers.get("Authorization");
  if (!authorization) {
    throw new Error("Authentication is required.");
  }

  const client = createClient(
    requiredSecret("SUPABASE_URL"),
    publishableKey(),
    {
      global: { headers: { Authorization: authorization } },
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    },
  );
  const {
    data: { user },
    error: userError,
  } = await client.auth.getUser();
  if (userError || !user) {
    throw new Error("The Supabase session is invalid.");
  }

  const { data: profile, error: profileError } = await client
    .from("profiles")
    .select("app_role,church_id")
    .eq("user_id", user.id)
    .single();
  if (
    profileError ||
    !profile ||
    !["admin", "editor"].includes(profile.app_role)
    || typeof profile.church_id !== "string"
  ) {
    throw new Error("An admin or editor account is required.");
  }
  return { userId: user.id, churchId: profile.church_id };
}

export type PlanningCenterCredentials = {
  applicationId: string;
  secret: string;
};

export function legacyPlanningCenterCredentials(): PlanningCenterCredentials {
  return {
    applicationId: requiredSecret("PCO_CLIENT_ID"),
    secret: requiredSecret("PCO_CLIENT_SECRET"),
  };
}

function planningCenterHeaders(credentials?: PlanningCenterCredentials): HeadersInit {
  const clientId = credentials?.applicationId ?? requiredSecret("PCO_CLIENT_ID");
  const clientSecret = credentials?.secret ?? requiredSecret("PCO_CLIENT_SECRET");

  return {
    Accept: "application/json",
    Authorization: `Basic ${btoa(`${clientId}:${clientSecret}`)}`,
    "User-Agent":
      "Riverview Ministry Volunteers (jason.worf@riverviewadventist.org)",
    "X-PCO-API-Version": planningCenterApiVersion,
  };
}

export async function planningCenterRequest(
  url: string,
  credentials?: PlanningCenterCredentials,
): Promise<PlanningCenterResponse> {
  const response = await fetch(url, {
    method: "GET",
    headers: planningCenterHeaders(credentials),
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(
      `Planning Center returned ${response.status}: ${body.slice(0, 500)}`,
    );
  }

  return (await response.json()) as PlanningCenterResponse;
}

function relationshipResources(
  person: JsonApiResource,
  included: JsonApiResource[],
  relationshipName: string,
): JsonApiResource[] {
  const relationship = person.relationships?.[relationshipName]?.data;
  const identifiers = Array.isArray(relationship)
    ? relationship
    : relationship
      ? [relationship]
      : [];
  const ids = new Set(identifiers.map((identifier) => identifier.id));
  return included.filter((resource) => ids.has(resource.id));
}

function primaryResource(resources: JsonApiResource[]): JsonApiResource | null {
  return (
    resources.find((resource) => resource.attributes.primary === true) ??
    resources[0] ??
    null
  );
}

function stringAttribute(
  resource: JsonApiResource | null,
  name: string,
): string | null {
  const value = resource?.attributes[name];
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

export function personRecordFromResponse(
  person: JsonApiResource,
  included: JsonApiResource[],
): MinistryPersonRecord {
  const emails = relationshipResources(person, included, "emails");
  const phones = relationshipResources(person, included, "phone_numbers");
  const addresses = relationshipResources(person, included, "addresses");
  const suffixes = relationshipResources(person, included, "name_suffix");

  const email = primaryResource(emails);
  const primaryPhone = primaryResource(phones);
  const mobilePhone =
    phones.find((phone) =>
      String(phone.attributes.location ?? "")
        .toLowerCase()
        .includes("mobile")
    ) ?? primaryPhone;
  const homePhone =
    phones.find((phone) =>
      String(phone.attributes.location ?? "")
        .toLowerCase()
        .includes("home")
    ) ?? null;
  const address = primaryResource(addresses);
  const suffix = primaryResource(suffixes);
  const status = String(person.attributes.status ?? "").toLowerCase();

  return {
    first_name: String(person.attributes.first_name ?? "").trim(),
    middle_name:
      typeof person.attributes.middle_name === "string"
        ? person.attributes.middle_name.trim() || null
        : null,
    last_name: String(person.attributes.last_name ?? "").trim(),
    preferred_name:
      typeof person.attributes.nickname === "string"
        ? person.attributes.nickname.trim() || null
        : null,
    suffix:
      stringAttribute(suffix, "value") ?? stringAttribute(suffix, "name"),
    email: stringAttribute(email, "address"),
    mobile_phone:
      stringAttribute(mobilePhone, "number") ??
      stringAttribute(mobilePhone, "national"),
    home_phone:
      stringAttribute(homePhone, "number") ??
      stringAttribute(homePhone, "national"),
    address_line_1: stringAttribute(address, "street_line_1"),
    address_line_2: stringAttribute(address, "street_line_2"),
    city: stringAttribute(address, "city"),
    state_region: stringAttribute(address, "state"),
    postal_code: stringAttribute(address, "zip"),
    country_code: stringAttribute(address, "country_code"),
    membership_status:
      typeof person.attributes.membership === "string"
        ? person.attributes.membership.trim() || null
        : null,
    is_active: status === "active" && !person.attributes.inactivated_at,
    source_created_at:
      typeof person.attributes.created_at === "string"
        ? person.attributes.created_at
        : null,
    source_updated_at:
      typeof person.attributes.updated_at === "string"
        ? person.attributes.updated_at
        : null,
  };
}

export async function fetchPeoplePage(
  url:
    | string
    | null = "https://api.planningcenteronline.com/people/v2/people?include=emails,phone_numbers,addresses,name_suffix&per_page=100",
  credentials?: PlanningCenterCredentials,
): Promise<{
  people: Array<{ externalId: string; record: MinistryPersonRecord }>;
  nextUrl: string | null;
}> {
  if (!url) return { people: [], nextUrl: null };

  const response = await planningCenterRequest(url, credentials);
  const people = Array.isArray(response.data) ? response.data : [response.data];
  const included = response.included ?? [];

  return {
    people: people
      .map((person) => ({
        externalId: person.id,
        record: personRecordFromResponse(person, included),
      }))
      .filter(
        ({ record }) => Boolean(record.first_name) && Boolean(record.last_name),
      ),
    nextUrl: response.links?.next ?? null,
  };
}

export async function fetchPerson(
  personId: string,
): Promise<{ externalId: string; record: MinistryPersonRecord }> {
  const url =
    `https://api.planningcenteronline.com/people/v2/people/${encodeURIComponent(personId)}` +
    "?include=emails,phone_numbers,addresses,name_suffix";
  const response = await planningCenterRequest(url);
  if (Array.isArray(response.data)) {
    throw new Error("Expected one Planning Center person.");
  }

  return {
    externalId: response.data.id,
    record: personRecordFromResponse(response.data, response.included ?? []),
  };
}

export async function mergePlanningCenterPerson(
  supabase: SupabaseClient,
  churchId: string,
  person: { externalId: string; record: MinistryPersonRecord },
  importRunId: string | null,
): Promise<{ outcome: string; person_id?: string; message?: string }> {
  const { data, error } = await supabase.rpc("sync_planning_center_person_for_church", {
    p_church_id: churchId,
    p_external_id: person.externalId,
    p_record: person.record,
    p_import_run_id: importRunId,
    p_row_number: null,
  });

  if (error) throw error;
  return data as { outcome: string; person_id?: string; message?: string };
}

export async function mapWithConcurrency<T, R>(
  values: T[],
  concurrency: number,
  work: (value: T) => Promise<R>,
): Promise<R[]> {
  const results = new Array<R>(values.length);
  let cursor = 0;

  async function worker(): Promise<void> {
    while (true) {
      const index = cursor;
      cursor += 1;
      if (index >= values.length) return;
      results[index] = await work(values[index]);
    }
  }

  await Promise.all(
    Array.from(
      { length: Math.min(concurrency, values.length) },
      () => worker(),
    ),
  );
  return results;
}
