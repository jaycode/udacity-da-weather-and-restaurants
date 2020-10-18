use schema public;

/* *********************************************************************************** */
/* *** WEATHER DATA ****************************************************************** */
/* *********************************************************************************** */
list @temperature;

create or replace table temperatures (
  date date,
  min_value float,
  max_value float,
  normal_min float,
  normal_max float
);

copy into temperatures from (
  select to_date($1, 'YYYYMMDD'), $2, $3, $4, $5
  from @temperature (file_format => 'CSV')
);

list @precipitation;

create or replace table precipitations (
  date date,
  precipitation float,
  precipitation_normal float
);

copy into precipitations from (
  select to_date($1, 'YYYYMMDD'), $2, $3
  from @precipitation (file_format => 'PRECIPITATION_CSV')
);


/* *********************************************************************************** */
/* *** YELP DATA - COVID ************************************************************* */
/* *********************************************************************************** */

-- Load Covid-19 staging data
list @covid19;

create or replace table covid19_json (v variant);

create or replace file format covid19_json_format
  type = 'json';

copy into covid19_json
from @covid19
file_format = covid19_json_format;

-- Get sample data from covid19_json
select v from covid19_json limit 1;
select distinct v:"Temporary Closed Until" from covid19_json limit 5;
-- Is business_id unique?
select v:business_id, count(*) as cnt from covid19_json group by v:business_id order by cnt desc limit 1;
-- No it isn't

drop table if exists covid19;
create or replace view covid19 as
select
  v:business_id::string as business_id,
  v:"Call To Action enabled"::boolean as call_to_action_enabled,
  v:"Covid Banner"::string as covid_banner,
  v:"Grubhub enabled"::boolean as grubhub_enabled,
  v:"Request a Quote Enabled"::boolean as request_a_quote_enabled,
  nullif(v:"Temporary Closed Until"::string, 'FALSE')::date as temporary_closed_until,
  v:"Virtual Services Offered"::string as virtual_services_offered,
  v:"delivery or takeout"::string as delivery_or_takeout,
  v:highlights::string as highlights
from covid19_json;


-- Example of multiple entries with the same business_id
select * from covid19 where business_id = 'tjmeouazwTU50QFUuL6cDA';

-- Example of various temporary_closed_until
select distinct(temporary_closed_until) from covid19;


/* *********************************************************************************** */
/* *** YELP DATA - JSON ************************************************************** */
/* *********************************************************************************** */

-- Load Yelp staging data
list @yelp;

create or replace table yelp_json (filename string, file_row_number integer, v variant);

create or replace file format yelp_json_format
  type = 'json' compression = 'AUTO';

copy into yelp_json from (
  select
    metadata$filename,
    metadata$file_row_number,
    parse_json(t.$1) from @yelp
    (file_format => yelp_json_format) t
)
on_error = CONTINUE;

/* *** YELP REVIEWS *** */

-- Get sample json data of a review
select v from yelp_json where filename like '%review%' limit 1;

-- Create yelp_reviews view
create or replace view yelp_reviews as
select
  v:review_id::string as review_id,
  v:business_id::string as business_id,
  v:user_id::string as user_id,
  v:cool::int as cool,
  v:date::date as date,
  v:funny::int as funny,
  v:stars::int as stars,
  v:text::string as text,
  v:useful::int as useful
from yelp_json
where filename like '%review%';

/* *** YELP TIPS *** */

-- Get sample data of a tip
select v from yelp_json where filename like '%tip%' limit 1;

-- Create yelp_tips view
create or replace view yelp_tips as
select
  v:business_id::string as business_id,
  v:user_id::string as user_id,
  v:compliment_count::int as compliment_count,
  v:date::date as date,
  v:text::string as text
from yelp_json
where filename like '%tip%';

/* *** YELP CHECKINS *** */

-- Get sample data of a checkin
select v from yelp_json where filename like '%checkin%' limit 1;
select split(v:date, ' ') from yelp_json where filename like '%checkin%' limit 1;

create or replace view yelp_checkins as
select
  v:business_id::string as business_id,
  c.value::datetime as datetime
from yelp_json y,
     lateral flatten(input=>split(y.v:date, ', ')) c
where y.filename like '%checkin%';

/* *** YELP USERS *** */
-- Get sample data of a user
select v from yelp_json where filename like '%user%' limit 1;
select distinct v:elite from yelp_json where filename like '%user%' limit 10;

create or replace view yelp_users as
select
  v:user_id::string as user_id,
  v:average_stars::float as average_stars,
  v:compliment_cool::int as compliment_cool,
  v:compliment_cute::int as compliment_cute,
  v:compliment_funny::int as compliment_funny,
  v:compliment_hot::int as compliment_hot,
  v:compliment_list::int as compliment_list,
  v:compliment_more::int as compliment_more,
  v:compliment_note::int as compliment_note,
  v:compliment_photos::int as compliment_photos,
  v:compliment_plain::int as compliment_plain,
  v:compliment_profile::int as compliment_profile,
  v:compliment_writer::int as compliment_writer,
  v:cool::int as cool,
  v:elite::string as elite, -- array of years
  v:fans::int as fans,
  v:friends::string as friends, -- array of user_ids
  v:name::string as name,
  v:review_count::int as review_count,
  v:useful::int as useful,
  v:yelping_since::datetime as yelping_since
from yelp_json where filename like '%user%';

