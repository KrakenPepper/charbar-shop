// Public order intake endpoint. Uses service-role credentials only on the server.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed." }, 405);

  try {
    const body = await req.json();
    const required = ["customer_name", "customer_email", "customer_phone", "fulfillment_method", "payment_method", "items"];
    for (const key of required) if (body[key] === undefined || body[key] === null || body[key] === "") return json({ error: `Missing ${key.replaceAll("_"," ")}.` }, 400);

    if (!Array.isArray(body.items) || body.items.length === 0 || body.items.length > 30) return json({ error: "Your cart is empty or too large." }, 400);
    if (!["shipping", "pickup"].includes(body.fulfillment_method)) return json({ error: "Choose shipping or local pickup." }, 400);
    if (!["venmo", "cashapp"].includes(body.payment_method)) return json({ error: "Choose Venmo or Cash App." }, 400);

    const normalizedItems = body.items.map((item: any) => ({
      variant_id: String(item.variant_id || ""),
      quantity: Number(item.quantity),
    }));
    if (normalizedItems.some((item: any) => !/^[0-9a-f-]{36}$/i.test(item.variant_id) || !Number.isInteger(item.quantity) || item.quantity < 1 || item.quantity > 12)) {
      return json({ error: "One or more cart items are invalid. Please refresh and try again." }, 400);
    }

    const url = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !serviceKey) return json({ error: "Order service is not configured yet." }, 503);

    const admin = createClient(url, serviceKey, { auth: { persistSession: false } });
    const address = body.fulfillment_method === "shipping" ? {
      address1: String(body.address1 || "").trim(),
      address2: String(body.address2 || "").trim(),
      city: String(body.city || "").trim(),
      state: String(body.state || "").trim(),
    } : null;

    const { data, error } = await admin.rpc("create_charbar_pending_order", {
      p_customer_name: String(body.customer_name).trim(),
      p_customer_email: String(body.customer_email).trim(),
      p_customer_phone: String(body.customer_phone).trim(),
      p_fulfillment_method: body.fulfillment_method,
      p_shipping_address: address,
      p_postal_code: body.fulfillment_method === "shipping" ? String(body.postal_code || "").trim() : null,
      p_pickup_location: body.fulfillment_method === "pickup" ? String(body.pickup_location || "") : null,
      p_payment_method: body.payment_method,
      p_items: normalizedItems,
    });
    if (error) {
      console.error("Order creation failed:", error.message);
      return json({ error: error.message || "Unable to create your order." }, 400);
    }
    const order = data?.[0];
    if (!order) return json({ error: "The order could not be created." }, 500);

    return json({
      order_id: order.order_id,
      order_number: order.order_number,
      subtotal_cents: order.subtotal_cents,
      sampler_discount_cents: order.sampler_discount_cents,
      volume_discount_cents: order.volume_discount_cents,
      total_cents: order.total_cents,
      pickup_location: order.pickup_location,
      payment_method: body.payment_method,
      payment_url: body.payment_method === "venmo"
        ? "https://venmo.com/u/krakenpepper"
        : "https://cash.app/$krakenpepper",
      payment_due_note: body.fulfillment_method === "shipping"
        ? "Shipping cost has not been added. CharBar will confirm shipping and the final amount before payment."
        : "Please pay the product total shown. Your pickup arrangements will be confirmed by CharBar.",
      expires_in_hours: 24,
    });
  } catch (error) {
    console.error("Unexpected order intake error:", error);
    return json({ error: "Something went wrong. Please try again." }, 500);
  }
});
