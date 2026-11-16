/* =====================================================================
   03b_ph_check.sas
   Purpose : Proportional-hazards check for the Cox model in 03_reporting.sas.
             Resampling-based ASSESS PH is too heavy for SAS OnDemand, so the
             same model is fitted separately for the first 365 days after
             primary completion and for the period after 365 days (entry at
             365). Similar hazard ratios in both windows support PH.
   Inputs  : aact.rep (from 01_prepare.sas)
   Outputs : output/cox_hr_by_window.csv
   Snapshot: AACT 2026-11-15
   ===================================================================== */

%let root = /home/&sysuserid./aact;
libname aact "&root.";

%let classvars = sponsor_class phase start_period allocation masking primary_purpose;
%let numvars   = terminated_flag n_arms_cap n_primary_cap log_countries has_biological
                 area_oncology area_cns area_cardiovascular area_infectious
                 area_metabolic area_respiratory area_immune;

/* Window 1: first 365 days; later events are censored at 365 */
data work.w1;
  set aact.rep(where=(likely_applicable=1));
  t = min(time_days, 365);
  e = (event = 1 and time_days <= 365);
run;

/* Window 2: trials still without a submission after 365 days; entry at 365 */
data work.w2;
  set aact.rep(where=(likely_applicable=1 and time_days > 365));
  t0 = 365;
run;

proc phreg data=work.w1;
  class &classvars. / param=ref ref=first order=freq;
  model t*e(0) = &classvars. &numvars. / ties=efron risklimits;
  ods output ParameterEstimates=work.hr_w1;
run;

proc phreg data=work.w2;
  class &classvars. / param=ref ref=first order=freq;
  model (t0, time_days)*event(0) = &classvars. &numvars. / ties=efron risklimits;
  ods output ParameterEstimates=work.hr_w2;
run;

data work.hr_windows;
  length window $24;
  set work.hr_w1(in=a) work.hr_w2(in=b);
  if a then window = '0-365 days'; else window = 'after 365 days';
run;

proc export data=work.hr_windows
  outfile="&root./output/cox_hr_by_window.csv" dbms=csv replace;
run;
