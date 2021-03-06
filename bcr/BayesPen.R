
Bayes.pen <- function(y, x, joint = TRUE, prior = NULL, nIter = 8000, burnIn = 500, 
				thin = 1, update=200, max.steps=NULL)
{
	require(BLR)
	require(lars)
 
	p<-ncol(x)
	n<-nrow(x)

   	if (nIter < p && joint) 
	{
             stop("The number of MCMC draws must be set to be larger than the dimension to use the joint posterior covariance matrix.")
    	}

	xc <- scale(x, scale=F)
	yc <- y-mean(y) 
	fit<-BLR2(yc, XR=xc, prior=prior, nIter = nIter, burnIn = burnIn, 
				thin = thin, update=update)
	
	if (is.null(max.steps)) {max.steps = 8 * min(n, p)}

	beta_mn<-fit$bR
	beta_cov<-fit$COV.bR
	beta_sd<-sqrt(diag(beta_cov))

	if (joint)
	{
		prec_est<-solve(beta_cov)

		x1 <- chol(prec_est, pivot=TRUE)
		pivot <- attr(x1, "pivot")
		x1 <- x1[, order(pivot)]
 
		y1 <- x1%*%beta_mn
		w <- beta_mn^2 
		xs<-scale(x1,center=FALSE,scale=1/w)
		adapt.cred.set<-lars(xs,y1,type="lasso",normalize=FALSE,intercept=FALSE,max.steps=max.steps,use.Gram=F)

		adapt.ind<-1*(coef(adapt.cred.set)!=0)
		test.df<-apply(adapt.ind,1,sum)
	
		coefs.joint<-matrix(0,nrow=length(test.df),ncol=p+1)
		SSE.joint<-rep(0,length(test.df))	

		for (dloc in 1:length(test.df))
		{
			if (test.df[dloc]==0){fits<-lm(y~1)}
			else
			{
				X_curr<-x[,adapt.ind[dloc,]!=0]
				fits<-lm(y~X_curr)
			}
			coefs.joint.temp<-rep(0,p)
			coefs.joint.temp[adapt.ind[dloc,]!=0]<-fits$coef[-1]
			coefs.joint[dloc,]<-c(fits$coef[1],coefs.joint.temp)
			SSE.joint[dloc]<-t(fits$res)%*%fits$res
		}
		coefs.joint=coefs.joint[test.df<=min((n-1),p),]
		SSE.joint=SSE.joint[test.df<=min((n-1),p)]
	}
	else
	{
		coefs.joint=matrix(c(lm(y~1)$coef,rep(0,p)),nrow=1)
		SSE.joint=var(y)*(n-1)
	}

	z.stats<-beta_mn/beta_sd
	ordered.z.s<-rank(-abs(z.stats),ties.method="random")
	
	coefs.marg<-matrix(0,nrow=min((n-1),p),ncol=p+1)
	SSE.marg<-rep(0,min((n-1),p))

	for (dloc in 1:min((n-1),p))
	{
		X_curr<-x[,(ordered.z.s<=dloc)]
		fits<-lm(y~X_curr)
		coefs.marg.temp<-rep(0,p)
		coefs.marg.temp[(ordered.z.s<=dloc)]<-fits$coef[-1]
		coefs.marg[dloc,]<-c(fits$coef[1],coefs.marg.temp)
		SSE.marg[dloc]<-t(fits$res)%*%fits$res
	}
	coefs.marg<-rbind(coefs.joint[1,],coefs.marg)
	SSE.marg<-c(SSE.joint[1],SSE.marg)

	if (!joint) 
	{
		coefs.joint=NULL
		SSE.joint=NULL		
		order.joint=NULL
		df.joint=NULL
	}
	else
	{
		order.joint=unlist(adapt.cred.set$action)
		df.joint=(1+test.df)
	}

	out <- list(SSE.joint=SSE.joint,SSE.marg=SSE.marg,coefs.joint=coefs.joint,
				coefs.marg=coefs.marg,df.joint=df.joint,df.marg=(1:min(n,(p+1))),
				order.joint=order.joint,order.marg=sort(ordered.z.s,index.return=T)$ix)
	return(out)
}



