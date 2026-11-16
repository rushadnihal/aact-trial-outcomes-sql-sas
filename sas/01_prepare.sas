/* =====================================================================
   01_prepare.sas
   Purpose : Import the CSV exports from sql/05 and build the SAS analysis
             datasets used by 02_termination.sas and 03_reporting.sas.
   Inputs  : model_termination.csv, model_termination_sens.csv,
             model_reporting.csv  (upload them to the folder in &root)
   Outputs : aact.term, aact.term_sens, aact.rep  (permanent datasets)
   Snapshot: AACT 2026-11-15
   Run     : SAS Studio (SAS OnDemand for Academics), Run > all.
   Config  : only &root below. Upload the CSV files there first.
   ===================================================================== */

%let root = /home/&sysuserid./aact;      /* folder holding the uploaded CSV files */
libname aact "&root.";

options dlcreatedir;
libname outdir "&root./output";           /* creates the output folder if needed */
libname outdir clear;

%macro import_csv(file=, out=);
  proc import datafile="&root./&file..csv" out=&out. dbms=csv replace;
    guessingrows=max;
    getnames=yes;
  run;
%mend import_csv;

%import_csv(file=model_termination,      out=work.term_raw);
%import_csv(file=model_termination_sens, out=work.sens_raw);
%import_csv(file=model_reporting,        out=work.rep_raw);

/* ---- shared recoding for the termination datasets ---- */
%macro prep_term(in=, out=);
  data &out.;
    length allocation intervention_model primary_purpose masking gender
           healthy_volunteers $32 us_site $8 start_period $9;
    set &in.;
    format _character_;                 /* clear imported display formats ($6. etc. truncated labels) */
    array cat{*} allocation intervention_model primary_purpose masking
                 gender healthy_volunteers;
    do i = 1 to dim(cat);
      if missing(cat{i}) then cat{i} = 'MISSING';
    end;
    drop i;

    /* 12 trials have missing sex eligibility and none was terminated (quasi-complete
       separation, odds ratio not estimable); treated as 'ALL' (no sex restriction recorded) */
    if gender = 'MISSING' then gender = 'ALL';

    if      has_us_facility = 1 then us_site = 'Yes';
    else if has_us_facility = 0 then us_site = 'No';
    else                             us_site = 'Unknown';

    if      start_year <= 2011 then start_period = '2008-2011';
    else if start_year <= 2015 then start_period = '2012-2015';
    else if start_year <= 2019 then start_period = '2016-2019';
    else                            start_period = '2020-2022';

    /* capped counts limit the leverage of a few extreme trials */
    n_arms_cap    = min(n_arms, 6);
    n_primary_cap = min(n_primary_outcomes, 5);
    n_interv_cap  = min(n_interventions, 5);
    log_countries = log(1 + n_countries);
  run;
%mend prep_term;

%prep_term(in=work.term_raw, out=aact.term);
%prep_term(in=work.sens_raw, out=aact.term_sens);

/* ---- reporting dataset ---- */
data aact.rep;
  length allocation masking primary_purpose $32 us_site fda_reg $8 start_period $9;
  set work.rep_raw;
  format _character_;                   /* clear imported display formats */
  array cat{*} allocation masking primary_purpose;
  do i = 1 to dim(cat);
    if missing(cat{i}) then cat{i} = 'MISSING';
  end;
  drop i;

  if      has_us_facility = 1 then us_site = 'Yes';
  else if has_us_facility = 0 then us_site = 'No';
  else                             us_site = 'Unknown';

  if      is_fda_regulated_drug = 1 then fda_reg = 'Yes';
  else if is_fda_regulated_drug = 0 then fda_reg = 'No';
  else                                   fda_reg = 'Unknown';

  if      start_year <= 2011 then start_period = '2008-2011';
  else if start_year <= 2015 then start_period = '2012-2015';
  else if start_year <= 2019 then start_period = '2016-2019';
  else                            start_period = '2020-2022';

  n_arms_cap    = min(n_arms, 6);
  n_primary_cap = min(n_primary_outcomes, 5);
  log_countries = log(1 + n_countries);
run;

/* ---- checks: row counts and levels (compare with logs/05.log) ---- */
proc sql;
  select 'aact.term'      as dataset, count(*) as n, sum(terminated_flag) as events from aact.term
  union all
  select 'aact.term_sens', count(*), sum(any_stop_flag) from aact.term_sens
  union all
  select 'aact.rep',       count(*), sum(event) from aact.rep;
quit;

proc freq data=aact.term;
  tables sponsor_class phase start_period allocation intervention_model
         primary_purpose masking us_site gender / missing nocum;
run;

proc means data=aact.term n nmiss min median max;
  var n_arms n_primary_outcomes n_interventions n_countries min_age_years;
run;
