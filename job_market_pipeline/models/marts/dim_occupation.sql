with distinct_occupation as (

    select distinct
        noc16_code,
        noc16_code_name,
        noc21_code,
        noc21_code_name

    from {{ ref('int_postings_enriched') }}

),

occupation_table as (

    select
        {{ dbt_utils.generate_surrogate_key(['noc16_code', 'noc21_code']) }} as occupation_id,
        noc16_code,
        noc16_code_name,
        noc21_code,
        noc21_code_name

    from distinct_occupation

)

select * from occupation_table