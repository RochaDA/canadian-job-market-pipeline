with distinct_occupation as (

    select distinct
        noc16_code,
        noc16_code_name,
        noc21_code,
        noc21_code_name

    from {{ ref('int_postings_enriched') }}

),

categories as (

    select * from {{ ref('noc_broad_categories') }}

),

teers as (
    select * from {{ref('teer_categories')}}
),

with_category as (

    select
        d.*,
        case
            when d.noc21_code = 'Not specified' then 'Not specified'
            else left(d.noc21_code, 1)
        end as noc21_broad_category_code,
        coalesce(c.broad_category_name, 'Not specified') as noc21_broad_category,
        case
            when d.noc21_code = 'Not specified' then 'Not specified'
            else substring(d.noc21_code, 2, 1)
        end as noc21_teer_code,
        coalesce(t.teer_category_name, 'Not specified') as noc21_teer_category

    from distinct_occupation d
    left join categories c
        on left(d.noc21_code, 1) = c.broad_category_code
    left join teers t
        on substring(d.noc21_code,2, 1) = t.teer_category_code

)

select
    {{ dbt_utils.generate_surrogate_key(['noc16_code', 'noc21_code']) }} as occupation_id,
    *
from with_category