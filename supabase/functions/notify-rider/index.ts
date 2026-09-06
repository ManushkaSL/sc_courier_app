// Sends a push to a rider when the admin changes their work.
//
// Called by the triggers in docs/push-notifications.sql via pg_net. The request
// carries no Supabase JWT, so deploy with --no-verify-jwt and authenticate on
// the shared secret in the x-webhook-secret header instead.
//
// Secrets required (supabase secrets set ...):
//   NOTIFY_WEBHOOK_SECRET      same string as app.notify_webhook_secret in SQL
//   FIREBASE_SERVICE_ACCOUNT   the whole service-account JSON, on one line
//
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected by the platform.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.47.10";

const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";
/**
 * How long after a trip is assigned its deliveries count as part of that same
 * assignment rather than separate additions. Long enough to cover an admin
 * adding several parcels to a new trip; short enough that a genuine addition
 * later in the day still notifies.
 */
const NEW_TRIP_GRACE_MS = 5 * 60 * 1000;

const CANCELLED_STATUSES = [
  "cancelled",
  "canceled",
  "failed",
  "returned",
  "rejected",
];

interface WebhookBody {
  event?: string;
  table?: string;
  op?: string;
  record?: Record<string, unknown> | null;
  old_record?: Record<string, unknown> | null;
}

interface Message {
  nic: string;
  type: string;
  title: string;
  body: string;
  deliveryId?: string | null;
  tripId?: string | null;
}

const supabase = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  { auth: { persistSession: false } },
);

// ---------------------------------------------------------------------------
// Google OAuth: a service-account JWT exchanged for an FCM access token.
// Cached in module scope so a burst of assignments does not re-mint one each
// time; Deno keeps the isolate warm between calls.
// ---------------------------------------------------------------------------

let cachedToken: { value: string; expiresAt: number } | null = null;

function serviceAccount(): { client_email: string; private_key: string; project_id: string } {
  const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
  if (!raw) throw new Error("FIREBASE_SERVICE_ACCOUNT secret is not set");
  return JSON.parse(raw);
}

function pemToPkcs8(pem: string): ArrayBuffer {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const binary = atob(body);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

function base64Url(input: string | Uint8Array): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function getAccessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.expiresAt > now + 60) return cachedToken.value;

  const account = serviceAccount();
  const claims = {
    iss: account.client_email,
    scope: FCM_SCOPE,
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };

  const unsigned = `${base64Url(JSON.stringify({ alg: "RS256", typ: "JWT" }))}.${
    base64Url(JSON.stringify(claims))
  }`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToPkcs8(account.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );

  const assertion = `${unsigned}.${base64Url(new Uint8Array(signature))}`;
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });

  if (!response.ok) {
    throw new Error(`Google token exchange failed: ${await response.text()}`);
  }

  const json = await response.json();
  cachedToken = {
    value: json.access_token,
    expiresAt: now + (json.expires_in ?? 3600),
  };
  return cachedToken.value;
}

type FcmCredentials =
  | { projectId: string; accessToken: string; error?: undefined }
  | { projectId?: undefined; accessToken?: undefined; error: string };

/**
 * Returned rather than thrown so the caller can report the reason instead of
 * the whole request failing.
 */
async function fcmCredentials(): Promise<FcmCredentials> {
  try {
    return {
      projectId: serviceAccount().project_id,
      accessToken: await getAccessToken(),
    };
  } catch (error) {
    return { error: String(error) };
  }
}

// ---------------------------------------------------------------------------
// Turning a database event into messages.
// ---------------------------------------------------------------------------

function text(value: unknown): string | null {
  if (value === null || value === undefined) return null;
  const str = String(value).trim();
  return str.length > 0 ? str : null;
}

function destinationOf(delivery: Record<string, unknown>): string | null {
  return text(delivery.drop_location) ??
    text(delivery.delivery_address) ??
    text(delivery.dropLocation);
}

async function tripRow(
  tripId: string | null,
): Promise<Record<string, unknown> | null> {
  if (!tripId) return null;
  const { data } = await supabase
    .from("trip")
    .select("*")
    .eq("trip_id", tripId)
    .maybeSingle();
  return data ?? null;
}

/** Which rider currently holds a trip. */
async function riderNicForTrip(tripId: string | null): Promise<string | null> {
  return text((await tripRow(tripId))?.rider_nic);
}

