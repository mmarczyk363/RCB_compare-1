RCB_diff <- function(RCB_ctrl, RCB_exp, fold=5, sig=10^seq(-1,0.2,length.out=50), lam=10^seq(-3,0,length.out=50), ifplot=F, grp_ctrl_name="Control", grp_exp_name="Experimental"){
# Estimate Treatment Efficacy Score (TES) by comparing densities of RCB in experimental treatment cohort vs control cohort
# Step1: estimate density difference using kernel function
# Step2: calculate eCDF of density ratio
# Step3: calculate TES as area under eCDF
#
# Input:
# RCB_ctrl - vector of RCB values in control cohort
# RCB_exp - vector of RCB values in experimental treatment cohort
# fold - no. of cross-validation iterations (k-fold)
# sig - kernel bandwidth (vector with numeric values > 0)
# lam - regularization parameter (vector with numeric values > 0)
# ifplot - if plot should be generated
#
# Output: TES with 95% confidence intervals
# 
# Author: Michal Marczyk (michal.marczyk@yale.edu; michal.marczyk@polsl.edu)
# Based on Matlab implementation of Least-Squares Density-Difference Estimation by Masashi Sugiyama
# sugi@cs.titech.ac.jp, sugi@k.u-tokyo.ac.jp
  
  require(pcg)

  if (sig == "auto"){
    sig <- bw.nrd0(c(RCB_ctrl, RCB_exp)) 
  }
  
  n1 <- length(RCB_exp)
  n2 <- length(RCB_ctrl)
  
  RCB_all <- c(RCB_exp, RCB_ctrl)
  # rm(RCB_ctrl, RCB_exp)
  n <- n1+n2;
  kernel_num <- min(1000,n); # Number of kernel bases
  RCBmax <- max(RCB_all)
  n_pts <- 1000
  RCB_tmp <- seq(0,RCBmax,length.out=n_pts)
  
  center_index_tmp <- sample.int(n)
  center_index <- center_index_tmp[1:kernel_num]
  C <- RCB_all[center_index] 
  XXsum <- RCB_all^2
  XC_dist2 <- matrix(rep(XXsum,each=kernel_num), nrow=kernel_num,byrow=RCB_tmp) + 
    t(matrix(rep(XXsum[center_index],each=n), nrow=n, byrow=RCB_tmp)) - 2*as.matrix(C) %*% t(as.matrix(RCB_all))
  TC_dist2 <- matrix(rep(RCB_tmp^2,each=kernel_num), nrow=kernel_num,byrow=RCB_tmp) + 
    t(matrix(rep(XXsum[center_index],each=n_pts), nrow=n_pts, byrow=RCB_tmp)) - 2*as.matrix(C) %*% t(as.matrix(RCB_tmp))
  rm(XXsum,RCB_all)
  
  X1C_dist2 <- XC_dist2[,1:n1]
  X2C_dist2 <- XC_dist2[,(n1+1):n]
  CC_dist2 <- XC_dist2[,center_index]
  rm(XC_dist2)
  
  # prepare k-fold cross-validation parameters
  cv_fold <- 1:fold
  cv_split1 <- floor((0:(n1-1))*fold/n1)+1
  cv_split2 <- floor((0:(n2-1))*fold/n2)+1;
  cv_index1 <- cv_split1[sample.int(n1)]
  cv_index2 <- cv_split2[sample.int(n2)]
  n1_cv <- as.numeric(table(cv_index1))
  n2_cv <- as.numeric(table(cv_index2))
  
  # Find optimal sigma and lambda in CV scheme
  score_cv <- array(dim=c(length(sig),length(lam),fold))
  for (sigma_index in 1:length(sig)){
    sigma <- sig[sigma_index];
    H <- (sqrt(pi)*sigma)*exp(-CC_dist2/(4*sigma^2))
    h1_cv <- h2_cv <- matrix(nrow=kernel_num, ncol=fold)
    for (k in cv_fold ){
      h1_cv[,k] <- rowSums(exp(-X1C_dist2[,cv_index1==k]/(2*sigma^2)))
      h2_cv[,k] <- rowSums(exp(-X2C_dist2[,cv_index2==k]/(2*sigma^2)))
    }
    for (k in cv_fold){
      htrain <- rowSums(h1_cv[,cv_fold!=k])/sum(n1_cv[cv_fold!=k]) - 
        rowSums(h2_cv[,cv_fold!=k])/sum(n2_cv[cv_fold!=k])
      htest <- (h1_cv[,cv_fold==k])/sum(n1_cv[cv_fold==k]) - 
        (h2_cv[,cv_fold==k])/sum(n2_cv[cv_fold==k])
      for (lambda_index in 1:length(lam)){
        lambda <- lam[lambda_index]
        thetah <- as.matrix(pcg(H+lambda*diag(kernel_num),htrain))
        score_cv[sigma_index,lambda_index,k] <- t(thetah) %*% H %*% thetah - 2*t(thetah) %*% htest
      }
    }
  }
  
  # Find minimum Score
  score_cv <- rowSums(score_cv, dims=2)
  opt_ind <- arrayInd(which.min(score_cv), dim(score_cv))
  sigma <- sig[opt_ind[1]];
  lambda <- lam[opt_ind[2]]
  if(ifplot) cat("Estimated parameters: lambda =",lambda, "; bandwidth =", sigma,"\n")
  
  # Find density difference for optimal parameters
  H <- (sqrt(pi)*sigma)*exp(-CC_dist2/(4*sigma^2))
  h <- as.matrix(rowMeans(exp(-X1C_dist2/(2*sigma^2)))-rowMeans(exp(-X2C_dist2/(2*sigma^2))))
  thetah <- as.matrix(pcg(H+lambda*diag(kernel_num), h))

  # Compute Density difference and its CDF
  w_hat <- as.numeric(t(thetah) %*% exp(-TC_dist2/(2*sigma^2)))
  w_hat_pos <- w_hat
  w_hat_pos[w_hat<0] <- 0
  cdf_hat <- cumsum(w_hat_pos)
  cdf_hat <- cdf_hat/max(cdf_hat)
  
  # Calculate area under eCDF(Treatment Efficacy Score)
  TES <- sum(cdf_hat[-length(cdf_hat)] * (RCB_tmp[-1] - RCB_tmp[-length(RCB_tmp)]))/RCBmax  #step function method
  
  # plot density difference
  if(ifplot){
    data_plot <- data.frame(cbind(RCB_tmp,w_hat))
    p <- ggplot(data_plot,aes(x=RCB_tmp, y=w_hat)) + geom_point(col="#56B4E9") + 
      labs(x="RCBscore", y=paste0("Density difference\n(",grp_exp_name," - ",grp_ctrl_name,")")) + 
      geom_hline(yintercept=0) + theme_bw() + theme(plot.title = element_text(hjust=0.5))
    
    res <- list()
    res[["TES"]] <- TES
    res[["Plot"]] <- p
    res[["Parameters"]] <- c(lambda, sigma)
    names(res[["Parameters"]]) <- c("Lambda","Sigma")
    return(res)
  } else {
    return(TES)
  }
}