with staged as (

    select * from {{ ref('stg_job_postings') }}

),

enriched as (

    select
        job_posting_id,
        job_title,
        case when noc16_code is null then 'Not specified' else noc16_code end as noc16_code,
        case when noc16_code_name is null then 'Not specified' else noc16_code_name end as noc16_code_name,
        case when noc21_code is null then 'Not specified' else noc21_code end as noc21_code,
        case when noc21_code_name is null then 'Not specified' else noc21_code_name end as noc21_code_name,
        posting_date,
        vacancy_count,
        case
            when official_language is null then 'Not specified'
            when trim(official_language) = '*No data' then 'Not specified'
            else trim(official_language)
        end as official_language,
        province_territory,
        case
            when city is null then 'Not specified'
            else trim(city)
        end as city,
        case
            when economic_region is null then 'Not specified'
            else trim(economic_region)
        end as economic_region,
        case
            when employment_type is null then 'Not specified'
            else trim(employment_type)
        end as employment_type,
        case
            when employment_term is null then 'Not specified'
            else trim(employment_term)
        end as employment_term,
        salary_condition_detail,
        salary_period as salary_period_raw,
        case
            when salary_period is not null then salary_period
            when salary_condition_detail like '%commission%' then null
            when salary_min is not null and salary_min < 1000 then 'Hour'
            when salary_min is not null and salary_min >= 1000 then 'Year'
            else null
        end as salary_period,
        case
            when salary_period is null
                and salary_condition_detail not like '%commission%'
                and salary_min is not null
            then true
            else false
        end as salary_period_was_inferred,
        salary_min,
        salary_max,
        hours_per,
        hours_min,
        hours_max,
        case
            when education_los is null then 'minimal'
            else 'detailed'
        end as posting_detail_level

    from staged

)

select * from enriched