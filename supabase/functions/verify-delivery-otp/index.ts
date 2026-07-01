// ============================================================
// verify-delivery-otp
// Delivery agent submits the 4-digit OTP the customer shows them.
// This function:
//   1. authenticates the caller (must be the assigned delivery agent)
//   2. calls confirm_delivery_atomic() with the SERVICE ROLE, which
//      verifies the OTP against the stored bcrypt hash and, on match,
//      atomically marks the order delivered + bumps agent earnings.
// The OTP hash is never returned to the client.
//
// Deploy:  supabase functions deploy verify-delivery-otp
// Secrets: SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY
//          are injected automatically by the Supabase platform.
// ============================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

interface Body {
  orderId?: string;
  otp?: string;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.startsWith("Bearer ")) {
      return json({ error: "missing bearer token" }, 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    // Client bound to the caller's JWT — used only to identify the agent.
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userErr } = await userClient.auth.getUser();
    if (userErr || !userData?.user) {
      return json({ error: "invalid session" }, 401);
    }
    const agentId = userData.user.id;

    const { orderId, otp }: Body = await req.json();
    if (!orderId || !otp) {
      return json({ error: "orderId and otp are required" }, 400);
    }

    // Service-role client performs the privileged, atomic confirmation.
    const admin = createClient(supabaseUrl, serviceKey);
    const { data, error } = await admin.rpc("confirm_delivery_atomic", {
      p_order_id: orderId,
      p_otp: otp,
      p_agent_id: agentId,
    });

    if (error) {
      return json({ error: error.message }, 400);
    }

    // data is the boolean returned by the RPC (true = match).
    return json({ success: data === true });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
