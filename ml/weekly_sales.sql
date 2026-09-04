--weekly sales
SELECT 
    DATE_TRUNC('week', order_purchase_timestamp) AS week,
    COUNT(DISTINCT o.order_id) AS total_orders,
	ROUND(SUM(oi.price)::numeric,2) AS weekly_total,
	ROUND(SUM(oi.price + oi.freight_value)::numeric,2) AS weekly_gross_revenue
FROM orders o
JOIN order_items oi
ON o.order_id = oi.order_id
WHERE order_purchase_timestamp IS NOT NULL AND order_purchase_timestamp >= '2017-01-01' AND order_status = 'delivered'
GROUP BY 1
ORDER BY 1 ASC;