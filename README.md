# Olist E-Commerce Analysis


![Overview page](/pbi/Overview.png)

End-to-end analysis of the [Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce): ~100K orders placed between 2016 and 2018 across 9 relational tables covering orders, items, payments, reviews, products, customers, sellers, and geolocation. The pipeline runs from raw CSVs through a constraint-enforced PostgreSQL database into six SQL analyses and a four-page Power BI dashboard.

**Stack:** Python (pandas, SQLAlchemy) · PostgreSQL · Power BI


## Executive summary

1. **Delivery completion, not speed, drives customer satisfaction.** On-time orders average a 4.29 review score (n=88,168); confirmed-but-late orders average 2.57 (n=7,662); orders that never reach a confirmed delivery — stuck at `shipped`, `invoiced`, `unavailable`, `processing` — average 1.28–2.00, below even the late deliveries.
2. **Revenue grew steadily from 2017**, totaling R$15.38M in delivered payment revenue over the analysis window. The apparent late-2018 decline is the dataset's collection cutoff, not a business slowdown.
3. **Delivery time follows a strong regional gradient** — Norte averages 22.5 days vs. Sudeste's 10.8 — explained by seller concentration (92.5% of sellers are in Sudeste + Sul; Norte has 5) and documented infrastructure gaps, not by higher failure rates.
4. **Retention is minimal: 3.12% of 96,096 customers ever place a second order**, and ~9.2% of those "repeat" customers are same-instant checkout artifacts, so the behavioral repeat rate is lower still.
5. **Customer value is concentrated and skewed.** Order-level spend is approximately log-normal (peak ≈ R$50–300); purchase frequency is so skewed (96.88% single-order) that standard quintile scoring is invalid for it and required a distribution-based tier scheme instead.

---

## Business context

Olist is a Brazilian marketplace integrator: it lets small merchants list and sell through major Brazilian e-commerce channels without registering on each one separately. The dataset is real, anonymized commercial data. The analysis addresses four operational questions a marketplace of this kind faces: what drives customer satisfaction, how revenue is developing, where fulfillment underperforms, and which customers carry the value.

## Project structure

```
├── main.ipynb              # Stage 1: cleaning + PostgreSQL database build (pandas, SQLAlchemy)
├── Olist-Analysis-Log.md   # Stage 2: six SQL analyses — question, query, finding, caveats
├── sql/                      # one file per log entry, numbered to match
│   ├── 1_reviews.sql         #   Delivery status vs. review scores
│   ├── 2_sales.sql           #   Order volume & revenue over time
│   ├── 3_seller.sql          #   Seller performance & category mix
│   ├── 4_delivery_time.sql   #   Delivery time by geography
│   ├── 5_repeat_customer.sql #   Repeat-customer behavior
│   └── 6_rfm.sql             #   RFM customer segmentation
├── pbi/                    # Stage 3: Power BI dashboard + page exports
│   ├── olist.pbix
│   ├── Overview.png
│   ├── Delivery.png
│   ├── Seller.png
│   └── Customer.png
├── data/                   # raw Kaggle CSVs — not committed (see Reproduce)
├── schema.png              # Database entity-relationship diagram
├── requirements.txt        # Python dependencies for main.ipynb
├── .gitignore
└── README.md
```

## Pipeline

```
Kaggle CSVs (9 tables, ~100K orders)
   │  pandas: dedup, normalize, type enforcement, NULL policy
   ▼
PostgreSQL (explicit schema: PKs, composite PKs, FKs)
   │  SQL: CTEs, window functions, cross-checked aggregations
   ▼
Six analysis entries (Olist-Analysis-Log.md)
   │  CSV exports of final queries
   ▼
Power BI (4 pages: Overview · Delivery · Seller · Customer)
```

---

## Stage 1 — Data cleaning and database build (`main.ipynb`)

Each cleaning step follows the same procedure: audit, quantify the issue, decide with the trade-off recorded.

