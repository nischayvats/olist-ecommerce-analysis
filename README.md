# Olist E-Commerce Business Analysis: Customer Retention & Delivery Performance

**🔗 [Live dashboard](https://nischayvats.github.io/olist-ecommerce-analysis/olist_dashboard.html)** · **[SQL queries](olist_analysis.sql)** · **[EDA notebook](olist_eda.ipynb)** · **[Portfolio](https://nischayvats.github.io)**

A business review of Olist, a Brazilian e-commerce marketplace: 99,441 orders across 8 tables (1.5M+ rows). The project starts with requirements, moves through SQL analysis and customer segmentation, and ends with three recommendations, each with a KPI to track.

---

## Business problem

Order growth stalled in 2018 at about 6,500 orders a month, while almost every customer bought once and never returned. The goal was to find out why customers leave, which valuable customers are at risk, and where the business should act first.

## Approach

1. **Requirements:** wrote a short BRD (problem, objectives, scope, success KPIs), a stakeholder map and 7 user stories with acceptance criteria. Each user story links to the dashboard section that answers it.
2. **Data:** loaded the 8 Olist tables into MySQL.
3. **Analysis:** 20 SQL queries using joins, CTEs, subqueries and window functions (LAG, NTILE, DENSE_RANK, ROW_NUMBER, cumulative SUM), plus Python EDA.
4. **Segmentation:** RFM scoring (recency, frequency, monetary) to group customers.
5. **Reporting:** an interactive dashboard with findings and recommendations.

## Key findings

| Finding | Number |
|---|---|
| Customers who never ordered again | **97%** of 93,358 |
| Average review: late vs on-time orders | **2.6 vs 4.3 stars** |
| Late orders rated 1–2 stars | **54%** (vs 9% for on-time) |
| High-value customers gone quiet (RFM "At Risk") | **21,888**, holding **R$5.0M** of past spend |
| Share of orders from São Paulo | **42%** |
| Worst late-delivery rates (10 largest states) | **Bahia 14.0%**, **Rio de Janeiro 13.5%** |

## Recommendations

| Action | KPI to track |
|---|---|
| Win back the At Risk segment with targeted offers | Reactivation rate per campaign |
| Encourage a second order (e.g. coupon after a good review) | Repeat purchase rate within 90 days |
| Fix carriers and delivery estimates in Bahia and Rio | On-time delivery rate by state, weekly |

## Repository contents

| File | Description |
|---|---|
| `olist_dashboard.html` | Interactive dashboard: brief, growth, delivery vs reviews, RFM segments, state map, recommendations |
| `olist_analysis.sql` | 20 SQL queries (MySQL 8 / MariaDB), grouped by business question |
| `olist_eda.ipynb` | Python exploratory analysis (pandas, matplotlib, seaborn) |
| `chart*.png` | EDA charts exported from the notebook |

## Tools

MySQL · SQL (CTEs, window functions) · Python (pandas, NumPy, matplotlib, seaborn) · Jupyter · JavaScript/SVG dashboard · GitHub Pages

## Data

[Olist Brazilian E-Commerce Public Dataset](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) (Kaggle), Sep 2016 – Aug 2018. Business metrics use delivered orders only. Stakeholders in the brief are representative roles for a marketplace like Olist, defined to scope this portfolio project.

---

**Nischay Vats**, Business Analyst · [LinkedIn](https://www.linkedin.com/in/nischay-vats-b2b2b820a) · [Portfolio](https://nischayvats.github.io)
