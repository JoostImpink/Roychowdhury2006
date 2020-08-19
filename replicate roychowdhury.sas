/* 

Attempt to replicate: 

Sugata Roychowdhury, 2006. Earnings management through real activities manipulation.
Journal of Accounting and Economics (42) pp. 350-370

Section 4.1 on page 343 describes sample selection:
- all firms in Compustat between 1987 and 2001
- dropping regulated firms (drop between 4400 and 5000, and between 6000 and 6500)
- at least 15 observations for each 2-digit SIC-fyear
- data availability to construct variables

"Imposing all the data-availability requirements yields 21,758 firm-years over the
period 1987–2001, including 36 industries and 4,252 individual firms."

Issues replcating
-----------------
- The sample size is much larger (64,257 observations vs 21,758 in the paper)
- Coefficients for models 1-3 in table 2 are (somewhat) similar (but much less significant compared to paper) 
- Coefficient for model 4 (accruals) in table 2 are very different

*/

rsubmit;endrsubmit;
%let wrds = wrds-cloud.wharton.upenn.edu 4016;options comamid = TCP remote=WRDS;signon username=_prompt_;

rsubmit;

/* Key variables */
proc sql;
	create table a_comp as
	select gvkey, datadate, fyear, sich, sale, at, xsga, xrd, xad, cogs, invt, oancf, ib, ppegt, prcc_f * csho as mcap, exchg
	from comp.funda 
	where 1987 <= fyear <= 2001		
	and indfmt='INDL' and datafmt='STD' and popsrc='D' and consol='C'; 
quit;

/* lagged values for assets (at), sales (sale), inventory (invt), ppe (ppegt)*/
proc sql;
	create table b_comp as 
	select a.*, b.at as at_lag, b.sale as sale_lag, b.invt as invt_lag, b.ppegt as ppegt_lag
	from a_comp a, comp.funda b
	where a.gvkey = b.gvkey and a.fyear - 1 = b.fyear 
	and b.indfmt='INDL' and b.datafmt='STD' and b.popsrc='D' and b.consol='C'; 
quit;

/* 2-year lagged sales (needed for lagged change in sales) */
proc sql;
	create table b_comp2 as 
	select a.*, b.sale as sale_lag2
	from b_comp a, comp.funda b
	where a.gvkey = b.gvkey and a.fyear - 2 = b.fyear 
	and b.indfmt='INDL' and b.datafmt='STD' and b.popsrc='D' and b.consol='C'; 
quit;

/* header SIC (from comp.company) */
proc sql;
	create table c_comp as select a.*, b.sic from b_comp2 a, comp.company b where a.gvkey = b.gvkey;
quit;

proc download data=c_comp out = c_comp;run;

endrsubmit;

/* key variables to be winsorized; also used to drop observations that have a missing value for any of these */
%let keyVars = one_at sale_ch_at sale_ch2_at sale_lag_at sale_at ppe_at accruals_at prod_at disexp_at cfo_at mcap;

/* create main variables */
data c_comp2;
set c_comp;
/* missing R&D or advertising replace with 0 */
if xrd eq . then xrd = 0;
if xad eq . then xad = 0;

/* drop SIC 4400-5000, 6000-6500 */
if sic >= 4400 and sic <5000 then delete;
if sic >= 6000 and sic <6500 then delete;

/* 2-digit SIC */
sic2 = floor(sic/100);

/* require positive lagged assets (used as scalar) */
if at_lag > 0;

/* change in sales (and change in lagged sales)*/
sale_ch = sale - sale_lag;
sale_ch2 = sale_lag - sale_lag2;

/* dependent variables, all scaled by lagged assets */
cfo_at = oancf / at_lag;
disexp_at = (xrd + xad + xsga) / at_lag;
prod_at = (cogs + invt - invt_lag ) / at_lag;
accruals_at = (ib - oancf) / at_lag;

/* control variables */
ppe_at = ppegt_lag / at_lag;
sale_at = sale / at_lag;
sale_lag_at = sale_lag / at_lag;
sale_ch_at = sale_ch / at_lag;
sale_ch2_at = sale_ch2 / at_lag;
one_at = 1 / at_lag;

/* key variables may not be missing (cmiss function counts missing values of a list of variables)*/
if cmiss (of &keyVars) eq 0;
run;

