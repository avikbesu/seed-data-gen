-- SQL equivalent of postprocess/csv/retail.sh's awk fixups, run by
-- data-caterer/script/seed.sh against the live database before pg_dump
-- (same `sql` same-row/same-step limitation as banking.yaml bug 5 --
-- see plan/retail.yaml's file-level comment):
--
--   1. order_item.unit_price is overwritten with that row's real
--      product.price (joined on product_id), and line_total recomputed
--      from the corrected unit_price.
--   2. invoice.subtotal_amount/tax_amount/total_amount are recomputed
--      from the real sum of its order's order_item.line_total (now
--      correct, per step 1). Every invoice is zeroed first so an order
--      with no order_item rows at all (same documented limitation as
--      banking's transactions.accounts_FK) gets $0, not an untouched
--      random placeholder -- matching postprocess/csv/retail.sh exactly.

-- ROUND(double precision, integer) has no overload in Postgres (only
-- round(double precision) and round(numeric, integer) do) -- confirmed
-- directly (`ERROR: function round(double precision, integer) does not
-- exist`). Every field here is `type: "double"` in the plan, so every
-- ROUND below casts to numeric first.

UPDATE order_item oi
SET unit_price = p.price,
    line_total = ROUND(CAST(oi.quantity * p.price AS NUMERIC), 2)
FROM product p
WHERE oi.product_id = p.id;

UPDATE invoice
SET subtotal_amount = 0,
    tax_amount = 0,
    total_amount = 0;

UPDATE invoice i
SET subtotal_amount = s.subtotal,
    tax_amount = ROUND(CAST(s.subtotal * i.tax_rate AS NUMERIC), 2),
    total_amount = ROUND(CAST(s.subtotal + s.subtotal * i.tax_rate AS NUMERIC), 2)
FROM (
    SELECT order_id, SUM(line_total) AS subtotal
    FROM order_item
    GROUP BY order_id
) s
WHERE i.order_id = s.order_id;
