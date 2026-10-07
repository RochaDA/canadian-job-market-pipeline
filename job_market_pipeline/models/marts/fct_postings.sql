select
    job_posting_id,
    job_posting_id_was_generated,

    /*
    Foreign keys, computed with the same hash expressions as each
    dimension's surrogate key. This guarantees a match without requiring
    the dimension tables to be built first, and stays correct if a future
    month introduces a combination a dimension hasn't seen yet.
    */
    {{ dbt_utils.generate_surrogate_key(['province_territory', 'city', 'economic_region']) }} as geography_id,
    {{ dbt_utils.generate_surrogate_key(['noc16_code', 'noc21_code']) }} as occupation_id,
    {{ dbt_utils.generate_surrogate_key(['employment_type', 'employment_term', 'official_language', 'posting_detail_level']) }} as employment_id,
    posting_date,

    /*
    Degenerate dimensions: descriptive, but too high-cardinality or
    free-text to normalize into their own dimension table.
    */
    job_title,
    salary_condition_detail,

    -- Measures
    vacancy_count,
    salary_min,
    salary_max,
    salary_period,
    salary_period_was_inferred,
    salary_annual_min,
    salary_annual_max,
    salary_annual_method,
    salary_hourly_min,
    salary_hourly_max,
    salary_hourly_method,
    hours_min,
    hours_max,
    hours_per,
    hours_per_was_inferred,
    weekly_hours_basis,
    weekly_hours_source

from {{ ref('int_postings_enriched') }}