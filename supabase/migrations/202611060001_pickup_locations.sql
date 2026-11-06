-- CharBar pickup location support, retaining server-side sampler and volume pricing.
-- Run this migration once after migration 002.

alter table public.orders
  add column if not exists sampler_discount_cents integer not null default 0 check (sampler_discount_cents >= 0),
  add column if not exists volume_discount_cents integer not null default 0 check (volume_discount_cents >= 0);

drop function if exists public.create_charbar_pending_order(text,text,text,text,jsonb,text,text,jsonb);
drop function if exists public.create_charbar_pending_order(text,text,text,text,jsonb,text,text,text,jsonb);

create function public.create_charbar_pending_order(
  p_customer_name text,
  p_customer_email text,
  p_customer_phone text,
  p_fulfillment_method text,
  p_shipping_address jsonb,
  p_postal_code text,
  p_pickup_location text,
  p_payment_method text,
  p_items jsonb
)
returns table(order_id uuid, order_number text, subtotal_cents integer, sampler_discount_cents integer, volume_discount_cents integer, total_cents integer, pickup_location text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order_id uuid;
  v_order_number text;
  v_gross integer := 0;
  v_sampler_qty integer := 0;
  v_sampler_discount integer := 0;
  v_volume_discount integer := 0;
  v_total integer := 0;
  v_item jsonb;
  v_variant public.product_variants%rowtype;
  v_product public.products%rowtype;
  v_qty integer;
  v_line integer;
  v_after_sampler integer;
begin
  if length(trim(coalesce(p_customer_name,''))) < 2 then raise exception 'Please enter your name.'; end if;
  if p_customer_email !~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$' then raise exception 'Please enter a valid email address.'; end if;
  if length(regexp_replace(coalesce(p_customer_phone,''),'[^0-9]','','g')) < 10 then raise exception 'Please enter a valid phone number.'; end if;
  if p_fulfillment_method not in ('shipping','pickup') then raise exception 'Invalid fulfillment method.'; end if;
  if p_fulfillment_method = 'pickup' and p_pickup_location not in (
    'Hartford pickup — 2940 Main St, Hartford, CT 06120',
    'Plainville pickup — 60 Johnson Ave, Plainville, CT 06062'
  ) then raise exception 'Please choose a valid pickup location.'; end if;
  if p_fulfillment_method = 'shipping' and p_pickup_location is not null then raise exception 'Pickup location must be blank for shipping orders.'; end if;
  if p_payment_method not in ('venmo','cashapp') then raise exception 'Invalid payment method.'; end if;
  if p_fulfillment_method = 'shipping' and (
    coalesce(p_shipping_address->>'address1','') = '' or
    coalesce(p_shipping_address->>'city','') = '' or
    coalesce(p_shipping_address->>'state','') = '' or
    coalesce(p_postal_code,'') !~ '^[0-9]{5}(-[0-9]{4})?$'
  ) then raise exception 'Complete your shipping address and ZIP code.'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 or jsonb_array_length(p_items) > 30 then
    raise exception 'Your cart is empty or contains too many line items.';
  end if;

  -- Release expired reservations before checking current availability.
  for v_item in
    select jsonb_build_object('variant_id', oi.variant_id::text, 'quantity', oi.quantity)
    from public.orders o join public.order_items oi on oi.order_id = o.id
    where o.status = 'pending_payment' and o.expires_at < now()
  loop
    update public.product_variants set reserved_quantity = greatest(0, reserved_quantity - (v_item->>'quantity')::integer)
    where id = (v_item->>'variant_id')::uuid;
  end loop;
  update public.orders set status = 'cancelled', updated_at = now()
  where status = 'pending_payment' and expires_at < now();

  v_order_number := 'CB-' || to_char(now(),'YYMMDD') || '-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));
  insert into public.orders (
    order_number,status,payment_provider,customer_name,customer_email,customer_phone,
    fulfillment_method,shipping_address,postal_code,pickup_location,
    subtotal_cents,discount_cents,sampler_discount_cents,volume_discount_cents,shipping_cents,total_cents,expires_at
  ) values (
    v_order_number,'pending_payment',p_payment_method,trim(p_customer_name),lower(trim(p_customer_email)),
    trim(p_customer_phone),p_fulfillment_method,p_shipping_address,p_postal_code,
    case when p_fulfillment_method='pickup' then p_pickup_location else null end,
    0,0,0,0,0,0,now()+interval '24 hours'
  ) returning id into v_order_id;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    begin v_qty := (v_item->>'quantity')::integer;
    exception when others then raise exception 'Invalid quantity in cart.'; end;
    if v_qty < 1 or v_qty > 12 then raise exception 'Each SKU quantity must be between 1 and 12.'; end if;

    select * into v_variant from public.product_variants
    where id = (v_item->>'variant_id')::uuid and active = true for update;
    if not found then raise exception 'A selected product size is no longer available.'; end if;
    select * into v_product from public.products where id = v_variant.product_id and active = true;
    if not found then raise exception 'A selected product is no longer available.'; end if;
    if v_variant.stock_quantity - v_variant.reserved_quantity < v_qty then
      raise exception 'Not enough stock remains for % (%). Please update your cart.', v_product.name, v_variant.size_label;
    end if;

    update public.product_variants set reserved_quantity = reserved_quantity + v_qty where id = v_variant.id;
    v_line := v_variant.unit_price_cents * v_qty;
    v_gross := v_gross + v_line;
    if (v_product.product_type = 'sauce' and lower(trim(v_variant.size_label)) = '3oz')
       or (v_product.product_type = 'jam' and lower(trim(v_variant.size_label)) = '4oz') then
      v_sampler_qty := v_sampler_qty + v_qty;
    end if;

    insert into public.order_items (
      order_id,product_id,variant_id,product_name_snapshot,size_snapshot,unit_price_cents,quantity,line_total_cents
    ) values (
      v_order_id,v_product.id,v_variant.id,v_product.name,v_variant.size_label,v_variant.unit_price_cents,v_qty,v_line
    );
  end loop;

  -- Each group of 3 qualifying samplers costs $12 instead of $15. Sizes larger than sampler sizes are excluded.
  v_sampler_discount := (v_sampler_qty / 3) * 300;
  v_after_sampler := v_gross - v_sampler_discount;

  -- Strictly over $50 = 5%; strictly over $100 = 15% (not stacked).
  if v_after_sampler > 10000 then
    v_volume_discount := round(v_after_sampler * 0.15);
  elsif v_after_sampler > 5000 then
    v_volume_discount := round(v_after_sampler * 0.05);
  end if;
  v_total := v_after_sampler - v_volume_discount;

  update public.orders set
    subtotal_cents = v_gross,
    sampler_discount_cents = v_sampler_discount,
    volume_discount_cents = v_volume_discount,
    discount_cents = v_sampler_discount + v_volume_discount,
    total_cents = v_total,
    updated_at = now()
  where id = v_order_id;

  return query select v_order_id,v_order_number,v_gross,v_sampler_discount,v_volume_discount,v_total,
    case when p_fulfillment_method='pickup' then p_pickup_location else null end;
end;
$$;

revoke all on function public.create_charbar_pending_order(text,text,text,text,jsonb,text,text,text,jsonb) from public, anon, authenticated;
grant execute on function public.create_charbar_pending_order(text,text,text,text,jsonb,text,text,text,jsonb) to service_role;
