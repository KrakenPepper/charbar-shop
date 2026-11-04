# Supabase Edge Functions — implementation checklist

Do not deploy live checkout until these functions are implemented and tested.

## Required endpoints

- `create-checkout`: accept cart variant IDs, quantities, customer contact, fulfillment and consent. Reload catalog/prices/stock from the database; never trust client prices. Recompute all discounts, shipping, pickup eligibility and total on the server. Create the provider checkout session.
- `paypal-webhook`: verify PayPal webhook signature using the configured webhook ID; handle relevant capture-completed and refund events.
- `stripe-webhook`: verify the Stripe signature against the raw request body; handle `checkout.session.completed`, asynchronous payment success/failure, refunds and disputes as appropriate.
- `admin-orders`: require authenticated admin authorization for viewing orders, updating fulfillment, tracking numbers, inventory and document access.
- `send-order-documents`: generate invoice, paid receipt and price-free packing slip after verified payment; store PDFs in a private bucket and send signed/authorized links or attachments.
- `notify-order`: email store and customer; SMS store alert and optional customer update only with consent.

## Required safety properties

1. Verify provider webhook signatures.
2. Record each provider event ID in `payment_events`; reject/replay-ignore duplicate event IDs.
3. Mark an order paid only after verified provider confirmation.
4. Deduct stock atomically and exactly once; reject insufficient stock.
5. Keep Supabase service-role keys and all provider credentials server-side.
6. Use authenticated admin access and least-privilege policies.
7. Do not expose customer/order/document tables to anonymous clients.
8. Use idempotency keys when creating provider checkout sessions.
9. Validate phone/email/address input and escape all generated document content.
10. Log provider event IDs and order IDs, but never log secrets or full payment credentials.

## Secrets

Set credentials with Supabase project Edge Function secrets. Do not commit real values or place them in `index.html`, client JavaScript, GitHub Actions logs, or this repository.
