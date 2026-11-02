/* Wealth Management Portfolio Analysis (MySQL)
   Client #128, two accounts, 27 securities, data as of 2022-09-09
   Author: Michel Ward, Hult International Business School */

/* Step 1: Confirm the client and list the accounts */
SELECT customer_id, first_name, last_name, customer_location
FROM invest.customer_details
WHERE customer_id = 128;

SELECT account_id, client_id, main_account, opt38_desc, acct_open_date, acct_open_status
FROM invest.account_dim
WHERE client_id = 128;

/* Step 2: Client view with adjusted prices for every holding (joins 5 tables) */
CREATE VIEW invest.michel_ward AS
SELECT DISTINCT s.major_asset_class, s.minor_asset_class,
       s.ticker, s.security_name, s.sec_type,
       p.date AS price_date, p.value AS price, p.price_type
FROM invest.customer_details c
LEFT JOIN invest.account_dim a ON c.customer_id = a.client_id
LEFT JOIN invest.holdings_current h ON a.account_id = h.account_id
LEFT JOIN invest.security_masterlist s ON h.ticker = s.ticker
LEFT JOIN invest.pricing_daily_new p ON s.ticker = p.ticker
WHERE c.customer_id = 128
  AND p.price_type = 'Adjusted'
  AND p.value IS NOT NULL
  AND p.value > 0;

/* Q1a: Return per security and market value (change INTERVAL to 12, 24 or 36) */
SELECT e.ticker, e.major_asset_class, e.minor_asset_class,
       s.price AS p0, e.price AS p1,
       (e.price - s.price) / s.price AS ROR,
       w.mv
FROM invest.michel_ward e
LEFT JOIN invest.michel_ward s
  ON e.ticker = s.ticker
 AND s.price_date = DATE_SUB('2022-09-09', INTERVAL 12 MONTH)
LEFT JOIN (
  SELECT h.ticker, SUM(h.quantity * h.value) AS mv
  FROM invest.customer_details c
  LEFT JOIN invest.account_dim a ON c.customer_id = a.client_id
  LEFT JOIN invest.holdings_current h ON a.account_id = h.account_id
  WHERE c.customer_id = 128
  GROUP BY h.ticker
) w ON e.ticker = w.ticker
WHERE e.price_date = '2022-09-09'
ORDER BY ROR DESC;

/* Q1b: Market value weighted portfolio return and share of the portfolio covered */
SELECT SUM(r.ROR * w.mv) / SUM(w.mv) AS portfolio_ROR,
       SUM(w.mv) / (SELECT SUM(h2.quantity * h2.value)
                    FROM invest.account_dim a2
                    JOIN invest.holdings_current h2 ON a2.account_id = h2.account_id
                    WHERE a2.client_id = 128) AS share_covered
FROM (
  SELECT e.ticker, (e.price - s.price) / s.price AS ROR
  FROM invest.michel_ward e
  JOIN invest.michel_ward s
    ON e.ticker = s.ticker
   AND s.price_date = DATE_SUB('2022-09-09', INTERVAL 12 MONTH)
  WHERE e.price_date = '2022-09-09'
) r
JOIN (
  SELECT h.ticker, SUM(h.quantity * h.value) AS mv
  FROM invest.customer_details c
  LEFT JOIN invest.account_dim a ON c.customer_id = a.client_id
  LEFT JOIN invest.holdings_current h ON a.account_id = h.account_id
  WHERE c.customer_id = 128
  GROUP BY h.ticker
) w ON r.ticker = w.ticker;

/* Q2 and Q4: Average daily return (mu), risk (sigma) and risk adjusted return per security, last 12 months */
SELECT o.ticker, o.major_asset_class,
       AVG(o.ROR) AS mu,
       STD(o.ROR) AS sigma,
       AVG(o.ROR) / STD(o.ROR) AS risk_adj,
       COUNT(o.ROR) AS n_days
FROM (
  SELECT z.ticker, z.major_asset_class, (z.p1 - z.p0) / z.p0 AS ROR
  FROM (
    SELECT ticker, major_asset_class, price_date, price AS p1,
           LAG(price, 1) OVER (PARTITION BY ticker ORDER BY price_date) AS p0
    FROM invest.michel_ward
    WHERE price_date >= DATE_SUB('2022-09-09', INTERVAL 12 MONTH)
  ) z
) o
WHERE o.ROR IS NOT NULL
GROUP BY o.ticker, o.major_asset_class
ORDER BY risk_adj DESC;