/** When the trip row itself was created, if the table records that. */
function tripCreatedAt(trip: Record<string, unknown> | null): Date | null {
  if (!trip) return null;
  for (const key of ["created_at", "createdAt", "created", "created_date"]) {
    const value = text(trip[key]);
    if (!value) continue;
    const parsed = new Date(value);
    if (!Number.isNaN(parsed.getTime())) return parsed;
  }
  return null;
}

/**
 * True when the rider was already told about this trip a moment ago.
 *
 * Assigning a trip writes the trip row and then its delivery rows, which fires
 * both trip_assigned and delivery_added. The rider only needs to hear about it
 * once, so deliveries arriving in the wake of a fresh assignment stay silent.
 * A delivery added to a trip the rider has had for a while is a genuinely new
 * event and still notifies.
 */
/** Any delivery on the trip, so a trip-level notification can still be tapped. */
async function firstDeliveryIdForTrip(
  tripId: string | null,
): Promise<string | null> {
  if (!tripId) return null;
  const { data } = await supabase
    .from("delivery")
    .select("del_id")
    .eq("trip_id", tripId)
    .limit(1)
    .maybeSingle();
  return text(data?.del_id);
}

/**
 * Whether this trip has ever been announced to a rider. Permanent, not
 * time-boxed: it is what decides "assigned" (the first time the rider hears
 * about the trip) versus "added" (something new on a trip they already have).
 */
async function tripAlreadyAnnounced(tripId: string | null): Promise<boolean> {
  if (!tripId) return false;
  const { data } = await supabase
    .from("notifications")
    .select("id")
    .eq("trip_id", tripId)
    .eq("type", "trip_assigned")
    .limit(1);
  return (data?.length ?? 0) > 0;
}

async function wasTripJustAssigned(tripId: string | null): Promise<boolean> {
  if (!tripId) return false;

  const cutoff = Date.now() - NEW_TRIP_GRACE_MS;

  // Preferred check: the trip's own age. The two triggers reach this function
  // as independent pg_net requests with no ordering guarantee, so asking
  // whether the assignment notification has landed yet can race. The trip row
  // is already committed by the time either request arrives.
  const created = tripCreatedAt(await tripRow(tripId));
  if (created) return created.getTime() >= cutoff;

  // Fallback for a trip table that does not record a creation time.
  const { data } = await supabase
    .from("notifications")
    .select("id")
    .eq("trip_id", tripId)
    .eq("type", "trip_assigned")
    .gte("created_at", new Date(cutoff).toISOString())
    .limit(1);

  return (data?.length ?? 0) > 0;
}

/**
 * One delivery arriving on a rider's trip, turned into at most one message.
 *
 * The first delivery on a trip is what announces the assignment, so the
 * notification carries a real delivery id and tapping it opens that delivery.
 * The rest of the batch stays silent, and anything landing on a trip the rider
 * already has is a genuine addition.
 */
async function deliveryArrivalMessage(
  nic: string,
  tripId: string | null,
  record: Record<string, unknown>,
): Promise<Message | null> {
  const deliveryId = text(record.del_id) ?? text(record.id);
  const destination = destinationOf(record);

  if (!(await tripAlreadyAnnounced(tripId))) {
    return {
      nic,
      type: "trip_assigned",
      title: "New delivery assigned",
      body: destination
        ? `You have a new delivery to ${destination}. Tap to see the details.`
        : "You have been assigned a new delivery. Tap to see the details.",
      deliveryId,
      tripId,
    };
  }

  // Already announced and the trip is still fresh: this is the rest of the
  // same assignment, which the rider has just been told about.
  if (await wasTripJustAssigned(tripId)) return null;

  return {
    nic,
    type: "delivery_added",
    title: "New delivery added",
    body: destination
      ? `A delivery to ${destination} was added to your trip.`
      : "A delivery was added to your trip.",
    deliveryId,
    tripId,
  };
}

