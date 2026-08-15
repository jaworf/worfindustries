import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {
  adminClient,
  fetchPerson,
  mergePlanningCenterPerson,
} from "../_shared/planning-center.ts";

const jsonHeaders = {
  "Content-Type": "application/json",
};

function bytesToHex(bytes: Uint8Array): string {
  return [...bytes].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function timingSafeEqual(left: string, right: string): boolean {
  if (left.length !== right.length) return false;
  let mismatch = 0;
  for (let index = 0; index < left.length; index += 1) {
    mismatch |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return mismatch === 0;
}

async function validSignature(body: string, supplied: string): Promise<boolean> {
  const secret = Deno.env.get("PCO_WEBHOOK_SECRET");
  if (!secret) throw new Error("Missing PCO_WEBHOOK_SECRET.");

  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(body)),
  );
  const expected = bytesToHex(signature);
  const normalizedSupplied = supplied.toLowerCase().replace(/^sha256=/, "");
  return timingSafeEqual(expected, normalizedSupplied);
}

type Delivery = {
  id: string;
  attributes: {
    name: string;
    payload: string;
  };
};

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") {
    return new Response(
      JSON.stringify({ error: "Method not allowed." }),
      { status: 405, headers: jsonHeaders },
    );
  }

  const body = await request.text();
  const suppliedSignature =
    request.headers.get("X-PCO-Webhooks-Authenticity") ?? "";

  if (!suppliedSignature || !(await validSignature(body, suppliedSignature))) {
    return new Response(
      JSON.stringify({ error: "Invalid webhook signature." }),
      { status: 401, headers: jsonHeaders },
    );
  }

  const payload = JSON.parse(body) as { data?: Delivery[] };
  const deliveries = payload.data ?? [];
  const supabase = adminClient();
  // This legacy webhook endpoint belongs to Riverview's existing Planning
  // Center webhook. Other churches use their own full sync connection.
  const { data: riverview, error: churchError } = await supabase
    .from("churches")
    .select("id")
    .eq("slug", "riverview")
    .single();
  if (churchError || !riverview) throw churchError ?? new Error("Riverview church not found.");
  const results: Array<Record<string, unknown>> = [];

  for (const delivery of deliveries) {
    const eventName = delivery.attributes.name;
    const { data: inserted, error: insertError } = await supabase
      .from("webhook_deliveries")
      .insert({
        church_id: riverview.id,
        source_system: "planning_center",
        delivery_id: delivery.id,
        event_name: eventName,
        payload: delivery,
      })
      .select("id")
      .maybeSingle();

    if (insertError?.code === "23505") {
      results.push({ delivery_id: delivery.id, status: "duplicate" });
      continue;
    }
    if (insertError) throw insertError;

    try {
      if (
        !eventName.endsWith(".person.created") &&
        !eventName.endsWith(".person.updated")
      ) {
        await supabase
          .from("webhook_deliveries")
          .update({
            status: "ignored",
            processed_at: new Date().toISOString(),
          })
          .eq("id", inserted!.id);
        results.push({ delivery_id: delivery.id, status: "ignored" });
        continue;
      }

      const eventPayload = JSON.parse(delivery.attributes.payload) as {
        data?: { id?: string };
      };
      const personId = eventPayload.data?.id;
      if (!personId) throw new Error("Webhook payload has no person ID.");

      const person = await fetchPerson(personId);
      const mergeResult = await mergePlanningCenterPerson(
        supabase,
        riverview.id,
        person,
        null,
      );

      await supabase
        .from("webhook_deliveries")
        .update({
          status: "completed",
          processed_at: new Date().toISOString(),
        })
        .eq("id", inserted!.id);
      results.push({
        delivery_id: delivery.id,
        status: "completed",
        outcome: mergeResult.outcome,
        person_id: mergeResult.person_id,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      await supabase
        .from("webhook_deliveries")
        .update({
          status: "failed",
          error_message: message,
          processed_at: new Date().toISOString(),
        })
        .eq("id", inserted!.id);
      results.push({
        delivery_id: delivery.id,
        status: "failed",
        error: message,
      });
    }
  }

  const failed = results.some((result) => result.status === "failed");
  return new Response(
    JSON.stringify({ deliveries: results }),
    { status: failed ? 500 : 200, headers: jsonHeaders },
  );
});
