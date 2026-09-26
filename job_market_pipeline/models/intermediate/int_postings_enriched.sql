with staged as (

    select * from {{ ref('stg_job_postings') }}

),

with_hours_per as (

    select
        staged.*,

        case
            when staged.hours_per = 'Year' and staged.hours_min is not null and staged.hours_min < 10 then null
            when staged.hours_per = 'Year' and staged.hours_min is not null and staged.hours_min < 80 then 'Week'
            when staged.hours_per is not null then staged.hours_per
            when staged.hours_min is not null then 'Week'
            else null
        end as hours_per_corrected,

        case
            when staged.hours_per = 'Year' and staged.hours_min is not null and staged.hours_min < 80 then true
            when staged.hours_per is null and staged.hours_min is not null then true
            else false
        end as hours_per_was_inferred

    from staged

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

        -- Salary validation goes here
        with_hours_per.salary_period                                    as salary_period_raw,

        case
            when with_hours_per.salary_condition_detail not like '%$%' then null
            when with_hours_per.salary_condition_detail like '%per night%' then null
            when with_hours_per.salary_min > 10000000 then null
            when with_hours_per.salary_period = 'Hour' and with_hours_per.salary_min > 200 then 'Year'
            when with_hours_per.salary_period = 'Day' and with_hours_per.salary_min > 3000 then 'Year'
            when with_hours_per.salary_period = 'Week' and with_hours_per.salary_min > 10000 then 'Year'
            when with_hours_per.salary_period = 'Bi-weekly' and with_hours_per.salary_min > 20000 then 'Year'
            when with_hours_per.salary_period = 'Month' and with_hours_per.salary_min > 30000 then 'Year'
            when with_hours_per.salary_period = 'Hour' and with_hours_per.salary_min = 600 and with_hours_per.job_posting_id = 15828371 then null
            when with_hours_per.salary_period is not null then with_hours_per.salary_period
            when with_hours_per.salary_condition_detail like '%commission%' then null
            when with_hours_per.salary_min is not null and with_hours_per.salary_min < 1000 then 'Hour'
            when with_hours_per.salary_min is not null and with_hours_per.salary_min >= 1000 then 'Year'
            else null
        end                                                             as salary_period,

        case
            when with_hours_per.salary_condition_detail not like '%$%' then true
            when with_hours_per.salary_condition_detail like '%per night%' then true
            when with_hours_per.salary_min > 10000000 then true
            when with_hours_per.salary_period = 'Hour' and with_hours_per.salary_min > 200 then true
            when with_hours_per.salary_period = 'Day' and with_hours_per.salary_min > 3000 then true
            when with_hours_per.salary_period = 'Week' and with_hours_per.salary_min > 10000 then true
            when with_hours_per.salary_period = 'Bi-weekly' and with_hours_per.salary_min > 20000 then true
            when with_hours_per.salary_period = 'Month' and with_hours_per.salary_min > 30000 then true
            when with_hours_per.job_posting_id = 15828371 then false
            when with_hours_per.salary_period is null
                and with_hours_per.salary_condition_detail not like '%commission%'
                and with_hours_per.salary_min is not null
            then true
            else false
        end                                                             as salary_period_was_inferred,

        with_hours_per.salary_min                                       as salary_min,

        case
            when with_hours_per.salary_min > 10000000 then null
            when with_hours_per.salary_period = 'Hour' and with_hours_per.salary_max > 200 then null
            when with_hours_per.salary_period = 'Day' and with_hours_per.salary_max > 3000 then null
            when with_hours_per.salary_period = 'Week' and with_hours_per.salary_max > 10000 then null
            when with_hours_per.salary_period = 'Bi-weekly' and with_hours_per.salary_max > 20000 then null
            when with_hours_per.salary_period = 'Month' and with_hours_per.salary_max > 30000 then null
            when with_hours_per.salary_period = 'Year' and with_hours_per.salary_max > 1000000 then null
            else with_hours_per.salary_max
        end                                                             as salary_max,
        -- Salary ends here

        -- Work time validation
        with_hours_per.hours_per                                        as hours_per_raw,
        with_hours_per.hours_per_corrected                              as hours_per,
        with_hours_per.hours_per_was_inferred,

        case
            when with_hours_per.hours_per_corrected = 'Week' and with_hours_per.hours_min is not null and with_hours_per.hours_min < 5 then null
            when with_hours_per.hours_per_corrected = 'Year' and with_hours_per.hours_min is not null and with_hours_per.hours_min < 10 then null
            when with_hours_per.hours_per_corrected = 'Week' and with_hours_per.hours_min > 168 then null
            when with_hours_per.hours_per_corrected = 'Bi-weekly' and with_hours_per.hours_min > 336 then null
            when with_hours_per.hours_per_corrected = 'Month' and with_hours_per.hours_min > 744 then null
            when with_hours_per.hours_per_corrected = 'Year' and with_hours_per.hours_min > 8760 then null
            else with_hours_per.hours_min
        end                                                             as hours_min,

        case
            when with_hours_per.hours_per_corrected = 'Week' and with_hours_per.hours_max is not null and with_hours_per.hours_max < 5 then null
            when with_hours_per.hours_per_corrected = 'Year' and with_hours_per.hours_min is not null and with_hours_per.hours_min < 10 then null
            when with_hours_per.hours_per_corrected = 'Week' and with_hours_per.hours_max > 168 then null
            when with_hours_per.hours_per_corrected = 'Bi-weekly' and with_hours_per.hours_max > 336 then null
            when with_hours_per.hours_per_corrected = 'Month' and with_hours_per.hours_max > 744 then null
            when with_hours_per.hours_per_corrected = 'Year' and with_hours_per.hours_max > 8760 then null
            else with_hours_per.hours_max
        end                                                             as hours_max,
        -- Time ends here

        case
            when with_hours_per.education_los is null then 'minimal'
            else 'detailed'
        end as posting_detail_level

    from with_hours_per

),

with_hours_basis as (

    select
        *,
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