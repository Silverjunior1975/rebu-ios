// Supabase Edge Function: driver-cash-out
// Initiates a Stripe payout to the driver's connected bank account.
// Requires the driver to have a Stripe Connect account with a bank account linked.
//
// Deploy: supabase functions deploy driver-cash-out
// Set secret: supabase secrets set STRIPE_SECRET_KEY=sk_test_YOUR_KEY

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const STRIPE_SECRET_KEY = Deno.env.get("STRIPE_SECRET_KEY") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

serve(async (req) => {
  try {
    const { driver_id, amount } = await req.json();

    if (!driver_id || !amount || amount <= 0) {
      return new Response(
        JSON.stringify({ error: "driver_id and amount are required" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // Look up the driver's Stripe Connect account ID
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const { data: driver, error: dbError } = await supabase
      .from("drivers")
      .select("stripe_account_id")
      .eq("id", driver_id)
      .single();

    if (dbError || !driver?.stripe_account_id) {
      return new Response(
        JSON.stringify({
          error: "Driver not found or no Stripe account linked. Please set up your bank account first.",
        }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // Create a transfer to the driver's Connect account
    const params = new URLSearchParams();
    params.append("amount", String(amount)); // already in cents
    params.append("currency", "usd");
    params.append("destination", driver.stripe_account_id);

    const transferResponse = await fetch("https://api.stripe.com/v1/transfers", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${STRIPE_SECRET_KEY}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: params.toString(),
    });

    const transfer = await transferResponse.json();

    if (transfer.error) {
      return new Response(
        JSON.stringify({ error: transfer.error.message }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    return new Response(
      JSON.stringify({ success: true, transfer_id: transfer.id }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: err.message }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
