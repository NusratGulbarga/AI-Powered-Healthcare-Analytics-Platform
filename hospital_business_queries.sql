/*
================================================================================
 HOSPITAL SQL ANALYSIS -- BUSINESS QUERIES
================================================================================
 Author  : Nusrat -- Data Analyst @ Wmolex | Educator, Gurukul Institute of
           Advanced Technology
 Dataset : healthcare_admissions.csv (55,500 hospital admission records,
           2019-2024), loaded into a table named `admissions`
 Engine  : Written and tested against SQLite. Minor syntax changes may be
           needed for other engines (see notes marked SQLite-specific below).

 SETUP (SQLite):
   CREATE TABLE admissions (
       Name                TEXT,
       Age                 INTEGER,
       Gender              TEXT,
       Blood_Type          TEXT,
       Medical_Condition   TEXT,
       Date_of_Admission   TEXT,   -- 'YYYY-MM-DD'
       Doctor              TEXT,
       Hospital            TEXT,
       Insurance_Provider  TEXT,
       Billing_Amount      REAL,
       Room_Number         INTEGER,
       Admission_Type      TEXT,   -- 'Elective' | 'Urgent' | 'Emergency'
       Discharge_Date      TEXT,   -- 'YYYY-MM-DD'
       Medication          TEXT,
       Test_Results        TEXT    -- 'Normal' | 'Abnormal' | 'Inconclusive'
   );
   -- then bulk-load healthcare_admissions.csv into this table (column names
   -- have underscores instead of spaces to stay SQL-friendly)

   CREATE INDEX idx_dates ON admissions(Date_of_Admission, Discharge_Date);
   CREATE INDEX idx_type  ON admissions(Admission_Type);
   CREATE INDEX idx_name  ON admissions(Name);

 CAVEATS (apply throughout this file, flagged again inline where relevant):
   - No patient ID column exists -> Readmission Rate and the readmission
     component of High-Risk Patients use repeat `Name` as a proxy.
   - No Department column exists -> Department KPIs use Medical_Condition
     as a department / service-line proxy.
   - No ICU/ward column exists   -> ICU Occupancy uses
     Admission_Type = 'Emergency' as a proxy for acute/ICU-level demand.
================================================================================
*/

-- ============================================================================
-- 1. TOP DISEASES
-- Ranks medical conditions by patient volume.
-- ============================================================================

SELECT
    Medical_Condition,
    COUNT(*) AS patient_count,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM admissions), 2) AS pct_of_total
FROM admissions
GROUP BY Medical_Condition
ORDER BY patient_count DESC;


-- ============================================================================
-- 2. MONTHLY ADMISSIONS
-- Admission volume trend by calendar month.
-- ============================================================================

SELECT
    strftime('%Y-%m', Date_of_Admission) AS admission_month,
    COUNT(*) AS admissions
FROM admissions
GROUP BY admission_month
ORDER BY admission_month;


-- ============================================================================
-- 3. REVENUE ANALYSIS
-- Total and average billing by year and by admission type.
-- ============================================================================

SELECT
    strftime('%Y', Date_of_Admission) AS year,
    COUNT(*) AS admissions,
    ROUND(SUM(Billing_Amount), 2) AS total_revenue,
    ROUND(AVG(Billing_Amount), 2) AS avg_billing
FROM admissions
GROUP BY year
ORDER BY year;


SELECT
    Admission_Type,
    COUNT(*) AS admissions,
    ROUND(SUM(Billing_Amount), 2) AS total_revenue,
    ROUND(AVG(Billing_Amount), 2) AS avg_billing
FROM admissions
GROUP BY Admission_Type
ORDER BY total_revenue DESC;


-- ============================================================================
-- 4. INSURANCE CLAIMS
-- Claim volume and billed amount by insurance provider.
-- ============================================================================

SELECT
    Insurance_Provider,
    COUNT(*) AS claim_count,
    ROUND(SUM(Billing_Amount), 2) AS total_billed,
    ROUND(AVG(Billing_Amount), 2) AS avg_claim_amount
FROM admissions
GROUP BY Insurance_Provider
ORDER BY total_billed DESC;


-- ============================================================================
-- 5. READMISSION RATE
-- PROXY METRIC: no patient ID exists in the source data, so this relies on
--   exact patient Name match via a window-style visit count (CTE) to flag repeat visits.
-- ============================================================================