**Duplicates.** A full-row audit found 261,831 exact duplicates in `geolocation`. A key-level check on `order_reviews` found 814 duplicated `review_id`s and 551 duplicated `order_id`s; the data dictionary attributes repeated `review_id`s to platform bugs, so deduplication was keyed on `order_id` (one review per order). This choice is what later allows `order_reviews` to carry a primary key on `order_id`.

**Geolocation.** After exact deduplication, Unicode normalization (NFKD → ASCII) unified accented and unaccented spellings of the same city, exposing 17,837 further duplicates. 555 zip prefixes (~3%) still mapped to more than one city/state, which blocks using the zip prefix as a key. The table was aggregated to one row per zip prefix — mean lat/lng, modal city/state — and re-checked: zero conflicts remain (19,015 rows).

**Missing values.** Treatment depends on whether a NULL carries information:

- `order_reviews` title/message (88.3% / 58.7% missing) — expected behavior (most buyers rate without writing) — filled with explicit sentinels.
- `orders` delivery timestamps (0.16%–2.98% missing) — these NULLs mark orders that never completed a pipeline stage. They were left as NULL; Analysis #1 depends on this signal, and imputation would fabricate delivery events.
- `products` category (1.85%) — filled with `'Unknown'`; the affected products are referenced by real sales and cannot be dropped. Physical dimensions were left nullable rather than imputed.

**Types.** Datetime conversions use `errors='raise'` so parsing failures halt the pipeline rather than inserting silent `NaT`s; count-like columns use nullable `Int64`; two source-column typos (`lenght`) were renamed.

**Schema.** Tables were declared explicitly in SQLAlchemy rather than auto-created by `pandas.to_sql`: primary keys on all dimensions, composite keys where single columns are non-unique (`order_items`: `order_id`+`order_item_id`; `order_payments`: `order_id`+`payment_sequential`), and foreign keys on every relationship. The initial load raised a foreign-key violation: 162 zip prefixes referenced by `customers`/`sellers` were absent from the cleaned `geolocation` table. Of the three options — dropping the constraint, deleting the affected rows, or inserting placeholder geolocation rows — placeholders (`Unknown` city/state, NULL coordinates) preserve both referential integrity and the affected sales data; the cost is that 162 zips cannot be mapped by coordinate, which does not affect the analyses since geography is handled at state level. Final integrity checks confirm zero orphaned rows in all child tables.

---

## Stage 2 — SQL analyses (`Olist-Analysis-Log.md`)

Each log entry records the business question, the query, the finding, and its caveats. Summary of the six entries:

### 1. Delivery status vs. review scores

On-time orders average **4.29** (n=88,168); confirmed-but-late orders **2.57** (n=7,662); orders with no confirmed delivery timestamp (`shipped`, `canceled`, `invoiced`, `unavailable`, `processing`) average **1.28–2.00** — below the late-but-delivered group. A qualitative review of low-scoring `shipped`-status comments found ~85–90% are direct non-delivery complaints. Delivery completion is the dominant satisfaction driver; lateness is secondary.

### 2. Order volume and revenue over time

