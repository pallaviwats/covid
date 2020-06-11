global idi $iec/covid/idi_survey

/* use most recent data */
use $idi/round1/wb1_cleaned_dataset_2020-06-02, clear

/*********/
/* Setup */
/*********/

/* declare survey data */
svyset psu [pw=weight_hh], strata(strata_id) singleunit(scaled)

/* merge to shrug data */
merge m:1 shrid using $idi/survey_shrid_data, keep(match master) nogen
/* 70 obs with missing shrid didn't match */
/* 2 obs with shrid 11-10-244076 didn't match, not present in shrug data */

/* pc11 ids in the dataset are nonsensical drop them */
drop pc11*id 

/* merge using shrid to shrug-pc11 key to extract pc11 state and district ids*/
merge m:1 shrid using $shrug/keys/shrug_pc11_district_key, keep(match master) nogen 

/* note: pc11 ids are missing for the 70 obs in idi survey data with no shrid */
/* pc11 district ids are missing for additional 43 obs (bc shrug-pc11 key has missing pc11_district_ids) */

/* gen no weight condition for robustness check of results */
gen no_weight = 1

/***************************************************/
/* Note on sample options available:            */
/* 1. weight using weight_hh (included in dataset) */
/* 2. weight using no_weight                       */
/* 3. limit sample to Jharkhand and Rajasthan      */
/***************************************************/

/* generate earnings */
gen lab_march_earn = lab_march_wage * lab_march_freq
gen lab_curr_earn = lab_curr_wage * lab_curr_freq
gen lost_earn = lab_curr_earn - lab_march_earn
gen lab_earn_change = lost_earn/lab_march_earn

/* indicator for whether hh has at least one migrant */
gen mig = 1 if mig_size > 0 & !mi(mig_size)
replace mig = 0 if mig_size == 0 

/* migrants ratio */
gen mig_ratio = mig_total_ratio/demo_hh_size

/* label variables */
la var lab_march_earn "Pre-lockdown weekly earning"
la var lab_curr_earn "Post-lockdown weekly earning"
la var lab_earn_change "% change in weekly earnings"
label define gt 0 "No transfer" 1 "Received a govt transfer"
label values rel_govt_transfer_fa_prop gt
label define m 0 "No migrants in hh" 1 "At least one migrant in hh"
label values mig m

/* nrega */
label define n 0 "NREGA available" 1 "NREGA unavailable"
label values rel_nrega_unavail_prop n
la var rel_nrega_unavail_prop "NREGA availability"

/* non-agricultural households cannot be self-employed in ag, dropping them */
drop if lab_curr_occu == 1 & demo_ag_hh == 0
drop if lab_march_occu == 1 & demo_ag_hh == 0

/* not doing much with health - drop those vars */
drop hea*

/* save as tempfile */
save $tmp/idi_survey_clean, replace

/************/
/* Analysis */
/************/

cd $tmp
use $tmp/idi_survey_clean, clear

/* 1. Total earnings, wage and days worked loss */

