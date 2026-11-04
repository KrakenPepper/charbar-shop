-- CharBar initial catalog seed
-- Run once in Supabase SQL Editor after schema.sql.
-- Each newly created size/SKU starts with 12 units.
-- Re-running this script updates product details and prices but DOES NOT reset existing inventory.

insert into public.products (id, name, product_type, description, heat_level, active)
values
  ('s1', 'Blueberry Bandit', 'sauce', 'Blueberry + Habanero + Ghost', 2, true),
  ('s2', 'Tropical Punch', 'sauce', 'Pineapple + Mango + Habanero + Ghost', 1, true),
  ('s3', 'Peach Tsunami', 'sauce', 'Peach + Habanero + Ghost', 3, true),
  ('s4', 'Mermaid Moss', 'sauce', 'Green Chile + Garlic + Ghost', 2, true),
  ('j1', 'Spicy Apple Pie', 'jam', 'Apple profile spice spread', 3, true),
  ('j2', 'Peach Mango', 'jam', 'Sweet heat fruit fusion', 1, true),
  ('j3', 'Pineapple Mango', 'jam', 'Tropical pepper jam zest', 2, true),
  ('j4', 'Strawberry', 'jam', 'Classic mild sweet glaze', 0, true),
  ('j5', 'Cranberry', 'jam', 'Holiday special reserve', 1, true)
on conflict (id) do update set
  name = excluded.name,
  product_type = excluded.product_type,
  description = excluded.description,
  heat_level = excluded.heat_level,
  active = excluded.active,
  updated_at = now();

insert into public.product_variants (product_id, size_label, unit_price_cents, stock_quantity, active)
values
  ('s1', '3oz', 500, 12, true), ('s1', '5oz', 800, 12, true),
  ('s2', '3oz', 500, 12, true), ('s2', '5oz', 800, 12, true),
  ('s3', '3oz', 500, 12, true), ('s3', '5oz', 800, 12, true),
  ('s4', '3oz', 500, 12, true), ('s4', '5oz', 800, 12, true),
  ('j1', '4oz', 500, 12, true), ('j1', '8oz', 800, 12, true),
  ('j2', '4oz', 500, 12, true), ('j2', '8oz', 800, 12, true),
  ('j3', '4oz', 500, 12, true), ('j3', '8oz', 800, 12, true),
  ('j4', '4oz', 500, 12, true), ('j4', '8oz', 800, 12, true),
  ('j5', '4oz', 500, 12, true), ('j5', '8oz', 800, 12, true)
on conflict (product_id, size_label) do update set
  unit_price_cents = excluded.unit_price_cents,
  active = excluded.active;

-- Verify: should return 9 products and 18 variants, with 12 on each new SKU.
select p.name, p.product_type, v.size_label, v.unit_price_cents / 100.0 as price_usd,
       v.stock_quantity
from public.products p
join public.product_variants v on v.product_id = p.id
order by p.product_type, p.name, v.size_label;
