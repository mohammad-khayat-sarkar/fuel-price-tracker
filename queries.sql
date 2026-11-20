-- queries.sql
-- Analysis queries for the fuel price database (SQLite).

-- 1. Filter and sort: weekly Midwest diesel prices since 2024.
SELECT week_date, region, price
FROM retail_prices
WHERE product = 'diesel' AND region = 'Midwest' AND week_date >= '2024-01-01'
ORDER BY week_date;

-- 2. Aggregate: average diesel price by region and year.
SELECT region,
       strftime('%Y', week_date) AS year,
       ROUND(AVG(price), 3) AS avg_price
FROM retail_prices
WHERE product = 'diesel'
GROUP BY region, year
ORDER BY region, year;

-- 3. Join: each retail diesel price next to its benchmark spot price, and the spread.
SELECT r.week_date, r.region,
       r.price AS retail_price,
       s.price AS spot_price,
       ROUND(r.price - s.price, 3) AS spread
FROM retail_prices AS r
JOIN regions AS g
  ON g.region = r.region
JOIN spot_prices AS s
  ON s.hub = g.benchmark_hub
 AND s.product = r.product
 AND s.week_date = date(r.week_date, '-3 days')
WHERE r.product = 'diesel'
ORDER BY r.week_date DESC, r.region;

-- 4. Window function: week-over-week change in the diesel price by region.
SELECT week_date, region, price,
       ROUND(price - LAG(price) OVER (PARTITION BY region, product
                                      ORDER BY week_date), 3) AS wow_change
FROM retail_prices
WHERE product = 'diesel'
ORDER BY week_date DESC, region;

-- 5. CTE and ranking: regions ranked by diesel price in the latest week.
WITH latest AS (
  SELECT MAX(week_date) AS week_date FROM retail_prices
)
SELECT r.region, r.price,
       RANK() OVER (ORDER BY r.price DESC) AS price_rank
FROM retail_prices AS r
JOIN latest AS l ON l.week_date = r.week_date
WHERE r.product = 'diesel';

-- 6. The views that feed the dashboard are defined in views.sql.
SELECT * FROM v_dashboard WHERE is_latest_week = 1;
