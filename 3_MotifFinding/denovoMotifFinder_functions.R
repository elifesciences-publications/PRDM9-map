#denovoMotifFinder_functions.R
#Implementation of a Bayesian, de novo, joint motif finding algorithm
#Simon Myers, Nicolas Altemose
#2015

####If you use this program, please cite Altemose et al. eLife 2017
####This is free software shared in the hope it may be of use; no warranty is given or implied
####See FindMotifs_Human.R for usage example

###Required libraries
library(gtools)
library(seqLogo)

#####function 1: findamotif returns the single most enriched motif in a set of DNA sequences

##############################################################################################################################################
###OVERVIEW: 

#This function identifies a single PWM from an iterative Gibbs sampler described in Altemose et al. eLife 2017. Function 2 can refine multiple motifs further, jointly.

#The user must input a set of DNA sequences, a score for each sequence (e.g. an enrichment value or any other score), and a length for an initial motif (e.g. 8 bp) used to seed the algorithm.

#There are additional optional parameters.

#The program outputs a list of results, including information on the inferred PWM (i.e. motif found), as well as a probabilistic output of which regions contain this motif, and posterior distributions of the other parameters


##############################################################################################################################################
###ARGUMENTS: 

###seqs: a vector of strings giving the DNA sequences in which to find a motif

###len: length of motif to find

###scores: a set of regional scores giving weights; e.g. ChIP-Seq enrichment values

###nits: number of iterations used for motif refinement

###ntries: usually leave at default, number of motifs to be attempted from list of possible starts

###n_for_refine: the top n_for_refine scoring regions only are used for motif refinement

###noutfile: a file to output a final PWM plot into

###prior: a vector of length 10 probabilities giving the initial probability of a motif being found across different parts of the sequence from start:end. If left unspecified the initial prior is set at uniform and the algorithm tries to learn where motifs are, e.g. if they are centrally enriched.

###updateprior: a flag - should the algorithm update (learn) the prior on where the motifs occur within the DNA sequences(default is 1)?


##############################################################################################################################################
###RETURNED VALUES:

####The code returns detailed output as a list, whose elements are as follows (access these using commands like outputlist$scoremat)

##############################details of input data given ####################################################################################

###seqs: the vector of input sequences used for finding motifs within

###trimmedseqs: the vector of input sequences used for finding motifs within, after trimming to shorten long input sequences


##############################################################################################################################################
##############################details of overall fitted model ################################################################################
###scoremat: a matrix giving the pwm (log-scale) for the identified motif after iteration

###scorematdim: the length of the identified motif, and scoremat is of dimension scorematdimx4 

###prior: a vector of length 10 probabilities giving the inferred probability of a motif being found across different parts of the sequence from start to end. 

###alpha: a vector of probabilities giving the inferred probability of the motif being found within each input region

###bindmat: a version of scoremat accounting for the background sequence composition

###background is the inferred background model

##############################################################################################################################################
##############################details of output for given data ###############################################################################

###regprobs, regprob are in this case identical vectors giving the probability of the motif occurring in each given input sequence

###bestpos is a vector giving the best match to the motif in each given input sequence

###whichregs is a vector showing which input sequences had motifs identified in the final round of sampling of the Gibbs sampler

###whichpos: for motifs identified in regions described in whichreg, the start positions of motifs identified in the final round of sampling of the Gibbs sampler

###whichmot: not needed in this case

###whichstrand: for motifs identified in regions described in whichreg, the strand associated with motifs identified in the final round of sampling of the Gibbs sampler, relative to the input sequence

##############################################################################################################################################