async function buildMessages(payload: WebhookBody): Promise<Message[]> {
  const record = payload.record ?? {};
  const oldRecord = payload.old_record ?? {};
  const messages: Message[] = [];

  switch (payload.event) {
    case "trip_assigned": {
      // Deliberately silent. A trip row is created before its deliveries
      // exist, so notifying here means a notification with nothing to open.
      // The trip's first delivery announces the assignment instead, carrying a
      // delivery id so the rider lands on the delivery itself.
      break;
    }

    case "trip_reassigned": {
      const newNic = text(record.rider_nic);
      const previousNic = text(oldRecord.rider_nic);

      if (newNic) {
        // An existing trip changing hands already has deliveries on it.
        const tripId = text(record.trip_id);
        messages.push({
          nic: newNic,
          type: "trip_assigned",
          title: "New delivery assigned",
          body: "You have been assigned a new trip. Tap to see the details.",
          deliveryId: await firstDeliveryIdForTrip(tripId),
          tripId,
        });
      }
      // Tell the rider who lost it, so they do not ride to a dead pickup.
      if (previousNic && previousNic !== newNic) {
        messages.push({
          nic: previousNic,
          type: "delivery_reassigned",
          title: "Trip reassigned",
          body: "A trip has been moved to another rider and is no longer yours.",
          tripId: text(oldRecord.trip_id),
        });
      }
      break;
    }

    case "delivery_added": {
      const tripId = text(record.trip_id);
      const nic = await riderNicForTrip(tripId);
      if (nic) {
        const message = await deliveryArrivalMessage(nic, tripId, record);
        if (message) messages.push(message);
      }
      break;
    }

    case "delivery_changed": {
      const status = (text(record.delivery_status) ?? "").toLowerCase();
      const newTripId = text(record.trip_id);
      const oldTripId = text(oldRecord.trip_id);
      const deliveryId = text(record.del_id) ?? text(record.id);
      const destination = destinationOf(record);

      if (CANCELLED_STATUSES.includes(status)) {
        const nic = await riderNicForTrip(newTripId);
        if (nic) {
          messages.push({
            nic,
            type: "delivery_cancelled",
            title: "Delivery cancelled",
            body: destination
              ? `The delivery to ${destination} was cancelled.`
              : "One of your deliveries was cancelled.",
            deliveryId,
            tripId: newTripId,
          });
        }
        break;
      }

      if (newTripId !== oldTripId) {
        const [newNic, oldNic] = await Promise.all([
          riderNicForTrip(newTripId),
          riderNicForTrip(oldTripId),
        ]);

        if (newNic) {
          const message = await deliveryArrivalMessage(
            newNic,
            newTripId,
            record,
          );
          if (message) messages.push(message);
        }
        if (oldNic && oldNic !== newNic) {
          messages.push({
            nic: oldNic,
            type: "delivery_reassigned",
            title: "Delivery reassigned",
            body: destination
              ? `The delivery to ${destination} was moved to another rider.`
              : "One of your deliveries was moved to another rider.",
            deliveryId,
            tripId: oldTripId,
          });
        }
      }
      break;
    }

    default:
      break;
  }

  return messages;
}

// ---------------------------------------------------------------------------
// Delivering one message: inbox row first, then push.
// ---------------------------------------------------------------------------

/** rider.NIC -> the auth user id the app signs in as. */
async function riderIdForNic(nic: string): Promise<string | null> {
  const { data: rider, error: riderError } = await supabase
    .from("rider")
    .select("email")
    .eq("NIC", nic)
    .limit(1)
    .maybeSingle();

  if (riderError) {
    console.error("Rider lookup error:", riderError);
    return null;
  }

  const email = text(rider?.email);
  if (!email) return null;

  const { data, error } = await supabase.auth.admin.listUsers();

  if (error) {
    console.error("Auth user lookup error:", error);
    return null;
  }

  const user = data.users.find(
    (u) => u.email?.toLowerCase() === email.toLowerCase(),
  );

  return user?.id ?? null;
}

async function sendToDevice(
  projectId: string,
  accessToken: string,
  token: string,
  message: Message,
): Promise<{ status: "sent" | "stale" | "failed"; error?: string }> {
  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token,
          // A `notification` block is what lets Android draw the tray entry
          // while the app is killed; `data` is what the app routes on.
          notification: { title: message.title, body: message.body },
          data: {
            type: message.type,
            delivery_id: message.deliveryId ?? "",
            trip_id: message.tripId ?? "",
            click_action: "FLUTTER_NOTIFICATION_CLICK",
          },
          android: {
            priority: "HIGH",
            notification: {
              channel_id: "sc_courier_deliveries",
              sound: "default",
            },
          },
        },
      }),
    },
  );

  if (response.ok) return { status: "sent" };

  const errorText = await response.text();
  // The device uninstalled or the token rotated: drop it rather than retrying
  // it forever.
  if (
    response.status === 404 ||
    errorText.includes("UNREGISTERED") ||
    errorText.includes("INVALID_ARGUMENT")
  ) {
    console.warn(`Dropping stale token: ${errorText}`);
    return { status: "stale", error: `${response.status}: ${errorText}` };
  }

  console.error(`FCM send failed (${response.status}): ${errorText}`);
  return { status: "failed", error: `${response.status}: ${errorText}` };
}