BLR2<-function (y, XF = NULL, XR = NULL, XL = NULL, GF = list(ID = NULL, 
    A = NULL), prior = NULL, nIter = 8000, burnIn = 500, thin = 1, update=200, 
    thin2 = 1e+10, saveAt = "", minAbsBeta = 1e-09, weights = NULL) 
{
    y <- as.numeric(y)
    n <- length(y)
    if (!is.null(XF)) {
        if (any(is.na(XF)) | nrow(XF) != n) 
            stop("The number of rows in XF does not correspond with that of y or it contains missing values")
    }
    if (!is.null(XR)) {
        if (any(is.na(XR)) | nrow(XR) != n) 
            stop("The number of rows in XR does not correspond with that of y or it contains missing values")
    }
    if (!is.null(XL)) {
        if (any(is.na(XL)) | nrow(XL) != n) 
            stop("The number of rows in XL does not correspond with that of y or it contains missing values")
    }
    if (is.null(prior)) {
        cat("===============================================================\n")
        cat("No prior was provided, BLR is running with improper priors.\n")
        cat("===============================================================\n")
        prior = list(varE = list(S = 0, df = 0), varBR = list(S = 0, 
            df = 0), varU = list(S = 0, df = 0), lambda = list(shape = 0, 
            rate = 0, type = "random", value = 50))
    }
    nSums <- 0
    whichNa <- which(is.na(y))
    nNa <- sum(is.na(y))
    if (is.null(weights)) {
        weights <- rep(1, n)
    }
    sumW2 <- sum(weights^2)
    mu <- weighted.mean(x = y, w = weights, na.rm = TRUE)
    yStar <- y * weights
    yStar[whichNa] <- mu * weights[whichNa]
    e <- (yStar - weights * mu)
    varE <- var(e, na.rm = TRUE)/2
    if (is.null(prior$varE)) {
        cat("==============================================================================\n")
        cat("No prior was provided for residual variance, BLR will use an improper prior.\n")
        prior$varE <- list(df = 0, S = 0)
        cat("==============================================================================\n")
    }
    post_mu <- 0
    post_varE <- 0
    post_logLik <- 0
    post_yHat <- rep(0, n)
    post_yHat2 <- rep(0, n)
    hasRidge <- !is.null(XR)
    hasXF <- !is.null(XF)
    hasLasso <- !is.null(XL)
    hasGF <- !is.null(GF[[1]])
    if (hasXF) {
        for (i in 1:n) {
            XF[i, ] <- weights[i] * XF[i, ]
        }
        SVD.XF <- svd(XF)
        SVD.XF$Vt <- t(SVD.XF$v)
        SVD.XF <- SVD.XF[-3]
        pF0 <- length(SVD.XF$d)
        pF <- ncol(XF)
        bF0 <- rep(0, pF0)
        bF <- rep(0, pF)
        namesBF <- colnames(XF)
        post_bF <- bF
        post_bF2 <- bF
        rm(XF)
    }
    if (hasLasso) {
        if (is.null(prior$lambda)) {
            cat("==============================================================================\n")
            cat("No prior was provided for lambda, BLR will use an improper prior.\n")
            cat("==============================================================================\n")
            prior$lambda <- list(shape = 0, rate = 0, value = 50, 
                type = "random")
        }
        for (i in 1:n) {
            XL[i, ] <- weights[i] * XL[i, ]
        }
        pL <- ncol(XL)
        xL2 <- colSums(XL * XL)
        bL <- rep(0, pL)
        namesBL <- colnames(XL)
        tmp <- 1/2/sum(xL2/n)
        tau2 <- rep(tmp, pL)
        lambda <- prior$lambda$value
        lambda2 <- lambda^2
        post_lambda <- 0
        post_bL <- rep(0, pL)
        post_bL2 <- post_bL
        post_tau2 <- rep(0, pL)
        XLstacked <- as.vector(XL)
        rm(XL)
    }
    else {
        lambda = NA
    }
    if (hasRidge) {
        if (is.null(prior$varBR)) {
            cat("==============================================================================\n")
            cat("No prior was provided for varBR, BLR will use an improper prior.\n")
            cat("==============================================================================\n")
            prior$varBR <- list(df = 0, S = 0)
        }
        for (i in 1:n) {
            XR[i, ] <- weights[i] * XR[i, ]
        }
        pR <- ncol(XR)
        xR2 <- colSums(XR * XR)
        bR <- rep(0, pR)
        namesBR <- colnames(XR)
        varBR <- varE/2/sum(xR2/n)
        post_bR <- rep(0, pR)
        post_bR2 <- post_bR
        post_bR3<-matrix(0,pR,pR)
        post_varBR <- 0
        XRstacked <- as.vector(XR)
        rm(XR)
    }
    if (hasGF) {
        if (is.null(prior$varU)) {
            cat("==============================================================================\n")
            cat("No prior was provided for varU, BLR will use an improper prior.\n")
            cat("==============================================================================\n")
            prior$varU <- list(df = 0, S = 0)
        }
        ID <- factor(GF$ID)
        pU <- nrow(GF$A)
        L <- t(chol(GF$A))
        if (pU != nrow(table(ID))) {
            stop("L must have as many columns and rows as levels on ID\n")
        }
        Z <- model.matrix(~ID - 1)
        for (i in 1:n) {
            Z[i, ] <- weights[i] * Z[i, ]
        }
        Z <- Z %*% L
        z2 <- colSums(Z * Z)
        u <- rep(0, pU)
        namesU <- colnames(GF$A)
        varU <- varE/4/mean(diag(GF$A))
        GF$A <- NULL
        post_U <- u
        post_U2 <- post_U
        post_varU <- 0
        Zstacked <- as.vector(Z)
        rm(Z)
    }
    time <- proc.time()[3]
    for (i in 1:nIter) {
        if (hasXF) {
            sol <- (crossprod(SVD.XF$u, e) + bF0)
            tmp <- sol + rnorm(n = pF0, sd = sqrt(varE))
            bF <- crossprod(SVD.XF$Vt, tmp/SVD.XF$d)
            e <- e + SVD.XF$u %*% (bF0 - tmp)
            bF0 <- tmp
        }
        if (hasRidge) {
            ans <- .Call("sample_beta", n, pR, XRstacked, xR2, 
                bR, e, rep(varBR, pR), varE, minAbsBeta)
            bR <- ans[[1]]
            e <- ans[[2]]
            SS <- crossprod(bR) + prior$varBR$S
            df <- pR + prior$varBR$df
            varBR <- SS/rchisq(df = df, n = 1)
        }
        if (hasLasso) {
            varBj <- tau2 * varE
            ans <- .Call("sample_beta", n, pL, XLstacked, xL2, 
                bL, e, varBj, varE, minAbsBeta)
            bL <- ans[[1]]
            e <- ans[[2]]
            nu <- sqrt(varE) * lambda/abs(bL)
            tmp <- NULL
            try(tmp <- rinvGauss(n = pL, nu = nu, lambda = lambda2))
            if (!is.null(tmp)) {
                if (!any(is.na(sqrt(tmp)))) {
                  tau2 <- 1/tmp
                }
                else {
                  cat("WARNING: tau2 was not updated due to numeric problems with beta\n")
                }
            }
            else {
                cat("WARNING: tau2 was not updated due to numeric problems with beta\n")
            }
            if (prior$lambda$type == "random") {
                if (is.null(prior$lambda$rate)) {
                  lambda <- metropLambda(tau2 = tau2, lambda = lambda, 
                    shape1 = prior$lambda$shape1, shape2 = prior$lambda$shape2, 
                    max = prior$lambda$max)
                  lambda2 <- lambda^2
                }
                else {
                  rate <- sum(tau2)/2 + prior$lambda$rate
                  shape <- pL + prior$lambda$shape
                  lambda2 <- rgamma(rate = rate, shape = shape, 
                    n = 1)
                  if (!is.na(lambda2)) {
                    lambda <- sqrt(lambda2)
                  }
                  else {
                    cat("WARNING: lambda was not updated due to numeric problems with beta\n")
                  }
                }
            }
        }
        if (hasGF) {
            ans <- .Call("sample_beta", n, pU, Zstacked, z2, 
                u, e, rep(varU, pU), varE, minAbsBeta)
            u <- ans[[1]]
            e <- ans[[2]]
            SS <- crossprod(u) + prior$varU$S
            df <- pU + prior$varU$df
            varU <- SS/rchisq(df = df, n = 1)
        }
        e <- e + weights * mu
        rhs <- sum(weights * e)/varE
        C <- sumW2/varE
        sol <- rhs/C
        mu <- rnorm(n = 1, sd = sqrt(1/C)) + sol
        e <- e - weights * mu
        SS <- crossprod(e) + prior$varE$S
        df <- n + prior$varE$df
        if (hasLasso) {
            if (!any(is.na(sqrt(tau2)))) {
                SS <- SS + as.numeric(crossprod(bL/sqrt(tau2)))
            }
            else {
                cat("WARNING: SS was not updated due to numeric problems with beta\n")
            }
            df <- df + pL
        }
        varE <- as.numeric(SS)/rchisq(n = 1, df = df)
        sdE <- sqrt(varE)
        yHat <- yStar - e
        if (nNa > 0) {
            e[whichNa] <- rnorm(n = nNa, sd = sdE)
            yStar[whichNa] <- yHat[whichNa] + e[whichNa]
        }
        if ((i%%thin == 0)) {
            tmp <- c(varE)
            fileName <- paste(saveAt, "varE", ".dat", sep = "")
            write(tmp, ncol = length(tmp), file = fileName, append = TRUE, 
                sep = " ")
            if (hasXF) {
                tmp <- bF
                fileName <- paste(saveAt, "bF", ".dat", sep = "")
                write(tmp, ncol = length(tmp), file = fileName, 
                  append = TRUE, sep = " ")
            }
            if (hasLasso) {
                tmp <- lambda
                fileName <- paste(saveAt, "lambda", ".dat", sep = "")
                write(tmp, ncol = length(tmp), file = fileName, 
                  append = TRUE, sep = " ")
            }
            if (hasRidge) {
                tmp <- varBR
                fileName <- paste(saveAt, "varBR", ".dat", sep = "")
                write(tmp, ncol = length(tmp), file = fileName, 
                  append = TRUE, sep = " ")
            }
            if (hasGF) {
                tmp <- varU
                fileName <- paste(saveAt, "varU", ".dat", sep = "")
                write(tmp, ncol = length(tmp), file = fileName, 
                  append = TRUE, sep = " ")
            }
            if (i >= burnIn) {
                nSums <- nSums + 1
                k <- (nSums - 1)/(nSums)
                tmpE <- e/weights
                tmpSD <- sqrt(varE)/weights
                if (nNa > 0) {
                  tmpE <- tmpE[-whichNa]
                  tmpSD <- tmpSD[-whichNa]
                }
                logLik <- sum(dnorm(tmpE, sd = tmpSD, log = TRUE))
                post_logLik <- post_logLik * k + logLik/nSums
                post_mu <- post_mu * k + mu/nSums
                post_varE <- post_varE * k + varE/nSums
                post_yHat <- post_yHat * k + yHat/nSums
                post_yHat2 <- post_yHat2 * k + (yHat^2)/nSums
                if (hasXF) {
                  post_bF <- post_bF * k + bF/nSums
                  post_bF2 <- post_bF2 * k + (bF^2)/nSums
                }
                if (hasLasso) {
                  post_lambda <- post_lambda * k + lambda/nSums
                  post_bL <- post_bL * k + bL/nSums
                  post_bL2 <- post_bL2 * k + (bL^2)/nSums
                  post_tau2 <- post_tau2 * k + tau2/nSums
                }
                if (hasRidge) {
################
                  post_bR <- post_bR * k + bR/nSums
                  post_bR2 <- post_bR2 * k + (bR^2)/nSums
                  post_varBR <- post_varBR * k + varBR/nSums
                  post_bR3<-post_bR3*k+outer(bR,bR)/nSums
################
                }
                if (hasGF) {
                  tmpU <- L %*% u
                  post_U <- post_U * k + tmpU/nSums
                  post_U2 <- post_U2 * k + (tmpU^2)/nSums
                  post_varU <- post_varU * k + varU/nSums
                }
            }
        }
        if ((i%%thin2 == 0) & (i > burnIn)) {
            tmp <- post_yHat
            fileName <- paste(saveAt, "rmYHat", ".dat", sep = "")
            write(tmp, ncol = length(tmp), file = fileName, append = TRUE, 
                sep = " ")
            if (hasLasso) {
                tmp <- post_bL
                fileName <- paste(saveAt, "rmBL", ".dat", sep = "")
                write(tmp, ncol = length(tmp), file = fileName, 
                  append = TRUE, sep = " ")
            }
            if (hasRidge) {
                tmp <- post_bR
                fileName <- paste(saveAt, "rmBR", ".dat", sep = "")
                write(tmp, ncol = length(tmp), file = fileName, 
                  append = TRUE, sep = " ")
            }
            if (hasGF) {
                tmp <- post_U
                fileName <- paste(saveAt, "rmU", ".dat", sep = "")
                write(tmp, ncol = length(tmp), file = fileName, 
                  append = TRUE, sep = " ")
            }
        }
        tmp <- proc.time()[3]
        if(i%%update==0){
          cat(paste(c("Iter: ", "time/iter: ", "varE: ", "varB: "), 
              c(i, round(tmp - time, 3), round(varE, 3), round(varBR, 
                  3))))
          cat("\n")
          cat(paste("------------------------------------------------------------"))
          cat("\n")
        }
        time <- tmp
    }
    tmp <- sqrt(post_yHat2 - (post_yHat^2))
    out <- list(y = y, weights = weights, mu = post_mu, varE = post_varE, 
        yHat = I(post_yHat/weights), SD.yHat = I(tmp/weights), 
        whichNa = whichNa)
    names(out$yHat) <- names(y)
    names(out$SD.yHat) <- names(y)
    tmpE <- (yStar - post_yHat)/weights
    tmpSD <- sqrt(post_varE)/weights
    if (nNa > 0) {
        tmpE <- tmpE[-whichNa]
        tmpSD <- tmpSD[-whichNa]
    }
    out$fit <- list()
    out$fit$logLikAtPostMean <- sum(dnorm(tmpE, sd = tmpSD, log = TRUE))
    out$fit$postMeanLogLik <- post_logLik
    out$fit$pD <- -2 * (post_logLik - out$fit$logLikAtPostMean)
    out$fit$DIC <- out$fit$pD - 2 * post_logLik
    if (hasXF) {
        out$bF <- as.vector(post_bF)
        out$SD.bF <- as.vector(sqrt(post_bF2 - post_bF^2))
        names(out$bF) <- namesBF
        names(out$SD.bF) <- namesBF
    }
    if (hasLasso) {
        out$lambda <- post_lambda
        out$bL <- as.vector(post_bL)
        tmp <- as.vector(sqrt(post_bL2 - (post_bL^2)))
        out$SD.bL <- tmp
        out$tau2 <- post_tau2
        names(out$bL) <- namesBL
        names(out$SD.bL) <- namesBL
    }
    if (hasRidge) {
        out$bR <- as.vector(post_bR)
        tmp <- as.vector(sqrt(post_bR2 - (post_bR^2)))
        out$SD.bR <- tmp
        out$varBR <- post_varBR
############
        out$COV.bR<-post_bR3-outer(out$bR,out$bR)
#############
        names(out$bR) <- namesBR
        names(out$SD.bR) <- namesBR
    }
    if (hasGF) {
        out$u <- as.vector(post_U)
        tmp <- as.vector(sqrt(post_U2 - (post_U^2)))
        out$SD.u <- tmp
        out$varU <- post_varU
        names(out$u) <- namesU
        names(out$SD.u) <- namesU
    }
    out$prior <- prior
    out$nIter <- nIter
    out$burnIn <- burnIn
    out$thin <- thin
    return(out)
}

