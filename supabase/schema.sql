-- CharBar production database foundation.
-- Apply in the Supabase SQL editor after creating a project.
-- Do not disable RLS. Order/payment mutations must be performed by trusted server functions.

create extension if not exists pgcrypto;

create table if not exists public.products (
  id text primary key,
  name text not null,
  product_type text not null check (product_type in ('sauce','jam')),
  description text not null default '',
  heat_level smallint not null default 0 check (heat_level between 0 and 3),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.product_variants (
  id uuid primary key default gen_random_uuid(),
  product_id text not null references public.products(id) on delete cascade,
  size_label text not null,
  unit_price_cents integer not null check (unit_price_cents >= 0),
  stock_quantity integer not null default 0 check (stock_quantity >= 0),
  active boolean not null default true,
  unique(product_id, size_label)
);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  order_number text unique not null,
  status text not null default 'pending_payment'
    check (status in ('pending_payment','paid','processing','ready_for_pickup','shipped','cancelled','refunded')),
  payment_provider text check (payment_provider in ('paypal','stripe')),
  provider_order_id text,
  provider_payment_id text,
  customer_name text not null,
  customer_email text not null,
  customer_phone text not null,
  fulfillment_method text not null check (fulfillment_method in ('shipping','pickup')),
  shipping_address jsonb,
  pickup_location text,
  postal_code text,
  subtotal_cents integer not null check (subtotal_cents >= 0),
  discount_cents integer not null default 0 check (discount_cents >= 0),
  shipping_cents integer not null default 0 check (shipping_cents >= 0),
  total_cents integer not null check (total_cents >= 0),
  currency text not null default 'USD' check (currency = 'USD'),
  customer_sms_consent boolean not null default false,
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists orders_provider_payment_unique
  on public.orders(payment_provider, provider_payment_id)
  where provider_payment_id is not null;

create table if not exists public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id text not null references public.products(id),
  variant_id uuid not null references public.product_variants(id),
  product_name_snapshot text not null,
  size_snapshot text not null,
  unit_price_cents integer not null check (unit_price_cents >= 0),
  quantity integer not null check (quantity > 0),
  line_total_cents integer not null check (line_total_cents >= 0)
);

create table if not exists public.payment_events (
  id uuid primary key default gen_random_uuid(),
  provider text not null check (provider in ('paypal','stripe')),
  provider_event_id text not null,
  event_type text not null,
  processed_at timestamptz not null default now(),
  unique(provider, provider_event_id)
);

create table if not exists public.order_documents (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  document_type text not null check (document_type in ('invoice','paid_receipt','packing_slip')),
  storage_path text not null,
  created_at timestamptz not null default now(),
  unique(order_id, document_type)
);

alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.payment_events enable row level security;
alter table public.order_documents enable row level security;

-- Public storefront may read active catalog rows only.
drop policy if exists "Public can read active products" on public.products;
create policy "Public can read active products" on public.products
  for select to anon, authenticated using (active = true);

drop policy if exists "Public can read active variants" on public.product_variants;
create policy "Public can read active variants" on public.product_variants
  for select to anon, authenticated using (
    active = true and exists (
      select 1 from public.products p where p.id = product_id and p.active = true
    )
  );

-- Intentionally no public policies for orders, order_items, payment_events,
-- or order_documents. Trusted Edge Functions using server-side credentials
-- must validate requests, create orders, process signed webhooks, and mutate stock.
