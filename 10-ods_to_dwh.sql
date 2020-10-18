/* *********************************************************************************** */
/* *** ODS TO DWH ******************************************************************** */
/* *********************************************************************************** */
use schema public;

create or replace view weather_effects_global as
select
    date,
    avg(temperature_celcius) as temperature_celcius,
    avg(precipitation) as precipitation,
    avg(avg_stars) as avg_stars,
    sum(num_reviews) as num_reviews
from weather_effects
    group by date;

select * from weather_effects_global;

select * from weather_effects_global where date = '2013-03-26';

create or replace view weather_effects_global_monthly as
select
    month(date) as month,
    avg(temperature_celcius) as temperature_celcius,
    avg(precipitation) as precipitation,
    avg(avg_stars) as avg_stars,
    sum(num_reviews) as num_reviews
from weather_effects_global g
-- where to_date(date) >= '2012-01-01'
group by month(date)
order by month;

select * from weather_effects_global_monthly;
