// ============================================================
// send-push
// Sends FCM notifications to a specific user or every user with an app role.
//
// Secrets required:
//   FIREBASE_PROJECT_ID
//   FIREBASE_CLIENT_EMAIL
//   FIREBASE_PRIVATE_KEY
// ============================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

interface Body {
  userId?: string;
  appRole?: "customer" | "supplier" | "delivery" | "admin";
  title?: string;
  body?: string;
  data?: Record<string, string>;
}

const encoder = new TextEncoder();

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.startsWith("Bearer ")) {
      return json({ error: "missing bearer token" }, 401);
    }

    const payload: Body = await req.json();
    if (!payload.title || !payload.body) {
      return json({ error: "title and body are required" }, 400);
    }
    if (!payload.userId && !payload.appRole) {
      return json({ error: "userId or appRole is required" }, 400);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(supabaseUrl, serviceKey);

    let query = admin.from("device_tokens").select("token");
    if (payload.userId) query = query.eq("user_id", payload.userId);
    if (payload.appRole) query = query.eq("app_role", payload.appRole);

    const { data: rows, error } = await query;
    if (error) return json({ error: error.message }, 400);

    const tokens = [...new Set((rows ?? []).map((row) => row.token).filter(Boolean))];
    if (tokens.length === 0) return json({ success: true, sent: 0 });

    const accessToken = await getAccessToken();
    const projectId = Deno.env.get("FIREBASE_PROJECT_ID")!;
    const endpoint = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

    let sent = 0;
    const failed: Array<{ token: string; status: number; error: string }> = [];

    for (const token of tokens) {
      const res = await fetch(endpoint, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token,
            notification: {
              title: payload.title,
              body: payload.body,
            },
            data: stringifyData(payload.data ?? {}),
            android: {
              priority: "HIGH",
            },
          },
        }),
      });

      if (res.ok) {
        sent++;
      } else {
        failed.push({ token, status: res.status, error: await res.text() });
      }
    }

    return json({ success: true, sent, failed });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});

async function getAccessToken(): Promise<string> {
  const clientEmail = Deno.env.get("FIREBASE_CLIENT_EMAIL")!;
  const privateKey = Deno.env.get("FIREBASE_PRIVATE_KEY")!.replaceAll("\\n", "\n");
  const now = Math.floor(Date.now() / 1000);
  const jwtHeader = { alg: "RS256", typ: "JWT" };
  const jwtClaim = {
    iss: clientEmail,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };

  const unsignedJwt = `${base64Url(JSON.stringify(jwtHeader))}.${base64Url(JSON.stringify(jwtClaim))}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(privateKey),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, encoder.encode(unsignedJwt));
  const jwt = `${unsignedJwt}.${base64Url(signature)}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!res.ok) throw new Error(await res.text());
  const data = await res.json();
  return data.access_token as string;
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const base64 = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

function base64Url(input: string | ArrayBuffer): string {
  const bytes = typeof input === "string" ? encoder.encode(input) : new Uint8Array(input);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

function stringifyData(data: Record<string, string>): Record<string, string> {
  return Object.fromEntries(Object.entries(data).map(([key, value]) => [key, String(value)]));
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
