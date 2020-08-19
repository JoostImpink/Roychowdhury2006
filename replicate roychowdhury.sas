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
- The sample size is much larger (64,257 observations vs 21,758 in the paper; I can reduce it to 37,768 when filtering on exchanges)
- Coefficients for models 1-3 in table 2 are (somewhat) similar (but much less significant compared to paper) 
- Coefficient for model 4 (accruals) in table 2 are very different

*/

rsubmit;endrsubmit;
%let wrds = wrds-cloud.wharton.upenn.edu 4016;options comamid = TCP remote=WRDS;signon username=_prompt_;

rsubmit;

/* Key variables */
proc sql;
	create table a_comp as
	select gvkey, datadate, fyear, sich, sale, at, xsga, xrd, xad, cogs, invt, oancf, ib, ppegt, exchg, 
	prcc_f * csho as mcap, calculated mcap / ceq as mtb, log(calculated mcap) as size
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
%let keyVars = one_at sale_ch_at sale_ch2_at sale_lag_at sale_at ppe_at accruals_at prod_at disexp_at cfo_at mcap mtb size;

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

/* net income scaled by lagged assets */
ni = ib / at_lag;

/* indicator, 1 if ib / lagged assets is between 0 and 0.005 */
SUSPECT_NI = (  0 <= ni <= 0.005  );

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

/* main exchanges (not mentioned in paper, but brings sample size more in line with #obs in paper)*/
if exchg in (11,12,14);
run;

/*	winsorize */
filename mwins url 'http://www.wrds.us/winsorize.sas';
%include mwins;

/* winsorize &keyVars */
%winsor(dsetin=c_comp2, dsetout=c_comp2_wins, vars=&keyVars, type=winsor, pctl=1 99);

/* keep 15 obs per industry-year (35,342 obs remain)*/
proc sql;
	create table d_15obs as
	select * from c_comp2_wins
	group by sic2, fyear
	/* at least 15 obs in each sic2-fyear*/
	having count(*) >= 15;
quit;

/* Calculate relative net income (ni_rel) as net income (ni) minus industry-year mean */
proc sql;
	create table e_main as 
	select *, 
	/* take ni and subtract the mean net income (calculated for each sic2-fyear) */
	ni - mean(ni) as ni_rel
	from d_15obs 
	group by sic2, fyear;
quit;


/* 5,245 unique gvkeys vs 4,252 mentioned in the paper */
proc sql; create table gvkey as select distinct gvkey from e_main; quit;

/* 38 unique industries vs 36 mentioned in the paper */
proc sql; create table sic2 as select distinct sic2 from e_main; quit;

/* 474 unique industry-years vs 416 mentioned in the paper (table 2 footnote) */
proc sql; create table sic2_yrs as select distinct sic2, fyear from e_main; quit;

/* some descriptives, these are similar as those in paper 
	Median market cap: 154.6 vs 137.3 inpaper
	Median assets: 150.8 vs 137.3 in paper
	Median sales: 166.4 vs 221.0 in paper
	Median CFO: 0.088 vs 0.082 in paper
	Median Production costs: 0.750 vs 0.788 in paper	
*/
proc means data=e_main n mean median;  var mcap at sale oancf ib ni cfo_at disexp_at prod_at accruals_at; run;

/* 	Table 2 
	-------	

	Four models: cfo, disexp, prod, accruals
	Regressions by industry-year: table presents mean and t-values (mean/standard deviation) 

	Some of the coefficients are similar, but overall not significant (i.e., higher standard errors)

	I may have overlooked something.
*/

/* First regression: cfo */

proc sort data=e_main; by fyear sic2;run;

proc reg data=e_main noprint edf outest=e_parms_cfo; 
model cfo_at = one_at sale_at sale_ch_at ; 
output out=f_fitted1  p=yhat r=yresid ; 
by fyear sic2;
run;

/* 	sale_at: 0.0476839 vs 0.0516 in paper, bot not significant (paper: t-value 12.8)
	sale_ch_at: 0.0120487 vs 0.0173 in paper
*/
proc means data=e_parms_cfo n mean stddev;
  var Intercept one_at sale_at sale_ch_at _RMSE_; 
run;


/* Second regression: disexp */

proc reg data=e_main noprint edf outest=e_parms_disexp; 
model disexp_at = one_at sale_lag_at ; 
output out=f_fitted2  p=yhat r=yresid ;
by fyear sic2;
run;

/* 	sale_lag_at is 0.1356134, vs 0.1596 in paper, but not significant (paper: t-value 18)
	by the way: not clear if there is a typo in the paper, St listed twice, assuming second one should be St-1
*/
proc means data=e_parms_disexp  n mean stddev;
  var Intercept one_at sale_lag_at _RMSE_; 
run;


/* Third regression: prod */

