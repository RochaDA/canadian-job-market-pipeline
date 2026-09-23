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
        staged.salary_period                                          as salary_period_raw,
        case
            when staged.job_posting_id = 15828371 then null
            when staged.salary_period = 'Hour' and staged.salary_min > 200 then 'Year'
            when staged.salary_period = 'Day' and staged.salary_min > 3000 then 'Year'
            when staged.salary_period = 'Week' and staged.salary_min > 10000 then 'Year'
            when staged.salary_period = 'Bi-weekly' and staged.salary_min > 20000 then 'Year'
            when staged.salary_period = 'Month' and staged.salary_min > 30000 then 'Year'
            when staged.salary_period is not null then staged.salary_period
            when staged.salary_condition_detail like '%commission%' then null
            when staged.salary_min is not null and staged.salary_min < 1000 then 'Hour'
            when staged.salary_min is not null and staged.salary_min >= 1000 then 'Year'
            else null
        end as salary_period,
        case
            when staged.job_posting_id = 15828371 then false
            when staged.salary_period = 'Hour' and staged.salary_min > 200 then true
            when staged.salary_period = 'Day' and staged.salary_min > 3000 then true
            when staged.salary_period = 'Week' and staged.salary_min > 10000 then true
            when staged.salary_period = 'Bi-weekly' and staged.salary_min > 20000 then true
            when staged.salary_period = 'Month' and staged.salary_min > 30000 then true
            when staged.salary_period is null
                and staged.salary_condition_detail not like '%commission%'
                and staged.salary_min is not null
            then true
            else false
        end as salary_period_was_inferred,
        staged.salary_min as salary_min,
        case
            when staged.salary_period = 'Hour' and staged.salary_max > 200 then null
            when staged.salary_period = 'Day' and staged.salary_max > 3000 then null
            when staged.salary_period = 'Week' and staged.salary_max > 10000 then null
            when staged.salary_period = 'Bi-weekly' and staged.salary_max > 20000 then null
            when staged.salary_period = 'Month' and staged.salary_max > 30000 then null
            when staged.salary_period = 'Year' and staged.salary_max > 1000000 then null
            else staged.salary_max
        end as salary_max,
        staged.hours_per as hours_per_raw,
        case
            when staged.job_posting_id = 15784703 then 'Week'
            when staged.hours_per is not null then staged.hours_per
            when staged.hours_min is not null then 'Week'
            else null
        end as hours_per,
        case
            when staged.job_posting_id = 15784703 then true
            when staged.hours_per is null and staged.hours_min is not null then true
            else false
        end as hours_per_was_inferred,
        case
            when staged.job_posting_id = 15811636 then null
            when staged.hours_per = 'Week' and staged.hours_min > 168 then null
            when staged.hours_per = 'Bi-weekly' and staged.hours_min > 336 then null
            when staged.hours_per = 'Month' and staged.hours_min > 744 then null
            when staged.hours_per = 'Year' and staged.hours_min > 8760 then null
            else staged.hours_min
        end as hours_min,

        case
            when staged.job_posting_id = 15811636 then null
            when staged.hours_per = 'Week' and staged.hours_max > 168 then null
            when staged.hours_per = 'Bi-weekly' and staged.hours_max > 336 then null
            when staged.hours_per = 'Month' and staged.hours_max > 744 then null
            when staged.hours_per = 'Year' and staged.hours_max > 8760 then null
            else staged.hours_max
        end as hours_max,
        case
            when education_los is null then 'minimal'
            else 'detailed'
        end as posting_detail_level

    from staged

),

with_hours_basis as (

    select
        *,
        /*
        Normalizes hours to a weekly figure regardless of hours_per's unit,
        using the midpoint of min/max when both exist. Falls back to a
        standard 40-hour week when no real hours data is available.
        This fallback is what makes salary_annual_method = 'estimated'
        for Hour-based postings below.
        */
        case
            when hours_per = 'Week' and hours_min is not null and hours_max is not null
                then (hours_min + hours_max) / 2.0
            when hours_per = 'Week' and hours_min is not null
                then hours_min
            when hours_per = 'Bi-weekly' and hours_min is not null and hours_max is not null
                then (hours_min + hours_max) / 2.0 / 2.0
            when hours_per = 'Bi-weekly' and hours_min is not null
                then hours_min / 2.0
            when hours_per = 'Month' and hours_min is not null and hours_max is not null
                then (hours_min + hours_max) / 2.0 / 4.345
            when hours_per = 'Month' and hours_min is not null
                then hours_min / 4.345
            when hours_per = 'Year' and hours_min is not null and hours_max is not null
                then (hours_min + hours_max) / 2.0 / 52.0
            when hours_per = 'Year' and hours_min is not null
                then hours_min / 52.0
            else 40.0
        end as weekly_hours_basis,

        case
            when hours_per is not null and hours_min is not null then 'actual'
            else 'assumed_40'
        end as weekly_hours_source

    from enriched

),

with_annual_salary as (

    select
        *,

        case
            when salary_period = 'Year' then round(salary_min, 2)
            when salary_period = 'Month' then round(salary_min * 12, 2)
            when salary_period = 'Bi-weekly' then round(salary_min * 26, 2)
            when salary_period = 'Week' then round(salary_min * 52, 2)
            when salary_period = 'Day' then round(salary_min * 260, 2)
            when salary_period = 'Hour' then round(salary_min * weekly_hours_basis * 52, 2)
            else null
        end as salary_annual_min,

        case
            when salary_period = 'Year' then round(salary_max, 2)
            when salary_period = 'Month' then round(salary_max * 12, 2)
            when salary_period = 'Bi-weekly' then round(salary_max * 26, 2)
            when salary_period = 'Week' then round(salary_max * 52, 2)
            when salary_period = 'Day' then round(salary_max * 260, 2)
            when salary_period = 'Hour' then round(salary_max * weekly_hours_basis * 52, 2)
            else null
        end as salary_annual_max,

        case
            when salary_period in ('Year', 'Month', 'Bi-weekly', 'Week') then 'direct'
            when salary_period in ('Hour', 'Day') then 'estimated'
            else null
        end as salary_annual_method

    from with_hours_basis

),

with_hourly_salary as (

    select
        *,

        case
            when salary_period = 'Hour' then round(salary_min, 2)
            when salary_annual_min is not null then round(salary_annual_min / (weekly_hours_basis * 52), 2)
            else null
        end as salary_hourly_min,

        case
            when salary_period = 'Hour' then round(salary_max, 2)
            when salary_annual_max is not null then round(salary_annual_max / (weekly_hours_basis * 52), 2)
            else null
        end as salary_hourly_max,

        case
            when salary_period = 'Hour' then 'direct'
            when salary_annual_min is not null then 'estimated'
            else null
        end as salary_hourly_method

    from with_annual_salary

)

select * from with_hourly_salary