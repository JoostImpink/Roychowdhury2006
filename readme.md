# Replication Roychowdhury, 2006

## Roychowdhury, 2006. Earnings management through real activities manipulation. Journal of Accounting and Economics (42) pp. 350-370

See [replicate roychowdhury.sas](replicate roychowdhury.sas) for SAS code to replicate tables 1 and 2.

> Warning: you can use my code, but my findings are not in line with the paper's results. I am very interested in hearing about any possible mistakes I may have made.

There are two main issues in replicating the paper:

- sample size
- regression output table 2

### Sample size

When I closely follow the instructions on how to select the firms, my sample size is about 3 times the size of the paper's sample. When I add an extra filter (which is not mentioned in the paper) to only include firms listed on NYSE, AMEX, and Nasdaq, then the sample is only 1.5 times the size.

The descriptive statistics (for size variables, and the dependent variables) on table 1 are similar.

### Table 2

In table 2, the dependent variables (cash flow from operations, discretionary expenses, production costs and accruals) are regresses on some factors like sales, change in sales, PPE, etc. Some of my coefficients for models 1-3 are similar, but my standard deviations are much higher (meaning I mostly find no significant variables). My estimates for model 4 (accruals) are very different.
