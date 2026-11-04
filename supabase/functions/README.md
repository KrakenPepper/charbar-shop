# Supabase Edge Functions

## Deploy the manual-order endpoint

1. Apply `supabase/migrations/202611040001_manual_venmo_cashapp_orders.sql` in the Supabase SQL Editor.
2. From a local checkout of this repository, install/use the Supabase CLI and link it to project `tcjvtejwfwpzcelupzrc`.
3. Set the server secret (never put this in GitHub or browser code): `supabase secrets set SUPABASE_SERVICE_ROLE_KEY=YOUR_SERVICE_ROLE_KEY`.
4. Deploy: `supabase functions deploy create-order --no-verify-jwt`.
5. Test with a small cart and verify an order appears in the private `orders` and `order_items` tables.

The storefront calls `create-order` to create a pending order. The function calculates prices from Supabase, validates stock, and reserves selected units for 24 hours. It does not mark orders paid or deduct physical stock. Expired pending reservations are released when a new order is submitted.

## Current manual payment flow

- Venmo: https://venmo.com/u/krakenpepper
- Cash App: https://cash.app/$krakenpepper
- Payment is manually verified by the store.
- For shipping orders, shipping is not included yet; the store must confirm shipping and the final amount before the customer pays.
- For pickup orders, the displayed amount is the product subtotal; pickup arrangements are confirmed separately.

## Not production-complete

No admin order dashboard, secure mark-as-paid action, automated inventory deduction on verified payment, email/SMS notifications, PDF invoices/receipts/packing slips, automatic reservation cleanup schedule, or shipping-rate calculation is included yet. Keep the storefront labelled as an order-request/manual-payment beta until these are implemented and tested. Do not mark an order paid based on a customer screenshot or browser redirect alone; manually verify the payment in the Venmo/Cash App account first.
