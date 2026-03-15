// Supabase Edge Function: create-payment-intent
// Creates a Stripe PaymentIntent with manual capture (authorize only).
// Payment is captured later when the restaurant accepts the order.
//
// Deploy: supabase functions deploy create-payment-intent
// Set secret: supabase secrets set STRIPE_SECRET_KEY=sk_test_YOUR_KEY

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const STRIPE_SECRET_KEY = Deno.env.get("STRIPE_SECRET_KEY") ?? "";

serve(async (req) => {
  try {
    const { amount, currency, customer_phone, capture_method } = await req.json();

    if (!amount || amount <= 0) {
      return new Response(
        JSON.stringify({ error: "Invalid amount" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // Create PaymentIntent via Stripe API
    const params = new URLSearchParams();
    params.append("amount", String(amount)); // already in cents
    params.append("currency", currency || "usd");
    params.append("capture_method", capture_method || "manual");
    params.append("metadata[customer_phone]", customer_phone || "");

    const stripeResponse = await fetch("https://api.stripe.com/v1/payment_intents", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${STRIPE_SECRET_KEY}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: params.toString(),
    });

    const paymentIntent = await stripeResponse.json();

    if (paymentIntent.error) {
      return new Response(
        JSON.stringify({ error: paymentIntent.error.message }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    return new Response(
      JSON.stringify({
        client_secret: paymentIntent.client_secret,
        payment_intent_id: paymentIntent.id,
      }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: err.message }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
