# Canadian Job Market Analytics Pipeline

An end-to-end analytics pipeline built on 36 months of job posting data from
the Canadian Job Bank, structured to mirror how a real analytics team would
build and run one.

**Status: in progress.** See [Progress](#progress) below
for where things currently stand.

## Goal

### Problem

Job seekers, career changers, and workforce analysts trying to understand
which occupations, regions, and skills are gaining or losing demand across
Canada run into fragmented information. Job Bank's own site shows a live,
point-in-time snapshot with no historical view — close the tab and that data
is gone. Posting text is unstructured, so answering something like "what
skills are increasingly required for this role" means reading listings one
at a time. And comparing trends across regions or months means manually
repeating searches, with no memory of what things looked like last quarter.

### Alternatives considered

- **Manually browsing Job Bank's search filters** — fine for a single
  snapshot, but has no history and doesn't scale past a handful of ad hoc
  questions.
- **Statistics Canada's Labour Force Survey / Job Vacancy and Wage Survey** —
  authoritative, but published quarterly at a highly aggregated level, with
  lag, and no posting-level detail like skills language.
- **Third-party labour-market dashboards** — often paywalled or opaque about
  methodology, and not adaptable to a specific question.
- **A one-off spreadsheet pull** — the fastest way to answer a single
  question today, but not repeatable: each new month means redoing the work
  by hand, with no tests and no way to hand it off.

### Solution

This project turns 36 months of raw Job Bank postings into a historical,
queryable dataset via an automated, tested pipeline: postings are ingested
incrementally and validated, modeled through a bronze/silver/gold layered
transformation with data-quality checks at each stage, and exposed as
a start schema that power dashboards and downstream analysis. 
The result functions closer to a lightweight internal labour-market-intelligence 
tool than a one-time analysis rerunnable, versioned, and built to extend as 
new months of data arrive.

## Architecture

```
Job Bank postings (36 monthly CSV exports, via CKAN open-data API)
        |
        v
  ingestion (Python) -- validated parsing, retries, idempotent, manifest-logged
        |
        v
  bronze   (raw Delta table in Databricks / Unity Catalog)
        |
        v
  silver   (dbt staging models -- cleaned, typed, tested)
        |
        v
  gold     star schema (fct_postings + dim_date, dim_geography, dim_occupation, dim_employment)
        |
        +--> BI dashboards (Databricks SQL)
        +--> ML/NLP notebooks (skills extraction, demand forecasting)
```

## Tech stack

- **Ingestion**: Python, pandas, requests — pulls monthly postings from Job
  Bank's open-data CKAN API, with encoding/format validation, retry-with-backoff,
  schema-drift detection, and an idempotent manifest so reruns are safe.
- **Storage & compute**: Databricks Free Edition — Delta Lake, Unity Catalog,
  serverless SQL Warehouse.
- **Transformation**: dbt-core with the `dbt-databricks` adapter — staging,
  intermediate, and mart models, with `dbt test` enforcing data quality.
- **CI**: GitHub Actions — runs `dbt build` against a scratch schema on every
  pull request.
- **Testing**: pytest — unit tests on the ingestion module's parsing logic.

## Repo structure

```
├── job_market_pipeline/    # dbt project (models, tests, seeds)
├── src/data/                # ingestion module (download, config, manifest)
├── tests/                   # pytest unit tests for ingestion
├── data/raw/                 # downloaded monthly CSVs + manifest (gitignored)
└── .github/workflows/        # CI pipeline
```

## Progress

- [x] Ingestion module: monthly download, schema validation, retries,
      idempotent manifest, unit tests
- [x] Databricks workspace + dbt connection configured and verified
- [x] Bronze layer: first monthly file loaded as a raw Delta table (1 of 36 months)
- [x] Silver layer: staging model + intermediate model, fully validated against 1 month
      - [x] NOC code columns: leading-zero loss found and fixed, length-tested
      - [x] Date columns: format mismatch found and fixed
      - [x] Column profiling: null rates checked across all ~27 shortlisted columns
      - [x] Found a structural null pattern (6 columns null together in ~57.6% of
            rows) -- likely two distinct posting "shapes" (detailed vs. minimal)
      - [x] int_postings_enriched built: dropped 6 sparse/low-value columns,
            derived posting_detail_level flag, tested
      - [x] Every remaining column individually profiled: distinct values,
            placeholder strings (e.g. '*No data'), correlated nulls, and
            null-handling standardized to 'Not specified' where applicable
      - [x] Salary/hours normalization: derived weekly_hours_basis,
            salary_annual_min/max, salary_hourly_min/max (each flagged
            direct vs. estimated); found and fixed salary_period and
            salary_max mislabeling across multiple periods; nulled a small
            number of physically impossible or unrecoverable values
      - [ ] Not yet run against a second month to check for new surprises
- [x] Gold layer: star schema (fct_postings + dim_date, dim_geography,
      dim_occupation, dim_employment). Built to preserve ad hoc analysis flexibility.
      in Power BI. All foreign keys verified via dbt_utils relationships tests;
      dim_date generated using dbt_utils.date_spine() for full drill-down 
      (day -> week -> month -> quarter -> year)
- [ ] BI dashboard
- [ ] CI wired to real pull requests
- [ ] Skills-extraction and forecasting notebooks

## Setup

*(fill in once the pipeline is runnable end to end — install steps, how to
point dbt at your own Databricks workspace, how to run the ingestion script)*