findamotif=function(seqs,scores,len,nits=100,ntries=1,n_for_refine=1000,outfile="temp.pdf",prior=NULL,updateprior=1){
	if(n_for_refine>length(seqs)) n_for_refine=length(seqs)
	regs=seqs
	print("Concatenating sequences....")
	seqs=paste(seqs,collapse="")
	print("....done")
	
	print("Replacing DNA letters with numbers....")
	seqv=as.vector(unlist(strsplit(seqs,"")))
	seqv=gsub("A","0",seqv)
	seqv=gsub("C","1",seqv)
	seqv=gsub("G","2",seqv)
	seqv=gsub("T","3",seqv)
	seqv=gsub("a","4",seqv)
	seqv=gsub("c","5",seqv)
	seqv=gsub("g","6",seqv)
	seqv=gsub("t","7",seqv)
	seqv=gsub("N","8",seqv)
	seqv=as.integer(seqv)
	print("....done")
	
	print("Indexing....")
	nonrep=rep(0,(length(seqv)-len+1))
	for(i in 1:len){
		print(i)
		z=seqv[i:(i+length(nonrep)-1)]
		nonrep=nonrep+4^(len-i)*z
		nonrep[z>3]=-Inf
	}
	nonrep2=nonrep[!is.infinite(nonrep)]+1
	print("....done")
	
	print("Counting motifs....")
	res=1:(4^len)*0
	for(i in 1:length(nonrep2)){
		if(!i%%100000) print(i)
 		res[nonrep2[i]]=res[nonrep2[i]]+1
	}
	bases=c("A","C","G","T")
	ournames=""
	for(i in 1:len) ournames=c(paste(bases[1],ournames,sep=""),paste(bases[2],ournames,sep=""),paste(bases[3],ournames,sep=""),paste(bases[4],ournames,sep=""))
	names(res)=ournames
	ournamesc=""
	for(i in 1:len) ournamesc=c(paste(ournamesc,bases[4],sep=""),paste(ournamesc,bases[3],sep=""),paste(ournamesc,bases[2],sep=""),paste(ournamesc,bases[1],sep=""))
	restot=res+res[ournamesc]
	print("....done")
	
	print("Finding potential starts....")
	lookups=order(-restot)[1:200]
	restot=restot[lookups]
	seqs=ournames[lookups]
	seqsc=ournamesc[lookups]
	seqs=seqs[restot>10]
	seqsc=seqsc[restot>10]
	if(!length(seqs)){
 		print("No motif to start from is in above 10 sequences")
		return(0)
	}
	pos=1
	while(pos<length(seqs)){
		check1=seqs[pos]
		check2=seqsc[pos]
		if(check1!=check2) {
			seqs=seqs[seqs!=check2]
			seqsc=seqsc[seqsc!=check1]
		}
		pos=pos+1
	}
	print("....done")
	
	print("Checking for central enrichment....")
	mids=nchar(regs)/2
	range=50
	reg2=regs[nchar(regs)>=mids+range & mids-range>=1]
	midregs=substring(reg2,mids-range,mids+range)

	enrich=1:length(seqs)
	excess=enrich
	for(i in 1:length(seqs)){
		print(i)
		mot=seqs[i]
		motc=seqsc[i]
		ourset=unique(c(grep(mot,midregs),grep(motc,midregs)))
		ourset2=unique(c(grep(mot,reg2),grep(motc,reg2)))
		t2=sum(nchar(reg2)-len+1)
		t1=sum(nchar(midregs)-len+1)
		enrich[i]=length(ourset)/t1/(length(ourset2)-length(ourset))*(t2-t1)
		excess[i]=length(ourset)-(length(ourset2)-length(ourset))*t1/(t2-t1)
	}

	#####now take most enriched motif in top 50, and look at single-base alterations and extensions for their impact
	#####use pwm for motif refinement
	#####automatically obtain sequences without the motif

	pwmstart=matrix(0.1,nrow=10,ncol=4)
	excess=excess[enrich>1]
	seqs=seqs[enrich>1]
	seqsc=seqsc[enrich>1]
	enrich=enrich[enrich>1]
	if(!length(enrich)) {
 		print("No motif to start from is centrally enriched")
		return(0)
	}
	mot=seqs[order(-excess)][1]
	print("....done. Chose start motif:")
	print(mot)

	print("Initialising....")
	mot=as.vector(unlist(strsplit(mot,"")))
	mot[mot=="A"]=1
	mot[mot=="C"]=2
	mot[mot=="G"]=3
	mot[mot=="T"]=4
	mot=as.double(as.vector(unlist(mot)))

	for(i in 1:len) pwmstart[i,mot[i]]=1
	pwmstart=pwmstart/rowSums(pwmstart)
	logpwm=log(pwmstart)

	seqtemp=regs[order(-scores)][1:n_for_refine]
	print("....done")
	
	print("Attempting to refine....")
	z=getmotifs(logpwm,length(logpwm[,1]),seqtemp,maxwidth=max(nchar(seqtemp)),alpha=0.5,incprob=0.99999,maxits=nits,plen=0.9,updatemot=1,updatealpha=1,ourprior=prior,bg=-1,updateprior=updateprior,plotting=F)
	print("....done")

	print("Scoring regions....")
	z2=getmotifs(z$scoremat,z$scorematdim,regs,maxwidth=max(nchar(regs)),alpha=z$alpha,incprob=0.99999,maxits=1,plen=0.2,updatemot=0,updatealpha=1,ourprior=z$prior,updateprior=0,bg=-1,plotting=F)
	print("....done")
	return(z2)
}





#####function 2: getmotifs jointy calls and refines a set of seed motifs provided by the findamotif function

###OVERVIEW: 
#Given a user-input set of initial PWMs and input sequences to identify motifs, run a Gibbs sampler to update these motifs, and output the results

#The user can also optionally supply priors on the fraction of sequences containing motifs, the likely length of motifs, and the positional distribution of motifs within the sequences.

#User-supplied information can either be updated (the default) by the algorithm, or fixed at the input values

#The program outputs a list of results, including information on inferred PWMs (i.e. motifs found), as well as a probabilistic output of which regions contain which motifs, and posterior distributions of the other parameters

#If you use this program, please cite Altemose et al. eLife 2017


##############################################################################################################################################
###ARGUMENTS:

###scorematset is a set of matrices, row-concatenated, giving pwms (log-scale) for the initialisation of the algorithm
###dimvec gives the lengths of each of the initial motifs
###if dimvec is of length n_motifs, motif k is of length dimvec[k]
###scorematset is of dimension sum(dimvec)x4 and the first dimvec[1] rows of this matrix gives the pwm for the first motifs, the next dimvec[2] rows the second motif, and so on

