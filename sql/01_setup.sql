-- 01_setup.sql: database, schemas, warehouse, spending cap.
-- Run once, as ACCOUNTADMIN (trial accounts have this role).
-- Never add a payment method to the trial; the monitor below is a second safety net.

USE ROLE ACCOUNTADMIN;

CREATE DATABASE IF NOT EXISTS cos;
CREATE SCHEMA IF NOT EXISTS cos.raw;        -- copied TPC-H + synthetic tables
CREATE SCHEMA IF NOT EXISTS cos.analytics;  -- views the semantic view sits on
CREATE SCHEMA IF NOT EXISTS cos.ops;        -- briefings, claims, risks, agent, search

CREATE WAREHOUSE IF NOT EXISTS cos_wh
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE;

CREATE OR REPLACE RESOURCE MONITOR cos_rm
  WITH CREDIT_QUOTA = 10
  TRIGGERS ON 90 PERCENT DO SUSPEND
           ON 100 PERCENT DO SUSPEND_IMMEDIATE;

ALTER WAREHOUSE cos_wh SET RESOURCE_MONITOR = cos_rm;

-- Stage used later to publish Cortex Code skills (see README).
CREATE STAGE IF NOT EXISTS cos.ops.skills;

USE DATABASE cos;
USE WAREHOUSE cos_wh;
