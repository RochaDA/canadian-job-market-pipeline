with source as (

    select * from {{ source('raw', 'job_postings') }}

),

renamed as (

    select
        cast(`WIC Job Location Snapshot ID` as string)                     as job_posting_id_source,
        trim(`Job Title`)                                                    as job_title,
        trim(`Original Job Title`)                                           as original_job_title,
        lpad(regexp_replace(`NOC 2016 Code`, '\\.0$', ''), 4, '0')           as noc16_code,
        trim(`NOC 2016 Code Name`)                                           as noc16_code_name,
        lpad(regexp_replace(`NOC21 Code`, '\\.0$', ''), 5, '0')              as noc21_code,
        trim(`NOC21 Code Name`)                                              as noc21_code_name,
        cast(`External Indicator` as bigint)                                as external_indicator,

        -- yyyy/MM/dd is the usual format, but Sep 2024 (and possibly
        -- earlier months) uses yyyy-MM-dd instead -- try both, using
        -- try_to_date so a non-matching attempt returns null rather than
        -- erroring, and coalesce picks whichever one actually parsed.
        coalesce(
            try_to_date(`First Posting Date`, 'yyyy/MM/dd'),
            try_to_date(`First Posting Date`, 'yyyy-MM-dd')
        )                                                                    as posting_date,

        cast(`Vacancy Count` as bigint)                                      as vacancy_count,
        trim(`Official Language`)                                            as official_language,
        trim(`Education LOS`)                                                as education_los,
        trim(`Experience Level`)                                             as experience_level,
        trim(`Government Type`)                                              as government_type,
        trim(`Placement Agency`)                                             as placement_agency,
        trim(`NAICS`)                                                        as naics,
        trim(`Province/Territory`)                                          as province_territory,
        trim(`City`)                                                        as city,
        trim(`Work Location Postal Code`)                                   as work_location_postal_code,
        trim(`Economic Region`)                                             as economic_region,
        trim(`Various Location`)                                            as various_location,
        trim(`Employment Type`)                                             as employment_type,
        trim(`Employment Term`)                                             as employment_term,

        coalesce(
            try_to_date(`Employment Term Start Date`, 'yyyy/MM/dd'),
            try_to_date(`Employment Term Start Date`, 'yyyy-MM-dd')
        )                                                                    as employment_term_start_date,

        coalesce(
            try_to_date(`Employment Term End Date`, 'yyyy/MM/dd'),
            try_to_date(`Employment Term End Date`, 'yyyy-MM-dd')
        )                                                                    as employment_term_end_date,

        trim(`Employment Term Oncall`)                                      as employment_term_oncall,
        trim(`Employment Term Overtime`)                                    as employment_term_overtime,
        trim(`Employment Term Day`)                                         as employment_term_day,
        trim(`Employment Term Evening`)                                     as employment_term_evening,
        trim(`Employment Term Shift`)                                       as employment_term_shift,
        trim(`Employment Term Weekend`)                                     as employment_term_weekend,
        trim(`Employment Term Night`)                                       as employment_term_night,
        trim(`Employment Term Telework`)                                    as employment_term_telework,
        trim(`Employment Term Early`)                                       as employment_term_early,
        trim(`Employment Term Flex`)                                        as employment_term_flex,
        trim(`Employment Term Morning`)                                     as employment_term_morning,
        trim(`Employment Term TBD`)                                        as employment_term_tbd,
        trim(`Salary Condition Detail`)                                     as salary_condition_detail,
        trim(`Salary Per`)                                                  as salary_period,
        cast(`Salary Minimum` as double)                                   as salary_min,
        cast(`Salary Maximum` as double)                                   as salary_max,
        trim(`Salary Condition Collective`)                                 as salary_condition_collective,
        trim(`Salary Condition Bonus`)                                      as salary_condition_bonus,
        trim(`Salary Condition Disability`)                                 as salary_condition_disability,
        trim(`Salary Condition Gratuity`)                                   as salary_condition_gratuity,
        trim(`Salary Condition Medical`)                                    as salary_condition_medical,
        trim(`Salary Condition Mileage`)                                    as salary_condition_mileage,
        trim(`Salary Condition Piecework`)                                  as salary_condition_piecework,
        trim(`Salary Condition Commission`)                                 as salary_condition_commission,
        trim(`Salary Condition RESP`)                                       as salary_condition_resp,
        trim(`Salary Condition Dental`)                                     as salary_condition_dental,
        trim(`Salary Condition Group Insurance`)                            as salary_condition_group_insurance,
        trim(`Salary Condition Life Insurance`)                             as salary_condition_life_insurance,
        trim(`Salary Condition Pension`)                                    as salary_condition_pension,
        trim(`Salary Condition RRSP`)                                       as salary_condition_rrsp,
        trim(`Condition Vision Care`)                                       as salary_condition_vision_care,
        trim(`Salary Condition Other Benefits`)                             as salary_condition_other_benefits,
        trim(`Commission PER`)                                              as commission_per,
        trim(`Commission Type`)                                             as commission_type,
        trim(`Hours Per`)                                                   as hours_per,
        cast(`Hours Minimum` as double)                                    as hours_min,
        cast(`Hours Maximum` as double)                                    as hours_max,
        trim(`Work Hours`)                                                  as work_hours,
        `Work Hours From Time`                                              as work_hours_from_time,
        `Work Hours To Time`                                                as work_hours_to_time,
        _rescued_data

    from source

),

with_generated_id as (

    select
        renamed.*,

        -- A deterministic hash of fields unlikely to collide across
        -- genuinely different postings. Only used as a fallback when the
        -- source's own ID is missing (confirmed: entirely absent for all
        -- of September 2024 -- see notebooks/eda/ for the audit).
        sha2(
            concat_ws(
                '|',
                coalesce(job_title, ''),
                coalesce(cast(posting_date as string), ''),
                coalesce(province_territory, ''),
                coalesce(city, ''),
                coalesce(cast(salary_min as string), ''),
                coalesce(cast(salary_max as string), ''),
                coalesce(noc21_code, '')
            ),
            256
        ) as composite_hash

    from renamed

),

with_dedup_rank as (

    select
        *,

        -- Disambiguates genuinely identical postings sharing the same
        -- composite hash (e.g. an employer posting several identical
        -- vacancies, as seen with the optometrist rows earlier). The
        -- ORDER BY is an accepted, documented limitation: for rows
        -- identical across every field used in the hash, there's no
        -- remaining signal to break the tie deterministically -- but
        -- since those rows are also identical in every exposed column,
        -- which specific row receives which generated ID doesn't affect
        -- any downstream count, aggregate, or join.
        row_number() over (partition by composite_hash order by composite_hash) as dedup_rank

    from with_generated_id

),

final as (

    select
        * except (job_posting_id_source, composite_hash, dedup_rank),

        coalesce(
            job_posting_id_source,
            concat('GEN-', composite_hash, '-', cast(dedup_rank as string))
        )                                    as job_posting_id,

        job_posting_id_source is null        as job_posting_id_was_generated

    from with_dedup_rank

)

select * from final