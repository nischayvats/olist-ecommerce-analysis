/* =====================================================================
   Olist E-Commerce Business Analysis
   Author : Nischay Vats  (github.com/nischayvats)
   Engine : MySQL 8.0+ (also runs on MariaDB 10.6+)
   Data   : Olist Brazilian E-Commerce public dataset (Kaggle), 99,441 orders

   Tables (one per CSV):
     customers            olist_customers_dataset.csv
     orders               olist_orders_dataset.csv
     order_items          olist_order_items_dataset.csv
     order_payments       olist_order_payments_dataset.csv
     order_reviews        olist_order_reviews_dataset.csv
     products             olist_products_dataset.csv
     sellers              olist_sellers_dataset.csv
     category_translation product_category_name_translation.csv

   Conventions used throughout:
     - Business metrics use delivered orders only (order_status = 'delivered').
     - Revenue = total payment_value of the order.
     - A customer is a customer_unique_id (customer_id changes per order).
     - Late = delivered after order_estimated_delivery_date.
     - Delivery days = time from purchase to delivery, in days.

   Sections
     A. Overview           Q1-Q2
     B. Growth             Q3-Q4
     C. Retention          Q5
     D. Delivery & reviews Q6-Q9
     E. Regions            Q10-Q11
     F. Categories         Q12-Q13
     G. Payments           Q14-Q15
     H. Customer value     Q16-Q19
     I. Sellers            Q20
   ===================================================================== */


/* =====================================================================
   A. OVERVIEW
   ===================================================================== */

-- Q1. Order status breakdown: how many orders reach the customer?
SELECT
    order_status,
    COUNT(*)                                            AS orders,
    ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)    AS pct_of_orders
FROM orders
GROUP BY order_status
ORDER BY orders DESC;


-- Q2. Headline KPIs for delivered orders
WITH order_revenue AS (
    SELECT order_id, SUM(payment_value) AS revenue
    FROM order_payments
    GROUP BY order_id
)
SELECT
    COUNT(*)                               AS delivered_orders,
    COUNT(DISTINCT c.customer_unique_id)   AS customers,
    ROUND(SUM(r.revenue), 2)               AS revenue,
    ROUND(AVG(r.revenue), 2)               AS avg_order_value
FROM orders o
JOIN customers c          ON c.customer_id = o.customer_id
LEFT JOIN order_revenue r ON r.order_id = o.order_id
WHERE o.order_status = 'delivered';


/* =====================================================================
   B. GROWTH
   ===================================================================== */

-- Q3. Monthly orders and revenue with month-over-month growth (LAG)
WITH order_revenue AS (
    SELECT order_id, SUM(payment_value) AS revenue
    FROM order_payments
    GROUP BY order_id
),
monthly AS (
    SELECT
        DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS month,
        COUNT(*)                                         AS orders,
        SUM(r.revenue)                                   AS revenue
    FROM orders o
    LEFT JOIN order_revenue r ON r.order_id = o.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01'
    GROUP BY DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m')
)
SELECT
    month,
    orders,
    ROUND(revenue, 0)                                                        AS revenue,
    ROUND(100 * (orders - LAG(orders) OVER (ORDER BY month))
              / LAG(orders) OVER (ORDER BY month), 1)                         AS orders_mom_pct
FROM monthly
ORDER BY month;


-- Q4. Cumulative revenue by month (running SUM) and share of all revenue
WITH order_revenue AS (
    SELECT order_id, SUM(payment_value) AS revenue
    FROM order_payments
    GROUP BY order_id
),
monthly AS (
    SELECT
        DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS month,
        SUM(r.revenue)                                   AS revenue
    FROM orders o
    JOIN order_revenue r ON r.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m')
)
SELECT
    month,
    ROUND(revenue, 0)                                                   AS revenue,
    ROUND(SUM(revenue) OVER (ORDER BY month), 0)                        AS cumulative_revenue,
    ROUND(100 * SUM(revenue) OVER (ORDER BY month) / SUM(revenue) OVER (), 1) AS cumulative_pct
FROM monthly
ORDER BY month;


/* =====================================================================
   C. RETENTION
   ===================================================================== */