Late-2016 data is sparse launch-period activity (a 265-order burst, then a full-month gap), consistent with [Olist's company timeline](https://olist.com/sobre-nos/); the trend window was therefore restricted to 2017 onward. From 2017, growth is steady — monthly revenue does not fall below R$900K after January 2018 — with one unexplained single-month dip in June 2017. Total payment revenue on delivered orders in the window: **R$15,375,875.44**.

### 3. Seller performance and category mix

Seller income was measured from `order_items.price` (per-order payments would double-count multi-installment orders; freight is a pass-through cost). Top-income sellers cluster at 0.77–1.00 delivery adherence and 3.3–4.5 review scores. One outlier departs from this pattern: seller `b1b39487...` earns R$24,699 on 18 orders with 0.28 adherence and a 1.72 average review, specialized in a single category (`auto`). This is consistent with Entry #1: delivery failure, not product quality, accounts for most low scores. The category-revenue aggregation was cross-checked against seller income totals and reconciles exactly.

### 4. Delivery time by geography

| Region | Avg. delivery | Avg. estimated | Buffer | Orders |
|---|---|---|---|---|
| Sudeste | 10.8 days | 21.6 days | 11.0 days | 66,187 |
| Sul | 14.0 days | 26.4 days | 13.5 days | 13,812 |
| Centro-Oeste | 14.4 days | 26.7 days | 12.4 days | 5,624 |
| Nordeste | 19.2 days | 30.7 days | 11.4 days | 9,042 |
| Norte | 22.5 days | 37.5 days | 15.0 days | 1,796 |

Stage decomposition (purchase→approval→carrier→customer) shows approval and dispatch times are stable across regions; the variation is almost entirely in carrier-to-customer transit. Two cross-checks address alternative explanations: order-incompletion rates do not track the gradient (Norte is second-lowest at 2.97%), and seller supply does — 92.5% of sellers are in Sudeste + Sul against 5 sellers in Norte, compounded by documented road-infrastructure gaps in the Amazon region ([ALG Global](https://www.alg-global.com/blog/logistics/transportation-and-logistics-challenges-northern-brazil)). Olist's delivery estimates exceed actuals in every region, with the largest buffer applied to Norte.

### 5. Repeat-customer analysis

Measured on `customer_unique_id` (`customer_id` is per-order in this dataset), 96.88% of 96,096 customers are one-time buyers; 3.12% placed a second order. First-purchase category correlates modestly with returning — `home_appliances` leads at 9.01% repeat rate; durable/tech categories fall below 1.2%. A data-quality finding qualifies the headline number: 9.21% of repeat customers show an exact 0-second gap between their first two orders — single checkout sessions split into multiple `order_id`s — so the behavioral repeat rate is below the raw 3.12%. The split mechanism was tested against a multi-seller-cart hypothesis, which one counterexample disproved; the mechanism remains unconfirmed.

### 6. RFM segmentation

Recency and Monetary are scored as `NTILE(5)` quintiles. Frequency cannot be: 96.88% of customers share the value 1, and quintiles over a tie of that size split it arbitrarily by row order. Frequency instead uses fixed tiers matched to the observed distribution (92,507 / 2,673 / 192 / 29 / 19 customers at freq 1 / 2 / 3 / 4 / ≥5). Two implementation details materially affect correctness: `LEFT JOIN order_items` (an inner join drops ~700 customers whose orders have no line items) and a `::numeric` cast on the price sum (float accumulation otherwise shows rounding residue). Scores are reported as three separate dimensions rather than a blended index, since a high-spend one-time buyer and a loyal repeat buyer would otherwise collapse into the same score despite requiring different actions.

---

## Stage 3 — Power BI dashboard (pbi/olist.pbix)

Four pages built on CSV exports of the final SQL queries.

![Overview page](/pbi/Overview.png)

- **Overview (landing):** R$13.59M total revenue, 99.4K orders, 112.65K units sold, R$137.75 average order value (item revenue ÷ distinct orders); top categories, dual-axis monthly orders/revenue trend, payment-type split, customer-region treemap.

![Delivery page](/pbi/Delivery.png)

- **Delivery:** review score by delivery-status group, average delivery days by region (10.69–22.54), estimate-vs-actual gap.

![Seller page](/pbi/Seller.png)

- **Seller:** 3.1K sellers, 0.92 mean delivery adherence, income-vs-review scatter for sellers with >50 orders, seller-state concentration (SP: 65.97%).

![Customer page](/pbi/Customer.png)

- **Customer:** one-time vs. repeat split (97% / 3%), repeat rate by first-purchase category, Recency×Monetary score matrix (near-uniform, indicating R and M are largely independent), and a log₁₀ monetary histogram showing an approximately log-normal spend distribution peaking around R$50–300.

Modeling notes:

- **Two revenue definitions coexist by design.** The dashboard's R$13.59M sums `order_items.price` (seller-attributable item revenue, freight excluded, all orders); the log's R$15.38M sums `payment_value` (amounts actually paid, freight included) on delivered orders from 2017. They answer different questions and are labeled accordingly.
- **AOV uses distinct orders as its denominator** (`DISTINCTCOUNT(order_id)` = 98,666), giving R$137.75. Dividing by item rows (112,650) would produce average item value (R$120.65) mislabeled as AOV.
- **676 zero-monetary customers are retained** (orders with no line items; m_score = 1) rather than silently dropped by an inner join. An apparent NTILE scoring anomaly in diagnostic queries was investigated and attributed to `WHERE` executing before window functions, re-bucketing the filtered subset; the export queries contain no such filter and are unaffected.
- The model keeps the near-3NF relational shape from PostgreSQL rather than a star schema; see Next steps.

---

## Recommendations

Actions the findings support, in order of expected impact:

1. **Target stuck orders, not late ones.** ~2,800 orders sit at `shipped`/`invoiced`/`processing` with review scores of 1.28–2.00 — worse than late deliveries. An intervention pipeline for orders past their estimate without a delivery confirmation (carrier escalation, proactive customer contact) addresses the single largest satisfaction driver in the data.
2. **Flag sellers combining high income with low adherence.** The Entry #3 outlier pattern (0.28 adherence, 1.72 reviews at R$24.7K income) is detectable from existing data; a periodic adherence×review screen would surface such sellers for logistics support before review damage accumulates.
3. **Treat Norte/Nordeste as a supply problem, not an estimation problem.** Estimates are already buffered appropriately; transit time is the constraint. Seller recruitment or fulfillment partnerships closer to Norte would attack the 2x delivery-time gap directly, since only 5 sellers serve the region.
4. **Fix checkout order-splitting before setting retention targets.** ~9.2% of measured repeat customers are same-instant artifacts; retention KPIs computed on raw order counts overstate loyalty. Deduplicating same-instant orders (or fixing the split at the source) should precede any retention program.
5. **Address the R5/M5/F1 segment.** Recent, high-spend, one-time buyers are the largest actionable high-value group given the 96.88% single-order base — a distinct win-back audience from the small set of true repeat champions.

## Limitations

- `customer_state` is a registered state, not a verified shipping address; all geography is a proxy.
- `order_status` reflects the last recorded state, not necessarily the current one.
- The same-instant order-split mechanism is unexplained; no adjusted repeat rate was computed.
- Top repeat-rate categories rest on small samples (`home_appliances` n=688 vs. `bed_bath_table` n=8,872) — indicative, not precise.
- The June 2017 revenue dip is flagged but unexplained.
- RFM frequency tiers are judgment calls matched to the observed distribution, not derived from a formula.

## Reproducing the analysis

1. Start Virtual Environmenet & Install dependencies: 

   `python -m venv venv` Create venv

   Windows: `venv\Scripts\activate`

   Mac: `source venv/bin/activate`    Activate venv

   `pip install -r requirements.txt` install dependencies

2. Download the [dataset from Kaggle](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) into `data/`.
3. Create a PostgreSQL database named `olist` (connection string in `main.ipynb`).
4. Run `main.ipynb` end to end — it cleans the CSVs, builds the schema, loads the data, and verifies integrity.
5. Run the scripts in `sql/` against the database (note: `4_delivery_time.sql` creates the `state_region` reference table used by later queries).
6. Open `pbi/olist.pbix` and refresh against the exported query results.

## Next steps

- Restructure the Power BI model into a star schema (fact table at order-item grain, denormalized dimensions) to remove the ambiguous-filter-path workarounds in the current near-3NF model.
- Compute an artifact-adjusted repeat rate once the order-splitting mechanism is understood.
- Add confidence intervals (or bootstrap) to category-level repeat rates before ranking them.
- Test the June 2017 dip against Brazilian retail seasonality.
- Map RFM score combinations to named, actionable segments (champions, at-risk, win-back) with a defined business rule.

## Data source

[Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) (Kaggle, CC BY-NC-SA 4.0) — real, anonymized commercial data, 2016–2018.
