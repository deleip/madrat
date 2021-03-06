#' toolAggregate
#' 
#' (Dis-)aggregates a magclass object from one resolution to another based on a
#' relation matrix or mapping
#' 
#' Basically toolAggregate is doing nothing more than a normal matrix
#' multiplication which is taking into account the 3 dimensional structure of
#' MAgPIE objects. So, you can provide any kind of relation matrix you would
#' like. However, for easier usability it is also possible to provide weights
#' for a weighted (dis-)aggregation as a MAgPIE object. In this case rel must
#' be a 1-0-matrix or a mapping between both resolutions. The weight
#' needs to be provided in the higher spatial aggregation, meaning for
#' aggregation the spatial resolution of your input data and in the case of
#' disaggregation the spatial resolution of your output data. The temporal and
#' data dimension must be either identical to the resolution of the data set
#' that should be (dis-)aggregated or 1. If the temporal and/or data dimension
#' is 1 this means that the same transformation matrix is applied for all years
#' and/or all data columns. In the case that a column should be just summed up
#' instead of being calculated as a weighted average you either do not provide
#' any weight (then all columns are just summed up) or your set this specific
#' weighting column to NA and mixed_aggregation to TRUE.
#' 
#' @param x magclass object that should be (dis-)aggregated
#' @param rel relation matrix, mapping or file containing a mapping in a format
#' supported by \code{\link{toolGetMapping}} (currently csv, rds or rda).
#' A mapping object should contain 2 columns in which each element of x
#' is mapped to the category it should belong to after (dis-)aggregation
#' @param weight magclass object containing weights which should be considered
#' for a weighted aggregation. The provided weight should only contain positive
#' values, but does not need to be normalized (any positive number>=0 is allowed). 
#' Please see the "details" section below for more information.
#' @param from Name of source column to be used in rel if it is a
#' mapping (if not set the first column matching the data will be used). 
#' @param to Name of the target column to be used in rel if it is a
#' mapping (if not set the column following column \code{from} will be used
#' If column \code{from} is the last column, the column before \code{from is
#' used}). If data should be aggregated based on more than one column these
#' columns can be specified via "+", e.g. "region+global" if the data should
#' be aggregated to column regional as well as column global. 
#' @param dim Specifying the dimension of the magclass object that should be
#' (dis-)aggregated. Either specified as an integer
#' (1=spatial,2=temporal,3=data) or if you want to specify a sub dimension
#' specified by name of that dimension or position within the given dimension
#' (e.g. 3.2 means the 2nd data dimension, 3.8 means the 8th data dimension).
#' @param wdim Specifying the according weight dimension as chosen with dim
#' for the aggregation object. If set to NULL the function will try to
#' automatically detect the dimension.
#' @param partrel If set to TRUE allows that the relation matrix does contain
#' less entries than x and vice versa. These values without relation are lost
#' in the output.
#' @param negative_weight Describes how a negative weight should be treated. "allow"
#' means that it just should be accepted (dangerous), "warn" returns a warning and
#' "stop" will throw an error in case of negative values
#' @param mixed_aggregation boolean which allows for mixed aggregation (weighted 
#' mean mixed with summations). If set to TRUE weight columns filled with NA
#' will lead to summation.
#' @param verbosity Verbosity level of messages coming from the function: -1 = error, 
#' 0 = warning, 1 = note, 2 = additional information, >2 = no message
#' @return the aggregated data in magclass format
#' @author Jan Philipp Dietrich, Ulrich Kreidenweis
#' @export
#' @importFrom magclass wrap ndata fulldim clean_magpie mselect setCells getCells mbind setComment getNames getNames<- 
#' @importFrom magclass is.magpie getComment getComment<- dimCode getYears getYears<- getRegionList as.magpie getItems collapseNames 
#' @importFrom magclass updateMetadata withMetadata getDim getSets getSets<-
#' @importFrom utils object.size
#' @importFrom spam diag.spam as.matrix
#' @seealso \code{\link{calcOutput}}
#' @examples
#' 
#' # create example mapping
#' mapping <- data.frame(from   = getRegions(population_magpie),
#'                       region = rep(c("REG1","REG2"),5),
#'                       global = "GLO")
#' mapping 
#' 
#' # run aggregation
#' toolAggregate(population_magpie,mapping)
#' # weighted aggregation
#' toolAggregate(population_magpie,mapping, weight=population_magpie)
#' # combined aggregation across two columns
#' toolAggregate(population_magpie, mapping, to="region+global")

