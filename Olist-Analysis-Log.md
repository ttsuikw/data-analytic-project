# Olist E-Commerce Analysis Log

A running log of SQL analyses run against the `olist` PostgreSQL database.
Each entry: the business question, the query, the finding, and any caveats.

## Index

| # | Topic | Headline finding |
|---|---|---|
| [1](#1-does-delivery-status-affect-customer-review-scores) | Delivery status vs. review scores | Non-delivery, not lateness, drives bad reviews — on-time avg 4.29, late 2.57, stuck/never-delivered 1.28–2.00 |
| [2](#2-what-does-order-volume-and-revenue-look-like-over-time-any-seasonality-or-sudden-shifts) | Order volume & revenue over time | Steady 2017+ growth, a June 2017 dip, R$15,375,875.44 total revenue |
| [3](#3-how-does-seller-performance-vary--delivery-adherence-income-reviews-and-product-mix) | Seller performance | Worst seller (`b1b3948...`) combines 0.28 delivery adherence, 1.72 avg review, single-category `auto` specialization |
| [4](#4-how-does-delivery-time-vary-by-geography-and-does-olists-estimate-account-for-it) | Delivery time by region | Norte takes ~2x longer than Sudeste (22.6 vs. 10.8 days); explained by seller concentration (92.5% of sellers in Sudeste+Sul) and documented road/logistics gaps, not by a higher failure rate |
| [5](#5-repeat-customer-analysis-how-many-customers-come-back-does-first-purchase-category-predict-it-and-how-long-until-they-return) | Repeat-customer analysis | Only 3.12% of customers ever return; `home_appliances` first-buyers repeat most (9.01%); ~9.21% of "repeat" customers are same-instant split-order artifacts, not real second visits |
| [6](#6-rfm-segmentation-scoring-customers-on-recency-frequency-and-monetary-value) | RFM segmentation | R/F/M scored separately (not blended) since Frequency is too skewed (96.88% = 1 order) for standard quintiles — used custom tiers instead |
| [7](#7-does-seller-to-customer-distance-explain-the-regional-delivery-gradient) | Distance vs. delivery time | Per-order seller-to-customer distance (zip-prefix centroids) accounts for the Norte and Nordeste gaps in full: ~0.6 days per 100 km, Norte's residual after distance is 0.7 ± 0.7 days; Sul (+1.5) and Centro-Oeste (+1.1) are slower than their distance predicts |

---

## 1. Does delivery status affect customer review scores?

**Question:** Do orders that are late, or never confirmed delivered, receive worse reviews than on-time orders?

**Method:** Bucket orders by delivery outcome (on-time / late / never delivered — including
orders stuck at intermediate statuses like `shipped`, `processing`, `canceled`), join to
`order_reviews` on `order_id`, average `review_score` per bucket.

```sql
SELECT 
    CASE 
        WHEN o.order_delivered_customer_date IS NOT NULL 
             AND o.order_delivered_customer_date <= o.order_estimated_delivery_date THEN 'On-Time'
        WHEN o.order_delivered_customer_date IS NOT NULL THEN 'Late'
        ELSE o.order_status  -- shows the actual stuck status instead of a generic bucket
    END AS delivery_status,
    AVG(r.review_score) AS avg_score,
    COUNT(*) AS n_orders
FROM orders o
JOIN order_reviews r ON o.order_id = r.order_id
GROUP BY 1
ORDER BY 2 DESC;
```

**Finding:** Exact results:

| Bucket | Avg. review score | Orders |
|---|---|---|
| On-Time | 4.29 | 88,168 |
| Late (but delivered) | 2.57 | 7,662 |
| `shipped` (stuck) | 2.00 | 1,032 |
| `canceled` | 1.80 | 599 |
| `invoiced` | 1.63 | 309 |
| `unavailable` | 1.53 | 595 |
| `processing` | 1.28 | 295 |

(Buckets with n ≤ 8 — `delivered` with a missing delivery timestamp 4.50 / n=8,
`approved` 2.50 / n=2, `created` 2.33 / n=3 — are too small to interpret.)

On-time deliveries average **4.29**; a confirmed-but-late delivery costs ~1.7 points
(2.57). But every bucket that never reaches a confirmed, timestamped delivery scores
**below even the late orders** (1.28–2.00). Delivery **completion** (not just speed) is
the dominant driver of satisfaction, more than lateness alone.

**Qualitative follow-up:** Read a sample of `shipped`-status reviews scoring ≤2. ~85-90%
are direct non-delivery complaints ("não recebi o produto" / "product never arrived"),
often paired with cancellation/refund requests and complaints about no response from the
seller. A smaller minority (~10-15%) are unrelated complaints (wrong item/color sent,
damaged goods, missing quantity) that happened to also occur on a `shipped`-status order.

**Caveat:** `order_status` is not continuously updated — it reflects whatever the last
recorded state was, not necessarily the order's true current state. An order stuck at
`shipped` may have been sitting there for months with no status update, even if the
underlying shipment was lost, returned, or eventually resolved outside the tracked data.

---

## 2. What does order volume and revenue look like over time? Any seasonality or sudden shifts?

**Question:** What is the order volume over time — how does the trend look, and are there any
expressions of seasonality or sudden rises/drops?

**Method:** Use `DATE_TRUNC()` to bucket `order_purchase_timestamp` by month and by quarter,
count orders per bucket, and sum `payment_value` (joined from `order_payments`) per bucket.
Filtered to `order_status = 'delivered'` to rule out orders affected by the dataset's cutoff
or never-completed orders.

```sql
-- All-time monthly order counts (no status filter) — used to spot the launch-period anomaly
SELECT 
    DATE_TRUNC('month', order_purchase_timestamp) AS order_month,
    COUNT(order_id) AS total_orders
FROM orders
WHERE order_purchase_timestamp IS NOT NULL
GROUP BY 1
ORDER BY order_month ASC;

-- Quarterly order count + revenue, restricted to the stable analysis window (2017 onward)
SELECT 
    DATE_TRUNC('quarter', order_purchase_timestamp) AS order_quarter,
    COUNT(o.order_id) AS total_orders,
    ROUND(SUM(payment_value)::numeric, 2) AS quarterly_total
FROM orders o
JOIN order_payments p ON o.order_id = p.order_id
WHERE order_purchase_timestamp IS NOT NULL
  AND order_purchase_timestamp >= '2017-01-01'
  AND order_status = 'delivered'
GROUP BY 1
ORDER BY order_quarter ASC;

-- Monthly order count + revenue, restricted to the stable analysis window (2017 onward)
SELECT 
    DATE_TRUNC('month', order_purchase_timestamp) AS order_month,
    COUNT(o.order_id) AS total_orders,
    ROUND(SUM(payment_value)::numeric, 2) AS monthly_total
FROM orders o
JOIN order_payments p ON o.order_id = p.order_id
WHERE order_purchase_timestamp IS NOT NULL
  AND order_purchase_timestamp >= '2017-01-01'
  AND order_status = 'delivered'
GROUP BY 1
ORDER BY order_month ASC;

-- Grand total revenue, 2017-01-01 onward, delivered orders only
SELECT
    ROUND(SUM(payment_value)::numeric, 2) AS grand_total
FROM orders o
JOIN order_payments p ON o.order_id = p.order_id
WHERE order_purchase_timestamp IS NOT NULL
  AND order_purchase_timestamp >= '2017-01-01'
  AND order_status = 'delivered';
```

**Finding:** September–December 2016 shows unusually low, sparse order volume (as few as
1 order in some months, a brief 265-order burst across 128 sellers in early October, then a
complete gap in November). This is explained by Olist's own company timeline: Olist only
became an official storefront on major Brazilian marketplaces during 2016, reaching just
2,000 partner sellers by 2017 ([Olist, "Sobre Nós"](https://olist.com/sobre-nos/)) — so 2016
represents genuine early-platform activity, not a data quality issue. Decision: restrict the
stable trend analysis to 2017-01-01 onward.

From 2017 onward, order volume and revenue show sustained, monotonic growth — monthly
revenue never falls back below R$900K after January 2018. There is one notable dip in
June 2017 (R$567,066.73 → R$490,225.60), recovering to R$566,403.93 by July — a single-month
pause in an otherwise consistent uptrend, not a structural problem. Quarterly view confirms
the same steady-rise pattern through 2017, with the expected partial-quarter drop-off in
late 2018 due to the dataset's collection cutoff. Total revenue across the analysis window
(2017-01-01 onward, delivered orders only): **R$15,375,875.44**.

**Caveat:** The June 2017 dip has not been independently explained (e.g. against Brazilian
retail seasonality or a Southern Hemisphere winter effect) — flagged for follow-up, not yet
confirmed as meaningful or coincidental. The 2018 partial-year figures reflect the dataset's
collection cutoff (data ends ~August/September 2018), not a genuine business decline — do not
interpret the apparent lack of a full 2018 total as a slowdown.

---

## 3. How does seller performance vary — delivery adherence, income, reviews, and product mix?

**Question:** Which sellers perform best/worst on a combination of on-time delivery rate,
total income, and average review score — and does what a seller sells (product category mix)
help explain that performance?

**Method:** Seller income must come from `order_items.price` (not `order_payments.payment_value`),
since payments are per-order (composite key with `payment_sequential`, would double/triple count
when an order has multiple installments) while `order_items` gives seller-attributable revenue
directly, even when an order is split across multiple sellers. Freight is excluded from income —
it's largely a pass-through logistics cost outside a seller's control, not revenue they keep.
Delivery adherence is a 0–1 rate (1 = on-time or the order is still in flight and not yet judged
late; 0 = late or never delivered) averaged per seller. Product category mix is built in three
stages: (1) attach an English category name to every order-item row via `products` →
`translation`, using `LEFT JOIN` throughout so untranslated categories don't silently drop rows,
(2) aggregate revenue per seller per category, (3) collapse each seller's categories into one
ordered, comma-separated string (highest-revenue category first) via `STRING_AGG`, skipping the
small number of untranslated categories (see caveats).

```sql
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
    ROUND(AVG(CASE 
        WHEN o.order_delivered_customer_date IS NULL THEN 0
        WHEN o.order_delivered_customer_date <= o.order_estimated_delivery_date THEN 1
        ELSE 0 END)::numeric, 2) AS delivery_adherence,
    ROUND(SUM(s.total_amount)::numeric, 2) AS seller_income, 
    ROUND(AVG(r.review_score)::numeric, 2) AS seller_review_score,
    COUNT(DISTINCT o.order_id) AS total_orders,
    sc.category_mix AS category
FROM orders o
JOIN (SELECT order_id, seller_id, SUM(price) AS total_amount FROM order_items GROUP BY 1, 2) s 
    ON o.order_id = s.order_id
LEFT JOIN seller_categories sc ON s.seller_id = sc.seller_id
LEFT JOIN order_reviews r ON o.order_id = r.order_id
GROUP BY 1, 6
ORDER BY 3 DESC, 4 DESC, 5 DESC;
```

**Finding:** Top sellers by income cluster in the 0.77–1.00 delivery adherence band and the
3.3–4.5 review-score band — high performers are consistently reliable, not just high-volume.
One clear outlier surfaced when scanning down the ranked list: seller `b1b3948701c5c72445495bd161b83a4c`
has income of R$24,699.19 (18 orders) but only **0.28 delivery adherence** and a **1.72 average
review score** — both dramatically worse than every other seller near that income level. Their
`category_mix` is a single value, `auto` (auto parts/accessories, not literal vehicles — verified
via the official [Olist category translation table](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)
rather than assumed from the raw Portuguese label `automotivo`), confirming this seller is a
single-category specialist, not a mixed-catalog seller with auto as an incidental line. This is
consistent with the Entry #1 finding that delivery failure — not product quality — drives most
low review scores; a bulkier/heavier product category is a plausible (not yet confirmed)
contributor to their unusually poor adherence rate.

**Caveat:** (1) When an order is split across multiple sellers, that order's delivery outcome is
counted once for *each* seller involved — a fair representation of "orders this seller was
associated with," but not proof that any single seller caused a given late delivery. (2) The
`products` → `translation` join is missing English labels for 2 legitimate category values
(`pc_gamer`, `portateis_cozinha_e_preparadores_de_alimentos` — a gap in Olist's own published
translation file, not a pipeline error) plus a small number of rows already labeled `Unknown` in
the source data — together ~623 of 32,951 products (~1.9%). `category_mix` silently omits these
untranslated categories from a seller's listed mix (`STRING_AGG` skips `NULL`s); a seller's true
catalog may include unlisted items, though their income/order-count totals are unaffected since
those come from the unfiltered `order_items` sum, not the category pipeline. (3) Cross-verified:
summing `category_revenue` across all categories for the outlier seller reproduces their
`seller_income` exactly (R$24,699.19), confirming no rows were lost or duplicated between the two
aggregation paths for that seller.

---

## 4. How does delivery time vary by geography, and does Olist's estimate account for it?

**Question:** Brazil is huge — do interior/north states wait far longer for delivery than
São Paulo? Does Olist over-promise in remote regions, or pad its estimates to compensate?

**Method:** Broke delivery into four stages using `orders`' timestamp columns
(purchase→approved→carrier→customer), restricted to orders with all four timestamps populated
so every stage-average is computed over the same set of orders and all stages share one
denominator (consistent with the aggregation approach in Entry #3). Customer
geography comes from `customers.customer_state`, the only location field tied to an order in this
dataset (see caveats). States were grouped into Brazil's 5 official IBGE regions (Norte,
Nordeste, Sudeste, Sul, Centro-Oeste) via a small reference table, since 27 individual states
produced a long tail of noisy, low-volume states. Cross-checked the region rollup against (a) each
region's order-incompletion rate, to rule out "slow region" being an artifact of a higher
never-delivered rate, and (b) seller geographic distribution, to check whether slow regions are
simply far from where sellers physically are.

```sql
-- Reference table: state -> official IBGE region
CREATE TABLE state_region (
    state CHAR(2) PRIMARY KEY,
    region VARCHAR(20) NOT NULL
);

INSERT INTO state_region (state, region) VALUES
('AC','Norte'),('AP','Norte'),('AM','Norte'),('PA','Norte'),('RO','Norte'),('RR','Norte'),('TO','Norte'),
('AL','Nordeste'),('BA','Nordeste'),('CE','Nordeste'),('MA','Nordeste'),('PB','Nordeste'),('PE','Nordeste'),('PI','Nordeste'),('RN','Nordeste'),('SE','Nordeste'),
('ES','Sudeste'),('MG','Sudeste'),('RJ','Sudeste'),('SP','Sudeste'),
('PR','Sul'),('RS','Sul'),('SC','Sul'),
('DF','Centro-Oeste'),('GO','Centro-Oeste'),('MT','Centro-Oeste'),('MS','Centro-Oeste');

-- Stage-by-stage delivery time and estimate gap, by region
SELECT 
    region,
    AVG(order_approved_at - order_purchase_timestamp) AS purchase_to_approve,
    AVG(order_delivered_carrier_date - order_approved_at) AS approve_to_carrier,
    AVG(order_delivered_customer_date - order_delivered_carrier_date) AS carrier_to_deliver,
    AVG(order_delivered_customer_date - order_purchase_timestamp) AS average_delivery_time,
    AVG(order_estimated_delivery_date - order_purchase_timestamp) AS average_estimated_time,
    AVG(order_estimated_delivery_date - order_purchase_timestamp)
        - AVG(order_delivered_customer_date - order_purchase_timestamp) AS estimate_delivery_gap,
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

-- Cross-check 1: does incompletion rate explain the regional gap, or is it a genuine transit-time issue?
SELECT 
    sr.region,
    COUNT(*) AS total_orders,
    COUNT(CASE WHEN o.order_purchase_timestamp IS NULL 
                 OR o.order_approved_at IS NULL 
                 OR o.order_delivered_carrier_date IS NULL 
                 OR o.order_delivered_customer_date IS NULL 
               THEN 1 END) AS incomplete_orders,
    ROUND(100.0 * AVG(CASE WHEN o.order_purchase_timestamp IS NULL 
                             OR o.order_approved_at IS NULL 
                             OR o.order_delivered_carrier_date IS NULL 
                             OR o.order_delivered_customer_date IS NULL 
                           THEN 1 ELSE 0 END), 2) AS incomplete_pct
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
JOIN state_region sr ON c.customer_state = sr.state
GROUP BY 1
ORDER BY 4 DESC;

-- Cross-check 2: where are sellers actually located?
SELECT 
    r.region, 
    COUNT(*) AS count, 
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage
FROM sellers s
JOIN state_region r ON s.seller_state = r.state
GROUP BY r.region
ORDER BY count DESC;
```

**Finding:** Delivery speed shows a clear regional gradient. Approval time (hours) and
approve-to-carrier time (~2-3 days, plausibly the seller's own dispatch window) are both
remarkably stable across all 5 regions — the variation lives almost entirely in the carrier-to-
customer leg, which is where the real geography effect shows up:

| Region | Avg. total delivery | Avg. estimated | Estimate–actual gap | Orders |
|---|---|---|---|---|
| Sudeste | 10.8 days | 21.6 days | 10.9 days | 66,187 |
| Sul | 14.0 days | 26.4 days | 12.4 days | 13,812 |
| Centro-Oeste | 15.0 days | 26.7 days | 11.6 days | 5,624 |
| Nordeste | 20.0 days | 30.7 days | 10.7 days | 9,042 |
| Norte | 22.6 days | 37.5 days | 14.9 days | 1,796 |

(Averages are in fractional days; Postgres displays interval averages as `days hh:mm:ss`, and the
values above were re-read from `EXTRACT(EPOCH ...)/86400` in the statistical-checks notebook.)

Sudeste (São Paulo, Rio de Janeiro, Minas Gerais, Espírito Santo) delivers roughly twice as fast
as Norte. Olist's estimate consistently overshoots actual delivery time everywhere (Olist pads
its promise rather than under-delivering). The buffer is 10.7–12.4 days in four regions and
14.9 days in Norte, so the estimation model treats Norte specifically as higher-risk rather than
scaling the buffer smoothly with distance; the estimate itself does scale with distance (see the
distance analysis below).

Cross-check 1 rules out an obvious alternative explanation: order-incompletion rate does **not**
track region difficulty in the way the delivery-time gradient would predict. Nordeste has the
highest incompletion rate (3.75%), not Norte (2.97%, second-lowest of all 5 regions), and all 5
regions sit in a narrow 2.4%–3.75% band regardless of how slow or fast their completed deliveries
are. This means Norte's slowness is a genuine transit-time problem for orders that do complete,
not a symptom of a higher failure/dropout rate.

Cross-check 2 shows why the gradient exists: seller supply is extremely concentrated — 73.89% of
all sellers are in Sudeste and 21.58% in Sul, together **92.5%** of every seller on the platform,
while Norte has just 5 sellers nationwide (0.16%). This is consistent with independently
documented Brazilian logistics structure: Sudeste hosts the Port of Santos (Latin America's
largest container terminal) and roughly 42–54% of national freight/logistics activity, anchored
around São Paulo's industrial base ([IMARC Group](https://www.imarcgroup.com/brazil-logistics-market),
[Mordor Intelligence](https://www.mordorintelligence.com/industry-reports/brazil-freight-logistics-market-study)),
while Norte is documented as Brazil's most road-poor, Amazon-rainforest-dominated region, with
~77.8% of its roads rated regular-to-terrible condition and freight often dependent on river/air
transport instead of highways ([ALG Global](https://www.alg-global.com/blog/logistics/transportation-and-logistics-challenges-northern-brazil),
[Liberal Amazon / CNT road survey](https://www.liberalamazon.com/pt-BR/news/news/highways-in-the-north-in-precarious-condition)).
Norte's slow delivery is therefore best explained by a combination of raw distance from where
nearly all sellers are based, plus objectively worse transport infrastructure — not one single
cause.

**Caveat:** (1) `customer_state` is the customer's registered state, not a confirmed per-order
shipping address — this dataset has no separate delivery-address table, so state-level delivery
time is an assumption that registered state = delivery destination, not a verified fact. (2) The
explanation that Olist pads estimates for "refund policy" reasons, and that Sudeste's speed is
specifically driven by São Paulo/Rio's dense metro infrastructure, are both **untested
hypotheses** — plausible given the sourced context above, but not directly confirmed against
refund data or a city-level breakdown within Sudeste. (3) Norte's sample size (1,796 orders vs.
66,187 for Sudeste) is small relative to the other regions — reflecting Norte's genuinely lower
population/order share, not a data quality issue, but its average is less statistically stable
than Sudeste's. (4) Seller-state was intentionally left out of the main delivery-time query
(cross-checked separately instead) because joining `order_items`/`sellers` state alongside
customer state would reintroduce the multi-seller-per-order fan-out risk from Entry #3.

---

## 5. Repeat-customer analysis: how many customers come back, does first-purchase category predict it, and how long until they return?

**Question:** Olist mints a new `customer_id` for every single order, even from the same real
person — so "repeat customer" has to be measured on `customer_unique_id`, not `customer_id`.
Given that, what fraction of customers ever place a 2nd order? Does the category of a customer's
*first* purchase predict whether they come back? And for those who do return, how long is the gap
between their 1st and 2nd order?

**Method:** Verified that `orders.customer_id` maps 1:1 to exactly one order (`SELECT customer_id, COUNT(*) FROM orders GROUP BY customer_id` returns 1 for every
row) — this is what makes `COUNT(o.order_id)` after joining `customers` to `orders` and grouping
by `customer_unique_id` a valid total-order-count per real person, with no risk of double-counting
or undercounting from the `customer_id`/`customer_unique_id` split.

For the category question, needed one row per customer at the *first-order* grain, not the
order-item grain: used `ROW_NUMBER() OVER (PARTITION BY customer_unique_id ORDER BY
order_purchase_timestamp)` to tag each order with its sequence per customer, filtered to rank 1,
then joined to `order_items`/`products`/`translation` for category names — since a first order can
contain multiple items in different categories, used `DISTINCT ON (customer_unique_id) ... ORDER
BY customer_unique_id, price DESC` to deterministically pick the highest-value item's category per
customer (a simplification; see caveats). Categories were joined via
the `translation` table with a `LEFT JOIN` + `Unknown` fallback (consistent with Entry #3), so the
~1.9% of untranslated products don't silently drop customers.

For the return-time question, used `LAG(order_purchase_timestamp) OVER (PARTITION BY
customer_unique_id ORDER BY order_purchase_timestamp)` alongside the same `ROW_NUMBER()`, filtered
to rank 2, so each repeat customer's row shows both their 1st and 2nd purchase timestamp side by
side and the gap is a simple subtraction — no self-join or subquery needed.

```sql
-- Step 1: verify customer_id : order is 1:1
SELECT customer_id, COUNT(*) AS n_orders
FROM orders
GROUP BY customer_id
ORDER BY n_orders DESC
LIMIT 10;  -- returns 1 for every row

-- Step 2: one-time vs. repeated bucketing (Frequency, feeding into #11 RFM later)
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

-- Step 3: first-purchase category vs. repeat rate
WITH customer_rank AS (
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
        COALESCE(t.product_category_name_english, 'Unknown') AS first_category_name
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
    ROUND(100.0 * SUM(CASE WHEN total_orders_by_customer > 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS repeat_rate
FROM first_order_cat
GROUP BY 1
HAVING COUNT(*) > 100
ORDER BY repeat_rate DESC;

-- Step 4: gap between 1st and 2nd purchase, for repeat customers
WITH rank AS (
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
WHERE order_rank = 2;

-- Step 5: quantify same-instant "repeat" orders (0-second gap)
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
    SELECT customer_unique_id, order_purchase_timestamp - prev_order_date AS days_between
    FROM rank
    WHERE order_rank = 2
)
SELECT
    COUNT(*) AS total_repeat_customers,
    COUNT(CASE WHEN days_between = INTERVAL '0' THEN 1 END) AS zero_gap_customers,
    ROUND(100.0 * COUNT(CASE WHEN days_between = INTERVAL '0' THEN 1 END) / COUNT(*), 2) AS zero_gap_pct
FROM gaps;
```

**Finding:** Of 96,096 unique customers, 96.88% (93,099) are one-time buyers and only 3.12%
(2,997) ever placed a 2nd order — a low repurchase rate by any normal retail benchmark, though
Olist's own historical repeat-rate isn't available for direct comparison, so "low" here means low
in absolute terms, not confirmed low relative to a stated goal.

First-purchase category does correlate with eventual repeat behavior, though the effect is modest
and the ranking is dominated by home/fashion goods once tiny categories are filtered out
(`HAVING COUNT(*) > 100`): `home_appliances` (n=688) tops the list at 9.01% repeat rate, followed
by `fashion_male_clothing` (6.54%), `fashion_shoes` (6.06%), and `fashion_bags_accessories`
(5.84%, n=1,729). The two highest-*volume* categories, `bed_bath_table` (n=8,872) and
`furniture_decor` (n=6,031), sit in the middle of the pack at 4.50% and 4.71% — large sample,
moderate lift. Most categories cluster tightly in the 2–3% range regardless of volume, and
low-repeat categories skew toward construction/tech/electronics (`books_technical` 0.78%,
`construction_tools_lights` 0.90%, `computers` 1.13%) — plausibly durable, infrequently-repurchased
goods, though this is an inference from the category names, not a tested claim.

For customers who did return, the gap to their 2nd order includes a real artifact worth flagging:
**9.21% of the 2,997 repeat customers have an exact 0-second gap** between their 1st and 2nd
order — traced to specific cases (e.g. customer `2e43e031f10de28e557c35ef668f9396`, 3 orders
within 1 second of each other) where a single checkout session produced multiple separate
`order_id`s. Checking one such case directly ruled out the initial "one order_id per seller"
hypothesis: one of that customer's 3 orders (`df56136b...`) contained items from 2 different
sellers within a single `order_id`, so multi-seller carts don't cleanly force an order split — the
exact mechanism behind the split remains unconfirmed. Beyond the exact-0-second cases, gaps of a
few seconds to under a minute are also common, with no natural, defensible cutoff between
"same checkout, artifact" and "genuine fast second visit" — left unresolved rather than picking an
arbitrary boundary.

**Caveat:** (1) The first-purchase-category assignment picks one category per customer via their
first order's *highest-priced item* when the first order spans multiple categories — an explicit
simplification; a customer's "first category" could instead be defined by item count, or the
customer could be counted once per category, changing the category-level rates somewhat. (2)
Category-level repeat rates below `n=100` were excluded via `HAVING` as unreliable, but even
survivors like `fashion_male_clothing` (n=107) and `home_appliances` (n=688) are far smaller than
`bed_bath_table` (n=8,872) — treat the top-ranked categories' precise percentages as indicative,
not precise, until re-checked with a confidence interval or bootstrap. (3) The 9.21% same-instant
"repeat" figure means the *true* behavioral repeat rate (customers who came back on a different
day) is somewhat below the raw 3.12%, but no adjusted figure was computed — stated here as a flag,
not a corrected number. (4) The mechanism behind same-instant multi-order-id checkouts is
unconfirmed — the "one seller per order" theory was tested and disproven on one example, but no
replacement theory has been verified across the full ~276 affected customers.

---

## 6. RFM segmentation: scoring customers on Recency, Frequency, and Monetary value

**Question:** Which customers are the most valuable, and on what basis? Rather than treating all
96,096 customers the same, score each on three independent dimensions — how recently they last
ordered, how often they've ordered, and how much they've spent — to separate high-value customers
from one-time, low-value ones.

**Method:** Computed all three raw metrics in one CTE, grouped by `customer_unique_id`: Recency as
"dataset-wide max order date minus this customer's own max order date" (using a scalar subquery
for the global max, since the dataset is a static historical snapshot — there's no live "today" to
anchor against, so the last recorded activity date stands in for "now"), Frequency as
`COUNT(DISTINCT order_id)`, and Monetary as `SUM(price)` from `order_items`. Two join-related fixes
were necessary to get the population and values right:

- **`LEFT JOIN order_items`, not `INNER JOIN`** — an inner join silently dropped customers whose
  orders had no matching line items, undercounting the population by ~700 (95,420 vs. the true
  96,096 confirmed in Entry #5). Switching to `LEFT JOIN` + `COALESCE(SUM(...), 0)` restored the
  full, correct population.
- **`::numeric` cast on `SUM(i.price)`** — without it, Monetary values showed binary
  floating-point rounding artifacts (e.g. `664.1999999999999` instead of `664.20`), since `price`
  is stored as a float type and repeated addition of non-exact binary fractions accumulates
  visible residue. Cosmetic only — far too small to shift any customer's quintile — but fixed for
  a clean final table.

Scoring (1-5, 5 = best) used two different techniques depending on each metric's distribution
shape:

- **Recency and Monetary** — continuous, reasonably spread values, so `NTILE(5)` (data-driven
  quintiles) works correctly. Sort direction sets score orientation: `NTILE(5) OVER
  (ORDER BY recency_days DESC)` puts the *largest* recency_days (oldest, worst) first, bucket 1,
  and the smallest (most recent, best) last, bucket 5. Monetary uses `ORDER BY monetary ASC` for
  the same reason, in the opposite direction (lowest spend, bucket 1).
- **Frequency** — could not use `NTILE(5)` at all. 96.88% of customers share the single value
  `frequency = 1` (confirmed in Entry #5), so quintiles computed on this column arbitrarily split
  that one tied block across multiple buckets by row order, putting some one-time customers in the
  same top score as genuine 4-order repeat customers. Replaced with a hand-set `CASE WHEN` scheme
  grounded in the real distribution (checked via `SELECT frequency, COUNT(*) ... GROUP BY
  frequency`): 92,507 customers at freq=1, 2,673 at freq=2, 192 at freq=3, 29 at freq=4, and only
  19 total at freq>=5 (max observed: 17).

```sql
WITH rfm AS (
    SELECT 
        c.customer_unique_id,
        -- Recency: days between dataset's last recorded order and this customer's last order
        ((SELECT MAX(order_purchase_timestamp) FROM orders)::date 
            - MAX(o.order_purchase_timestamp)::date) AS recency_days,
        -- Frequency: total distinct orders
        COUNT(DISTINCT o.order_id) AS frequency,
        -- Monetary: total item-price spend (excludes freight -- freight reflects the customer's
        -- location, not their spend/value to the platform; consistent with Entry #3's revenue definition)
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
```

**Finding:** Segment scores were kept separate (R, F, M as three distinct 1-5 scores per customer)
rather than collapsed into one blended number, deliberately — a simple sum/average would hide the
difference between customer types (e.g. a brand-new high-spend one-time buyer vs. a lower-spend
but loyal repeat buyer could land on the same total score despite being completely different
segments to act on).

Sorting by the combined scores surfaces recognizable segments at the top: customers like
`8d50f5eadf50201ccdcedfb9e2ac8455` (recency 58 days, frequency 17, monetary R$729.62 — R=5, F=5,
M=5) represent genuine "champions": recent, highly frequent, and decent spend. Others at the top
by recency/monetary alone but with only 1 order (e.g. customers with R=5, M=5, F=1) are
high-value *one-time* buyers — worth a different business action (retention outreach) than the
true repeat champions, which is exactly the distinction a blended single score would have erased.

Because Frequency is so heavily skewed (92,507 of 96,096 customers, 96.88%, sit in the bottom
f_score=1 tier by construction), R and M carry most of the real discriminating power across the
customer base in practice — for the vast majority of customers, their overall value read mostly
comes down to how recently and how much they spent on their single order, not how often they
returned, simply because "how often" barely varies for almost everyone.

**Caveat:** (1) The Frequency `CASE WHEN` breakpoints (1 / 2 / 3-4 / 5+) were chosen to match the
observed distribution's natural size drop-offs, not a formula — a different analyst could
reasonably draw the lines elsewhere (e.g. splitting 3 and 4 into separate tiers), and the resulting
bucket sizes are intentionally very uneven (92,507 vs. 19) rather than balanced, unlike R and M's
quintiles. (2) Recency's reference point is the dataset's own last recorded order date, not a live
"today" — correct for this static historical snapshot, but this RFM table would need to be
rebuilt against a fresh reference date if applied to live, ongoing data. (3) Monetary excludes
freight_value by design (see Entry #3 precedent) — a customer in a remote/high-freight region
showing lower "Monetary" isn't necessarily a lower-value customer in total transaction size, just
lower in the specific revenue definition used here. (4) No single blended RFM score or named
segment labels (e.g. "Champions," "At risk") were assigned this round — scores are left as three
separate columns; grouping customers into named segments would be a reasonable next step but
requires a business-judgment mapping not yet defined.

---

## 7. Does seller-to-customer distance explain the regional delivery gradient?

**Question:** The geography analysis attributes Norte's 22.6-day average (vs. Sudeste's 10.8) to
seller concentration and infrastructure, but measures neither directly — the evidence is seller
counts by region. If the mechanism is distance, then delivery time should rise with the
seller-to-customer distance of each order, and region should carry little additional information
once distance is held constant. If infrastructure matters beyond distance, Norte should remain
slower than a Sudeste order shipped the same number of kilometres.

**Method:** For every delivered order with all four timestamps populated (the same order set as
the regional table), the haversine distance between the seller's and the customer's zip-prefix
centroid was computed from the cleaned `geolocation` table. Orders with more than one seller
(1,275 of 96,461, 1.3%) were excluded rather than fanned out, so each order has one origin.
Orders touching a placeholder zip (NULL coordinates) or one of 11 zip prefixes whose averaged
centroid falls outside Brazil's bounding box were also excluded, leaving 94,708 orders. The
per-order extract is stored as a view; the SQL below summarises it by distance band and by
customer region. The regression of delivery time on distance with region dummies (Sudeste as
reference, HC1 robust errors) is in `stats/statistical_checks.ipynb`.

```sql
-- Query 1: per-order extract — one row per single-seller, fully-timestamped delivered order
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


-- Query 2: delivery time by distance band
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


-- Query 3: average seller-to-customer distance by customer region
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
```

**Finding:** Delivery time rises roughly linearly with distance, about 0.6 days per 100 km on a
base of about 8.6 days at zero distance (approval, dispatch and last-mile handling that do not
scale with distance). Late-delivery rate doubles across the bands.

| Distance band | Orders | Avg. delivery | Carrier→customer | Avg. estimated | Late |
|---|---|---|---|---|---|
| < 100 km | 17,693 | 6.5 days | 3.4 days | 15.3 days | 6.44% |
| 100–500 km | 36,454 | 11.6 days | 8.4 days | 22.9 days | 7.24% |
| 500–1,000 km | 25,378 | 14.4 days | 11.1 days | 26.3 days | 8.52% |
| 1,000–2,000 km | 9,619 | 18.0 days | 14.7 days | 30.1 days | 10.88% |
| ≥ 2,000 km | 5,564 | 21.2 days | 17.8 days | 33.2 days | 13.75% |

The regional ordering of delivery time is the regional ordering of distance. Half of Sudeste's
orders are fulfilled in-state; none of Norte's are.

| Customer region | Orders | Median distance | Avg. delivery | Same-state seller |
|---|---|---|---|---|
| Sudeste | 65,090 | 330 km | 10.8 days | 50.3% |
| Sul | 13,575 | 625 km | 14.1 days | 9.1% |
| Centro-Oeste | 5,365 | 864 km | 15.1 days | 1.5% |
| Nordeste | 8,914 | 1,884 km | 20.0 days | 1.5% |
| Norte | 1,764 | 2,378 km | 22.6 days | 0.0% |

Regressing delivery days on distance and region together (notebook §4): region alone explains
10.9% of order-level variance, distance alone 15.5%, both 15.8%. Holding distance constant,
Norte's gap to Sudeste falls from 11.9 days to 0.7 (95% CI −0.02 to 1.34) and Nordeste's from
9.3 to 0.8 — distance accounts for both. Sul (+1.5 days, CI 1.4–1.7) and Centro-Oeste (+1.1,
CI 0.9–1.4) are the regions that remain slower than their distance predicts. A median regression
gives the same picture (Norte −0.05, Nordeste +0.08, Centro-Oeste +1.4, Sul +1.6 days). The
infrastructure explanation is therefore not needed to account for Norte's average; Norte is slow
because its orders travel ~2,200 km from Sudeste and Sul sellers at the same per-kilometre rate
as everyone else's. Olist's estimate tracks distance more closely (Spearman 0.62) than actual
delivery time does (0.54), so the estimation model is distance-aware.

**Caveat:** (1) Distances are between zip-prefix centroids (mean coordinate per prefix after the
cleaning in `main.ipynb`), not addresses; within-city distances are noisy near zero, and one
implausible pair (ES→SP, 3,927 km) survives the bounding-box filter without affecting the
estimates. (2) Haversine is straight-line distance. Road or river routing lengthens it unevenly by
region, so any infrastructure effect is folded into the per-kilometre rate rather than appearing
as a regional residual; the finding is that no residual exists for Norte beyond that, not that
infrastructure is irrelevant. (3) Excluding multi-seller orders removes 1.3% of orders that are,
by construction, more complex to fulfil; their delivery times are not represented. (4) R² of 0.16
means geography explains where the regional averages sit, not why an individual order is late —
84% of order-level variance is seller-, carrier- and order-specific.

---
