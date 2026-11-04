-- CharBar manual Venmo/Cash App order intake.
-- Run this migration in Supabase SQL Editor after schema.sql and seed_catalog.sql.
-- Orders reserve stock for 24 hours; stock is deducted only after manual payment verification.

alter table public.product_variants
  add column if not exists reserved_quantity integer not null default 0
  check (reserved_quantity >= 0 and reserved_quantity <= stock_quantity);

alter table public.orders
  drop constraint if exists orders_payment_provider_check;

alter table public.orders
  add constraint orders_payment_provider_check
  check (payment_provider is null or payment_provider in ('venmo','cashapp'));

alter table public.orders
  add column if not exists expires_at timestamptz;

create or replace function public.create_charbar_pending_order(
  p_customer_name text,
  p_customer_email text,
  p_customer_phone text,
  p_fulfillment_method text,
  p_shipping_address jsonb,
  p_postal_code text,
  p_payment_method text,
  p_items jsonb
)
returns table(order_id uuid, order_number text, total_cents integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order_id uuid;
  v_order_number text;
  v_subtotal integer := 0;
  v_item jsonb;
  v_variant public.product_variants%rowtype;
  v_product public.products%rowtype;
  v_qty integer;
  v_line integer;
begin
  if length(trim(coalesce(p_customer_name,''))) < 2 then
    raise exception 'Please enter your name.';
  end if;
  if p_customer_email !~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}$' then
    raise exception 'Please enter a valid email address.';
  end if;
  if length(regexp_replace(coalesce(p_customer_phone,''),'[^0-9]','','g')) < 10 then
    raise exception 'Please enter a valid phone number.';
  end if;
  if p_fulfillment_method not in ('shipping','pickup') then
    raise exception 'Invalid fulfillment method.';
  end if;
  if p_payment_method not in ('venmo','cashapp') then
    raise exception 'Invalid payment method.';
  end if;
  if p_fulfillment_method = 'shipping' and (
    coalesce(p_shipping_address->>'address1','') = '' or
    coalesce(p_shipping_address->>'city','') = '' or
    coalesce(p_shipping_address->>'state','') = '' or
    coalesce(p_postal_code,'') !~ '^[0-9]{5}(-[0-9]{4})?$'
  ) then
    raise exception 'Complete your shipping address and ZIP code.';
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 or jsonb_array_length(p_items) > 30 then
    raise exception 'Your cart is empty or contains too many line items.';
  end if;

  -- Release expired pending orders before checking current availability.
  for v_item in
    select jsonb_build_object('variant_id', oi.variant_id::text, 'quantity', oi.quantity)
    from public.orders o
    join public.order_items oi on oi.order_id = o.id
    where o.status = 'pending_payment' and o.expires_at < now()
  loop
    update public.product_variants
      set reserved_quantity = greatest(0, reserved_quantity - (v_item->>'quantity')::integer)
      where id = (v_item->>'variant_id')::uuid;
  end loop;
  update public.orders set status = 'cancelled', updated_at = now()
    where status = 'pending_payment' and expires_at < now();

  v_order_number := 'CB-' || to_char(now(),'YYMMDD') || '-' || upper(substr(encode(gen_random_bytes(4),'hex'),1,8));
  insert into public.orders (
    order_number,status,payment_provider,customer_name,customer_email,customer_phone,
    fulfillment_method,shipping_address,postal_code,pickup_location,
    subtotal_cents,discount_cents,shipping_cents,total_cents,expires_at
  ) values (
    v_order_number,'pending_payment',p_payment_method,trim(p_customer_name),lower(trim(p_customer_email)),
    trim(p_customer_phone),p_fulfillment_method,p_shipping_address,p_postal_code,
    case when p_fulfillment_method='pickup' then 'Pickup details to be arranged' else null end,
    0,0,0,0,now()+interval '24 hours'
  ) returning id into v_order_id;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    begin
      v_qty := (v_item->>'quantity')::integer;
    exception when others then
      raise exception 'Invalid quantity in cart.';
    end;
    if v_qty < 1 or v_qty > 12 then raise exception 'Each SKU quantity must be between 1 and 12.'; end if;

    select * into v_variant
      from public.product_variants
      where id = (v_item->>'variant_id')::uuid and active = true
      for update;
    if not found then raise exception 'A selected product size is no longer available.'; end if;

    select * into v_product from public.products where id = v_variant.product_id and active = true;
    if not found then raise exception 'A selected product is no longer available.'; end if;

    if v_variant.stock_quantity - v_variant.reserved_quantity < v_qty then
      raise exception 'Not enough stock remains for % (%). Please update your cart.', v_product.name, v_variant.size_label;
    end if;

    update public.product_variants
      set reserved_quantity = reserved_quantity + v_qty
      where id = v_variant.id;

    v_line := v_variant.unit_price_cents * v_qty;
    v_subtotal := v_subtotal + v_line;
    insert into public.order_items (
      order_id,product_id,variant_id,product_name_snapshot,size_snapshot,
      unit_price_cents,quantity,line_total_cents
    ) values (
      v_order_id,v_product.id,v_variant.id,v_product.name,v_variant.size_label,
      v_variant.unit_price_cents,v_qty,v_line
    );
  end loop;

  update public.orders
    set subtotal_cents=v_subtotal,total_cents=v_subtotal,updated_at=now()
    where id=v_order_id;

  return query select v_order_id,v_order_number,v_subtotal;
end;
$$;

revoke all on function public.create_charbar_pending_order(text,text,text,text,jsonb,text,text,jsonb) from public, anon, authenticated;
grant execute on function public.create_charbar_pending_order(text,text,text,text,jsonb,text,text,jsonb) to service_role;