toolAggregate <- function(x, rel, weight=NULL, from=NULL, to=NULL, dim=1, wdim=NULL, partrel=FALSE, negative_weight="warn", mixed_aggregation=FALSE, verbosity=1) {

  if(!is.magpie(x)) stop("Input is not a MAgPIE object, x has to be a MAgPIE object!")
  
  comment <- getComment(x)
  if (withMetadata() && !is.null(getOption("calcHistory_verbosity")) && getOption("calcHistory_verbosity")>1) {
    if (object.size(sys.call()) < 5000 && as.character(sys.call())[1]=="toolAggregate")  calcHistory <- "update"
    #Special calcHistory handling necessary for do.call(x$aggregationFunction,x$aggregationArguments) from calcOutput
    else  calcHistory <- paste0("toolAggregate(x=unknown, rel=unknown, dim=",dim,", mixed_aggregation=",mixed_aggregation,")")
  } else  calcHistory <- "copy"
  
  if(!is.numeric(rel) & !("spam" %in% class(rel))) {
    .getAggregationMatrix <- function(rel,from=NULL,to=NULL,items=NULL,partrel=FALSE) {
      
      if("tbl" %in% class(rel)){
        rel <- data.frame(rel)
      }
      if(!(is.matrix(rel) | is.data.frame(rel))) {
        if(!file.exists(rel)) stop("Cannot find given region mapping file!")
        rel <- toolGetMapping(rel, where="local")
      }
      if(is.matrix(rel)) rel <- as.data.frame(rel)
      
      if(is.null(from)) {
        if(partrel) {
          from <- as.integer(which(sapply(lapply(rel,setdiff,items),length)==0))
        } else {
          from <- as.integer(which(sapply(rel,setequal,items)))
        }
        if(length(from)==0) stop("Could not find matching 'from' column in mapping!")
        if(length(from)>1) from <- from[1]
      }
      if(is.null(to)) {
        if(from < length(rel)) {
          to <- from+1
        } else if(from > 1) {
          to <- from-1
        } else {
          to <- 1
        }
      }
      
      regions <- unique(rel[,to])
      countries <- unique(rel[,from])
      m <- matrix(data=0, nrow=length(regions),ncol=length(countries),dimnames=list(regions=regions,countries=countries))
      m[cbind(match(rel[,to],rownames(m)),match(rel[,from],colnames(m)))] <- 1
      if(is.numeric(to)) to <- dimnames(rel)[[2]][to]
      if(is.numeric(from)) from <- dimnames(rel)[[2]][from]
      names(dimnames(m)) <- c(to,from)
      return(m)
    } 
    if(length(to)==1 && grepl("+",to,fixed=TRUE)) {
      tmprel <- NULL
      to <- strsplit(to, "+", fixed=TRUE)[[1]]
      for(t in to) {
        tmp <- .getAggregationMatrix(rel,from=from,to=t,items=getItems(x,dim=dim),partrel=partrel) 
        tmprel <- rbind(tmprel,tmp)
      }
      rel <- tmprel
    } else {
      rel <- .getAggregationMatrix(rel,from=from,to=to,items=getItems(x,dim=dim),partrel=partrel) 
    }
  }

  #translate dim to dim code
  dim <- dimCode(dim,x,missing="stop")
  

  ## allow the aggregation, even if not for every entry in the initial dataset there is a respective one in the relation matrix
  if (partrel){
    datnames <-  getItems(x,dim)
    
    common <- intersect(datnames, colnames(rel))
    if(length(common)==0) stop("The relation matrix consited of no entry that could be used for aggregation")
    if(floor(dim)==1) x <- x[common,,]
    if(floor(dim)==2) x <- x[,common,]
    if(floor(dim)==3) x <- x[,,common]
    
    # datanames not in relnames
    noagg <- datnames[!datnames %in% colnames(rel)]
    if(length(noagg)>1) vcat(verbosity, "The following entries were not aggregated because there was no respective entry in the relation matrix", noagg, "\n")
    
    rel <- rel[,common]
    rel <- subset(rel, subset=rowSums(rel)>0)
  }

  if(!is.null(weight)) {
    if(!is.magpie(weight)) stop("Weight is not a MAgPIE object, weight has to be a MAgPIE object!")
    #get proper weight dim
    
    if(is.null(wdim)) {
      wdim <- union(getDim(rownames(rel),weight,fullmatch=TRUE),
                    getDim(colnames(rel),weight,fullmatch=TRUE))
      # wdim must be in same main dimension as dim
      wdim <- wdim[floor(wdim)==floor(dim)]
    }

    if(length(wdim)==0) stop("Could not detect aggregation dimension in weight (no match)!")
    if(length(wdim)>1) {
      if(any(wdim==floor(dim))) wdim <- floor(dim) # if full dimension and subdimension is matched, use only full dimension
      else stop("Could not detect aggregation dimension in weight (multiple matches)!")
    }  
      
    if(floor(dim)==dim) wdim <- floor(wdim)
    
    if(anyNA(weight)) {
      if(!mixed_aggregation) {
        stop("Weight contains NAs which is only allowed if mixed_aggregation=TRUE!")
      } else {
        n <- length(getItems(weight,dim=wdim))
        r <- dimSums(is.na(weight), dim=wdim)
        if(!all(r %in% c(0,n))) stop("Weight contains columns with a mix of NAs and numbers which is not allowed!")
      }
    }
    if(nyears(weight)==1) getYears(weight) <- NULL
    weight <- collapseNames(weight)
    if(negative_weight!="allow" & any(weight<0, na.rm=TRUE)) {
      if(negative_weight=="warn") {
        warning("Negative numbers in weight. Dangerous, was it really intended?")
      } else {
        stop("Negative numbers in weight. Weight should be positive!")
      }
    }
    weight2 <- 1/(toolAggregate(weight, rel, from=from, to=to, dim=wdim, partrel=partrel, verbosity=10) + 10^-100)
    if(mixed_aggregation) {
      weight2[is.na(weight2)] <- 1
      weight[is.na(weight)] <- 1
    }
    
    if(setequal(getItems(weight, dim=wdim), getItems(x, dim=dim))) {
      if(wdim!=floor(wdim)) getSets(weight)[paste0("d",wdim)] <- getSets(x)[paste0("d",dim)]
      out <- toolAggregate(x*weight,rel, from=from, to=to, dim=dim, partrel=partrel)*weight2
    } else if(setequal(getItems(weight2, dim=wdim), getItems(x, dim=dim))) {
      if(wdim!=floor(wdim)) getSets(weight2)[paste0("d",wdim)] <- getSets(x)[paste0("d",dim)]
      out <- toolAggregate(x*weight2,rel, from=from, to=to, dim=dim, partrel=partrel)*weight
    } else {
      if(partrel) {
        stop("Weight does not match data. For partrel=TRUE make sure that the weight is already reduced to the intersect of relation matrix and x!") 
      } else {
        stop("Weight does not match data")
      }
    }
    getComment(out) <- c(comment,paste0("Data aggregated (toolAggregate): ",date()))
    return(updateMetadata(out,x,unit="copy",calcHistory=calcHistory))
  }  else {
    
    #make sure that rel and weight cover a whole dimension (not only a subdimension)
    #expand data if necessary
    #set dim to main dimension afterwards
    if(round(dim)!=dim) {
      .expand_rel <- function(rel,names,dim){
        #Expand rel matrix to full dimension if rel is only provided for a subdimension
        
        if(round(dim)==dim | suppressWarnings(all(colnames(rel)==names))) {
          #return rel if nothing has to be done
          return(rel)
        } 
        
        subdim <- round((dim-floor(dim))*10)
        maxdim <- nchar(gsub("[^\\.]","",names[1])) + 1
        
        search <- paste0("^(",paste(rep("[^\\.]*\\.",subdim-1),collapse=""),")([^\\.]*)(",paste(rep("\\.[^\\.]*",maxdim-subdim),collapse=""),")$")
        onlynames <- unique(sub(search,"\\2",names))
          
        if(length(setdiff(colnames(rel),onlynames))>0) {
          if (length(setdiff(rownames(rel),onlynames))>0) {
            stop("The provided mapping contains entries which could not be found in the data: ",paste(setdiff(colnames(rel),onlynames),collapse=", "))
          }else  rel <- t(rel)
        }else if(length(setdiff(onlynames,colnames(rel)))>0) {
          if (length(setdiff(onlynames,rownames(rel)))>0) {
            stop("The provided data set contains entries not covered by the given mapping: ",paste(setdiff(onlynames,colnames(rel)),collapse=", "))
          }else  rel <- t(rel)
        }
          
        tmp <- unique(sub(search,"\\1#|TBR|#\\3",names)) 
        additions <- strsplit(tmp,split="#|TBR|#",fixed=TRUE)
        cnames <- NULL
        rnames <- NULL
        for(i in 1:length(additions)) {
          if(is.na(additions[[i]][2])) additions[[i]][2] <- ""
          cnames <- c(cnames,paste0(additions[[i]][1],colnames(rel),additions[[i]][2]))
          rnames <- c(rnames,paste0(additions[[i]][1],rownames(rel),additions[[i]][2]))
        }
        
        new_rel <- matrix(0,nrow=length(rnames),ncol=length(cnames),dimnames=list(rnames,cnames))
        
        for(i in 1:length(additions)) {
          new_rel[1:nrow(rel)+(i-1)*nrow(rel),1:ncol(rel)+(i-1)*ncol(rel)] <- rel
        }
        return(new_rel[,names])
      }
      rel <- .expand_rel(rel,getItems(x,round(floor(dim))),dim)
      dim <- round(floor(dim))
    }
    
    if(dim(x)[dim]!=dim(rel)[2]){
      if(dim(x)[dim]!=dim(rel)[1]) {
        stop("Relation matrix has in both dimensions a different number of entries (",dim(rel)[1],", ",dim(rel)[2],") than x has cells (",dim(x)[dim],")!")
      } else {
        rel <- t(rel)
      }
    }
    
    #reorder MAgPIE object based on column names of relation matrix if available
    if(!is.null(colnames(rel))) {
      if(dim==1) if(any(colnames(rel)!=getCells(x))) x <- x[colnames(rel),,]
      if(dim==2) if(any(colnames(rel)!=getYears(x))) x <- x[,colnames(rel),]
      if(dim==3) if(any(colnames(rel)!=getNames(x))) x <- x[,,colnames(rel)]
    }
    
    #Aggregate data
    matrix_multiplication <- function(y,x) {
      if(any(is.infinite(y))) {
        #Special Inf treatment to prevent that a single Inf in x
        #is setting the full output to NaN (because 0*Inf is NaN)
        #Infs are now treated in a way that anything except 0 times Inf
        #leads to NaN, but 0 times Inf leads to NaN
        for(i in c(-Inf,Inf)) {
          j <- (is.infinite(y) & (y == i))
          x[,j][x[,j]!=0] <- i
          y[j] <- 1
        }
      }
      if(any(is.na(y))) {
        #Special NA treatment to prevent that a single NA in x
        #is setting the full output to NA (because 0*NA is NA)
        #NAs are now treated in a way that anything except 0 times NA
        #leads to NA, but 0 times NA leads to 0
        x[,is.na(y)][x[,is.na(y)]!=0] <- NA
        y[is.na(y)] <- 0
      }
      return(x%*%y)   
    }
    out <- apply(x, which(1:3!=dim),matrix_multiplication,rel)
    if(length(dim(out))==2) out <- array(out,dim=c(1,dim(out)),dimnames=c("",dimnames(out)))
    
    #Write dimnames of aggregated dimension
    if(!is.null(rownames(rel))) {
      reg_out <- rownames(rel)
    } else if(dim==1) {
      reg_out <- factor(round(rel %*% as.numeric(getRegionList(x))/(rel %*% rep(1, dim(rel)[2]))))
      levels(reg_out) <- levels(getRegionList(x))
    } else {
      stop("Missing dimnames for aggregated dimension")
    }
    if(!any(grepl("\\.",reg_out))) {
      if(anyDuplicated(reg_out)) reg_out <- paste(reg_out,1:dim(out)[1],sep=".")
    }
    
    dimnames(out)[[1]] <- reg_out
    
    if(dim==2) out <- wrap(out,map=list(2,1,3))
    if(dim==3) out <- wrap(out,map=list(2,3,1))
    
    getSets(out,fulldim=FALSE) <- getSets(x,fulldim=FALSE)
    
    getComment(out) <- c(comment,paste0("Data aggregated (toolAggregate): ",date()))
    out <- as.magpie(out,spatial=1,temporal=2)
    return(updateMetadata(out,x,unit="copy",calcHistory=calcHistory))
  }
}
