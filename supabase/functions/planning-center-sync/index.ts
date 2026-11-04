import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { corsHeaders } from "npm:@supabase/supabase-js@2.110.8/cors";
import {
  adminClient,
  fetchPeoplePage,
  planningCenterRequest,
  mapWithConcurrency,
  mergePlanningCenterPerson,
  legacyPlanningCenterCredentials,
  planningCenterApiVersion,
  requireEditor,
} from "../_shared/planning-center.ts";

const jsonHeaders = {
  ...corsHeaders,
  "Content-Type": "application/json",
};

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") {
    return new Response(
      JSON.stringify({ error: "Method not allowed." }),
      { status: 405, headers: jsonHeaders },
    );
  }

  try {
    const caller = await requireEditor(request);
    const supabase = adminClient();
    const { data: credentialsRows, error: credentialsError } = await supabase.rpc(
      "get_planning_center_credentials",
      { p_church_id: caller.churchId },
    );
    if (credentialsError) throw credentialsError;
    const credentials = Array.isArray(credentialsRows) ? credentialsRows[0] : null;
    let resolvedCredentials;
    if (credentials?.application_id && credentials?.secret) {
      resolvedCredentials = {
        applicationId: credentials.application_id,
        secret: credentials.secret,
      };
    } else {
      const { data: church } = await supabase
        .from("churches")
        .select("slug")
        .eq("id", caller.churchId)
        .single();
      if (church?.slug !== "riverview") {
        throw new Error("Connect this church's Planning Center account before syncing.");
      }
      // Preserve Riverview's existing server-side connection while it is
      // migrated to the new per-church Vault form.
      resolvedCredentials = legacyPlanningCenterCredentials();
    }

    const payload = await request.json().catch(() => ({}));
    if (payload?.action && payload.action !== "membership_types") throw new Error("Unknown Planning Center action.");
    if (payload?.action === "membership_types") {
      const values: string[] = [];
      let next: string | null = "https://api.planningcenteronline.com/people/v2/membership_types?per_page=100";
      for (let page = 0; next; page++) {
        if (page >= 100 || new URL(next).origin !== "https://api.planningcenteronline.com" || new URL(next).pathname !== "/people/v2/membership_types") throw new Error("Invalid membership pagination.");
        const result = await planningCenterRequest(next, resolvedCredentials);
        for (const resource of Array.isArray(result.data) ? result.data : [result.data]) {
          if (typeof resource.attributes.value === "string") values.push(resource.attributes.value.trim());
        }
        next = result.links?.next ?? null;
      }
      const options = [...new Set(values.filter(Boolean))].sort();
      const { error } = await supabase.rpc("cache_pco_membership_types", { p_church_id: caller.churchId, p_values: options });
      if (error) throw error;
      return new Response(JSON.stringify({ membership_types: options }), { headers: jsonHeaders });
    }
    return await runSync(caller.churchId, resolvedCredentials);
  } catch (error) {
    return new Response(
      JSON.stringify({
        error: error instanceof Error ? error.message : "Access denied.",
      }),
      { status: 400, headers: jsonHeaders },
    );
  }
});

async function runSync(
  churchId: string,
  credentials: { applicationId: string; secret: string },
): Promise<Response> {
  const supabase = adminClient();
  const { data: run, error: runError } = await supabase
    .from("import_runs")
    .insert({
      church_id: churchId,
      source_type: "planning_center",
      source_name: `Planning Center People ${planningCenterApiVersion}`,
      status: "processing",
    })
    .select("id")
    .single();

  if (runError) {
    return new Response(
      JSON.stringify({ error: runError.message }),
      { status: 500, headers: jsonHeaders },
    );
  }

  const counts: Record<string, number> = {
    inserted: 0,
    updated: 0,
    unchanged: 0,
    conflict: 0,
    error: 0,
  };

  try {
    let nextUrl: string | null =
      "https://api.planningcenteronline.com/people/v2/people?include=emails,phone_numbers,addresses,name_suffix&per_page=100";
    let pageCount = 0;

    while (nextUrl) {
      pageCount += 1;
      if (pageCount > 1000) {
        throw new Error("Planning Center pagination exceeded the safety limit.");
      }

      const page = await fetchPeoplePage(nextUrl, credentials);
      const results = await mapWithConcurrency(
        page.people,
        10,
        (person) => mergePlanningCenterPerson(supabase, churchId, person, run.id),
      );
      for (const result of results) {
        const outcome = result.outcome in counts ? result.outcome : "error";
        counts[outcome] += 1;
      }
      nextUrl = page.nextUrl;
    }

    const finalStatus =
      counts.error > 0
        ? "failed"
        : counts.conflict > 0
          ? "completed_with_conflicts"
          : "completed";
    await supabase
      .from("import_runs")
      .update({
        status: finalStatus,
        inserted_count: counts.inserted,
        updated_count: counts.updated,
        unchanged_count: counts.unchanged,
        conflict_count: counts.conflict,
        error_count: counts.error,
        completed_at: new Date().toISOString(),
      })
      .eq("id", run.id);

    return new Response(
      JSON.stringify({
        import_run_id: run.id,
        status: finalStatus,
        counts,
      }),
      { status: finalStatus === "failed" ? 500 : 200, headers: jsonHeaders },
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    await supabase
      .from("import_runs")
      .update({
        status: "failed",
        error_count: counts.error + 1,
        error_message: message,
        completed_at: new Date().toISOString(),
      })
      .eq("id", run.id);

    return new Response(
      JSON.stringify({ import_run_id: run.id, error: message }),
      { status: 500, headers: jsonHeaders },
    );
  }
}
