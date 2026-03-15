// Supabase Edge Function: capture-payment
// Captures a previously authorized PaymentIntent when restaurant accepts order.
// Can be called via a Supabase Database Webhook on orders.status change to ACCEPTED,
// or invoked manually.
//
// Deploy: supabase functions deploy capture-payment
// Set secret: supabase secrets set STRIPE_SECRET_KEY=sk_test_YOUR_KEY
//
// Database Webhook setup (optional, automates capture on ACCEPTED):
//   1. Go to Supabase Dashboard → Database → Webhooks
//   2. Create webhook on table "orders" for UPDATE events
//   3. Set condition: new.status = 'ACCEPTED'
//   4. URL: https://YOUR_PROJECT.supabase.co/functions/v1/capture-payment
//   5. Add header: Authorization: Bearer YOUR_ANON_KEY

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const STRIPE_SECRET_KEY = Deno.env.get("STRIPE_SECRET_KEY") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

serve(async (req) => {
  try {
    const body = await req.json();

    // Support both direct call and webhook trigger
    let orderId: string;
    let paymentIntentId: string | undefined;

    if (body.record) {
      // Called from database webhook
      orderId = body.record.id;
      paymentIntentId = body.record.payment_intent_id;
    } else {
      // Called directly
      orderId = body.order_id;
      paymentIntentId = body.payment_intent_id;
    }

    // If no payment_intent_id provided, look it up from the order
    if (!paymentIntentId && orderId) {
      const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
      const { data: order } = await supabase
        .from("orders")
        .select("payment_intent_id")
        .eq("id", orderId)
        .single();
      paymentIntentId = order?.payment_intent_id;
    }

    if (!paymentIntentId) {
      return new Response(
        JSON.stringify({ error: "No payment_intent_id found for this order" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // Capture the PaymentIntent via Stripe API
    const stripeResponse = await fetch(
      `https://api.stripe.com/v1/payment_intents/${paymentIntentId}/capture`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${STRIPE_SECRET_KEY}`,
          "Content-Type": "application/x-www-form-urlencoded",
        },
      }
    );

    const result = await stripeResponse.json();

    if (result.error) {
      return new Response(
        JSON.stringify({ error: result.error.message }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    return new Response(
      JSON.stringify({ success: true, status: result.status }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: err.message }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
