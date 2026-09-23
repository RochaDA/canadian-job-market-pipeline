with distinct_geography as (

    select distinct
        province_territory,
        city,
        economic_region

    from {{ ref('int_postings_enriched') }}

),

geography_table as (

    select
        {{ dbt_utils.generate_surrogate_key(['province_territory', 'city', 'economic_region']) }} as geography_id,
        province_territory,
        city,
        economic_region

    from distinct_geography

)

select * from geography_table