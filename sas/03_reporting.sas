/* =====================================================================
   03_reporting.sas
   Purpose : Time from primary completion to first results SUBMISSION.
             Kaplan-Meier curves (as cumulative submission), Cox models
             with sponsor-clustered robust variance, and a logistic model
             for late reporting (> 12 months or never).
   Inputs  : aact.rep (from 01_prepare.sas)
   Outputs : output/km_submission_by_class.png, output/km_submission_by_period.png,
             output/cox_hazard_ratios.csv, output/late_odds_ratios.csv
   Snapshot: AACT 2026-11-15
   Notes   : Event = results submitted by the snapshot; trials without a
             submission are censored at the snapshot date. Main analysis
             uses trials flagged likely_applicable (US facility, not marked
             non-FDA-regulated); the all-trials model is a comparison.
             Associations, not causal effects.
   ===================================================================== */

%let root = /home/&sysuserid./aact;
libname aact "&root.";
ods listing gpath="&root./output";
ods graphics on / reset width=7in imagefmt=png;

/* us_site is constant (Yes) in the likely-applicable subset, so it enters only the all-trials model */
%let classvars = sponsor_class phase start_period allocation masking primary_purpose;
%let numvars   = terminated_flag n_arms_cap n_primary_cap log_countries has_biological
                 area_oncology area_cns area_cardiovascular area_infectious
                 area_metabolic area_respiratory area_immune;

/* ---- descriptive ---- */
proc freq data=aact.rep;
  tables likely_applicable*event / nocol nopercent;
  tables sponsor_class*late_12m / nocol nopercent;
run;

/* ---- Kaplan-Meier: cumulative submission among likely-applicable trials ---- */
ods graphics / imagename="km_submission_by_class";
proc lifetest data=aact.rep(where=(likely_applicable=1))
              plots=survival(failure) timelist=365 730 1095;
  time time_days*event(0);
  strata sponsor_class / test=logrank;
run;

ods graphics / imagename="km_submission_by_period";
proc lifetest data=aact.rep(where=(likely_applicable=1))
              plots=survival(failure) timelist=365 730 1095;
  time time_days*event(0);
  strata start_period / test=logrank;
run;

/* ---- Cox model, sponsor-clustered robust variance ---- */
proc phreg data=aact.rep(where=(likely_applicable=1)) covs(aggregate);
  class &classvars. / param=ref ref=first order=freq;
  model time_days*event(0) = &classvars. &numvars. / ties=efron risklimits;
  id sponsor_name;
  ods output ParameterEstimates=work.cox_main;
run;

/* comparison: all trials, with the applicability flag as a covariate */
proc phreg data=aact.rep covs(aggregate);
  class &classvars. us_site / param=ref ref=first order=freq;
  model time_days*event(0) = &classvars. us_site &numvars. likely_applicable / ties=efron risklimits;
  id sponsor_name;
  ods output ParameterEstimates=work.cox_all;
run;

/* ---- late reporting (more than 12 months or never), >= 12 months follow-up ---- */
proc surveylogistic data=aact.rep(where=(likely_applicable=1 and eligible_12m=1));
  class &classvars. / param=ref ref=first order=freq;
  cluster sponsor_name;
  model late_12m(event='1') = &classvars. &numvars.;
  ods output OddsRatios=work.late_or;
run;

/* ---- save tables for the README ---- */
data work.cox_both;
  length analysis $32;
  set work.cox_main(in=a) work.cox_all(in=b);
  if a then analysis = 'Likely applicable'; else analysis = 'All trials';
run;

proc export data=work.cox_both
  outfile="&root./output/cox_hazard_ratios.csv" dbms=csv replace;
run;

proc export data=work.late_or
  outfile="&root./output/late_odds_ratios.csv" dbms=csv replace;
run;
