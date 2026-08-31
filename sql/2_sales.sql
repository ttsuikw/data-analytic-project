/*
Entry #2 — Order volume and revenue over time
(full write-up: Olist-Analysis-Log.md, entry 2)

Queries, in order:
1. All-time monthly order counts — identifies the sparse late-2016 launch
   period, which sets the analysis window to 2017 onward.
2. Spot-check of November 2016 (the empty month).
3. Quarterly order count + revenue, 2017 onward, delivered orders only.
4. Monthly order count + revenue, same window.
5. Grand total revenue for the window: R$15,375,875.44.
*/

-- Adding condition of order_status = delivered to rule out the orders that got cutoff and those not delivered
SELECT 
    DATE_TRUNC('month', order_purchase_timestamp) AS order_month,
    COUNT(order_id) AS total_orders
FROM orders
WHERE order_purchase_timestamp IS NOT NULL
GROUP BY 1
ORDER BY order_month ASC;



SELECT *
FROM orders
WHERE order_purchase_timestamp BETWEEN '2016-11-01' AND '2016-11-30';

/* 
The unusually low values from September 2016 up until January 2017 can be explained by the olist company does actually launches around September 2016
According to the company page itself, Olist officially launched as a storefront on major Brazilian marketplaces in 2016, 
only reaching 2,000 partner sellers by 2017. 

This is consistent with the dataset's own pattern: a small, concentrated burst of 265 orders across 128 distinct sellers in early October 2016, 
a complete gap in November 2016, and steady ramp-up beginning in 2017 as the marketplace matured.

So the method would be to consider only the sales starting from the beginning of 2017.
*/

-- Quarterly Sales
SELECT 
    DATE_TRUNC('quarter', order_purchase_timestamp) AS order_month,
    COUNT(o.order_id) AS total_orders,
	ROUND(SUM(payment_value)::numeric,2) AS quarterly_total
FROM orders o
JOIN order_payments p
ON o.order_id = p.order_id
WHERE order_purchase_timestamp IS NOT NULL AND order_purchase_timestamp >= '2017-01-01' AND order_status = 'delivered'
GROUP BY 1
ORDER BY order_month ASC;


-- Bimonthly sales
SELECT 
    DATE_TRUNC('month', order_purchase_timestamp) AS order_month,
    COUNT(o.order_id) AS total_orders,
	ROUND(SUM(payment_value)::numeric,2) AS monthly_total
FROM orders o
JOIN order_payments p
ON o.order_id = p.order_id
WHERE order_purchase_timestamp IS NOT NULL AND order_purchase_timestamp >= '2017-01-01' AND order_status = 'delivered'
GROUP BY 1
ORDER BY order_month ASC;

--Grand total between 2017 to 2018
SELECT
	ROUND(SUM(payment_value)::numeric,2) AS grand_total
FROM orders o
JOIN order_payments p
ON o.order_id = p.order_id
WHERE order_purchase_timestamp IS NOT NULL AND order_purchase_timestamp >= '2017-01-01' AND order_status = 'delivered';
