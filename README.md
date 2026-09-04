# Olist E-Commerce Analysis


![Overview page](/pbi/Overview.png)

End-to-end analysis of the [Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce): ~100K orders placed between 2016 and 2018 across 9 relational tables covering orders, items, payments, reviews, products, customers, sellers, and geolocation. The pipeline runs from raw CSVs through a constraint-enforced PostgreSQL database into seven SQL analyses, a four-page Power BI dashboard, a weekly revenue forecasting study, and a set of statistical checks that put confidence intervals and tests on the headline findings.

**Stack:** Python (pandas, SQLAlchemy, SciPy, statsmodels, XGBoost) · PostgreSQL · Power BI


## Executive summary

1. **Delivery completion, not speed, drives customer satisfaction.** On-time orders average a 4.29 review score (n=88,168); confirmed-but-late orders average 2.57 (n=7,662); orders that never reach a confirmed delivery — stuck at `shipped`, `invoiced`, `unavailable`, `processing` — average 1.28–2.00, below even the late deliveries.
2. **Revenue grew through 2017 and settled on a plateau in 2018**, totaling R$15.38M in delivered payment revenue over the analysis window. Weekly gross revenue rose from low volumes in early 2017 to a noisy plateau of roughly R$250–320K per week in 2018. The apparent late-2018 decline is the dataset's collection cutoff, not a business slowdown.
3. **Delivery time follows a strong regional gradient, and distance explains it.** Norte averages 22.6 days vs. Sudeste's 10.8. Computing the seller-to-customer distance of every order shows delivery time rising about 0.6 days per 100 km; once distance is held constant, Norte's gap to Sudeste shrinks from 11.9 days to 0.7 (not distinguishable from zero). Norte is slow because 92.5% of sellers are in Sudeste + Sul and Norte's orders travel a median 2,378 km, not because of a higher failure rate or a region-specific penalty. Sul and Centro-Oeste are the regions slower than their distance predicts (+1.5 and +1.1 days).
4. **Retention is minimal: 3.12% of 96,096 customers ever place a second order** (95% CI 3.01–3.23%), and ~9.2% of those "repeat" customers are same-instant checkout artifacts, putting the behavioral repeat rate between roughly 2.8% and 3.1%.
5. **Customer value is concentrated and skewed.** Order-level spend is approximately log-normal (peak ≈ R$50–300); purchase frequency is so skewed (96.88% single-order) that standard quintile scoring is invalid for it and required a distribution-based tier scheme instead.
6. **Weekly revenue is forecastable to about ±24%, and not much better than a 4-week average.** Fifteen forecasting models were compared on a rolling backtest; the best (ARIMA) forecasts about R$270K per week for the twelve weeks after the data ends, with an error of about 24% of the weekly level. The one event that matters most — Black Friday, worth about R$210K of extra revenue in 2017 — occurs once in the data and cannot be learned by any model; it has to be planned as a business scenario.

---

## Business context

Olist is a Brazilian marketplace integrator: it lets small merchants list and sell through major Brazilian e-commerce channels without registering on each one separately. The dataset is real, anonymized commercial data. The analysis addresses five operational questions a marketplace of this kind faces: what drives customer satisfaction, how revenue is developing, where fulfillment underperforms, which customers carry the value, and how far ahead revenue can be planned.

## Project structure