/* Q3a: Screen fixed income candidates and their price history */
SELECT s.ticker, s.security_name, s.major_asset_class, s.minor_asset_class,
       COUNT(p.value) AS n_days, MIN(p.date) AS first_date, MAX(p.date) AS last_date
FROM invest.security_masterlist s
LEFT JOIN invest.pricing_daily_new p
  ON s.ticker = p.ticker
 AND p.price_type = 'Adjusted'
 AND p.value IS NOT NULL
WHERE s.major_asset_class LIKE 'fixed%'
GROUP BY s.ticker, s.security_name, s.major_asset_class, s.minor_asset_class
ORDER BY s.major_asset_class, s.ticker;

/* Q3b: Compare the shortlisted funds (mu and sigma, last 12 months) */
SELECT o.ticker, AVG(o.ROR) AS mu, STD(o.ROR) AS sigma, COUNT(o.ROR) AS n_days
FROM (
  SELECT z.ticker, (z.p1 - z.p0) / z.p0 AS ROR
  FROM (
    SELECT ticker, date, value AS p1,
           LAG(value, 1) OVER (PARTITION BY ticker ORDER BY date) AS p0
    FROM invest.pricing_daily_new
    WHERE price_type = 'Adjusted'
      AND ticker IN ('VTIP', 'IGSB', 'VCSH', 'SHY', 'TIP', 'AGG')
      AND date >= DATE_SUB('2022-09-09', INTERVAL 12 MONTH)
  ) z
) o
WHERE o.ROR IS NOT NULL
GROUP BY o.ticker
ORDER BY sigma;

/* Q3c: Portfolio mu and sigma BEFORE the change */
SELECT AVG(pd.port_ROR) AS mu, STD(pd.port_ROR) AS sigma, COUNT(*) AS n_days
FROM (
  SELECT d.price_date, SUM(d.ROR * w.mv) / SUM(w.mv) AS port_ROR
  FROM (
    SELECT z.ticker, z.price_date, (z.p1 - z.p0) / z.p0 AS ROR
    FROM (
      SELECT ticker, price_date, price AS p1,
             LAG(price, 1) OVER (PARTITION BY ticker ORDER BY price_date) AS p0
      FROM invest.michel_ward
      WHERE price_date >= DATE_SUB('2022-09-09', INTERVAL 12 MONTH)
    ) z
    WHERE z.p0 IS NOT NULL
  ) d
  JOIN (
    SELECT h.ticker, SUM(h.quantity * h.value) AS mv
    FROM invest.account_dim a
    JOIN invest.holdings_current h ON a.account_id = h.account_id
    WHERE a.client_id = 128
    GROUP BY h.ticker
  ) w ON d.ticker = w.ticker
  GROUP BY d.price_date
) pd;

/* Q3d: Portfolio mu and sigma AFTER moving $122,578 (10%) from ROK into VTIP */
SELECT AVG(pd.port_ROR) AS mu, STD(pd.port_ROR) AS sigma, COUNT(*) AS n_days
FROM (
  SELECT d.price_date, SUM(d.ROR * w.mv) / SUM(w.mv) AS port_ROR
  FROM (
    SELECT z.ticker, z.price_date, (z.p1 - z.p0) / z.p0 AS ROR
    FROM (
      SELECT ticker, price_date, price AS p1,
             LAG(price, 1) OVER (PARTITION BY ticker ORDER BY price_date) AS p0
      FROM invest.michel_ward
      WHERE price_date >= DATE_SUB('2022-09-09', INTERVAL 12 MONTH)
      UNION ALL
      SELECT ticker, date, value AS p1,
             LAG(value, 1) OVER (PARTITION BY ticker ORDER BY date) AS p0
      FROM invest.pricing_daily_new
      WHERE price_type = 'Adjusted'
        AND ticker = 'VTIP'
        AND date >= DATE_SUB('2022-09-09', INTERVAL 12 MONTH)
    ) z
    WHERE z.p0 IS NOT NULL
  ) d
  JOIN (
    SELECT h.ticker,
           SUM(h.quantity * h.value) - CASE WHEN h.ticker = 'ROK' THEN 122578 ELSE 0 END AS mv
    FROM invest.account_dim a
    JOIN invest.holdings_current h ON a.account_id = h.account_id
    WHERE a.client_id = 128
    GROUP BY h.ticker
    UNION ALL
    SELECT 'VTIP', 122578
  ) w ON d.ticker = w.ticker
  GROUP BY d.price_date
) pd;
