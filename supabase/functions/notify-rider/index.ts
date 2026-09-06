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

/** Which rider currently holds a trip. */
async function riderNicForTrip(tripId: string | null): Promise<string | null> {
  if (!tripId) return null;
  const { data } = await supabase
    .from("trip")
    .select("rider_nic")
    .eq("trip_id", tripId)
    .maybeSingle();
  return text(data?.rider_nic);
}

async function buildMessages(payload: WebhookBody): Promise<Message[]> {
  const record = payload.record ?? {};
  const oldRecord = payload.old_record ?? {};
  const messages: Message[] = [];

  switch (payload.event) {
    case "trip_assigned": {
      const nic = text(record.rider_nic);
      if (nic) {
        messages.push({
          nic,
          type: "trip_assigned",
          title: "New delivery assigned",
          body: "You have been assigned a new trip. Tap to see the details.",
          tripId: text(record.trip_id),
        });
      }
      break;
    }

    case "trip_reassigned": {
      const newNic = text(record.rider_nic);
      const previousNic = text(oldRecord.rider_nic);

      if (newNic) {
        messages.push({
          nic: newNic,
          type: "trip_assigned",
          title: "New delivery assigned",
          body: "You have been assigned a new trip. Tap to see the details.",
          tripId: text(record.trip_id),
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
      const nic = await riderNicForTrip(text(record.trip_id));
      if (nic) {
        const destination = destinationOf(record);
        messages.push({
          nic,
          type: "delivery_added",
          title: "New delivery added",
          body: destination
            ? `A delivery to ${destination} was added to your trip.`
            : "A delivery was added to your trip.",
          deliveryId: text(record.del_id) ?? text(record.id),
          tripId: text(record.trip_id),
        });
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
          messages.push({
            nic: newNic,
            type: "delivery_added",
            title: "New delivery added",
            body: destination
              ? `A delivery to ${destination} was added to your trip.`
              : "A delivery was added to your trip.",
            deliveryId,
            tripId: newTripId,
          });
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
  const { data } = await supabase
    .from("rider")
    .select("id, user_id")
    .eq("NIC", nic)
    .limit(1)
    .maybeSingle();

  return text(data?.user_id) ?? text(data?.id);
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

  let account;
  let accessToken;
  try {
    account = serviceAccount();
    accessToken = await getAccessToken();
  } catch (error) {
    // A bad or missing FIREBASE_SERVICE_ACCOUNT stops here rather than looking
    // like a delivery failure.
    return {
      nic: message.nic,
      type: message.type,
      outcome: "fcm_auth_failed",
      tokens: tokens.length,
      fcmError: String(error),
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
        account.project_id,
        accessToken,
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
