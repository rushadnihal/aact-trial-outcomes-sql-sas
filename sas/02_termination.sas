/* =====================================================================
   02_termination.sas
   Purpose : What predicts early termination? Logistic regression of
             TERMINATED vs COMPLETED among interventional Phase 2/3 drug
             trials, with sponsor-clustered standard errors, plus
             sensitivity analyses (earlier start years; withdrawn trials
             counted as early stops).
   Inputs  : aact.term, aact.term_sens (from 01_prepare.sas)
   Outputs : output/termination_forest.png, output/termination_roc.png,
             output/termination_odds_ratios.csv
   Snapshot: AACT 2026-11-15
   Notes   : Reference level of each class variable = its most frequent
             level (ref=first with order=freq). Enrollment is excluded on
             purpose: it is the actual count after the outcome occurs.
             Results are associations, not causal effects.
   ===================================================================== */

%let root = /home/&sysuserid./aact;
libname aact "&root.";
ods listing gpath="&root./output";
ods graphics on / reset width=7in imagefmt=png;

%let classvars = sponsor_class phase start_period allocation intervention_model
                 primary_purpose masking us_site gender;
%let numvars   = n_arms_cap n_primary_cap n_interv_cap log_countries
                 has_biological has_other_type
                 area_oncology area_cns area_cardiovascular area_infectious
                 area_metabolic area_respiratory area_immune;

/* ---- descriptive: termination rate by key factors ---- */
proc freq data=aact.term;
  tables (sponsor_class phase start_period)*terminated_flag / nocol nopercent;
run;

/* ---- main model: sponsor-clustered (robust) standard errors ---- */
%macro fit(data=, where=1, outcome=terminated_flag, tag=);
  proc surveylogistic data=&data.(where=(&where.));
    class &classvars. / param=ref ref=first order=freq;
    cluster sponsor_name;
    model &outcome.(event='1') = &classvars. &numvars.;
    ods output OddsRatios=work.or_&tag.;
  run;
%mend fit;

%fit(data=aact.term,      tag=main);
%fit(data=aact.term,      where=start_year<=2018, tag=early);
%fit(data=aact.term_sens, outcome=any_stop_flag,  tag=withdrawn);

/* ---- discrimination and calibration of the main model (naive SEs) ---- */
ods graphics / imagename="termination_roc";
proc logistic data=aact.term plots(only)=roc;
  class &classvars. / param=ref ref=first order=freq;
  model terminated_flag(event='1') = &classvars. &numvars. / lackfit rsquare;
run;

/* ---- forest plot of the main model ---- */
ods graphics / imagename="termination_forest";
proc sgplot data=work.or_main noautolegend;
  scatter y=Effect x=OddsRatioEst / xerrorlower=LowerCL xerrorupper=UpperCL
          markerattrs=(symbol=circlefilled size=7);
  refline 1 / axis=x;
  xaxis type=log label="Odds ratio of early termination (95% CI, sponsor-clustered)";
  yaxis discreteorder=data reverse display=(nolabel);
run;

/* ---- all analyses in one table, saved for the README ---- */
data work.or_all;
  length analysis $24;
  set work.or_main(in=a) work.or_early(in=b) work.or_withdrawn(in=c);
  if a then analysis = 'Main';
  else if b then analysis = 'Start year <= 2018';
  else if c then analysis = 'Withdrawn counted';
run;

proc print data=work.or_all noobs;
  var analysis Effect OddsRatioEst LowerCL UpperCL;
run;

proc export data=work.or_all
  outfile="&root./output/termination_odds_ratios.csv" dbms=csv replace;
run;
