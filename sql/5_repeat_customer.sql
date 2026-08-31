/*
Entry #5 — Repeat-customer analysis
(full write-up: Olist-Analysis-Log.md, entry 5)

Repeat behavior is measured on customer_unique_id: customer_id is minted
per order in this dataset and cannot identify a returning person.

Queries, in order:
1. One-time vs. repeat split: 96.88% / 3.12% of 96,096 customers.
2. First-purchase category vs. repeat rate — first order tagged via
   ROW_NUMBER, category taken from its highest-priced item, categories
   with n >= 100.
3. Gap between 1st and 2nd purchase per repeat customer (ROW_NUMBER + LAG).
4. Quantify same-instant "repeat" orders: 9.21% of repeat customers show a
   0-second gap — split-checkout artifacts, not real second visits.
*/

-- bucketing customers into one-time and repeated customer and checking the proportion
WITH customer_counts AS (
    SELECT customer_unique_id, 
      	CASE 
            WHEN COUNT(o.order_id) = 1 THEN 'one-time' 
            ELSE 'repeated' 
        END AS customer_type
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    GROUP BY customer_unique_id
)

SELECT 
    customer_type,
    COUNT(*) AS total_customers,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage
FROM customer_counts c
GROUP BY customer_type
ORDER BY 3 DESC, 2 DESC;

-- 96.88% of the customers are one-time customers and 3.12 are repeated, showing a low repurchase rate, but cannot determine its a retention issue without a benchmark.


-- Analyzing the category of customers' first purchase and the rate of them become a repeated customer
WITH customer_rank AS(
	SELECT customer_unique_id, order_id, order_purchase_timestamp,
	ROW_NUMBER() OVER (PARTITION BY customer_unique_id ORDER BY order_purchase_timestamp) AS order_rank,
	COUNT(o.order_id) OVER (PARTITION BY c.customer_unique_id) AS total_orders_by_customer
	FROM customers c
	JOIN orders o ON c.customer_id = o.customer_id
),

first_order_cat AS (
	SELECT DISTINCT ON (cr.customer_unique_id)
		cr.customer_unique_id, 
		cr.total_orders_by_customer,
		COALESCE(t.product_category_name_english, p.product_category_name, 'unknown') AS first_category_name
	FROM customer_rank cr
	JOIN order_items i ON cr.order_id = i.order_id
	JOIN products p ON i.product_id = p.product_id
	LEFT JOIN translation t ON p.product_category_name = t.product_category_name
	WHERE cr.order_rank = 1
	ORDER BY cr.customer_unique_id, i.price DESC
)

SELECT 
	first_category_name,
	COUNT(*) AS n_customers,
	SUM(CASE WHEN total_orders_by_customer > 1 THEN 1 ELSE 0 END) AS n_became_repeat,
	ROUND(100.0 * SUM(CASE WHEN total_orders_by_customer > 1 THEN 1 ELSE 0 END)/ COUNT(*), 2) AS repeat_rate
FROM first_order_cat
GROUP BY 1
HAVING COUNT(*) >= 100
ORDER BY repeat_rate DESC;


-- Analyzing the gap between the first purchase and second purchase for repeated customers
WITH rank AS(
	SELECT
		customer_unique_id,
		order_purchase_timestamp,
		ROW_NUMBER() OVER (PARTITION BY customer_unique_id ORDER BY order_purchase_timestamp) AS order_rank,
		LAG(order_purchase_timestamp) OVER (PARTITION BY customer_unique_id ORDER BY order_purchase_timestamp) AS prev_order_date
	FROM customers c
	JOIN orders o ON c.customer_id = o.customer_id
)

SELECT
	customer_unique_id,
	prev_order_date AS first_purchase,
	order_purchase_timestamp AS second_purchase,
	order_purchase_timestamp - prev_order_date AS days_between
FROM rank
WHERE order_rank = 2
ORDER BY 4;

/* 
Many customers have a gap that is close or exactly zero seconds between their first and second purchase
Unsure they are splitted orders for one single purchase or not
Therefore the decision is to quantify the issue and state in the caveat
*/

WITH rank AS (
    SELECT
        customer_unique_id,
        order_purchase_timestamp,
        ROW_NUMBER() OVER (PARTITION BY customer_unique_id ORDER BY order_purchase_timestamp) AS order_rank,
        LAG(order_purchase_timestamp) OVER (PARTITION BY customer_unique_id ORDER BY order_purchase_timestamp) AS prev_order_date
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
),
gaps AS (
    SELECT
        customer_unique_id,
        order_purchase_timestamp - prev_order_date AS days_between
    FROM rank
    WHERE order_rank = 2
)
SELECT
    COUNT(*) AS total_repeat_customers,
    COUNT(CASE WHEN days_between = INTERVAL '0' THEN 1 END) AS zero_gap_customers,
    ROUND(100.0 * COUNT(CASE WHEN days_between = INTERVAL '0' THEN 1 END) / COUNT(*), 2) AS zero_gap_pct
FROM gaps;
