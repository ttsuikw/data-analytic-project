/*
Question: Does seller-to-customer distance explain the regional delivery-time gradient
          (Norte 22.6 days vs. Sudeste 10.8), or is there a regional effect beyond distance?
Method:   Haversine distance between the seller's and the customer's zip-prefix centroid
          (geolocation table, mean lat/lng per prefix), per delivered order with all four
          timestamps populated (same order set as the delivery-time-by-region analysis).
          Restricted to single-seller orders so each order has one origin; multi-seller
          orders (1,275 of 96,461, 1.3%) are excluded rather than fanned out.
          Query 1 stores the per-order extract as a view (order_distance), which
          stats/statistical_checks.ipynb reads for the correlation and regression with
          region dummies. Queries 2-3 are the SQL-level summaries recorded in the log.
Date:     2026-09-04
*/


-- per-order extract — one row per single-seller, fully-timestamped delivered order
CREATE OR REPLACE VIEW order_distance AS
WITH complete_orders AS (
    SELECT *
    FROM orders
    WHERE order_purchase_timestamp IS NOT NULL
      AND order_approved_at IS NOT NULL
      AND order_delivered_carrier_date IS NOT NULL
      AND order_delivered_customer_date IS NOT NULL
),
single_seller AS (                      -- one origin per order
    SELECT order_id, MIN(seller_id) AS seller_id
    FROM order_items
    GROUP BY order_id
    HAVING COUNT(DISTINCT seller_id) = 1
),
located AS (
    SELECT
        o.order_id,
        c.customer_state,
        sr.region                                   AS customer_region,
        se.seller_state,
        gc.geolocation_lat  AS c_lat, gc.geolocation_lng AS c_lng,
        gs.geolocation_lat  AS s_lat, gs.geolocation_lng AS s_lng,
        EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_purchase_timestamp))   / 86400.0 AS delivery_days,
        EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_delivered_carrier_date)) / 86400.0 AS carrier_to_customer_days,
        EXTRACT(EPOCH FROM (o.order_estimated_delivery_date - o.order_purchase_timestamp))   / 86400.0 AS estimated_days
    FROM complete_orders o
    JOIN customers     c  ON c.customer_id = o.customer_id
    JOIN state_region  sr ON sr.state = c.customer_state
    JOIN single_seller s  ON s.order_id = o.order_id
    JOIN sellers       se ON se.seller_id = s.seller_id
    JOIN geolocation   gc ON gc.geolocation_zip_code_prefix = c.customer_zip_code_prefix
    JOIN geolocation   gs ON gs.geolocation_zip_code_prefix = se.seller_zip_code_prefix
    WHERE gc.geolocation_lat IS NOT NULL       -- drop the 162 placeholder zips (NULL coordinates)
      AND gs.geolocation_lat IS NOT NULL
      -- 11 zip-prefix centroids fall outside Brazil's bounding box (bad source coordinates
      -- pulled the per-prefix mean off the map); orders touching them are excluded
      AND gc.geolocation_lat BETWEEN -34 AND 5.5 AND gc.geolocation_lng BETWEEN -74 AND -34.5
      AND gs.geolocation_lat BETWEEN -34 AND 5.5 AND gs.geolocation_lng BETWEEN -74 AND -34.5
)
SELECT
    order_id,
    customer_state,
    customer_region,
    seller_state,
    ROUND((2 * 6371 * ASIN(SQRT(
          POWER(SIN(RADIANS(c_lat - s_lat) / 2), 2)
        + COS(RADIANS(s_lat)) * COS(RADIANS(c_lat)) * POWER(SIN(RADIANS(c_lng - s_lng) / 2), 2)
    )))::numeric, 1)                              AS distance_km,
    ROUND(delivery_days::numeric, 2)              AS delivery_days,
    ROUND(carrier_to_customer_days::numeric, 2)   AS carrier_to_customer_days,
    ROUND(estimated_days::numeric, 2)             AS estimated_days
FROM located;

SELECT COUNT(*) AS n_orders, MIN(distance_km), MAX(distance_km) FROM order_distance;


-- delivery time by distance band
SELECT
    CASE
        WHEN distance_km <  100  THEN '0. < 100 km'
        WHEN distance_km <  500  THEN '1. 100-500 km'
        WHEN distance_km < 1000  THEN '2. 500-1,000 km'
        WHEN distance_km < 2000  THEN '3. 1,000-2,000 km'
        ELSE                          '4. >= 2,000 km'
    END                                          AS distance_band,
    COUNT(*)                                     AS n_orders,
    ROUND(AVG(delivery_days), 1)                 AS avg_delivery_days,
    ROUND(AVG(carrier_to_customer_days), 1)      AS avg_carrier_to_customer_days,
    ROUND(AVG(estimated_days), 1)                AS avg_estimated_days,
    ROUND(100.0 * AVG(CASE WHEN delivery_days > estimated_days THEN 1 ELSE 0 END), 2) AS late_pct
FROM order_distance
GROUP BY 1
ORDER BY 1;


-- average seller-to-customer distance by customer region
--          (to set against the region delivery-time table in the geography analysis)
SELECT
    customer_region,
    COUNT(*)                                     AS n_orders,
    ROUND(AVG(distance_km), 0)                   AS avg_distance_km,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY distance_km)::numeric, 0) AS median_distance_km,
    ROUND(AVG(delivery_days), 1)                 AS avg_delivery_days,
    ROUND(100.0 * AVG(CASE WHEN seller_state = customer_state THEN 1 ELSE 0 END), 1) AS same_state_pct
FROM order_distance
GROUP BY 1
ORDER BY 3;
