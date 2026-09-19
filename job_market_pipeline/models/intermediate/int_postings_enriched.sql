with staged as (

    select * from {{ ref('stg_job_postings') }}

),

enriched as (

    select
        job_posting_id,
        job_title,
        noc16_code,
        noc16_code_name,
        noc21_code,
        noc21_code_name,
        posting_date,
        vacancy_count,
        official_language,
        province_territory,
        city,
        economic_region,
        employment_type,
        employment_term,
        salary_condition_detail,
        salary_period,
        salary_min,
        salary_max,
        hours_per,
        hours_min,
        hours_max,

        -- Derived from the data profiling finding that education_los, experience_level,
        -- naics, employment_term_weekend, employment_term_telework, and
        -- hours_per are null together in ~57.6% of rows -- flags which
        -- "shape" of posting this row is, without carrying the sparse
        -- columns themselves forward.
        case
            when education_los is null then 'minimal'
            else 'detailed'
        end as posting_detail_level

    from staged

)

select * from enriched