#!/usr/bin/env bash
# Post-processing for SYS=retail, run automatically by
# data-caterer/script/seed.sh after Data Caterer finishes (FORMAT=csv).
#
# A field's `sql` can only see other fields in its own row of its own
# step -- it can't reach into another step's rows (see plan/retail.yaml's
# file-level comment). So order_item.unit_price/line_total and
# invoice.subtotal_amount/tax_amount/total_amount are generated as
# independently-random placeholders; this script corrects them:
#
#   1. order_item.unit_price is overwritten with that row's real
#      product.price (joined on product_id), and line_total recomputed
#      from the corrected unit_price.
#   2. invoice.subtotal_amount is overwritten with the real sum of its
#      order's order_item.line_total (now correct, per step 1), and
#      tax_amount/total_amount recomputed from that against the
#      invoice's already-assigned tax_rate. An order with no order_item
#      rows at all (same documented limitation as banking's
#      transactions.accounts_FK -- see that plan's "known limitation of
#      the workaround" section) gets a $0 subtotal, not an error.
#
# Usage: retail.sh <output-dir>   (e.g. data/retail, containing that
# run's product.csv, order_item.csv and invoice.csv)
set -euo pipefail

dir="$1"

awk -F, '
	NR==FNR {
		if (FNR==1) { for (i=1;i<=NF;i++) h[$i]=i; next }
		price[$(h["id"])] = $(h["price"]); next
	}
	FNR==1 { for (i=1;i<=NF;i++) ch[$i]=i; print; next }
	{
		p = price[$(ch["product_id"])] + 0
		$(ch["unit_price"]) = sprintf("%.2f", p)
		$(ch["line_total"]) = sprintf("%.2f", $(ch["quantity"]) * p)
		print
	}
' OFS=, "$dir/product.csv" "$dir/order_item.csv" > "$dir/order_item.csv.tmp"
mv -f "$dir/order_item.csv.tmp" "$dir/order_item.csv"

awk -F, '
	NR==FNR {
		if (FNR==1) { for (i=1;i<=NF;i++) h[$i]=i; next }
		subtotal[$(h["order_id"])] += $(h["line_total"]); next
	}
	FNR==1 { for (i=1;i<=NF;i++) ch[$i]=i; print; next }
	{
		# NB: not named "sub" -- that collides with the awk built-in
		# sub() function and silently breaks parsing of everything after.
		subamt = subtotal[$(ch["order_id"])] + 0
		tax = subamt * $(ch["tax_rate"])
		$(ch["subtotal_amount"]) = sprintf("%.2f", subamt)
		$(ch["tax_amount"]) = sprintf("%.2f", tax)
		$(ch["total_amount"]) = sprintf("%.2f", subamt + tax)
		print
	}
' OFS=, "$dir/order_item.csv" "$dir/invoice.csv" > "$dir/invoice.csv.tmp"
mv -f "$dir/invoice.csv.tmp" "$dir/invoice.csv"