/*	winsorize */
filename mwins url 'http://www.wrds.us/winsorize.sas';
%include mwins;
%winsor(dsetin=c_comp2, dsetout=c_comp2_wins, vars=&keyVars, type=winsor, pctl=1 99);

/* not in paper: keep obs on main exchanges
	reduces sample size from 65,794 to 37,768
*/
data d_main;
set c_comp2_wins;
if exchg in (11,12,14);
run;

/* keep 15 obs per industry-year (35,342 obs remain)*/
proc sql;
	create table d_15obs as
	select * from d_main
	group by sic2, fyear
	/* at least 15 obs in each sic2-fyear*/
	having count(*) >= 15;
quit;


/* 5,245 unique gvkeys vs 4,252 mentioned in the paper */
proc sql; create table gvkey as select distinct gvkey from d_15obs; quit;

/* 38 unique industries vs 36 mentioned in the paper */
proc sql; create table sic2 as select distinct sic2 from d_15obs; quit;

/* 474 unique industry-years vs 416 mentioned in the paper (table 2 footnote) */
proc sql; create table sic2_yrs as select distinct sic2, fyear from d_15obs; quit;

/* some descriptives, these are similar as those in paper 
	Median market cap: 154.6 vs 137.3 inpaper
	Median assets: 150.8 vs 137.3 in paper
	Median sales: 166.4 vs 221.0 in paper
	Median CFO: 0.088 vs 0.082 in paper
	Median Production costs: 0.750 vs 0.788 in paper	
*/
proc means data=d_15obs n mean median;  var mcap at sale oancf ib cfo_at disexp_at prod_at accruals_at; run;

/* 	Attempt to replicate table 2 
	----------------------------

	Four models: cfo, disexp, prod, accruals
	Regressions by industry-year: table presents mean and t-values (mean/standard deviation) 

	Some of the coefficients are similar, but overall not significant (i.e., higher standard errors)

	I may have overlooked something.
*/

/* First regression: cfo */

proc sort data=d_15obs; by fyear sic2;run;

proc reg data=d_15obs noprint edf outest=e_parms_cfo; 
model cfo_at = one_at sale_at sale_ch_at ; 
output out=f_fitted1  p=yhat r=yresid ; 
by fyear sic2;
run;

/* 	sale_at: 0.0485591 vs 0.0516 in paper, bot not significant (paper: t-value 12.8)
	sale_ch_at: 0.0081310 vs 0.0173 in paper
*/
proc means data=e_parms_cfo n mean stddev;
  var Intercept one_at sale_at sale_ch_at _RMSE_; 
run;


/* Second regression: disexp */

proc reg data=d_15obs noprint edf outest=e_parms_disexp; 
model disexp_at = one_at sale_lag_at ; 
output out=f_fitted2  p=yhat r=yresid ;
by fyear sic2;
run;

/* 	sale_lag_at is 0.1355628, vs 0.1596 in paper, but not significant (paper: t-value 18)
	by the way: not clear if there is a typo in the paper, St listed twice, assuming second one should be St-1
*/
proc means data=e_parms_disexp (where = (_EDF_ >= 12) ) n mean stddev;
  var Intercept one_at sale_lag_at _RMSE_; 
run;


/* Third regression: prod */

proc reg data=d_15obs noprint edf outest=e_parms_prod; 
model prod_at = one_at sale_at sale_ch_at sale_ch2_at ; 
output out=f_fitted3  p=yhat r=yresid ;
by fyear sic2;
run;

/*	sale_at: 0.7986351 vs 0.7874 in paper, t-value about 6 vs 109 in paper
	sale_ch_at: -0.0204092 vs 0.0404 in paper
	sale_ch2_at: -0.0471120 vs -0.0147 in paper*/

proc means data=e_parms_prod  n mean stddev;
  var Intercept one_at sale_at sale_ch_at sale_ch2_at _RMSE_; 
run;


/* Fourth regression: accruals */

proc reg data=d_15obs noprint edf outest=e_parms_accr; 
model prod_at = one_at sale_ch_at ppe_at ; 
output out=f_fitted4  p=yhat r=yresid ;
by fyear sic2;
run;

/* 	sale_ch_at: 0.9283935 vs 0.0490 in paper
	ppe_at: 0.1036949 vs -0.060 in paper */

proc means data=e_parms_accr n mean stddev;
  var Intercept one_at sale_ch_at ppe_at _RMSE_; 
run;