-- Q5. One-time vs repeat customers
WITH customer_orders AS (
    SELECT c.customer_unique_id, COUNT(DISTINCT o.order_id) AS orders
    FROM orders o
    JOIN customers c ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
)
SELECT
    CASE WHEN orders = 1 THEN 'One-time' ELSE 'Repeat (2+ orders)' END AS customer_type,
    COUNT(*)                                                           AS customers,
    ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)                   AS pct_of_customers
FROM customer_orders
GROUP BY CASE WHEN orders = 1 THEN 'One-time' ELSE 'Repeat (2+ orders)' END;


/* =====================================================================
   D. DELIVERY & REVIEWS
   ===================================================================== */

-- Q6. Average delivery time and late-delivery rate
SELECT
    COUNT(*)                                                             AS delivered_orders,
    ROUND(AVG(TIMESTAMPDIFF(SECOND, order_purchase_timestamp,
                            order_delivered_customer_date) / 86400), 1)  AS avg_delivery_days,
    ROUND(100 * AVG(order_delivered_customer_date > order_estimated_delivery_date), 1) AS late_pct
FROM orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL;


-- Q7. Review score for late vs on-time orders
WITH order_score AS (
    SELECT order_id, AVG(review_score) AS score
    FROM order_reviews
    GROUP BY order_id
)
SELECT
    CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
         THEN 'Late' ELSE 'On time' END                      AS delivery,
    COUNT(*)                                                 AS orders,
    ROUND(AVG(s.score), 2)                                   AS avg_review,
    ROUND(100 * AVG(s.score <= 2), 1)                        AS pct_rated_1_2_stars
FROM orders o
JOIN order_score s ON s.order_id = o.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
              THEN 'Late' ELSE 'On time' END;


-- Q8. Review score by delivery-time bucket: where do ratings break?
WITH order_score AS (
    SELECT order_id, AVG(review_score) AS score
    FROM order_reviews
    GROUP BY order_id
),
deliveries AS (
    SELECT
        o.order_id,
        TIMESTAMPDIFF(SECOND, o.order_purchase_timestamp, o.order_delivered_customer_date) / 86400 AS days
    FROM orders o
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
)
SELECT
    CASE
        WHEN d.days <= 7  THEN '1. 0-7 days'
        WHEN d.days <= 14 THEN '2. 8-14 days'
        WHEN d.days <= 21 THEN '3. 15-21 days'
        WHEN d.days <= 30 THEN '4. 22-30 days'
        WHEN d.days <= 45 THEN '5. 31-45 days'
        ELSE                   '6. 45+ days'
    END                                  AS delivery_bucket,
    COUNT(*)                             AS orders,
    ROUND(AVG(s.score), 2)               AS avg_review,
    ROUND(100 * AVG(s.score <= 2), 1)    AS pct_rated_1_2_stars
FROM deliveries d
JOIN order_score s ON s.order_id = d.order_id
GROUP BY delivery_bucket
ORDER BY delivery_bucket;


-- Q9. Average delivery days for each review score
WITH order_score AS (
    SELECT order_id, ROUND(AVG(review_score)) AS score
    FROM order_reviews
    GROUP BY order_id
)
SELECT
    s.score                                                              AS review_score,
    COUNT(*)                                                             AS orders,
    ROUND(AVG(TIMESTAMPDIFF(SECOND, o.order_purchase_timestamp,
                            o.order_delivered_customer_date) / 86400), 1) AS avg_delivery_days
FROM orders o
JOIN order_score s ON s.order_id = o.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY s.score
ORDER BY s.score;


/* =====================================================================
   E. REGIONS
   ===================================================================== */

-- Q10. State scorecard: share of orders, delivery time, late rate, review
WITH order_score AS (
    SELECT order_id, AVG(review_score) AS score
    FROM order_reviews
    GROUP BY order_id
)
SELECT
    c.customer_state                                                       AS state,
    COUNT(*)                                                               AS orders,
    ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)                       AS pct_of_orders,
    ROUND(AVG(TIMESTAMPDIFF(SECOND, o.order_purchase_timestamp,
                            o.order_delivered_customer_date) / 86400), 1)  AS avg_delivery_days,
    ROUND(100 * AVG(o.order_delivered_customer_date > o.order_estimated_delivery_date), 1) AS late_pct,
    ROUND(AVG(s.score), 2)                                                 AS avg_review
