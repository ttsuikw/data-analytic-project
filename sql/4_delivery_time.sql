/*
Entry #4 — Delivery time by geography
(full write-up: Olist-Analysis-Log.md, entry 4)

Queries, in order:
1. Create the state_region reference table mapping Brazil's 27 states to the
   5 official IBGE regions (reused by later analyses).
2. Stage-by-stage delivery times per region (purchase -> approve -> carrier ->
   customer), restricted to orders with all four timestamps, plus the
   estimate-vs-actual gap.
3. Cross-check: order-incompletion rate per region — rules out the regional
   gradient being a failure-rate artifact.
4. Cross-check: seller count and share per region — 92.5% of sellers are in
   Sudeste + Sul, which explains the gradient.
*/

CREATE TABLE state_region(
	state CHAR(2) PRIMARY KEY,
	region VARCHAR(20) NOT NULL
);

INSERT INTO state_region (state, region) VALUES
('AC', 'Norte'), ('AP', 'Norte'), ('AM', 'Norte'), ('PA', 'Norte'), ('RO', 'Norte'), ('RR', 'Norte'), ('TO', 'Norte'),
('AL', 'Nordeste'), ('BA', 'Nordeste'), ('CE', 'Nordeste'), ('MA', 'Nordeste'), ('PB', 'Nordeste'), ('PE', 'Nordeste'), ('PI', 'Nordeste'), ('RN', 'Nordeste'), ('SE', 'Nordeste'),
('ES', 'Sudeste'), ('MG', 'Sudeste'), ('RJ', 'Sudeste'), ('SP', 'Sudeste'),
('PR', 'Sul'), ('RS', 'Sul'), ('SC', 'Sul'),
('DF', 'Centro-Oeste'), ('GO', 'Centro-Oeste'), ('MT', 'Centro-Oeste'), ('MS', 'Centro-Oeste');



--Checking the new table
SELECT * FROM state_region;





-- Segment the delivery process and calculate the average, as well as the total delivery time and estimated delivery
SELECT 
region,
AVG(order_approved_at - order_purchase_timestamp) AS purchase_to_approve,
AVG(order_delivered_carrier_date - order_approved_at) AS approve_to_carrier,
AVG(order_delivered_customer_date - order_delivered_carrier_date) AS carrier_to_deliver,
AVG(order_delivered_customer_date - order_purchase_timestamp) AS average_delivery_time,
AVG(order_estimated_delivery_date - order_purchase_timestamp) AS average_estimated_time,
AVG(order_estimated_delivery_date - order_purchase_timestamp) - AVG(order_delivered_customer_date - order_purchase_timestamp) AS estimate_delivery_gap,
COUNT(*) AS counts
FROM (
	SELECT * FROM orders 
	WHERE order_purchase_timestamp IS NOT NULL
  	AND order_approved_at IS NOT NULL
  	AND order_delivered_carrier_date IS NOT NULL
  	AND order_delivered_customer_date IS NOT NULL
) o
JOIN customers c ON o.customer_id = c.customer_id
JOIN state_region s ON s.state = c.customer_state
GROUP BY 1
ORDER BY 5, 6, 7 DESC;


SELECT 
sr.region,
COUNT(*) AS total_orders,
COUNT(
	CASE 
		WHEN o.order_purchase_timestamp IS NULL 
		  OR o.order_approved_at IS NULL 
		  OR o.order_delivered_carrier_date IS NULL 
		  OR o.order_delivered_customer_date IS NULL 
		THEN 1 
	END
) AS incomplete_orders,
ROUND(
	100.0 * AVG(
		CASE 
		WHEN o.order_purchase_timestamp IS NULL 
		OR o.order_approved_at IS NULL 
		OR o.order_delivered_carrier_date IS NULL 
		OR o.order_delivered_customer_date IS NULL 
		THEN 1 
		ELSE 0 
		END), 2) AS incomplete_pct
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
JOIN state_region sr ON c.customer_state = sr.state
GROUP BY 1
ORDER BY 4 DESC;


SELECT 
r.region, 
COUNT(*) AS count, 
ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage
FROM sellers s
JOIN state_region r ON s.seller_state = r.state
GROUP BY r.region
ORDER BY count DESC;
