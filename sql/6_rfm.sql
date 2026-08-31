/*
Entry #6 — RFM segmentation
(full write-up: Olist-Analysis-Log.md, entry 6)

Single query. The CTE computes, per customer: Recency (days since the
dataset's last recorded order), Frequency (distinct orders), and Monetary
(item-price spend, freight excluded; LEFT JOIN + COALESCE keeps the ~700
customers whose orders have no line items). The outer query scores R and M
as NTILE(5) quintiles; F uses fixed tiers (1 / 2 / 3-4 / 5+) because 96.88%
of customers share frequency = 1, which makes quintile scoring invalid.
*/

WITH rfm AS (
    SELECT 
        c.customer_unique_id,
        -- Recency
        ((SELECT MAX(order_purchase_timestamp) FROM orders)::date - MAX(o.order_purchase_timestamp)::date) AS recency_days,
        -- Frequency
        COUNT(DISTINCT o.order_id) AS frequency,
        -- Monetary
        COALESCE(SUM(i.price::numeric), 0) AS monetary
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    LEFT JOIN order_items i ON o.order_id = i.order_id
    GROUP BY c.customer_unique_id
)

SELECT
	customer_unique_id,
	recency_days,
	frequency,
	monetary,
	NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,
	CASE 
	    WHEN frequency = 1 THEN 1
	    WHEN frequency = 2 THEN 3
	    WHEN frequency BETWEEN 3 AND 4 THEN 4
	    WHEN frequency >= 5 THEN 5
	END AS f_score,
	NTILE(5) OVER (ORDER BY monetary ASC) AS m_score
FROM rfm
ORDER BY 7 DESC, 5 DESC, 6 DESC
LIMIT 300;