FROM orders o
JOIN customers c        ON c.customer_id = o.customer_id
LEFT JOIN order_score s ON s.order_id = o.order_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_state
ORDER BY orders DESC;


-- Q11. Rank the 10 largest states by late-delivery rate (DENSE_RANK)
WITH state_stats AS (
    SELECT
        c.customer_state AS state,
        COUNT(*)         AS orders,
        AVG(o.order_delivered_customer_date > o.order_estimated_delivery_date) AS late_rate
    FROM orders o
    JOIN customers c ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
    GROUP BY c.customer_state
),
top10 AS (
    SELECT *, ROW_NUMBER() OVER (ORDER BY orders DESC) AS size_rank
    FROM state_stats
)
SELECT
    state,
    orders,
    ROUND(100 * late_rate, 1)                         AS late_pct,
    DENSE_RANK() OVER (ORDER BY late_rate DESC)       AS late_rank
FROM top10
WHERE size_rank <= 10
ORDER BY late_rank;


/* =====================================================================
   F. CATEGORIES
   ===================================================================== */

-- Q12. Top 10 categories by item revenue (price excluding freight)
SELECT
    COALESCE(t.product_category_name_english, p.product_category_name, 'unknown') AS category,
    COUNT(*)                                                    AS items_sold,
    ROUND(SUM(oi.price), 0)                                     AS item_revenue,
    ROUND(100 * SUM(oi.price) / SUM(SUM(oi.price)) OVER (), 1)  AS pct_of_item_revenue
FROM order_items oi
JOIN orders o                    ON o.order_id = oi.order_id
LEFT JOIN products p             ON p.product_id = oi.product_id
LEFT JOIN category_translation t ON t.product_category_name = p.product_category_name
WHERE o.order_status = 'delivered'
GROUP BY COALESCE(t.product_category_name_english, p.product_category_name, 'unknown')
ORDER BY item_revenue DESC
LIMIT 10;


-- Q13. Lowest-rated categories with real volume (500+ orders), ranked
WITH order_score AS (
    SELECT order_id, AVG(review_score) AS score
    FROM order_reviews
    GROUP BY order_id
),
category_scores AS (
    SELECT
        COALESCE(t.product_category_name_english, p.product_category_name, 'unknown') AS category,
        COUNT(DISTINCT oi.order_id) AS orders,
        AVG(s.score)                AS avg_review
    FROM order_items oi
    JOIN orders o                    ON o.order_id = oi.order_id
    JOIN order_score s               ON s.order_id = oi.order_id
    LEFT JOIN products p             ON p.product_id = oi.product_id
    LEFT JOIN category_translation t ON t.product_category_name = p.product_category_name
    WHERE o.order_status = 'delivered'
    GROUP BY COALESCE(t.product_category_name_english, p.product_category_name, 'unknown')
    HAVING COUNT(DISTINCT oi.order_id) >= 500
)
SELECT
    category,
    orders,
    ROUND(avg_review, 2)                          AS avg_review,
    RANK() OVER (ORDER BY avg_review ASC)         AS worst_rank
FROM category_scores
ORDER BY worst_rank
LIMIT 10;


/* =====================================================================
   G. PAYMENTS
   ===================================================================== */

-- Q14. Payment value by method
SELECT
    p.payment_type,
    COUNT(DISTINCT p.order_id)                                       AS orders,
    ROUND(SUM(p.payment_value), 0)                                   AS payment_value,
    ROUND(100 * SUM(p.payment_value) / SUM(SUM(p.payment_value)) OVER (), 1) AS pct_of_value
FROM order_payments p
JOIN orders o ON o.order_id = p.order_id
WHERE o.order_status = 'delivered'
GROUP BY p.payment_type
ORDER BY payment_value DESC;


-- Q15. Credit-card instalments: how do buyers split payments?
SELECT
    CASE
        WHEN payment_installments <= 1 THEN '1 (paid in full)'
        WHEN payment_installments <= 3 THEN '2-3'
        WHEN payment_installments <= 6 THEN '4-6'
        ELSE                                '7+'
    END                                               AS installments,
    COUNT(*)                                          AS payments,
    ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)  AS pct_of_payments,
    ROUND(AVG(payment_value), 2)                      AS avg_payment_value
