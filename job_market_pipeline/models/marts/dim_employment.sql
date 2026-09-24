with distinct_employment as (

    select distinct
        employment_type,
        employment_term,
        official_language,
        posting_detail_level

    from {{ ref('int_postings_enriched') }}

),

enriched as (

    select
        {{ dbt_utils.generate_surrogate_key(['employment_type', 'employment_term', 'official_language', 'posting_detail_level']) }} as employment_id,
        employment_type,
        employment_term,
        official_language,
        posting_detail_level

    from distinct_employment

)

select * from enriched