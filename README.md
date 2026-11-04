# CharBar Shop

Mobile-first storefront for CharBar / Kraken small-batch hot sauces and pepper jams.

## Status

**Preview only — not accepting orders or payments.** The storefront provides product browsing, heat filters, a cart, and an estimated total. It does not submit orders, collect payment, or maintain shared inventory.

## Hosting

This repository is designed for GitHub Pages. After files are pushed, open **Settings → Pages**, choose **Deploy from a branch**, select `main` and `/(root)`, then save. GitHub Pages publishes the root `index.html`.

Expected project URL: https://krakenpepper.github.io/charbar-shop/

## Planned production architecture

- **GitHub Pages:** public static storefront only.
- **Supabase:** database, inventory, order records, secure server-side functions.
- **PayPal Checkout:** PayPal, Venmo (subject to eligibility), and supported cards.
- **Stripe:** Cash App Pay (subject to account eligibility) and supported cards.
- **Resend:** transactional order email and PDF attachments.
- **Twilio:** store SMS alerts and optional customer SMS updates.

Payment-provider secrets, Supabase service-role keys, email keys, and SMS credentials must be stored only as server-side environment variables or Supabase function secrets. Never commit them to this repository or expose them in browser JavaScript.

## Planned order lifecycle

1. Browser sends product IDs, quantities, and fulfillment details to a server function.
2. Server reloads current prices and inventory from Supabase and calculates the authoritative total.
3. Server creates a checkout session with the selected payment provider.
4. A verified provider webhook confirms payment.
5. Server records the paid order and decrements inventory exactly once.
6. Server generates an itemized invoice, paid receipt, and price-free packing slip.
7. Server sends customer email and store email/SMS notifications.

A browser redirect is not proof of payment. Orders must only be marked paid from a verified provider webhook.

## Setup checklist

- [ ] Confirm product names, descriptions, sizes, prices, and starting stock.
- [ ] Confirm shipping rates, free-shipping threshold, volume discounts, pickup locations/service radius.
- [ ] Create a Supabase project and apply `supabase/schema.sql`.
- [ ] Configure PayPal and Stripe sandbox credentials in server-side secrets.
- [ ] Configure Resend and Twilio credentials and store notification destinations.
- [ ] Implement and test checkout creation, signed webhooks, idempotent stock deduction, PDFs, and notifications.
- [ ] Run test purchases for shipping, pickup, discounts, out-of-stock items, failed payments, and duplicate webhooks.
- [ ] Switch to live provider credentials only after end-to-end tests pass.

## Business rules to verify before production

The prototype currently displays sample products and a draft pricing model. Confirm these before production:
- Samplers: $5 each or any three qualifying samplers for $12.
- Large bottles: $8 each.
- Volume discounts: 5% at $50 and 15% at $100.
- Free shipping at $50 product subtotal; below that, shipping is estimated by cart quantity.
- Local pickup minimum: $50.

The prototype's ZIP-prefix pickup check is only an estimate and must be replaced with a verified service-area rule before live checkout.

## Security

The public GitHub Pages site is not a secure place for customer records, order data, admin credentials, API keys, or payment secrets. Supabase row-level security must remain enabled. Public users should only be able to read active product catalog information; order creation, payment confirmation, inventory updates, and admin operations must run through authenticated server-side functions.