```
├── main.ipynb              # Cleaning + PostgreSQL database build (pandas, SQLAlchemy)
├── Olist-Analysis-Log.md   # Seven SQL analyses — question, query, finding, caveats
├── sql/                    # one file per analysis, numbered to match the log
│   ├── 1_reviews.sql       #   Delivery status vs. review scores
│   ├── 2_sales.sql         #   Order volume & revenue over time
│   ├── 3_seller.sql        #   Seller performance & category mix
│   ├── 4_delivery_time.sql #   Delivery time by geography
│   ├── 5_repeat_customer.sql #   Repeat-customer behavior
│   ├── 6_rfm.sql           #   RFM customer segmentation
│   └── 7_distance.sql      #   Seller-to-customer distance vs. delivery time (order_distance view)
├── stats/                  # Confidence intervals and tests on the headline findings
│   ├── statistical_checks.ipynb
│   ├── distance_vs_delivery.png
│   └── repeat_rate_by_category_ci.png
├── pbi/                    # Power BI dashboard + page exports
│   ├── olist.pbix
│   ├── Overview.png
│   ├── Delivery.png
│   ├── Seller.png
│   └── Customer.png
├── ml/                     # Weekly revenue forecasting
│   ├── weekly_sales.sql    #   Weekly gross revenue extraction (W-MON, delivered orders, 2017+)
│   ├── time_series.ipynb   #   Baselines → Holt-Winters → ARIMA → XGBoost / hybrid / ARIMAX, rolling backtest
│   └── forecast_arima_vs_ma4.png  # 12-week forecast with 95% interval
├── data/                   # raw Kaggle CSVs — not committed (see Reproduce)
├── schema.png              # Database entity-relationship diagram
├── requirements.txt        # Python dependencies for the three notebooks
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
   ├──────────────────────────────────────┐
   ▼                                      ▼
Seven SQL analyses                   Weekly revenue series (ml/weekly_sales.sql)
(Olist-Analysis-Log.md)                   │  statsmodels, XGBoost: rolling-origin backtest
   │                                      ▼
   ├─────────────────────┐          12-week forecast + model comparison (ml/time_series.ipynb)
   │  CSV exports         │  same queries, SciPy/statsmodels
   ▼                      ▼
Power BI (4 pages)     Confidence intervals, tests, distance regression
                       (stats/statistical_checks.ipynb)
```

---

## Data cleaning and database build (`main.ipynb`)

Each cleaning step follows the same procedure: audit, quantify the issue, decide with the trade-off recorded.

**Duplicates.** A full-row audit found 261,831 exact duplicates in `geolocation`. A key-level check on `order_reviews` found 814 duplicated `review_id`s and 551 duplicated `order_id`s; the data dictionary attributes repeated `review_id`s to platform bugs, so deduplication was keyed on `order_id` (one review per order). This choice is what later allows `order_reviews` to carry a primary key on `order_id`.

**Geolocation.** After exact deduplication, Unicode normalization (NFKD → ASCII) unified accented and unaccented spellings of the same city, exposing 17,837 further duplicates. 555 zip prefixes (~3%) still mapped to more than one city/state, which blocks using the zip prefix as a key. The table was aggregated to one row per zip prefix — mean lat/lng, modal city/state — and re-checked: zero conflicts remain (19,015 rows).

**Missing values.** Treatment depends on whether a NULL carries information:

- `order_reviews` title/message (88.3% / 58.7% missing) — expected behavior (most buyers rate without writing) — filled with explicit sentinels.
- `orders` delivery timestamps (0.16%–2.98% missing) — these NULLs mark orders that never completed a pipeline stage. They were left as NULL; the delivery-status vs. review-score analysis depends on this signal, and imputation would fabricate delivery events.
- `products` category (1.85%) — filled with `'Unknown'`; the affected products are referenced by real sales and cannot be dropped. Physical dimensions were left nullable rather than imputed.

**Types.** Datetime conversions use `errors='raise'` so parsing failures halt the pipeline rather than inserting silent `NaT`s; count-like columns use nullable `Int64`; two source-column typos (`lenght`) were renamed.

**Schema.** Tables were declared explicitly in SQLAlchemy rather than auto-created by `pandas.to_sql`: primary keys on all dimensions, composite keys where single columns are non-unique (`order_items`: `order_id`+`order_item_id`; `order_payments`: `order_id`+`payment_sequential`), and foreign keys on every relationship. The initial load raised a foreign-key violation: 162 zip prefixes referenced by `customers`/`sellers` were absent from the cleaned `geolocation` table. Of the three options — dropping the constraint, deleting the affected rows, or inserting placeholder geolocation rows — placeholders (`Unknown` city/state, NULL coordinates) preserve both referential integrity and the affected sales data; the cost is that 162 zips cannot be mapped by coordinate, which does not affect the analyses since geography is handled at state level. Final integrity checks confirm zero orphaned rows in all child tables.