###seqs: a vector of input sequences used for finding motifs within. Lower case bases are ignored/masked - e.g. if repeats are an issue. In some cases it may be helpful NOT to mask repeats that may contain motif matches

###maxwidth: the length that elements of "seqs" will be trimmed to (around their centre). Run times depend roughly linearly on this parameter 

###alpha: a vector of initial assumed probabilities each motif is present in a sequence

###incprob: can usually be left as default value

###maxits: the number of iterations (if no motif is found the algorithm could terminate early)

###plen: a parameter setting the geometric prior on how long each motif found should be. plen=0.05 corresponds to a mean length of 20bp and is the default. Setting plen large penalises longer motifs more

###ourprior: a vector of length 10 probabilities giving the initial probability of a motif being found across different parts of the sequence from start:end. If left unspecified the initial prior is set at uniform and the algorithm tries to learn where motifs are, e.g. if they are centrally enriched.

###bg: should be left at default value normally (technical parameter setting background model)

###plotting: a parameter asking if run-time plots should be made.

###updatemot: a flag - should the algorithm update (learn) the initial motifs (default is 1)

###updatealpha: a flag - should the algorithm update (learn) the initial motifs (default is 1)

###updateprior: a flag - should the algorithm update (learn) the prior on where the motifs occur within the DNA sequences(default is 1)

##############################################################################################################################################

##############################################################################################################################################
###RETURNED VALUES:

###The code returns detailed output as a list, whose elements are as follows (access these using commands like outputlist$scoremat)

##############################details of input data given ####################################################################################

###seqs: the vector of input sequences used for finding motifs within

###trimmedseqs: the vector of input sequences used for finding motifs within, after trimming to shorten long input sequences


##############################################################################################################################################
##############################details of overall fitted model ################################################################################
###scoremat: a matrix made up of matrices, row-concatenated, giving pwms (log-scale) for the identified motifs after iteration

###scorematdim: the lengths of each of the identified motifs
###if scorematdim is of length n_motifs, motif k is of length scorematdim[k]
###scoremat is of dimension sum(scorematdim)x4 and the first scorematdim[1] rows of this matrix gives the pwm for the first motifs, the next scorematdim[2] rows the second motif, and so on

###prior: a vector of length 10 probabilities giving the inferred probability of a motif being found across different parts of the sequence from start to end. 

###alpha: a vector of probabilities giving the inferred probability of each motif being found within a single input region

###bindmat:a version of scoremat accounting for the background sequence composition

###background: the inferred background model

##############################################################################################################################################
##############################details of output for given data ###############################################################################

###regprobs: a matrix giving the probability of each motif occurring in each given input sequence

###regprob: a vector giving the overall probability of any motif occurring in each given input sequence

###bestpos: a matrix giving the best match for each motif in each given input sequence

###whichregs is a vector showing which input sequences had motifs identified in the final round of sampling of the Gibbs sampler

###whichpos: for motifs identified in regions described in whichreg, the start positions of motifs identified in the final round of sampling of the Gibbs sampler

###whichmot: for motifs identified in regions described in whichreg, the type (an integer in the range 1 to length(scorematdim)) of motifs identified in the final round of sampling of the Gibbs sampler

###whichstrand: for motifs identified in regions described in whichreg, the strand associated with motifs identified in the final round of sampling of the Gibbs sampler, relative to the input sequence

###############################################################################################################################################

