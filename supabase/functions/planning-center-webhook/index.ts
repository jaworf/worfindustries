import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { adminClient, fetchPerson, mergePlanningCenterPerson } from "../_shared/planning-center.ts";

const headers = { "Content-Type": "application/json" };
function json(status: number, value: unknown) {
  return new Response(JSON.stringify(value), { status, headers });
}
type Connection = { churchId: string; secret: string };
type Delivery = { id: string; attributes: { name: string; payload: string } };

function connections(): Connection[] {
  const encoded = Deno.env.get("PCO_WEBHOOK_CONNECTIONS");
  const configured = encoded ? JSON.parse(encoded) : [{
    churchId: Deno.env.get("PCO_WEBHOOK_CHURCH_ID"),
    secret: Deno.env.get("PCO_WEBHOOK_SECRET"),
  }];
  if (!Array.isArray(configured)) {
    throw new Error("Configure each webhook signing secret with its church ID.");
  }
  const valid = configured.filter(item =>
    typeof item?.churchId === "string" && item.churchId &&
    typeof item?.secret === "string" && item.secret);
  // A secret must identify exactly one church; URL/body fields never choose it.
  const unique = valid.filter(item => valid.filter(other => other.secret === item.secret).length === 1);
  if (unique.length !== configured.length) console.error("Invalid or ambiguous webhook connections were disabled.");
  if (!unique.length) throw new Error("No usable webhook connections configured.");
  return unique;
}
async function validSignature(body: string, supplied: string, secret: string) {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const bytes = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(body)));
  const expected = [...bytes].map(byte => byte.toString(16).padStart(2, "0")).join("");
  const actual = supplied.toLowerCase().replace(/^sha256=/, "");
  if (actual.length !== expected.length) return false;
  let mismatch = 0;
  for (let index = 0; index < expected.length; index++) mismatch |= expected.charCodeAt(index) ^ actual.charCodeAt(index);
  return mismatch === 0;
}
function changedPersonId(delivery: Delivery): string | null {
  const event = delivery.attributes.name;
  const payload = JSON.parse(delivery.attributes.payload);
  if (/^people\.v2\.events\.person\.(created|updated|destroyed)$/.test(event)) return payload?.data?.id ?? null;
  if (/^people\.v2\.events\.(email|phone_number|address)\.(created|updated|destroyed)$/.test(event)) {
    // The contact ID is not a Person ID. Fetch its owning person, including all
    // current contacts, so deletions clear mirrored fields too.
    const person = payload?.data?.relationships?.person?.data;
    return person?.type === "Person" ? person.id : null;
  }
  return null;
}
function isPersonChange(event: string) {
  return /^people\.v2\.events\.(person\.(created|updated|destroyed)|(email|phone_number|address)\.(created|updated|destroyed))$/.test(event);
}
function deliveriesFrom(body: string): Delivery[] {
  const payload = JSON.parse(body);
  if (!Array.isArray(payload?.data) || payload.data.length > 100) throw new Error("Expected at most 100 deliveries.");
  for (const delivery of payload.data) {
    if (typeof delivery?.id !== "string" || !delivery.id ||
        typeof delivery?.attributes?.name !== "string" ||
        typeof delivery?.attributes?.payload !== "string") throw new Error("Invalid delivery structure.");
    JSON.parse(delivery.attributes.payload);
    if (isPersonChange(delivery.attributes.name)) {
      const id = changedPersonId(delivery);
      if (typeof id !== "string" || !id) throw new Error("Webhook payload has no person ID.");
    }
  }
  return payload.data;
}
Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return json(405, { error: "Method not allowed." });
  try {
    const body = await request.text();
    const signature = request.headers.get("X-PCO-Webhooks-Authenticity") ?? "";
    if (!signature) return json(401, { error: "Invalid webhook signature." });
    let connection: Connection | undefined;
    for (const candidate of connections()) {
      if (await validSignature(body, signature, candidate.secret)) connection = candidate;
    }
    if (!connection) return json(401, { error: "Invalid webhook signature." });
    let deliveries: Delivery[];
    try { deliveries = deliveriesFrom(body); }
    catch { return json(400, { error: "Malformed webhook payload." }); }
    const supabase = adminClient();
    const { data: church, error: churchError } = await supabase.from("churches")
      .select("id,is_active").eq("id", connection.churchId).single();
    if (churchError || !church?.is_active) return json(403, { error: "Webhook church is unavailable." });
    const { data: rows, error: credentialsError } = await supabase.rpc("get_planning_center_credentials", { p_church_id: church.id });
    if (credentialsError) throw credentialsError;
    const credentials = rows?.[0];
    if (!credentials?.application_id || !credentials?.secret) return json(503, { error: "Connect this church's Planning Center account before receiving webhooks." });
    const results: Record<string, unknown>[] = [];
    for (const delivery of deliveries) {
      const eventName = delivery.attributes.name;
      const { data: inserted, error: insertError } = await supabase.from("webhook_deliveries")
        .insert({ church_id: church.id, source_system: "planning_center", delivery_id: delivery.id, event_name: eventName, payload: delivery })
        .select("id").maybeSingle();
      let deliveryRowId = inserted?.id;
      if (insertError?.code === "23505") {
        // Failed deliveries must remain retryable. Completed/ignored deliveries are idempotent.
        const { data: prior, error: priorError } = await supabase.from("webhook_deliveries")
          .select("id,status").eq("church_id", church.id).eq("source_system", "planning_center").eq("delivery_id", delivery.id).single();
        if (priorError) throw priorError;
        if (prior.status !== "failed") { results.push({ delivery_id: delivery.id, status: "duplicate" }); continue; }
        deliveryRowId = prior.id;
      } else if (insertError) throw insertError;
      try {
        let status = "ignored";
        let outcome: Record<string, unknown> = {};
        if (isPersonChange(eventName)) {
          const personId = changedPersonId(delivery)!;
          if (eventName === "people.v2.events.person.destroyed") {
            // Preserve assignment history while removing the person from active directories.
            const { data: link, error: linkError } = await supabase.from("person_external_ids")
              .select("person_id").eq("church_id", church.id)
              .eq("source_system", "planning_center").eq("external_id", personId).maybeSingle();
            if (linkError) throw linkError;
            if (link) {
              const { error } = await supabase.from("people").update({ is_active: false })
                .eq("church_id", church.id).eq("id", link.person_id);
              if (error) throw error;
            }
            outcome = { outcome: link ? "deactivated" : "not_found" };
          } else {
          const person = await fetchPerson(personId, { applicationId: credentials.application_id, secret: credentials.secret });
          const merged = await mergePlanningCenterPerson(supabase, church.id, person, null);
          if (merged.outcome === "error") throw new Error("Planning Center person merge failed.");
          outcome = { outcome: merged.outcome, person_id: merged.person_id };
          }
          status = "completed";
        }
        const { error } = await supabase.from("webhook_deliveries").update({ status, error_message: null, processed_at: new Date().toISOString() }).eq("id", deliveryRowId).eq("church_id", church.id);
        if (error) throw error;
        results.push({ delivery_id: delivery.id, status, ...outcome });
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        const { error: saveError } = await supabase.from("webhook_deliveries").update({ status: "failed", error_message: message, processed_at: new Date().toISOString() }).eq("id", deliveryRowId).eq("church_id", church.id);
        if (saveError) throw saveError;
        results.push({ delivery_id: delivery.id, status: "failed" });
      }
    }
    return json(results.some(result => result.status === "failed") ? 500 : 200, { deliveries: results });
  } catch (error) {
    console.error("Planning Center webhook failed:", error instanceof Error ? error.message : "Unexpected error");
    return json(500, { error: "Webhook processing failed." });
  }
});
