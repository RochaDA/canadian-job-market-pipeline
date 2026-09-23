with date_spine as (

    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('2023-01-01' as date)",
        end_date="cast('2027-01-01' as date)"
    ) }}

),

time_table as (

    select
        cast(date_day as date)                                  as date_day,
        cast(date_format(date_day, 'yyyyMMdd') as int)           as date_key,

        year(date_day)                                            as year,
        quarter(date_day)                                         as quarter,
        concat('Q', quarter(date_day))                            as quarter_name,
        month(date_day)                                           as month,
        date_format(date_day, 'MMMM')                             as month_name,
        weekofyear(date_day)                                      as week_of_year,
        date_format(date_day, 'EEEE')                             as day_name,

        /*Spark's dayofweek(): 1=Sunday ... 7=Saturday*/
        case
            when dayofweek(date_day) in (1, 7) then true
            else false
        end                                                        as is_weekend

    from date_spine

)

select * from time_table