FROM order_payments p
JOIN orders o ON o.order_id = p.order_id
WHERE o.order_status = 'delivered'
  AND p.payment_type = 'credit_card'
GROUP BY installments
ORDER BY MIN(payment_installments);


/* =====================================================================
   H. CUSTOMER VALUE & RFM SEGMENTATION
   ===================================================================== */

-- Q16. Customer spend quartiles (NTILE): how concentrated is revenue?
WITH order_revenue AS (
    SELECT order_id, SUM(payment_value) AS revenue
    FROM order_payments
    GROUP BY order_id
),
customer_spend AS (
    SELECT c.customer_unique_id, SUM(r.revenue) AS spend
    FROM orders o
    JOIN customers c     ON c.customer_id = o.customer_id
    JOIN order_revenue r ON r.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
quartiles AS (
    SELECT spend, NTILE(4) OVER (ORDER BY spend DESC) AS quartile
    FROM customer_spend
)
SELECT
    quartile                                                AS spend_quartile,  -- 1 = top 25%
    COUNT(*)                                                AS customers,
    ROUND(AVG(spend), 2)                                    AS avg_spend,
    ROUND(100 * SUM(spend) / SUM(SUM(spend)) OVER (), 1)    AS pct_of_revenue
FROM quartiles
GROUP BY quartile
ORDER BY quartile;


-- Q17. RFM base table: recency, frequency and monetary value per customer
--      Recency is measured from the day after the last order in the data.
WITH order_revenue AS (
    SELECT order_id, SUM(payment_value) AS revenue
    FROM order_payments
    GROUP BY order_id
),
snapshot AS (
    SELECT MAX(order_purchase_timestamp) + INTERVAL 1 DAY AS snap
    FROM orders
    WHERE order_status = 'delivered'
)
SELECT
    c.customer_unique_id,
    TIMESTAMPDIFF(DAY, MAX(o.order_purchase_timestamp), (SELECT snap FROM snapshot)) AS recency_days,
    COUNT(DISTINCT o.order_id)                                                       AS frequency,
    ROUND(SUM(r.revenue), 2)                                                         AS monetary
FROM orders o
JOIN customers c     ON c.customer_id = o.customer_id
JOIN order_revenue r ON r.order_id = o.order_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_unique_id
ORDER BY monetary DESC
LIMIT 20;


-- Q18. RFM scores (1-5 by NTILE) and segment for each customer
--      Note: 97% of customers have exactly one order, so the frequency score
--      mostly separates tied customers rather than true buying habits. Recency
--      and monetary carry most of the signal. A refinement would score
--      frequency as one-time vs repeat instead of by quintile.
WITH order_revenue AS (
    SELECT order_id, SUM(payment_value) AS revenue
    FROM order_payments
    GROUP BY order_id
),
snapshot AS (
    SELECT MAX(order_purchase_timestamp) + INTERVAL 1 DAY AS snap
    FROM orders
    WHERE order_status = 'delivered'
),
rfm AS (
    SELECT
        c.customer_unique_id,
        TIMESTAMPDIFF(DAY, MAX(o.order_purchase_timestamp), (SELECT snap FROM snapshot)) AS recency_days,
        COUNT(DISTINCT o.order_id) AS frequency,
        SUM(r.revenue)             AS monetary
    FROM orders o
    JOIN customers c     ON c.customer_id = o.customer_id
    JOIN order_revenue r ON r.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
scored AS (
    SELECT
        *,
        NTILE(5) OVER (ORDER BY recency_days DESC)                 AS r_score,  -- recent = 5
        NTILE(5) OVER (ORDER BY frequency, customer_unique_id)     AS f_score,  -- 97% buy once, so ties are split
        NTILE(5) OVER (ORDER BY monetary)                          AS m_score
    FROM rfm
)
SELECT
    customer_unique_id, recency_days, frequency, ROUND(monetary, 2) AS monetary,
    r_score, f_score, m_score,
    CASE
        WHEN r_score >= 4 AND (f_score + m_score) / 2 >= 4 THEN 'Champions'
        WHEN r_score >= 3 AND (f_score + m_score) / 2 >= 3 THEN 'Loyal'
        WHEN r_score >= 4                                  THEN 'New / Promising'
        WHEN r_score <= 2 AND (f_score + m_score) / 2 >= 3 THEN 'At Risk'
        WHEN r_score <= 2                                  THEN 'Hibernating'
        ELSE                                                    'Need Attention'
    END AS segment
FROM scored
ORDER BY monetary DESC
LIMIT 20;


-- Q19. RFM segment summary: size, revenue and spend vs the average customer
--      Result: At Risk is the largest revenue segment (~21,900 customers,
--      ~R$5.0M past spend, 1.4x average spend, ~13 months since last order).
--      Counts can differ by <1% from the pandas notebook, because NTILE splits
--      tied values differently from pandas.qcut.
WITH order_revenue AS (
    SELECT order_id, SUM(payment_value) AS revenue
    FROM order_payments
    GROUP BY order_id
),
snapshot AS (
    SELECT MAX(order_purchase_timestamp) + INTERVAL 1 DAY AS snap
    FROM orders
    WHERE order_status = 'delivered'
),
rfm AS (
    SELECT
        c.customer_unique_id,
        TIMESTAMPDIFF(DAY, MAX(o.order_purchase_timestamp), (SELECT snap FROM snapshot)) AS recency_days,
        COUNT(DISTINCT o.order_id) AS frequency,
        SUM(r.revenue)             AS monetary
    FROM orders o
    JOIN customers c     ON c.customer_id = o.customer_id
    JOIN order_revenue r ON r.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
scored AS (
    SELECT
        *,
        NTILE(5) OVER (ORDER BY recency_days DESC)             AS r_score,
        NTILE(5) OVER (ORDER BY frequency, customer_unique_id) AS f_score,
        NTILE(5) OVER (ORDER BY monetary)                      AS m_score
    FROM rfm
),
segmented AS (
    SELECT
        *,
        CASE
            WHEN r_score >= 4 AND (f_score + m_score) / 2 >= 4 THEN 'Champions'
            WHEN r_score >= 3 AND (f_score + m_score) / 2 >= 3 THEN 'Loyal'
            WHEN r_score >= 4                                  THEN 'New / Promising'
            WHEN r_score <= 2 AND (f_score + m_score) / 2 >= 3 THEN 'At Risk'
            WHEN r_score <= 2                                  THEN 'Hibernating'
            ELSE                                                    'Need Attention'
        END AS segment
    FROM scored
)
SELECT
    segment,
    COUNT(*)                                                     AS customers,
    ROUND(SUM(monetary), 0)                                      AS revenue,
    ROUND(AVG(monetary), 2)                                      AS avg_spend,
    ROUND(AVG(monetary) / (SELECT AVG(monetary) FROM rfm), 2)    AS spend_vs_avg,
    ROUND(AVG(recency_days), 0)                                  AS avg_days_since_order
FROM segmented
GROUP BY segment
ORDER BY revenue DESC;


/* =====================================================================
   I. SELLERS
   ===================================================================== */

-- Q20. Top 10 sellers by revenue, with their late rate and review score
WITH order_score AS (
    SELECT order_id, AVG(review_score) AS score
    FROM order_reviews
    GROUP BY order_id
),
seller_orders AS (
    SELECT
        oi.seller_id,
        oi.order_id,
        SUM(oi.price)                                                         AS item_revenue,
        MAX(o.order_delivered_customer_date > o.order_estimated_delivery_date) AS is_late
    FROM order_items oi
    JOIN orders o ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
    GROUP BY oi.seller_id, oi.order_id
),
seller_stats AS (
    SELECT
        so.seller_id,
        COUNT(*)              AS orders,
        SUM(so.item_revenue)  AS revenue,
        AVG(so.is_late)       AS late_rate,
        AVG(s.score)          AS avg_review
    FROM seller_orders so
    LEFT JOIN order_score s ON s.order_id = so.order_id
    GROUP BY so.seller_id
)
SELECT
    ROW_NUMBER() OVER (ORDER BY ss.revenue DESC) AS revenue_rank,
    ss.seller_id,
    se.seller_state,
    ss.orders,
    ROUND(ss.revenue, 0)                         AS item_revenue,
    ROUND(100 * ss.late_rate, 1)                 AS late_pct,
    ROUND(ss.avg_review, 2)                      AS avg_review
FROM seller_stats ss
JOIN sellers se ON se.seller_id = ss.seller_id
ORDER BY revenue_rank
LIMIT 10;