---

## SQL analyses (`Olist-Analysis-Log.md`)

The log records, for each of the seven analyses, the business question, the query, the finding, and its caveats. In summary:

### 1. Delivery status vs. review scores

On-time orders average **4.29** (n=88,168); confirmed-but-late orders **2.57** (n=7,662); orders with no confirmed delivery timestamp (`shipped`, `canceled`, `invoiced`, `unavailable`, `processing`) average **1.28–2.00** — below the late-but-delivered group. A qualitative review of low-scoring `shipped`-status comments found ~85–90% are direct non-delivery complaints. Delivery completion is the dominant satisfaction driver; lateness is secondary.

### 2. Order volume and revenue over time

Late-2016 data is sparse launch-period activity (a 265-order burst, then a full-month gap), consistent with [Olist's company timeline](https://olist.com/sobre-nos/); the trend window was therefore restricted to 2017 onward. From 2017, growth is steady — monthly revenue does not fall below R$900K after January 2018 — with one unexplained single-month dip in June 2017. Total payment revenue on delivered orders in the window: **R$15,375,875.44**.

### 3. Seller performance and category mix

Seller income was measured from `order_items.price` (per-order payments would double-count multi-installment orders; freight is a pass-through cost). Top-income sellers cluster at 0.77–1.00 delivery adherence and 3.3–4.5 review scores. One outlier departs from this pattern: seller `b1b39487...` earns R$24,699 on 18 orders with 0.28 adherence and a 1.72 average review, specialized in a single category (`auto`). This is consistent with the review-score finding above: delivery failure, not product quality, accounts for most low scores. The category-revenue aggregation was cross-checked against seller income totals and reconciles exactly.

### 4. Delivery time by geography

| Region | Avg. delivery (95% CI) | Avg. estimated | Buffer | Orders |
|---|---|---|---|---|
| Sudeste | 10.8 ± 0.1 days | 21.6 days | 10.9 days | 66,187 |
| Sul | 14.0 ± 0.1 days | 26.4 days | 12.4 days | 13,812 |
| Centro-Oeste | 15.0 ± 0.2 days | 26.7 days | 11.6 days | 5,624 |
| Nordeste | 20.0 ± 0.3 days | 30.7 days | 10.7 days | 9,042 |
| Norte | 22.6 ± 0.6 days | 37.5 days | 14.9 days | 1,796 |

Breaking delivery into its steps (purchase→approval→carrier→customer) shows approval and dispatch times are stable across regions; the variation is almost entirely in carrier-to-customer transit. Two cross-checks address alternative explanations: order-incompletion rates do not track the gradient (Norte is second-lowest at 2.97%), and seller supply does — 92.5% of sellers are in Sudeste + Sul against 5 sellers in Norte; documented road-infrastructure gaps in the Amazon region ([ALG Global](https://www.alg-global.com/blog/logistics/transportation-and-logistics-challenges-northern-brazil)) were a candidate second cause, tested directly in the distance analysis below. Olist's delivery estimates exceed actuals in every region, with the largest buffer applied to Norte.

### 5. Repeat-customer analysis

Measured on `customer_unique_id` (`customer_id` is per-order in this dataset), 96.88% of 96,096 customers are one-time buyers; 3.12% placed a second order. First-purchase category correlates modestly with returning — `home_appliances` leads at 9.01% (95% CI 7.1–11.4%), separable from every other category; the fashion group follows at 5.8–6.5%; below the top four the ranking is within sampling noise (see Statistical checks). A data-quality finding qualifies the headline number: 9.21% of repeat customers show an exact 0-second gap between their first two orders — single checkout sessions split into multiple `order_id`s — so the behavioral repeat rate is below the raw 3.12%. The split mechanism was tested against a multi-seller-cart hypothesis, which one counterexample disproved; the mechanism remains unconfirmed.

### 6. RFM segmentation

Recency and Monetary are scored as `NTILE(5)` quintiles. Frequency cannot be: 96.88% of customers share the value 1, and quintiles over a tie of that size split it arbitrarily by row order. Frequency instead uses fixed tiers matched to the observed distribution (92,507 / 2,673 / 192 / 29 / 19 customers at freq 1 / 2 / 3 / 4 / ≥5). Two implementation details materially affect correctness: `LEFT JOIN order_items` (an inner join drops ~700 customers whose orders have no line items) and a `::numeric` cast on the price sum (float accumulation otherwise shows rounding residue). Scores are reported as three separate dimensions rather than a blended index, since a high-spend one-time buyer and a loyal repeat buyer would otherwise collapse into the same score despite requiring different actions.

### 7. Distance vs. delivery time

The haversine distance between the seller's and the customer's zip-prefix centroid was computed for 94,708 single-seller, fully-timestamped orders (multi-seller orders and 11 zip prefixes with off-map centroids excluded). Delivery time rises about 0.6 days per 100 km on a base of about 8.6 days; the late-delivery rate doubles from 6.4% under 100 km to 13.8% beyond 2,000 km. The regional ordering of delivery time is the regional ordering of distance — half of Sudeste's orders are fulfilled in-state, none of Norte's are, and Norte's median order travels 2,378 km. Regressing delivery days on distance and region (Sudeste as reference), Norte's 11.9-day raw gap falls to 0.7 days (95% CI −0.02 to 1.34) and Nordeste's 9.3 to 0.8; Sul (+1.5) and Centro-Oeste (+1.1) are the regions slower than their distance predicts. Distance and region together explain 16% of order-level variance: geography sets the regional averages, not whether an individual order is late.

---

## Statistical checks (`stats/statistical_checks.ipynb`)

The SQL analyses report point estimates. The notebook attaches 95% confidence intervals and tests to each headline number, using the log's exact definitions, and runs the distance regression above.

![Delivery time vs. seller-to-customer distance, and regional gaps before and after adjusting for distance](/stats/distance_vs_delivery.png)

| Finding | Estimate and 95% interval | Test |
|---|---|---|
| Review score by delivery outcome | On-time 4.29 ± 0.01 · late 2.57 ± 0.04 · never delivered 1.75 ± 0.05 | Kruskal–Wallis and pairwise Mann–Whitney, all p < 10⁻¹¹⁸ after Bonferroni; rank-biserial 0.27 (late vs. never delivered) to 0.77 (on-time vs. never delivered) |
| Repeat rate | 3.12% (3.01–3.23%); net of same-instant splits, at least 2.83% (2.73–2.94%) | Wilson intervals |
| Same-instant split share of repeat customers | 9.21% (8.23–10.30%) | Wilson interval |
| Repeat rate by first-purchase category | `home_appliances` 9.01% (7.1–11.4%); 18 of 52 categories differ from the pooled 3.10% | χ² = 396 on 51 df; `home_appliances` vs. rest z = 9.0, vs. `bed_bath_table` z = 5.3 |
| Regional delivery averages | Norte 22.6 ± 0.6 days; Sudeste 10.8 ± 0.06 | Interval widths are 10–200× smaller than the regional gaps |
| Distance vs. delivery time | 0.60 days per 100 km (0.58–0.61); Norte residual after distance 0.7 days (−0.02 to 1.34) | OLS with HC1 errors; Spearman ρ = 0.54; confirmed by median regression |

Two statements in the log are narrowed by the intervals: the claim that durable/tech categories repeat below 1.2% rests on two repeaters each and is not established, and the category ranking is meaningful only at the top four and bottom few. The infrastructure explanation for Norte's delivery time is not needed once distance is accounted for.

### Metric definitions

The project uses several revenue and rate definitions, each chosen for the question it answers. They are collected here so figures from different sections are not compared directly.

| Metric | Definition | Where used | Value |
|---|---|---|---|
| Payment revenue | `SUM(order_payments.payment_value)`, delivered orders, 2017 onward; freight included | Log: revenue over time | R$15.38M |
| Item revenue | `SUM(order_items.price)`, all orders; freight excluded | Power BI Overview, seller income, category mix | R$13.59M |
| Weekly gross revenue | `SUM(price + freight_value)` per purchase week (W-MON), delivered orders, 2017 onward | Forecasting series | ≈R$250–320K per week in 2018 |
| Average order value | Item revenue ÷ `DISTINCTCOUNT(order_id)` (98,666) | Power BI Overview | R$137.75 |
| Average item value | Item revenue ÷ item rows (112,650) | Not reported as AOV | R$120.65 |
| Delivery adherence | Share of a seller's orders delivered on or before `order_estimated_delivery_date` | Seller performance | 0.92 platform mean |
| Delivery days | `order_delivered_customer_date − order_purchase_timestamp`, orders with all four timestamps, fractional days | Geography, distance, statistical checks | 10.8 (Sudeste) to 22.6 (Norte) |
| Late delivery | `order_delivered_customer_date > order_estimated_delivery_date` | Review scores, distance bands | 8.0% of reviewed delivered orders |
| Repeat rate | Share of `customer_unique_id` with ≥ 2 orders (`customer_id` is per order) | Repeat customers, RFM, statistical checks | 3.12% |
| Distance | Haversine between seller and customer zip-prefix centroids, single-seller orders | Distance analysis | Median 434 km |
| RFM scores | R and M: `NTILE(5)`; F: fixed tiers at 1 / 2 / 3 / 4 / ≥5 orders | RFM segmentation, Power BI Customer | — |

---

## Power BI dashboard (`pbi/olist.pbix`)

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

- **Two revenue definitions coexist by design.** The dashboard's R$13.59M sums `order_items.price` (seller-attributable item revenue, freight excluded, all orders); the SQL analysis log's R$15.38M sums `payment_value` (amounts actually paid, freight included) on delivered orders from 2017. They answer different questions and are labeled accordingly.
- **AOV uses distinct orders as its denominator** (`DISTINCTCOUNT(order_id)` = 98,666), giving R$137.75. Dividing by item rows (112,650) would produce average item value (R$120.65) mislabeled as AOV.
- **676 zero-monetary customers are retained** (orders with no line items; m_score = 1) rather than silently dropped by an inner join. An apparent NTILE scoring anomaly in diagnostic queries was investigated and attributed to `WHERE` executing before window functions, re-bucketing the filtered subset; the export queries contain no such filter and are unaffected.
- The model keeps the near-3NF relational shape from PostgreSQL rather than a star schema; see Next steps.

---

## Weekly revenue forecasting (`ml/time_series.ipynb`)

The question here was operational: how far ahead, and how precisely, can Olist plan platform revenue? Weekly gross revenue (item price plus freight, delivered orders, assigned to the purchase week) was extracted for the 85 weeks from January 2017 to mid-August 2018 and forecast twelve weeks ahead. Every model was judged the same way: repeatedly fit on the past, forecast the next twelve weeks, and score against what actually happened, across ten forecast origins. Technical detail — order selection, diagnostics, feature construction, the assumptions audit — is in the notebook; this section covers what the results mean.

![12-week forecast: ARIMA(1,1,1) with 95% interval vs. 4-week moving average](/ml/forecast_arima_vs_ma4.png)

### What was tested and what it found

| Approach | What it assumes about revenue | Result (avg. error over 12 weeks) | Business reading |
|---|---|---|---|
| Naive (repeat last week) | Next week looks like this week | R$55.9K | The floor: any useful model must beat this |
| 4-week moving average | Next week looks like the recent average | R$44.6K | Almost as good as the best model; a spreadsheet can do it |
| Seasonal naive (same week last year) | Revenue repeats an annual pattern | R$123.7K | Worst of all: last year's level is far below this year's, so annual patterns are useless while the platform is growing |
| Holt-Winters (trend smoothing) | A trend that can be extrapolated | R$49.6K–63.4K | Extrapolating the 2017 growth trend overshoots the 2018 plateau |
| **ARIMA(1,1,1) — model of record** | A slowly moving level plus short-lived shocks | **R$43.5K** | Best overall and steadiest across the horizon; forecasts a flat level |
| XGBoost on lagged features | Patterns in recent weeks and the calendar | R$45.6K | Best one-week-ahead model (R$24.5K), but needs more history than 85 weeks to hold that advantage further out |
| ARIMA + XGBoost hybrid, ARIMAX with Black Friday flag | ARIMA plus a learned or explicit event effect | R$56.0K–56.2K | No better than the naive floor: one Black Friday in the data is measurable but not learnable |

### What the results mean for Olist

1. **Planning baseline.** The operational forecast is about R$270K per week for 2018-08-20 to 2018-11-05, roughly R$3.2M for the quarter, with a 95% range of about ±R$90K in the first week widening to ±R$150K by the twelfth. The quarter should be planned as a range, not a point; the main uses are cash planning for seller payouts (which follow purchases by the delivery lag, 11 to 23 days depending on region) and variable marketing budgets.
2. **Platform revenue behaves like a random walk around a slow-moving level.** The best model's error is about 24% of the weekly level and a 4-week average is within 2.5% of it. Recent weeks are the best predictor; more sophisticated models do not help at this aggregation. Olist does not need a complex forecasting stack for the weekly total; the value is in the quantified uncertainty and in knowing what the data cannot support yet.
3. **This is what a 3% repeat rate looks like in a revenue series.** With 96.88% of customers buying once, weekly revenue is essentially a flow of first-time purchases with almost no recurring base underneath it. A recurring base is what makes a revenue series smooth and forecastable; its absence is consistent with the noisy, level-following behaviour observed here. Improving retention would improve forecastability as a side effect, and the 2018 plateau in weekly revenue is, on this reading, a plateau in new-customer acquisition.
4. **Black Friday must be planned by hand.** The forecast horizon ends two weeks before Black Friday 2018. The only quantitative estimate is the 2017 uplift of about R$210K (roughly 1.8x the surrounding weeks), from a single observation. Logistics capacity, seller inventory guidance and customer-service staffing for that week should be set from this figure scaled to the current level, with the caveat recorded. Since undelivered orders produce the lowest review scores in the data, a Black Friday week that overwhelms fulfillment would convert directly into the platform's worst satisfaction outcome.
5. **Set tolerances in percentages, not reais.** Forecast error grew with revenue over the sample. A fixed R$ tolerance calibrated in 2017 would be breached routinely at 2018 volumes.
6. **The reporting definition matters.** Revenue filtered on `delivered` status under-counts the latest weeks by the delivery lag, which averages 11 days in Sudeste and 23 in Norte. Every fresh forecast run on that definition is anchored on artificially low recent observations. For operational use, revenue should be attributed to the purchase week across all non-cancelled statuses, or the delivered series refreshed after the lag has closed.
7. **Where forecasting would pay is one level down.** The weekly total is too aggregated and too short to reward modelling, but seller onboarding, category promotion and regional logistics decisions are made per product category and per state. The same database yields dozens of such weekly series; a single model trained across all of them has the history the aggregate lacks and produces forecasts that map to decisions. This is the forecasting extension with a plausible return.

---

## Recommendations

Actions the findings support, in order of expected impact:

1. **Target stuck orders, not late ones.** ~2,800 orders sit at `shipped`/`invoiced`/`processing` with review scores of 1.28–2.00 — worse than late deliveries. An intervention pipeline for orders past their estimate without a delivery confirmation (carrier escalation, proactive customer contact) addresses the single largest satisfaction driver in the data.
2. **Flag sellers combining high income with low adherence.** The seller outlier pattern found above (0.28 adherence, 1.72 reviews at R$24.7K income) is detectable from existing data; a periodic adherence×review screen would surface such sellers for logistics support before review damage accumulates.
3. **Treat Norte/Nordeste as a supply problem, not an estimation or infrastructure problem.** Estimates are already buffered; the distance regression shows Norte's delivery time is fully accounted for by how far its orders travel, at the same per-kilometre rate as the rest of the country. Seller recruitment or fulfillment partnerships closer to Norte would attack the 2x delivery-time gap directly, since only 5 sellers serve the region. Sul and Centro-Oeste, which are slower than their distance predicts, are where a carrier-level investigation would be more informative than a supply one.
4. **Fix checkout order-splitting before setting retention targets.** ~9.2% of measured repeat customers are same-instant artifacts; retention KPIs computed on raw order counts overstate loyalty. Deduplicating same-instant orders (or fixing the split at the source) should precede any retention program.
5. **Address the R5/M5/F1 segment.** Recent, high-spend, one-time buyers are the largest actionable high-value group given the 96.88% single-order base — a distinct win-back audience from the small set of true repeat champions. The forecasting results add a second reason to pursue retention: a recurring customer base would also make platform revenue smoother and more forecastable.
6. **Plan the next quarter as a range, and Black Friday as a separate capacity event.** Use the ~R$270K/week baseline with its ±R$90–150K band for cash and marketing planning, with tolerances set in percentage terms rather than reais. Plan the Black Friday week outside the forecast, using the 2017 uplift (~R$210K, ~1.8x a normal week) scaled to current volume as the scenario for fulfillment capacity, seller stock and support staffing. For both, report operational revenue by purchase week across all non-cancelled statuses so the most recent weeks are not systematically under-stated.

## Limitations

- `customer_state` is a registered state, not a verified shipping address; all geography is a proxy.
- `order_status` reflects the last recorded state, not necessarily the current one.
- The same-instant order-split mechanism is unexplained; the adjusted repeat rate (2.83%) is a lower bound that removes only zero-second splits.
- Category repeat rates carry wide intervals below the top four categories; the bottom of the ranking (2 repeaters per category) is not established.
- Distances are between zip-prefix centroids, straight-line, and exclude multi-seller orders (1.3%). Any road-infrastructure effect is absorbed into the per-kilometre rate rather than appearing as a regional residual.
- The June 2017 revenue dip is flagged but unexplained.
- RFM frequency tiers are judgment calls matched to the observed distribution, not derived from a formula.
- The forecasting series is short (85 weeks, fewer than two annual cycles) with a single calendar event. Seasonality could be checked but not estimated; the Black Friday effect could be measured but not validated out-of-sample. Differences of a few percent between the leading models are not statistically distinguishable.
- Forecast intervals assume symmetric, constant-variance errors; the actual errors are right-skewed and grow with revenue, so the intervals are indicative and understate upside risk in event weeks.
- The forecasting series inherits the `delivered` status filter, so its final weeks are under-counted by the delivery lag.

## Reproducing the analysis

1. Create a virtual environment and install dependencies:

   `python -m venv venv`

   Windows: `venv\Scripts\activate`

   Mac: `source venv/bin/activate`

   `pip install -r requirements.txt`

2. Download the [dataset from Kaggle](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) into `data/`.
3. Create a PostgreSQL database named `olist` (connection string in `main.ipynb`).
4. Run `main.ipynb` end to end — it cleans the CSVs, builds the schema, loads the data, and verifies integrity.
5. Run the scripts in `sql/` against the database (note: `4_delivery_time.sql` creates the `state_region` reference table used by later queries, and `7_distance.sql` creates the `order_distance` view used by the statistical checks).
6. Open `pbi/olist.pbix` and refresh against the exported query results.
7. Run `ml/time_series.ipynb` end to end — it extracts the weekly series with `ml/weekly_sales.sql`, runs the backtest, and regenerates `ml/forecast_arima_vs_ma4.png`.
8. Run `stats/statistical_checks.ipynb` end to end — it reads from the database and regenerates the two figures in `stats/`.

## Next steps

- Restructure the Power BI model into a star schema (fact table at order-item grain, denormalized dimensions) to remove the ambiguous-filter-path workarounds in the current near-3NF model.
- Compute an artifact-adjusted repeat rate once the order-splitting mechanism is understood (the current 2.83% is a lower bound that removes only zero-second splits).
- Map RFM score combinations to named, actionable segments (champions, at-risk, win-back) with a defined business rule.
- Forecast at category and state level with one model trained across all series (the M5-competition approach), and compare its bottom-up total against the ARIMA aggregate forecast on the same backtest. This connects the forecasting work to the seller/category and regional-delivery analyses, and is the extension whose expected benefit the current results support.

## Data source

[Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) (Kaggle, CC BY-NC-SA 4.0) — real, anonymized commercial data, 2016–2018.
