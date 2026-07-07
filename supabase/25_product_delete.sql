-- ============================================================
-- ALLOW DELETING PRODUCTS THAT HAVE ORDER HISTORY
-- Run ONCE in the Supabase SQL editor. Idempotent.
--
-- order_items.product_id had no ON DELETE rule, so deleting a product that
-- had ever been ordered failed with a foreign-key violation. Switch it to
-- ON DELETE SET NULL: the product can be removed and historical order_items
-- keep their captured quantity + unit/total price (only the product link is
-- cleared). RLS already lets admins delete products.
-- ============================================================
alter table order_items
  drop constraint if exists order_items_product_id_fkey;

alter table order_items
  add constraint order_items_product_id_fkey
  foreign key (product_id) references products(id) on delete set null;