/* *** YELP BUSINESSES *** */
-- Get sample data of a business
select v from yelp_json where filename like '%business%' limit 1;
select distinct v:attributes from yelp_json where filename like '%business%' limit 5;
select distinct v:is_open from yelp_json;

create or replace view yelp_businesses as
select
  v:business_id::string as business_id,
  v:address::string as address,
  v:attributes::string as attributes, -- dict of attributes
  v:categories::string as categories, -- array of categories
  v:city::string as city,
  v:hours::string as hours, -- dict of days and opening hours e.g. {"Friday": "9:0-17:0", ...}
  nullif(v:is_open, 'NULL')::int::boolean as is_open, -- is_open starts as a string, nullify 'NULL' and convert to int then boolean.
  v:latitude::float as latitude,
  v:longitude::float as longitude,
  v:name::string as name,
  v:postal_code::string as postal_code,
  v:review_count::int as review_count,
  v:stars::int as stars,
  v:state::string as state
from yelp_json where filename like '%business%';

/* *********************************************************************************** */
/* *** STAGING to ODS **************************************************************** */
/* *********************************************************************************** */

/* *** COVID19 *** */
-- Remove the view and then recreate as a table with an additional field "id".
drop view if exists covid19;
create or replace sequence seq start with 1 increment by 1;
create or replace table covid19
(
    id number default seq.nextval,
    business_id string,
    call_to_action_enabled boolean,
    covid_banner string,
    grubhub_enabled boolean,
    request_a_quote_enabled boolean,
    temporary_closed_until date,
    virtual_services_offered string,
    delivery_or_takeout string,
    highlights string
);

insert into covid19
with data as
(
    select
      v:business_id::string as business_id,
      v:"Call To Action enabled"::boolean as call_to_action_enabled,
      v:"Covid Banner"::string as covid_banner,
      v:"Grubhub enabled"::boolean as grubhub_enabled,
      v:"Request a Quote Enabled"::boolean as request_a_quote_enabled,
      nullif(v:"Temporary Closed Until"::string, 'FALSE')::date as temporary_closed_until,
      v:"Virtual Services Offered"::string as virtual_services_offered,
      v:"delivery or takeout"::string as delivery_or_takeout,
      v:highlights::string as highlights
    from covid19_json
)
select NULL, * from data;


-- /* *** YELP CATEGORIES *** */
-- Not needed. Expensive to run since select category_id needs to be done for each row.
-- create or replace sequence seq_categories start with 1 increment by 1;

-- create or replace table yelp_categories
-- (
--     category_id number default seq_categories.nextval,
--     name string
-- );

-- insert into yelp_categories (name)
-- with data as (
--     select
--         distinct(c.value::string) as name
--     from yelp_json y,
--         lateral flatten(input=>split(y.v:categories, ', ')) c
--     where filename like '%business%'
--     order by name
-- )
-- select distinct(name) as name from data
-- order by name;


/* *** YELP BUSINESS CATEGORIES *** */
create or replace view yelp_business_categories as
select
  v:business_id::string as business_id,
  c.value::string as category
from yelp_json y,
     lateral flatten(input=>split(y.v:categories, ', ')) c
where y.filename like '%business%';

/* Update YELP_BUSINESSES to remove categories */

create or replace view yelp_businesses as
select
  v:business_id::string as business_id,
  v:address::string as address,
  v:attributes::string as attributes, -- dict of attributes
  -- v:categories::string as categories, -- array of categories
  v:city::string as city,
  v:hours::string as hours, -- dict of days and opening hours e.g. {"Friday": "9:0-17:0", ...}
  nullif(v:is_open, 'NULL')::int::boolean as is_open, -- is_open starts as a string, nullify 'NULL' and convert to int then boolean.
  v:latitude::float as latitude,
  v:longitude::float as longitude,
  v:name::string as name,
  v:postal_code::string as postal_code,
  v:review_count::int as review_count,
  v:stars::int as stars,
  v:state::string as state
from yelp_json where filename like '%business%';

select distinct(stars) from public.yelp_reviews;

/* *********************************************************************************** */
/* *** SUMMARY TABLE ***************************************************************** */
/* *********************************************************************************** */
list @yelp;
list @covid19;
list @temperature;
list @precipitation;

create or replace table summary
(
    raw_file string,
    staging string,
    ods string,
    size integer
);
insert into summary
values ('s3://weather-and-restaurants/yelp/yelp_academic_dataset_user.json', 'yelp_users', 'yelp_users', 152898689),
       ('s3://weather-and-restaurants/yelp/yelp_academic_dataset_review.json', 'yelp_reviews', 'yelp_reviews', 449663480),
       ('s3://weather-and-restaurants/yelp/yelp_academic_dataset_business.json', 'yelp_business', 'yelp_business, yelp_business_categories', 6325565224),
       ('s3://weather-and-restaurants/yelp/yelp_academic_dataset_checkin.json', 'yelp_checkins', 'yelp_checkins', 263489322),
       ('s3://weather-and-restaurants/yelp/yelp_academic_dataset_tip.json', 'yelp_tips', 'yelp_tips', 3268069927),
       ('s3://weather-and-restaurants/covid-19/covid.json', 'covid19', 'covid19', 64835031),
       ('s3://weather-and-restaurants/temperature/USW00023169-temperature-degreeF.csv', 'temperatures', 'temperatures', 806846),
       ('s3://weather-and-restaurants/temperature/USW00023169-LAS_VEGAS_MCCARRAN_INTL_AP-precipitation-inch.csv', 'precipitations', 'precipitations', 521904);
select * from summary;
