rm(list=ls(all=TRUE))
source('BayesPen.R')

require(mvtnorm)
rho = 0.9
sigma = 1
n = 60
p = 1000
times = 1:p
H = abs(outer(times, times, "-"))

V = sigma * rho^H
set.seed(77)
beta = rep(0,p)
beta[11:15] = runif(5)
beta[36:40] = runif(5)
x = rmvnorm(n,rep(0,p),V)
y = x%*%beta + rnorm(n)

# Fit the model
prior = list(varE=list(df=3,S=1),varBR=list(df=3,S=1))
example_fit = Bayes.pen(y, x, prior=prior)
# Results are similar as above.
