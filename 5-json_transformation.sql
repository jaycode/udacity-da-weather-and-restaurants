/* LATERAL and FLATTEN are used to transform lists into multiple rows.
 * Both code blocks below are taken from 4-staging_to_ods.sql for the
 * reviewing purpose.
 */

create or replace view yelp_checkins as
select
  v:business_id::string as business_id,
  c.value::datetime as datetime
from yelp_json y,
     lateral flatten(input=>split(y.v:date, ', ')) c
where y.filename like '%checkin%';

--

create or replace view yelp_business_categories as
select
  v:business_id::string as business_id,
  c.value::string as category
from yelp_json y,
     lateral flatten(input=>split(y.v:categories, ', ')) c
where y.filename like '%business%';