/* graph change in wages conditional on positive wages + excluding extreme +ve outliers (beyond p99) */
sum lab_wagechange_mean
hist lab_wagechange_mean if lab_wagechange_mean < 1 & lab_curr_wage != 0, saving(lwc3) xtitle("Labor wage % change") bin(10) ylabel(0(1)6,grid) xlabel(-1(.2)1) normal xline(`r(mean)')

/* graph change in workdays conditional on positive workdays */
sum lab_workdayschange_mean
hist lab_workdayschange_mean if lab_curr_freq != 0, saving(ldc3) xtitle ("Labor workdays % change") bin(10) ylabel(0(1)6,grid) xlabel(-1(.2)1) normal xline(`r(mean)')

/* graph change in earnings excluding crazy positive outliers (beyond p99) */
sum lab_earn_change
hist lab_earn_change if lab_earn_change < 1, saving(lec3) xtitle("Labor earnings % change") bin(10) ylabel(0(1)6,grid) xlabel(-1(.2)1) normal xline(`r(mean)')

/* combine graphs to show distribution + decomposition */
graph combine "lwc3" "ldc3" "lec3", ycommon
graphout lmchanges

/* 2. Variation in earnings change by categories */

foreach i in wt nowt {

  if "`i'" == "wt" local weight weight_hh
  if "`i'" == "nowt" local weight no_weight
  
  /* by pre-lockdown occupation category */
  cibar lab_earn_change if lab_earn_change < 1 [aw = `weight'], over(lab_march_occu) barcolor(black sienna sand maroon) graphopts(ytitle("Labor earnings % change") ylabel(-1 (0.2) 0))
  graphout earn_worker_`i'

  /* by education categories, excluding don't know, no responses */
  cibar lab_earn_change if lab_earn_change < 1 & demo_edu > 0 [aw = `weight'], over(demo_edu) barcolor(black teal green olive sand) graphopts(ytitle("Labor earnings % change") ylabel(-1 (0.2) 0))
  graphout earn_edu_`i'

  /* by state  */
  cibar lab_earn_change if lab_earn_change < 1  [aw = `weight'] , over(geo_state) barcolor(black pink*0.4 blue*0.6 green*0.4) graphopts(ytitle("Labor earnings % change") ylabel(-1 (0.2) 0))
  graphout earn_state_`i'

  /* worst hit by state  */
  cibar lab_earn_change if lab_earn_change < -0.7 & lab_earn_change != -1  [aw = `weight'] , over(geo_state) barcolor(black pink*0.4 blue*0.6 green*0.4) graphopts(ytitle("Labor earnings % change < -0.7") ylabel(-1 (0.2) 0))
  graphout earn_state_bad`i'

  /* by whether/not the hh as at least one migrant member */
  cibar lab_earn_change if lab_earn_change < 1  [aw = `weight'] , over(mig) barcolor(black maroon) graphopts(ytitle("Labor earnings % change") ylabel(-1 (0.2) 0))
  graphout earn_mig_`i'

  /* variance in earnings change by state */
  graph hbar (semean) lab_earn_change if lab_earn_change < 1 [aw = `weight'], over(geo_state) ytitle("Standard error of mean - lab earnings change")
  graphout variance_`i'

}

/* 3. Agriculture */

foreach i in wt nowt {

  if "`i'" == "wt" local weight weight_hh
  if "`i'" == "nowt" local weight no_weight
  
  /* price by crop category */
  cibar agr_prc_change_holi_mean [aw = `weight'], over(agr_crop_cat_prop) barcolor(black sienna sand) graphopts(ytitle("Price changes since holi, by crop category") ylabel(-1 (0.2) 0))
  graphout prc_crop_`i'

  /* reasons for sales not starting */
  graph hbar (mean) agr_nosell_notready - agr_nosell_machine [aw = `weight'], ascategory
  graphout nosell_reason_`i'

  /* selling difficulties for ongoing sales + sales completed within last two weeks  */
  graph hbar (mean) agr_selldiff_none - agr_selldiff_police [aw = `weight'], ascategory
  graphout selldiff_reason_`i'

  /* changes in prices, borrowing, planned land, and inputs */
  graph bar agr*borrow*mean *land*mean *inputs*mean *prc*yr_mean *prc*holi_mean [aw = `weight'], ylabel(-0.10 (0.01) 0.06) 
  graphout achanges_`i'

}

/* selling status */
catplot agr_crop_status
graphout sell_status

/* crop category */
catplot agr_crop_cat_prop
graphout crop_cat

/* change in prices, input exp, planned land for kharif cultivation, and borrowing */

/* graph change in prices between this year and last year */
sum agr_prc_change_yr_mean
hist agr_prc_change_yr_mean, saving(ap3) xtitle("Ag price yr % change") bin(10) ylabel(0(1)6,grid) xlabel(-1(.5)3) normal xline(`r(mean)')

/* graph change in input expenditure between this and last year */
sum agr_inputs_change_abs_mean
hist agr_inputs_change_abs_mean, saving(ac3) xtitle ("Input expend. % change") bin(10) ylabel(0(1)6,grid) xlabel(-1(.5)3) normal xline(`r(mean)')

/* graph change in planned land for cultivation */
sum agr_land_change_mean
hist agr_land_change_mean, saving(al3) xtitle("Planned land % change") bin(10) ylabel(0(1)6,grid) xlabel(-1(.5)3) normal xline(`r(mean)')

/* graph change in borrowing */
sum agr_borrow_change_abs_mean
hist agr_borrow_change_abs_mean, saving(ab3) xtitle("Borrowed % change") bin(10) ylabel(0(1)6,grid) xlabel(-1(.5)3) normal xline(`r(mean)')

/* combine graphs to show distribution */
graph combine "ap3" "ac3" "al3" "ab3", ycommon
graphout achanges

/* 4. collapse dataset at district level */

collapse_save_labels
collapse (mean) lost_earn lab_earn_change lab_workdayschange_mean agr*holi_mean agr*yr_mean agr*abs_mean agr*change_mean tdist* pc11_pca* ec13* land* con_weekchange_mean mig_wage_change_mean mig_total_ratio [aw = weight_hh], by(pc11_state_id pc11_district_id)
collapse_apply_labels

/* save district level dataset */
save $tmp/idi_survey_clean_district, replace

/* change in earnings and land planned for planting change */
twoway lfitci agr_land_change_mean lab_earn_change if lab_earn_change < 1 & agr_land_change_mean < 1, xtitle("% change in weekly earnings") ytitle("% change in land planned for kharif") ylabel(-.8 (0.2) .8) xlabel(-1 (0.2) 1) yline(0)
graphout earn_land_wt

/* change in earnings and ag input exp */
twoway lfitci agr_inputs_change_abs_mean lab_earn_change if lab_earn_change < 1 & agr_land_change_mean < 1, xtitle("% change in weekly earnings") ytitle("% change in input expenditure") ylabel(-.8 (0.2) .8) xlabel(-1 (0.2) 1) yline(0)
graphout earn_input_wt

/* change in earnings and change in consumption */
twoway lfitci con_weekchange_mean lab_earn_change if lab_earn_change < 1, xtitle("% change in weekly earnings") ytitle("% change in consumption") ylabel(-.8 (0.2) .8) xlabel(-1 (0.2) 1) yline(0)
graphout earn_con_wt

/* change in weekly earning and distance */
twoway lfitci lab_earn_change tdist_100 if lab_earn_change < 1, ytitle("% change in weekly earnings") xtitle("Distance to nearest place with pop > 100k") ylabel(-1 (0.2) 0) yline(0) xlabel(0 (10) 90)
graphout earn_dist_wt

/* change in weekly earning and employment per capita */
twoway lfitci lab_earn_change ec13* if lab_earn_change < 1, ytitle("% change in weekly earnings") xtitle("Non-farm jobs per capita") ylabel(-1 (0.2) 0) yline(0) 
graphout earn_emp


