-- views.sql
-- The three views behind the dashboard. Safe to run more than once.

DROP VIEW IF EXISTS v_dashboard;
DROP VIEW IF EXISTS v_weekly_change;
DROP VIEW IF EXISTS v_spread;

-- Retail price next to its benchmark spot price, and the difference.
-- Retail prices are dated Mondays and weekly spot averages end on Fridays,
-- so each retail price is matched to the spot price dated three days earlier.
CREATE VIEW v_spread AS
SELECT r.week_date, r.region, r.product,
       r.price AS retail_price,
       s.price AS spot_price,
       ROUND(r.price - s.price, 3) AS spread
FROM retail_prices AS r
JOIN regions AS g
  ON g.region = r.region
JOIN spot_prices AS s
  ON s.hub = g.benchmark_hub
 AND s.product = r.product
 AND s.week_date = date(r.week_date, '-3 days');

-- Week-over-week change in the retail price, for every region and product.
CREATE VIEW v_weekly_change AS
SELECT week_date, region, product, price,
       ROUND(price - LAG(price) OVER (PARTITION BY region, product
                                      ORDER BY week_date), 3) AS wow_change
FROM retail_prices;

-- One flat table for Power BI: the six main regions, with price, weekly change,
-- and spread. LEFT JOIN keeps regions and weeks that have no spot benchmark.
CREATE VIEW v_dashboard AS
SELECT c.week_date, c.region, c.product,
       c.price AS retail_price,
       c.wow_change,
       s.spot_price,
       s.spread,
       CASE WHEN c.week_date = (SELECT MAX(week_date) FROM retail_prices)
            THEN 1 ELSE 0 END AS is_latest_week
FROM v_weekly_change AS c
LEFT JOIN v_spread AS s
  ON s.week_date = c.week_date
 AND s.region = c.region
 AND s.product = c.product
WHERE c.region IN ('U.S.', 'East Coast', 'Midwest', 'Gulf Coast',
                   'Rocky Mountain', 'West Coast');
