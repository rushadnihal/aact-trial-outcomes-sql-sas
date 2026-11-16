/* =====================================================================
   03b_ph_check.sas   (optional, slow)
   Purpose : Proportional-hazards check for the Cox model in 03_reporting.sas,
             on a 25% random sample of likely-applicable trials (resampling
             on the full data exhausts SAS OnDemand work space and time).
   Run     : separately, after 03_reporting.sas has finished.
   ===================================================================== */

%let root = /home/&sysuserid./aact;
libname aact "&root.";
ods graphics on / reset width=7in imagefmt=png;
%let classvars = sponsor_class phase start_period allocation masking primary_purpose;
%let numvars   = terminated_flag n_arms_cap n_primary_cap log_countries has_biological
                 area_oncology area_cns area_cardiovascular area_infectious
                 area_metabolic area_respiratory area_immune;

/* proportional hazards check (no clustering, to keep the resampling valid) */
data work.rep_ph;
  set aact.rep(where=(likely_applicable=1));
  if ranuni(2026) < 0.25;
run;
proc phreg data=work.rep_ph;
  class &classvars. / param=ref ref=first order=freq;
  model time_days*event(0) = &classvars. &numvars. / ties=efron;
  assess ph / resample=50 npaths=10 seed=2026;
run;
