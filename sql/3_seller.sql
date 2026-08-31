/*
Entry #3 — Seller performance: delivery adherence, income, reviews, category mix
(full write-up: Olist-Analysis-Log.md, entry 3)

Single query. The CTEs build each seller's revenue-ordered category mix
(order_items -> products -> translation, LEFT JOIN so untranslated categories
do not drop rows); the outer query ranks sellers by income alongside on-time
delivery adherence (0-1) and average review score. Income is measured from
order_items.price rather than payments, to avoid double-counting installments
and to exclude freight from seller revenue.
*/

WITH cat AS (
    SELECT oi.order_id, oi.seller_id, oi.product_id, oi.price,
           t.product_category_name_english
    FROM order_items oi
    JOIN products p ON oi.product_id = p.product_id
    LEFT JOIN translation t ON p.product_category_name = t.product_category_name
),

cat_revenue AS (
    SELECT seller_id, product_category_name_english, SUM(price) AS category_revenue
    FROM cat
    GROUP BY 1, 2
),

seller_categories AS (
    SELECT 
        seller_id,
        STRING_AGG(product_category_name_english, ', ' ORDER BY category_revenue DESC) AS category_mix
    FROM cat_revenue
    GROUP BY seller_id
)

SELECT s.seller_id, 
	ROUND(AVG(CASE WHEN o.order_delivered_customer_date IS NULL THEN 0
	WHEN o.order_delivered_customer_date <= o.order_estimated_delivery_date THEN 1
	ELSE 0 END)::numeric, 2) AS delivery_adherence,
	ROUND(SUM(s.total_amount)::numeric, 2) AS seller_income, 
	ROUND(AVG(r.review_score)::numeric, 2) AS seller_review_score,
	COUNT(DISTINCT o.order_id) AS total_orders,
	sc.category_mix AS category
FROM orders o
JOIN (SELECT order_id, seller_id, SUM(price) AS total_amount FROM order_items GROUP BY 1, 2) s ON o.order_id = s.order_id
LEFT JOIN seller_categories sc ON s.seller_id = sc.seller_id
LEFT JOIN order_reviews r ON o.order_id = r.order_id
GROUP BY 1, 6
ORDER BY 3 DESC, 4 DESC, 5 DESC;