getmotifs=function(scorematset,dimvec ,seqs,maxwidth=800,alpha=0.5,incprob=0.99999,maxits=30,plen=0.05,updatemot=1,updatealpha=1,ourprior=NULL,updateprior=1,bg=-1,plotting=F){
	starttime=proc.time()
	its=0;

	### initialise vector of prior probabilities
	alphas=matrix(nrow=0,ncol=length(dimvec))
	if(length(alpha)!=length(dimvec)){
		print("Initialising fractions as uniform")
		alpha=rep(1/length(dimvec),length(dimvec))/2
	}

	###need later
	logfact=cumsum(log(1:(length(seqs)+4)))
	logfact=c(0,logfact)
	origseqs=seqs
	######external regions get score -10000

	####initialise so that need to construct background in the first iteration
	qvec=vector(length=0)
	#####for now, don't update background each iteration
	
	####get sequences, pad to make same length
	this=nchar(seqs)
	statement=paste("Removing ",sum(this>maxwidth)," long regions with over ",maxwidth, " characters, of ", length(this)," regions in total (", sum(this>maxwidth)/length(this),"%).",sep="")

	print(statement)
	seqs=seqs[this<=maxwidth]
	this=this[this<=maxwidth]
	fullseqs=seqs
	seqs=gsub("A","1",seqs)
	seqs=gsub("C","2",seqs)
	seqs=gsub("G","3",seqs)
	seqs=gsub("T","4",seqs)
	seqs=gsub("N","5",seqs)

	print("Padding with N's to equalize size")
	temp=rep("5",maxwidth)
	temp=paste(temp,collapse="")
	maxwidth=max(this)
	for(i in 1:length(seqs)) if(this[i]<max(this)) seqs[i]=paste(seqs[i],substring(temp,1,(max(this)-this[i])),sep="")

	####begin iteration!
	while(its<maxits){
		print("Setting up")
		###get start and end positions of each motif within the score matrix. note need to do this each time, as size of things can change

		starts=c(1,cumsum(dimvec)+1)
		starts=starts[1:length(dimvec)]
		ends=cumsum(dimvec)
		###score
		bestpos=matrix(0,nrow=length(seqs),ncol=length(starts))
		beststrand=bestpos
		newmat=matrix(0,ncol=maxwidth,nrow=length(seqs))
		scores=newmat
		scores2=newmat
		its=its+1
		print(paste("Iteration number ",its,sep=""))

		if(its==1 | updatemot==1){ #note this is different from original
			overallscores=matrix(0,nrow=length(seqs)*length(starts),ncol=maxwidth)
			overallscores2=overallscores
			background=overallscores
			priormat=overallscores
		}

		posmat=overallscores
		for(i in 1:maxwidth) posmat[,i]=i
		for(i in 1:maxwidth) newmat[,i]=as.numeric(substring(seqs,i,i)) #nick moved out of for loop

		print("...done")


		###scoremat now just prob of each base given binding
		###we'll get probs of a sequence without binding in the matrix "background"
		###get sets of probabilities

		for(j in 1:length(starts)){
			scoremat=scorematset[starts[j]:ends[j],]
			print(scoremat)
			scoremat=cbind(scoremat,rep(-10000,nrow(scoremat))) #nick removed pointless maxwidth=200 setting
			compmat=scoremat[,c(4:1,5)]
			compmat=compmat[nrow(compmat):1,]
			print(paste("Beginning scoring for Motif",j))
			if(updatemot==1 | its==1){
				startrange=seq(1,maxwidth-nrow(scoremat)+1)
				maxes=max(startrange)-1
				for(i in 1:nrow(scoremat)){ #####sum log probabilities of each base according to pwm
					if(i==1) scores=matrix(scoremat[i,newmat[,i:(i+maxes)]],nrow=nrow(newmat))
					else scores=scores+matrix(scoremat[i,newmat[,i:(i+maxes)]],nrow=nrow(newmat))
				}
				print("Complement")
				scores2=matrix(0,nrow=nrow(newmat),ncol=length(startrange))
				for(i in 1:nrow(scoremat)){
					if(i==1) scores2=matrix(compmat[i,newmat[,i:(i+maxes)]],nrow=nrow(newmat))
					else scores2=scores2+matrix(compmat[i,newmat[,i:(i+maxes)]],nrow=nrow(newmat))
				}
				print("Overall")
	
				overall=scores
				overall[scores2>scores]=scores2[scores2>scores]

				print("Finding best positions")
				for(i in 1:nrow(overall)){ 
					bestpos[i,j]=sample(c(which(overall[i,]==max(overall[i,])),which(overall[i,]==max(overall[i,]))),1)
					score1=scores[i,bestpos[i,j]]
					score2=scores2[i,bestpos[i,j]]
					beststrand[i,j]=1
					if(score2>score1) beststrand[i,j]=0
				}
				print("Next motif")
				overallscores[(nrow(newmat)*(j-1)+1):(nrow(newmat)*j),]=-1e9
				overallscores[(nrow(newmat)*(j-1)+1):(nrow(newmat)*j),1:ncol(scores)]=scores
				overallscores2[(nrow(newmat)*(j-1)+1):(nrow(newmat)*j),]=-1e9
				overallscores2[(nrow(newmat)*(j-1)+1):(nrow(newmat)*j),1:ncol(scores)]=scores2
			}
		} # closes for(j in 1:length(starts)


		if(updatemot!=1 & its!=1){
			###after first iteration, if not changing motif then unsubtract background from last iteration
			overallscores=overallscores+background
			overallscores2=overallscores2+background
		}

		print("Background finding")

		if(its==1){
			###index each sequence by its triplet
			index=newmat
			index[,3:ncol(newmat)]=16*(newmat[,1:(ncol(newmat)-2)]-1)+4*(newmat[,2:(ncol(newmat)-1)]-1)+newmat[,3:ncol(newmat)]
			index[newmat==5]=65
			index[,2:ncol(newmat)][newmat[,1:(ncol(newmat)-1)]==5]=65
			index[,3:ncol(newmat)][newmat[,1:(ncol(newmat)-2)]==5]=65
		}
		
		##tidy up the endpoints using 0.25

		if(length(bg)==1){
			if(length(qvec)==0){
				print("Setting up background....")
				bg=1:64*0
				bg2=matrix(0,nrow=length(seqs),ncol=length(bg))
				for(i in 1:length(seqs)){
					if(!i%%1000){ print(i);print(bg);}
					temp=substring(seqs[i],1,nchar(fullseqs[i]))
					temp=substring(temp,1:nchar(temp),1:nchar(temp))
					temp=as.numeric(temp)
					newtemp=1:(length(temp)-2)
					newtemp=16*(temp[1:(length(temp)-2)]-1)+4*(temp[2:(length(temp)-1)]-1)+(temp[3:(length(temp)-0)]-1)
					newtemp[temp[1:(length(temp)-2)]==5]=-1
					newtemp[temp[2:(length(temp)-1)]==5]=-1
					newtemp[temp[3:(length(temp)-0)]==5]=-1
					for(k in 1:64){
						bg2[i,k]=bg2[i,k]+sum(newtemp==(k-1))
					}
					bg=bg+bg2[i,]
				}
				print("...done")
				####allow either strand because under null don't expect this to matter
				####just getting triplet probs

				e=c("A","C","G","T")
				for(k in 1:2) e=c(paste("A",e,sep=""),paste("C",e,sep=""),paste("G",e,sep=""),paste("T",e,sep=""))
				d=c("T","G","C","A")
				for(k in 1:2) d=c(paste(d,"T",sep=""),paste(d,"G",sep=""),paste(d,"C",sep=""),paste(d,"A",sep=""))

				names(bg)=e
				bg=bg+bg[d]


				#### add one on for the prior, and to make robust to lack of data
				bg=bg+1
				bgstore=bg
				qvec=as.vector(bg)/sum(bg)
				qvecstore=qvec
			}
		}

		#####now use qvec to get scores for all our sequences under the null
		###first, get conditional probabilities for all triplets
		####adjust below!!

		letter1=floor(((1:64)-1)/16)+1
		letter2=floor(((1:64)-(letter1-1)*16-1)/4)+1
		letter3=floor(((1:64)-(letter1-1)*16-(letter2-1)*4-1))+1

		newqvec=qvec*0
		for(i in 1:64){
			newqvec[i]=qvec[i]/sum(qvec[letter1==letter1[i] & letter2==letter2[i]])
		}
		#####add an extra term for missing bases
		newqvec=c(newqvec,0.25)
		newqvec=log(newqvec)
		####now  apply to the matrix storing our triplet lookup information

		###take logs
		###now add up to give the background equivalent to the length of the motif
		background=background*0
		background[is.na(background)]=0
		print(dim(index))
		print(dim(scores))
		print("Putting in background information for the probability of each motif")
		for(j in 1:length(starts)){
			scoremat=scorematset[starts[j]:ends[j],]
			for(i in 1:nrow(scoremat)){
				cols=ncol(background)-nrow(scoremat)+1
				background[(nrow(newmat)*(j-1)+1):(nrow(newmat)*j),1:cols]=background[(nrow(newmat)*(j-1)+1):(nrow(newmat)*j),1:cols]+matrix(newqvec[as.double(index[,i:(i+cols-1)])],nrow=nrow(index))
			}
		}
		print("Done")

		print(range(overallscores))
		print(range(overallscores2))
		print(range(background))
		overallscores=overallscores-background
		overallscores2=overallscores2-background
		print(range(overallscores))
		print(range(overallscores2))

		###assume a uniform prob. inside regions at first then infer
		###priorprobs are just a set of densities

		print("Applying prior matrix")
		priormat=overallscores

		priormat=scores*0
		if(its==1){
			if(is.null(ourprior)){
				prior=rep(0.1,10)
			}
			###otherwise, has vector of 10 probabilities
			else{
				prior=ourprior
				prior=prior/sum(prior)
			}
		}
		print("...OK...")

		##define priormat - note only have to correctly get "proportion" along

		####first take stored "column positions"
		endpos=1:nrow(overallscores)*0
		for(j in 1:length(starts)){
			scoremat=scorematset[starts[j]:ends[j],]
			endpos[(nrow(newmat)*(j-1)+1):(nrow(newmat)*j)]=nchar(fullseqs[(1):(nrow(newmat))])-nrow(scoremat)+1
		}
		print("...OK3...")

		priormat=posmat/endpos
		priormat[priormat>1]=0
		priormat=priormat-1/endpos
		print("...OK4...")

		priormat=floor(priormat*10)+1
		for(i in 1:10) priormat[priormat==i]=prior[i]
		priormat[priormat<=0]=0
		priormat[priormat>10]=0
		priormat=priormat/rowSums(priormat)/2

		scoremat=scorematset

		print("Done")
		print("Setting up sampling probabilities for motifs")
		postforward=exp(overallscores)
		postbackward=exp(overallscores2)
		for(j in 1:length(starts)){
			priormat[(nrow(newmat)*(j-1)+1):(nrow(newmat)*j),]=priormat[(nrow(newmat)*(j-1)+1):(nrow(newmat)*j),]*alpha[j];
		}

		print("Calculating probabilities")
		postforward=postforward*priormat
		postbackward=postbackward*priormat

		for(j in 1:length(starts)){
			temp=postforward[(nrow(newmat)*(j-1)+1):(nrow(newmat)*j),]
			postforward[(nrow(newmat)*(j-1)+1):(nrow(newmat)*j),]=temp
			temp=postbackward[(nrow(newmat)*(j-1)+1):(nrow(newmat)*j),]
			postbackward[(nrow(newmat)*(j-1)+1):(nrow(newmat)*j),]=temp
		}
		print("Done")
		print("Making sampling matrix")
		samplemat=matrix(nrow=nrow(newmat),ncol=ncol(postforward)*length(starts)*2)
		s=ncol(postforward)
		for(j in 1:length(starts)){
			samplemat[,(s*(j-1)*2+1):(s*(2*j-1))]=postforward[(nrow(newmat)*(j-1)+1):(nrow(newmat)*j),];
			samplemat[,(s*(2*j-1)+1):(s*(2*j))]=postbackward[(nrow(newmat)*(j-1)+1):(nrow(newmat)*j),];
		}
		samplemat=samplemat/(rowSums(samplemat)+(1-sum(alpha)))
		###enables sampling

		print("Done")
		print("Sampling")
		######sample
		q=runif(nrow(samplemat))
	
		#####need to record which motif if any
		#####which strand
		#####best position,  best strand
		#####start point
	
		regprobs=matrix(0,nrow=length(q),ncol=length(starts))
		for(j in 1:length(starts)){
			regprobs[,j]=rowSums(samplemat[,(s*(j-1)*2+1):(s*(2*j))])
		}
		regprob=rowSums(regprobs)
		mot=q*0

		print("Picking positions within regions")
		whichcol=mot*0
		testmat=samplemat
		for(j in 2:ncol(samplemat)){
			testmat[,j]=testmat[,(j-1)]+testmat[,j]
		}
		for(j in ncol(samplemat):1){
			whichcol[q<=testmat[,j]]=j
		}
		mot[whichcol!=0]=1
	
		whichmot=floor((whichcol-1)/2/ncol(overallscores))+1
		whichstrand=(floor((whichcol-1)/ncol(overallscores))+1)%%2
		whichpos=whichcol-(whichmot-1)*ncol(overallscores)*2-(1-whichstrand)*ncol(overallscores)
		whichmot=whichmot[mot==1]
		whichpos=whichpos[mot==1]
		whichstrand=whichstrand[mot==1]
		print("Done")

		#######get a prior on positions
		######update prior using sampled positions
		totals=1:length(starts)
		for(i in 1:length(totals)) totals[i]=sum(whichmot==i)

		totals=c(totals,sum(mot==0))
		####make sure prior prob of motif is 1/2 in dirichlet
		totals[length(totals)]=totals[length(totals)]+length(starts)-1
		######need mcmc pack for rdirichlet(n,alpha)
		alphanew=rdirichlet(1,alpha=1+totals)
		##alphanew=rbeta(1,shape1=sum(mot==1)+1,shape2=sum(mot==0)+1)
		######sample start pos

		alphanew=alphanew[1:length(starts)]
		print("Alpha values sampled:")
		print(c(alphanew,sum(alphanew)))
		whichregs=which(mot==1)

		v=hist((whichpos-1)/(nchar(fullseqs[whichregs])-dimvec[whichmot]),breaks=seq(0,1,0.1),plot=plotting)
		if(updateprior==1){
			prior=v$counts+5
			prior=prior/sum(prior)
		}

		####for compatibility
		strand=whichstrand
		print("Sampling sequences")
		###get sequences, to make a new motif
		###background model is going to be based on the overall - inconsistent otherwise
		###so we'll successively subtract the motif occurrences

		bg=bgstore
		qvec=qvecstore

		ourcounts=matrix(nrow=65,ncol=0)
		oursummary=matrix(nrow=5,ncol=0)
		####new, stronger background model

		newbackground=matrix(0,nrow=length(starts),ncol=64)
		for(j in 1:length(starts)){
			print(paste("Updating Motif",j,"counts"))
			scoremat=scorematset[starts[j]:ends[j],]
			tempregs=whichregs[whichmot==j]
			newbackground[j,]=colSums(bg2[whichregs[whichmot==j],])
		
			print(newbackground[j,])
			tempstarts=whichpos[whichmot==j]
			tempends=tempstarts+nrow(scoremat)-1
			tempstrand=whichstrand[whichmot==j]
			ourseqs=matrix(nrow=length(tempregs),ncol=nrow(scoremat)+50)
			sampleseqs=seqs[tempregs]
			v=substring(sampleseqs,tempstarts-25,tempends+25)
			for(i in 1:length(v)) if(tempstarts[i]<=25){
				v[i]=paste(c(rep("5",25-tempstarts[i]+1),v[i]),collapse="")
			} 
			for(i in 1:length(v)) if(tempends[i]+25>nchar(sampleseqs)[i]){
				v[i]=paste(c(v[i],rep("5",tempends[i]+25-nchar(sampleseqs)[i])),collapse="")
			} 
			######have subsequences
			for(k in 1:(nrow(scoremat)+50)) ourseqs[,k]=as.double(substring(v,k,k))

			ourseqs2=ourseqs[,ncol(ourseqs):1]
			ourseqs2=5-ourseqs2
			ourseqs2[ourseqs2==0]=5
			ourseqs[tempstrand==0,]=ourseqs2[tempstrand==0,]
			summary=matrix(nrow=4,ncol=ncol(ourseqs))
			for(i in 1:4) summary[i,]=colSums(ourseqs==i)
			oursummary=cbind(oursummary,rbind(summary,j))
			####this gives us counts - now need to get likelihood under a background model 
			####enables us to sample a new motif in a relatively "principled" manner
	
			print("Building background model...")
			newtemp=16*(ourseqs[,1:(ncol(ourseqs)-2)]-1)+4*(ourseqs[,2:(ncol(ourseqs)-1)]-1)+(ourseqs[,3:(ncol(ourseqs)-0)]-1)
			newtemp[ourseqs[,1:(ncol(ourseqs)-2)]==5]=-1
			newtemp[ourseqs[,2:(ncol(ourseqs)-1)]==5]=-1
			newtemp[ourseqs[,3:(ncol(ourseqs)-0)]==5]=-1
			newtemp=newtemp+1
			motcounts=matrix(ncol=ncol(newtemp),nrow=64)
			for(i in 1:64) motcounts[i,]=colSums(newtemp==i)
			print("...done")

			bg=bg-rowSums(motcounts)
			ourcounts=cbind(ourcounts,rbind(motcounts,j))	
	
		}
		####fold over background - may need this to avoid negative values, given strand flipping

		e=c("A","C","G","T")
		for(i in 1:2) e=c(paste("A",e,sep=""),paste("C",e,sep=""),paste("G",e,sep=""),paste("T",e,sep=""))
		d=c("T","G","C","A")
		for(i in 1:2) d=c(paste(d,"T",sep=""),paste(d,"G",sep=""),paste(d,"C",sep=""),paste(d,"A",sep=""))

		names(bg)=e
		bg=bg+bg[d]
		###add one for prior
		bg=bg+1
		colnames(newbackground)=e
		newbackground=newbackground+newbackground[,d]
		qvec=as.vector(bg)/sum(bg)
		newqvec=newbackground/rowSums(newbackground)

		letter1=floor(((1:64)-1)/16)+1
		letter2=floor(((1:64)-(letter1-1)*16-1)/4)+1
		letter3=floor(((1:64)-(letter1-1)*16-(letter2-1)*4-1))+1

		predfrac=matrix(nrow=64,ncol=4)
		for(i in 1:64){
			predfrac[i,1]=qvec[letter1==letter1[i] & letter3==letter3[i] & letter2==1]
			predfrac[i,2]=qvec[letter1==letter1[i] & letter3==letter3[i] & letter2==2]
			predfrac[i,3]=qvec[letter1==letter1[i] & letter3==letter3[i] & letter2==3]
			predfrac[i,4]=qvec[letter1==letter1[i] & letter3==letter3[i] & letter2==4]
		}
		predfrac=predfrac/rowSums(predfrac)

		newpredfrac=array(0,dim=c(length(starts),64,4))

		for(i in 1:64){
			newpredfrac[,i,1]=newqvec[,letter1==letter1[i] & letter3==letter3[i] & letter2==1]
			newpredfrac[,i,2]=newqvec[,letter1==letter1[i] & letter3==letter3[i] & letter2==2]
			newpredfrac[,i,3]=newqvec[,letter1==letter1[i] & letter3==letter3[i] & letter2==3]
			newpredfrac[,i,4]=newqvec[,letter1==letter1[i] & letter3==letter3[i] & letter2==4]
		}
		for(j in 1:length(starts)){
			newpredfrac[j,,]=newpredfrac[j,,]/rowSums(newpredfrac[j,,])
		}

		###this gives the prediction we can now apply to each motif

		newnewdim=vector(length=0)
		newmatset=matrix(nrow=0,ncol=4)
		bindmatset=matrix(nrow=0,ncol=4)

		for(j in 1:length(starts)){
			motcounts=ourcounts[1:64,ourcounts[65,]==j]
			motcounts=t(motcounts)
			summary=oursummary[1:4,oursummary[5,]==j]
			expcounts=matrix(nrow=nrow(motcounts),ncol=4)
			###add one for robustness
			for(i in 1:4) expcounts[,i]=motcounts %*% newpredfrac[j,,i]+1
			expcounts=expcounts/rowSums(expcounts)
			summary=summary[,2:(ncol(summary)-1)]

			expsummary=t(expcounts)
			summary2=summary/expsummary*rowSums(expcounts)
			noninclogprob=colSums(summary*t(log(expcounts)))
			print("Calculating likelihood terms")
			###have a uniform prior for bases included, four bases
			########need likelihood for an included base
			###uniform dirichlet prior leads to following posterior after integrating out frequencies
			inclogprob=log(6)+logfact[summary[1,]+1]+logfact[summary[2,]+1]+logfact[summary[3,]+1]+
			logfact[summary[4,]+1]-logfact[colSums(summary)+4]
			increl=log(incprob*exp(inclogprob-noninclogprob)+(1-incprob))
			increl[is.infinite(increl)]=(inclogprob-noninclogprob)[is.infinite(increl)]
			newrel=c(0,cumsum((increl)))

			#####get lhood for each possible value
			lhood=matrix(0,nrow=ncol(summary),ncol=ncol(summary))
			for(start in 1:ncol(summary)){
				for(end in start:ncol(summary)){
					lhood[start,end]=log(plen)*(end-start)+log(1-plen)+newrel[end+1]-newrel[start]
				}
			}

			######these are relative log-probs
			lhood2=exp(lhood-max(lhood[lhood!=0]))
			lhood2[lhood==0]=0
			lhood2=lhood2/sum(lhood2[lhood!=0])
			motpos=sample(length(lhood2),1,prob=as.double(lhood2))
			start=motpos %% nrow(lhood2)
			if(start==0) start=nrow(lhood2)
			end=(motpos-start)/nrow(lhood2)+1
			#######have sampled new motif start and end positions
			###sample new parameters - should be dirichlet but use expectations instead
			temp=summary[,start:end]+1
			temp=matrix(temp,nrow=4)
			temp=t(t(temp)/colSums(temp))
			temp=matrix(log(temp),nrow=4)
			#######for binding, get rid of background
			temp2=summary2[,start:end]+1
			temp2=matrix(temp2,nrow=4)
			##temp2=t(t(temp2)/colSums(temp2))
			temp2=matrix(log(temp2),nrow=4)
			newmat=matrix(nrow=end-start+1,ncol=4)
			newmat[,1:4]=t(temp)
			newmat2=t(temp2)
			####make a new combined matrix for looking at...
			newmatset=rbind(newmatset,newmat)
			bindmatset=rbind(bindmatset,newmat2)
			newnewdim=c(newnewdim,nrow(newmat))
		}

		###expected fractions for each base conditional on their neighbours

		#####set new params
		scorematsetold=scorematset
		if(updatealpha==1) alpha=alphanew

		if(updatemot==1){
 			scorematset=newmatset[,1:4]
			dimvec=newnewdim
		}else {
			scorematset=scorematset[,1:4]
		}
		alphas=rbind(alphas,alpha)

		####remove motifs if not viable
		if(min(length(fullseqs)*alpha)<=10){
			print("Some motifs have <=10 expected copies, removing")
			print(which(length(fullseqs)*alpha<=10))
			newmat=matrix(nrow=0,ncol=4)
			newmat2=matrix(nrow=0,ncol=4)
			newstarts=c(1,cumsum(dimvec)+1)
			newends=cumsum(dimvec)
			for(i in 1:length(dimvec)) if(length(fullseqs)*alpha[i]>10){ 
				newmat=rbind(newmat,scorematset[newstarts[i]:newends[i],])
				newmat2=rbind(newmat2,bindmatset[newstarts[i]:newends[i],])
			}
			scorematset=newmat
			bindmatset=newmat2
			dimvec=dimvec[length(fullseqs)*alpha>10]
			####remove offending motif
			alphas=alphas[,length(fullseqs)*alpha>10]
			alpha=alpha[length(fullseqs)*alpha>10]
		}

		####remove motifs if not long enough
		if(min(dimvec)<=3){
			remo=which(dimvec<=3)
			print("Some motifs have length <=3, removing")
			print(remo)
			print(dimvec[remo])
			newmat=matrix(nrow=0,ncol=4)
			newmat2=matrix(nrow=0,ncol=4)
			newstarts=c(1,cumsum(dimvec)+1)
			newends=cumsum(dimvec)
			for(i in 1:length(dimvec)) if(dimvec[i]>3){ 
				newmat=rbind(newmat,scorematset[newstarts[i]:newends[i],])
				newmat2=rbind(newmat2,bindmatset[newstarts[i]:newends[i],])
			}
			scorematset=newmat
			bindmatset=newmat2

			scorematset=newmat
			####remove offending motif
			print(dim(alphas))
			print(length(dimvec))
			alphas=alphas[,dimvec>3]
			alpha=alpha[dimvec>3]
			dimvec=dimvec[dimvec>3]
		}

		###plot logos 
		if(plotting){
			length=length(dimvec)
			if(length%%3 !=0) length=length+3-(length %%3)
			rowcount=length/3
			library("seqLogo") 
			mySeqLogo = seqLogo::seqLogo 
			bad = (sapply( body(mySeqLogo), "==", "grid.newpage()") | sapply( body(mySeqLogo), "==", "par(ask = FALSE)"))
			body(mySeqLogo)[bad] = NULL 

			yvec=vector(length=0)
			for(i in 1:(length/3)) yvec=c(yvec,rep(1.2/length+(i-1)*3/length,3))
			xvec=c(0.1666667, 0.5000000, 0.8333333)
			xvec=rep(xvec,length=length)

			newstarts=c(1,cumsum(dimvec)+1)
			newends=cumsum(dimvec)
    		grid.newpage()

			for(i in 1:length(dimvec)){
				testmat=scorematset[newstarts[i]:newends[i],]
				testmat=exp(testmat)
				testmat=testmat/rowSums(testmat)
				norm = function(x) scale(x, center=FALSE, scale=colSums(x))
				pwm = t(testmat)


				pushViewport(viewport(x=xvec[i],y=yvec[i], width=0.8/2, height=1.2/rowcount,))
				mySeqLogo(pwm)
				popViewport()		
			}
		}
	} #ends iteration while loop
	cat(paste(proc.time()-starttime,"\n"))
	return(list(seqs=origseqs,alphas=alphas,beststrand=beststrand, trimmedseqs=fullseqs,prior=prior,alpha=alpha,bindmat=bindmatset,scoremat=scorematset,scorematdim=dimvec,regprob=regprob,regprobs=regprobs,bestmatch=bestpos,whichregs=whichregs,whichpos=whichpos,background=qvec,whichmot=whichmot, whichstrand=strand))
}