proc reg data=e_main noprint edf outest=e_parms_prod; 
model prod_at = one_at sale_at sale_ch_at sale_ch2_at ; 
output out=f_fitted3  p=yhat r=yresid ;
by fyear sic2;
run;

/*	sale_at: 0.7992878 vs 0.7874 in paper, t-value about 6 vs 109 in paper
	sale_ch_at: -0.0203214 vs 0.0404 in paper
	sale_ch2_at: -0.0489919 vs -0.0147 in paper*/

proc means data=e_parms_prod  n mean stddev;
  var Intercept one_at sale_at sale_ch_at sale_ch2_at _RMSE_; 
run;


/* Fourth regression: accruals */

proc reg data=e_main noprint edf outest=e_parms_accr; 
model prod_at = one_at sale_ch_at ppe_at ; 
output out=f_fitted4  p=yhat r=yresid ;
by fyear sic2;
run;

/* 	sale_ch_at: 0.9629538 vs 0.0490 in paper
	ppe_at: 0.1092990 vs -0.060 in paper */

proc means data=e_parms_accr n mean stddev;
  var Intercept one_at sale_ch_at ppe_at _RMSE_; 
run;


/* 	Table 4
	-------
	
	Regressions of abnormal cfo, abnormal discretionary exp and abnormal prod costs
	on size, mtb, net income, and suspect_ni 

	The paper presents Fama McBeth regressions (yearly regressions); below I have pooled regressions
*/

/*

Abnormal CFO:

Intercept 	-0.04694 	0.00213 	-22.05 	<.0001 
size   		0.00871 	0.00039472 	22.06 	<.0001 
mtb   		0.00072744 	0.00021366 	3.40 	0.0007 
ni   		0.00020496 	0.00004853 	4.22 	<.0001 
SUSPECT_NI  -0.01856 	0.00540 	-3.44 	0.0006  <<< in line
*/

/* yresid in f_fitted1 has the abnormal cash flow from operations */
proc reg data=f_fitted1 ;  
model yresid = size mtb ni suspect_NI; 
run;

/*
Abnormal discretionary expenses 

Intercept 	-0.08060 	0.00447 	-18.03 	<.0001 
size   		0.00645 	0.00082902 	7.78 	<.0001 
mtb   		0.01609 	0.00044874 	35.87 	<.0001 
ni   		-0.00060751 0.00010193 	-5.96 	<.0001 
SUSPECT_NI  -0.03273 	0.01135 	-2.88 	0.0039 <<< in line
*/

/* yresid in f_fitted2 has the abnormal discretionary expenses */
proc reg data=f_fitted2 ;  
model yresid = size mtb ni suspect_NI; 
run;


/*
Abnormal production costs

Intercept 	0.06387 	0.00347 	18.39 	<.0001 
size   		-0.00720 	0.00064402 	-11.18 	<.0001 
mtb   		-0.00918 	0.00034860 	-26.32 	<.0001 
ni   		-0.00006812 0.00007918 	-0.86 	0.3896 
SUSPECT_NI  0.03331 	0.00881 	3.78 	0.0002 <<< in line

*/

/* yresid in f_fitted3 has the abnormal production costs */
proc reg data=f_fitted3 ;  
model yresid = size mtb ni suspect_NI; 
run;


/* 	Yearly regressions (Fama McBeth) 
	-------------------------------
*/

/* CFO */
proc sort data=f_fitted1; by fyear;

proc reg data=f_fitted1 noprint edf outest=g_parms_cfo; 
model yresid = size mtb ni suspect_NI; 
by fyear;
run;

/* 	suspect_NI: -0.0194284 vs -0.020 in paper 
	stdev is 0.014, so not significant (paper: t-value of 3.0)*/

proc means data=g_parms_cfo n mean stddev;
  var Intercept size mtb ni suspect_NI _RMSE_; 
run;

/* Discretionary expenses */
proc sort data=f_fitted2; by fyear;

proc reg data=f_fitted2 noprint edf outest=g_parms_de; 
model yresid = size mtb ni suspect_NI; 
by fyear;
run;

/* 	suspect_NI: -0.0346076 vs -0.0591 in paper 
	stdev is 0.0330075, so not significant (paper: t-value of 4.3)*/

proc means data=g_parms_de n mean stddev;
  var Intercept size mtb ni suspect_NI _RMSE_; 
run;


/* Production costs */
proc sort data=f_fitted3; by fyear;

proc reg data=f_fitted3 noprint edf outest=g_parms_prod; 
model yresid = size mtb ni suspect_NI; 
by fyear;
run;

/* 	suspect_NI: 0.0354075 vs 0.0497 in paper 
	stdev is 0.0253694, so not significant (paper: t-value of 5.0)*/

proc means data=g_parms_prod n mean stddev;
  var Intercept size mtb ni suspect_NI _RMSE_; 
run;
