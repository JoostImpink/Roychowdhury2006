/*cfo */

proc sort data=e_main; by fyear sic2;run;

proc reg data=e_main noprint edf outest=e_parms_cfo; 
model cfo_at = one_at sale_at sale_ch_at ; 
output out=fit_cfo  p=yhat r=abn_cfo ; 
by fyear sic2;
run;

data z;
set fit_cfo;
if gvkey eq "160362";
if fyear eq 2015;
run;

data z2;
set fit_cfo;
if sic2 eq 1;
if fyear eq 2015;run;

proc sort data=z2; by gvkey;run;

gvkey: 
data z5;
set c_comp;
if gvkey eq "187285";
run;

/* prod */

proc reg data=e_main noprint edf outest=e_parms_prod; 
model prod_at = one_at sale_at sale_ch_at sale_ch2_at ; 
output out=fit_prod  p=yhat r=abn_prod ;
by fyear sic2;
run;


/* discretionary expenses */

proc reg data=e_main noprint edf outest=e_parms_disexp; 
model disexp_at = one_at sale_lag_at ; 
output out=fit_disexp  p=yhat r=abn_disexp ;
by fyear sic2;
run;

/* combine */
proc sql;
	create table h_sample as select a.*, b.abn_prod, c.abn_disexp
	from fit_cfo a, fit_prod b, fit_disexp c
	where a.gvkey = b.gvkey
	and b.gvkey = c.gvkey
	and a.fyear = b.fyear
	and b.fyear = c.fyear;
quit;

/* flip signs of abnormal cfo and abnormal expenditure */

data h_sample2;
set h_sample;
abn_cfo = -1 * abn_cfo;
abn_disexp = -1 * abn_disexp;
loss = (ni < 0) ;
run;

/* winsorize  */
%winsor(dsetin=h_sample2, dsetout=h_sample_wins, vars=abn_cfo abn_prod abn_disexp, type=winsor, pctl=1 99);

proc means data=h_sample_wins n mean median;  var  abn_cfo abn_prod abn_disexp ni size lev loss sale_gr; run;


/* what are the factors for abnormal cfo, prod, discretionary expenses */
proc surveyreg data=h_sample_wins ; 
class fyear sic2;
model abn_cfo = ni size lev loss sale_gr fyear sic2  / solution; 
quit;

proc surveyreg data=h_sample_wins ; 
class fyear sic2;
model abn_prod = ni size lev loss sale_gr fyear sic2  / solution; 
quit;


proc surveyreg data=h_sample_wins ; 
class fyear sic2;
model abn_disexp = ni size lev loss sale_gr fyear sic2  / solution; 
quit;

proc export data=work.h_sample_wins (keep = gvkey fyear abn_cfo abn_prod abn_disexp) outfile="E:\temp\real_em.dta" replace; run;
