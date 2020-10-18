/* *********************************************************************************** */
/* *** INTEGRATE CLIMATE AND YELP DATA *********************************************** */
/* *********************************************************************************** */
use schema public;

create or replace view weather_effects as
select
    yr.date as date,
    yr.business_id,
    yb.name as business_name,
    (((t.min_value + t.max_value) - 32) * 5 / 9) / 2 as temperature_celcius,
    p.precipitation as precipitation,
    yr.avg_stars as avg_stars,
    yr.num_reviews as num_reviews,
    c.temporary_closed_until
from (
    select
        cast(date_trunc('DAY', date) as date) as date,
        business_id,
        avg(stars) as avg_stars,
        count(*) as num_reviews
    from yelp_reviews
    group by date, business_id
) as yr
left join (
    select t.date as date
    from temperatures as t
    union
    select p.date as date
    from precipitations as p
) as tp
    on tp.date = yr.date
left join temperatures t
    on t.date = yr.date
left join precipitations p
    on p.date = yr.date
left join yelp_businesses yb
    on yb.business_id = yr.business_id
left join covid19 c
    on c.business_id = yr.business_id;

select * from weather_effects w where w.date = '2019-12-13';
select * from weather_effects order by date desc limit 5;
select * from weather_effects where avg_stars < 5.0 order by avg_stars desc limit 10;