interface DeliveryResult {
  nic: string;
  type: string;
  outcome: string;
  tokens?: number;
  delivered?: number;
  stale?: number;
  failed?: number;
  inboxError?: string;
  fcmError?: string;
}

async function deliver(message: Message): Promise<DeliveryResult> {
  const riderId = await riderIdForNic(message.nic);
  if (!riderId) {
    console.warn(`No rider row for NIC ${message.nic}; nothing sent`);
    return {
      nic: message.nic,
      type: message.type,
      outcome: "no_rider_for_nic",
    };
  }

  // Written first, so the rider still sees it in the inbox even if every push
  // fails (no token yet, notifications denied, phone offline).
  const { error: inboxError } = await supabase.from("notifications").insert({
    rider_id: riderId,
    rider_nic: message.nic,
    type: message.type,
    title: message.title,
    body: message.body,
    delivery_id: message.deliveryId,
    trip_id: message.tripId,
  });
  if (inboxError) console.error("Inbox insert failed:", inboxError.message);

  const { data: tokens } = await supabase
    .from("device_tokens")
    .select("token")
    .eq("rider_id", riderId);

  if (!tokens || tokens.length === 0) {
    console.log(`Rider ${riderId} has no registered devices`);
    return {
      nic: message.nic,
      type: message.type,
      outcome: "no_device_tokens",
      tokens: 0,
      inboxError: inboxError?.message,
    };
  }

  // A bad or missing FIREBASE_SERVICE_ACCOUNT stops here rather than looking
  // like a delivery failure.
  const credentials = await fcmCredentials();
  if (credentials.error !== undefined) {
    return {
      nic: message.nic,
      type: message.type,
      outcome: "fcm_auth_failed",
      tokens: tokens.length,
      fcmError: credentials.error,
      inboxError: inboxError?.message,
    };
  }

  const stale: string[] = [];
  let delivered = 0;
  let failed = 0;
  let firstError: string | undefined;

  await Promise.all(
    tokens.map(async (row: { token: string }) => {
      const result = await sendToDevice(
        credentials.projectId,
        credentials.accessToken,
        row.token,
        message,
      );
      if (result.status === "stale") stale.push(row.token);
      if (result.status === "sent") delivered++;
      if (result.status !== "sent") {
        failed++;
        firstError ??= result.error;
      }
    }),
  );

  if (stale.length > 0) {
    await supabase.from("device_tokens").delete().in("token", stale);
  }

  return {
    nic: message.nic,
    type: message.type,
    outcome: delivered > 0 ? "delivered" : "all_sends_failed",
    tokens: tokens.length,
    delivered,
    stale: stale.length,
    failed,
    fcmError: firstError,
    inboxError: inboxError?.message,
  };
}

// ---------------------------------------------------------------------------

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const expectedSecret = Deno.env.get("NOTIFY_WEBHOOK_SECRET");
  if (!expectedSecret) {
    console.error("NOTIFY_WEBHOOK_SECRET is not set; refusing every request");
    return new Response("Not configured", { status: 500 });
  }
  if (request.headers.get("x-webhook-secret") !== expectedSecret) {
    return new Response("Unauthorized", { status: 401 });
  }

  try {
    const payload = (await request.json()) as WebhookBody;
    const messages = await buildMessages(payload);

    const results: DeliveryResult[] = [];
    for (const message of messages) {
      results.push(await deliver(message));
    }

    // `delivered` is the count that actually reached a phone. The per-message
    // outcome is included so net._http_response alone explains a failure.
    const delivered = results.reduce((sum, r) => sum + (r.delivered ?? 0), 0);

    return new Response(
      JSON.stringify({
        ok: true,
        event: payload.event,
        messages: messages.length,
        delivered,
        results,
      }),
      { headers: { "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("notify-rider failed:", error);
    // 200 on purpose: pg_net does not retry, and a non-2xx only fills the
    // response log with noise. The error above is the record that matters.
    return new Response(
      JSON.stringify({ ok: false, error: String(error) }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  }
});