WITH patient_visits AS (
    SELECT
        Name,
        COUNT(*) AS visit_count
    FROM admissions
    GROUP BY Name
)
SELECT
    COUNT(*) AS total_patients,
    SUM(CASE WHEN visit_count > 1 THEN 1 ELSE 0 END) AS readmitted_patients,
    ROUND(100.0 * SUM(CASE WHEN visit_count > 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS readmission_rate_pct
FROM patient_visits;


WITH patient_visits AS (
    SELECT Name, Medical_Condition, COUNT(*) AS visit_count
    FROM admissions
    GROUP BY Name, Medical_Condition
)
SELECT
    Medical_Condition,
    COUNT(*) AS patients,
    SUM(CASE WHEN visit_count > 1 THEN 1 ELSE 0 END) AS readmitted,
    ROUND(100.0 * SUM(CASE WHEN visit_count > 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS readmission_rate_pct
FROM patient_visits
GROUP BY Medical_Condition
ORDER BY readmission_rate_pct DESC;


-- ============================================================================
-- 6. DEPARTMENT KPIs
-- PROXY METRIC: no Department column exists in the source data.
--   Medical_Condition is used as a department / service-line proxy.
-- ============================================================================

SELECT
    Medical_Condition AS department,
    COUNT(*) AS patient_count,
    ROUND(AVG(julianday(Discharge_Date) - julianday(Date_of_Admission)), 2) AS avg_length_of_stay,
    ROUND(AVG(Billing_Amount), 2) AS avg_billing,
    ROUND(SUM(Billing_Amount), 2) AS total_revenue
FROM admissions
GROUP BY department
ORDER BY total_revenue DESC;


-- ============================================================================
-- 7. DOCTOR PERFORMANCE
-- Top doctors by patient volume, with average billing, average length of
--   stay, and abnormal test result counts per doctor.
-- ============================================================================

SELECT
    Doctor,
    COUNT(*) AS patients_treated,
    ROUND(AVG(Billing_Amount), 2) AS avg_billing,
    ROUND(AVG(julianday(Discharge_Date) - julianday(Date_of_Admission)), 2) AS avg_length_of_stay,
    SUM(CASE WHEN Test_Results = 'Abnormal' THEN 1 ELSE 0 END) AS abnormal_results_count
FROM admissions
GROUP BY Doctor
ORDER BY patients_treated DESC
LIMIT 15;


-- ============================================================================
-- 8. AVERAGE LENGTH OF STAY
-- Overall average/min/max LOS, plus breakdown by admission type.
-- ============================================================================

SELECT
    ROUND(AVG(julianday(Discharge_Date) - julianday(Date_of_Admission)), 2) AS avg_los_days,
    ROUND(MIN(julianday(Discharge_Date) - julianday(Date_of_Admission)), 2) AS min_los_days,
    ROUND(MAX(julianday(Discharge_Date) - julianday(Date_of_Admission)), 2) AS max_los_days
FROM admissions;


SELECT
    Admission_Type,
    ROUND(AVG(julianday(Discharge_Date) - julianday(Date_of_Admission)), 2) AS avg_los_days
FROM admissions
GROUP BY Admission_Type
ORDER BY avg_los_days DESC;


-- ============================================================================
-- 9. ICU OCCUPANCY
-- PROXY METRIC: no ICU/ward column exists in the source data.
--   Admission_Type = 'Emergency' is used as a stand-in for acute/ICU-level
--   demand. A recursive date-spine CTE generates one row per calendar day,
--   then a range join counts how many proxy-ICU patients were active
--   (admitted and not yet discharged) on each day.
-- ============================================================================

WITH RECURSIVE date_spine(day) AS (
    SELECT MIN(Date_of_Admission) FROM admissions
    UNION ALL
    SELECT date(day, '+1 day')
    FROM date_spine
    WHERE day < (SELECT MAX(Discharge_Date) FROM admissions)
)
SELECT
    ds.day,
    COUNT(a.Name) AS icu_occupancy
FROM date_spine ds
LEFT JOIN admissions a
    ON a.Admission_Type = 'Emergency'
    AND a.Date_of_Admission <= ds.day
    AND a.Discharge_Date >= ds.day
GROUP BY ds.day
ORDER BY ds.day;


-- ============================================================================
-- 10. HIGH-RISK PATIENTS
-- Composite risk score built from: age > 60, an Abnormal test result, an
--   Emergency admission, and a repeat visit (proxy readmission). Patients
--   scoring 2+ are surfaced as high-risk.
-- ============================================================================

WITH patient_visits AS (
    SELECT Name, COUNT(*) AS visit_count
    FROM admissions
    GROUP BY Name
),
risk_flags AS (
    SELECT
        a.Name,
        a.Age,
        a.Medical_Condition,
        a.Admission_Type,
        a.Test_Results,
        v.visit_count,
        (CASE WHEN a.Age > 60 THEN 1 ELSE 0 END) +
        (CASE WHEN a.Test_Results = 'Abnormal' THEN 1 ELSE 0 END) +
        (CASE WHEN a.Admission_Type = 'Emergency' THEN 1 ELSE 0 END) +
        (CASE WHEN v.visit_count > 1 THEN 1 ELSE 0 END) AS risk_score
    FROM admissions a
    JOIN patient_visits v ON a.Name = v.Name
)
SELECT
    Name, Age, Medical_Condition, Admission_Type, Test_Results, visit_count, risk_score
FROM risk_flags
WHERE risk_score >= 2
ORDER BY risk_score DESC, Age DESC
LIMIT 20;


WITH patient_visits AS (
    SELECT Name, COUNT(*) AS visit_count
    FROM admissions
    GROUP BY Name
),
risk_flags AS (
    SELECT
        a.Name,
        (CASE WHEN a.Age > 60 THEN 1 ELSE 0 END) +
        (CASE WHEN a.Test_Results = 'Abnormal' THEN 1 ELSE 0 END) +
        (CASE WHEN a.Admission_Type = 'Emergency' THEN 1 ELSE 0 END) +
        (CASE WHEN v.visit_count > 1 THEN 1 ELSE 0 END) AS risk_score
    FROM admissions a
    JOIN patient_visits v ON a.Name = v.Name
)
SELECT
    risk_score,
    COUNT(*) AS record_count
FROM risk_flags
GROUP BY risk_score
ORDER BY risk_score;


