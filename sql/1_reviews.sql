/*
Entry #1 — Delivery status vs. review scores
(full write-up: Olist-Analysis-Log.md, entry 1)

Queries, in order:
1. Baseline: average review score and order count per raw order_status.
2. Main analysis: bucket orders into On-Time / Late / Never Delivered and
   average the review score per bucket.
3. Integrity check: count 'delivered' orders missing a delivery timestamp.
4. Qualitative follow-up: read low-scoring (<=2) reviews on 'shipped' orders.

Finding: on-time orders average 4.29; late 2.57; orders never confirmed
delivered score 1.28-2.00. Delivery completion, not speed, is the dominant
driver of review scores.
*/

--Confirming each order_status and their respective counts
SELECT o.order_status, AVG(r.review_score), COUNT(*) AS count
FROM orders o 
JOIN order_reviews r
ON o.order_id = r.order_id
GROUP BY 1
ORDER BY 2 DESC, 3 DESC;
/* 
Delivered is the category with the largest count as well as a significantly higher average review score.
Shipped is the second largest category in count, the status shouldn't be directly indicating a prolonged delivery, still have a unusually low score.
Approved and Created only have count of 2 and 3, so it might be just noise.
Other categories are more directly linked to the unsatisfaction of the customers, reasonable for the average review score to be lower.
*/

-- Bucketing based on delivery status and averaging the review scores 
SELECT CASE 
	WHEN o.order_delivered_customer_date IS NULL THEN 'Never Delivered'
	WHEN o.order_delivered_customer_date <= o.order_estimated_delivery_date THEN 'On-Time'
	ELSE 'Late'
END AS delivery_status,
AVG(r.review_score) AS avg_score,
COUNT(*) AS n_orders
FROM orders o
JOIN order_reviews r ON o.order_id = r.order_id
GROUP BY 1
ORDER BY 2 DESC;

-- Checking the count of nulls in delivered status, to check the data integrity
SELECT COUNT(*) 
FROM orders 
WHERE order_status = 'delivered' AND order_delivered_customer_date IS NULL;

-- Checking the reason of low review score for shipped status through the review titles and messages
SELECT order_status, review_comment_title, review_comment_message, review_score
FROM order_reviews r
JOIN orders o
ON o.order_id = r.order_id
WHERE order_status = 'shipped' AND review_score <= 2;

/* 
Went through the reviews via LLM and a couple via translation app,
The dominating reviews are about not receiving the product,
followed by refund requests, compliants about sellers, and citing estimated delivery date that passed with nothing showing up.
So we can somewhat conclude the main reason for low review score for shipped status is late delivery that hasn't reach the customer by the time of record.
*/
