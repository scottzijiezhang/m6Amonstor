#' @title plotGeneCov
#' @param readsOut The data list from countReads and other analysis.
#' @param geneName The gene symbol to be ploted.
#' @param GTF The GRanges object containing gtf annotation. Can obtain by rtracklayer::import("file.gtf", format= "gtf").
#' @param libraryType Specify whether the library is the same or opposite strand of the original RNA molecule. Default is "opposite".
#' @param center Specify the method to calculate average coverage of each group. Could be mean or median.
#' @param ZoomIn c(start,end) The coordinate to zoom in at the gene to be ploted.
#' @param adjustExprLevel logical parameter. Specify whether normalize the two group so that they have similar expression level.
#' @export
plotGeneCov <- function(readsOut, geneName, libraryType = "opposite", center = "mean", GTF, ZoomIn = NULL, adjustExprLevel = TRUE){
  if("X" %in% names(readsOut) ){
    X <- factor(readsOut$X)
    plotGeneCoverage(IP_BAMs = readsOut$bamPath.ip,
                     INPUT_BAMs = readsOut$bamPath.input,
                     size.IP = readsOut$sizeFactor$ip,
                     size.INPUT = readsOut$sizeFactor$input,
                     X, geneName,
                     geneModel = readsOut$geneModel,
                     libraryType, center  ,GTF,ZoomIn, adjustExprLevel, plotSNP = NULL  )+
      theme(plot.title = element_text(hjust = 0.5,size = 15,face = "bold"),legend.title =  element_text(hjust = 0.5,size = 13,face = "bold"),legend.text =  element_text(size = 12,face = "bold"))
  }else{
    plotGeneCoverage(IP_BAMs = readsOut$bamPath.ip,
                     INPUT_BAMs = readsOut$bamPath.input,
                     size.IP = readsOut$sizeFactor$ip,
                     size.INPUT = readsOut$sizeFactor$input,
                     rep("x",length(readsOut$samplenames)), geneName,
                     geneModel = readsOut$geneModel,
                     libraryType, center  ,GTF,ZoomIn, adjustExprLevel, plotSNP = NULL  )+
      theme(plot.title = element_text(hjust = 0.5,size = 15,face = "bold"),legend.position="none" )
  }


}


#' @title plotGeneCoverage
#' @param IP_BAM The bam files for IP samples
#' @param INPUT_BAM The bam files for INPUT samples
#' @param size.IP The size factor for IP libraries
#' @param size.INPUT The size factor for INPUT libraries
#' @param geneName The name (as defined in gtf file) of the gene you want to plot
#' @param geneModel The gene model generated by gtfToGeneModel() function
#' @param libraryType "opposite" for mRNA stranded library, "same" for samll RNA library
#' @param GTF gtf annotation as GRanges object. Can be obtained by GTF <- rtracklayer::import("xxx.gtf",format = "gtf")
#' @param adjustExprLevel Logic parameter determining whether adjust coverage so that input are at "same" expression level.
#' @param plotSNP The option to plot SNP on the figure. Null by default. If want to include SNP in the plot, the parameter needs to ba a dataframe like this:  data.frame(loc= position, anno="A/G")
#' @export
plotGeneCoverage <- function(IP_BAMs, INPUT_BAMs, size.IP, size.INPUT,X, geneName, geneModel, libraryType = "opposite", center = mean ,GTF,ZoomIn=NULL, adjustExprLevel = FALSE, plotSNP = NULL){

  registerDoParallel( length(levels(X)) )
  INPUT.cov <- foreach(ii = levels(X),.combine = cbind)%dopar%{
    getAveCoverage(geneModel= geneModel,bamFiles = INPUT_BAMs[X==ii],geneName = geneName,size.factor = size.INPUT[X==ii], libraryType = libraryType, center = center,ZoomIn = ZoomIn)
  }
  IP.cov <- foreach(ii = levels(X),.combine = cbind)%dopar%{
    getAveCoverage(geneModel= geneModel,bamFiles = IP_BAMs[X==ii],geneName = geneName,size.factor = size.IP[X==ii], libraryType = libraryType, center = center, ZoomIn = ZoomIn)
  }
  rm(list=ls(name=foreach:::.foreachGlobals), pos=foreach:::.foreachGlobals)

  if(adjustExprLevel){
    cov.size <- colSums(INPUT.cov)/mean(colSums(INPUT.cov))
    INPUT.cov <- t(  t(INPUT.cov)/cov.size )
    IP.cov <- t( t(IP.cov)/cov.size )
  }

  cov.data <- data.frame(genome_location=rep(as.numeric(rownames(IP.cov) ),length(levels(X))),
                         IP=c(IP.cov),Input=c(INPUT.cov),
                         Group = factor( rep(levels(X),rep(nrow(IP.cov),length(levels(X)) ) ), levels = levels(X) )
  )
  yscale <- max(IP.cov,INPUT.cov)

  chr <- unique(as.character(as.data.frame(geneModel[geneName])$seqnames))

  p1 <- "ggplot(data = cov.data,aes(genome_location))+geom_line(aes(y=Input,colour =Group))+geom_ribbon(aes(ymax = IP,ymin=0,fill=Group), alpha = 0.4)+labs(y=\"normalized coverage\",x = paste0( \"Genome location on chromosome: \", chr) )+scale_x_continuous(breaks = round(seq(min(cov.data$genome_location), max(cov.data$genome_location), by = ((max(cov.data$genome_location)-min(cov.data$genome_location))/10) )),expand = c(0,0))+theme_bw() + theme(panel.border = element_blank(), panel.grid.major = element_blank(),
  panel.grid.minor = element_blank(), axis.line = element_line(colour = \"black\"),axis.title = element_text(face = \"bold\"),axis.text = element_text(face = \"bold\") ) + scale_fill_discrete(name=\"IP\") + scale_colour_discrete(name=\"INPUT\")+ scale_y_continuous(expand = c(0, 0))"

  p2 <- .getGeneModelAnno(geneModel,geneName,GTF,ZoomIn)

  ## handle the option of plot the SNP in the gene model.
  if(is.null(plotSNP) ){
    p <- paste(p1,p2,sep = "+")
  }else{

    ## if the SNP is outside of the gene
    if(plotSNP$loc >max(cov.data$genome_location) ){

      plotSNP_new <- max(cov.data$genome_location) + 0.025*length(cov.data$genome_location)
      p3 <- "annotate(\"rect\",xmin = ( plotSNP_new -2 ), xmax = ( plotSNP_new +2 ) , ymin = -0.08*yscale, ymax = -0.02*yscale, alpha = .99, colour = \"red\")+
      annotate(\"text\", ,x=plotSNP_new, y = -0.1*yscale, label= paste0(  chr,\":\",as.character(plotSNP$loc)), alpha = .99, colour = \"black\")+
      annotate(\"text\", ,x=plotSNP_new, y = 0, label=as.character(plotSNP$anno), alpha = .99, colour = \"blue\")"
      p <- paste(p1,p2,p3,sep = "+")

    }else if( plotSNP$loc<min(cov.data$genome_location) ){

      plotSNP_new <- max(cov.data$genome_location) - 0.025*length(cov.data$genome_location)
      p3 <- "annotate(\"rect\",xmin = ( plotSNP_new -2 ), xmax = ( plotSNP_new +2 ) , ymin = -0.08*yscale, ymax = -0.02*yscale, alpha = .99, colour = \"red\")+
      annotate(\"text\", ,x=plotSNP_new, y = -0.1*yscale, label= paste0(  chr,\":\",as.character(plotSNP$loc)), alpha = .99, colour = \"black\")+
      annotate(\"text\", ,x=plotSNP_new, y = 0, label=as.character(plotSNP$anno), alpha = .99, colour = \"blue\")"
      p <- paste(p1,p2,p3,sep = "+")

    }else{ ## if the SNP is within the gene
      p3 <- "annotate(\"rect\",xmin = (plotSNP$loc-2 ), xmax = ( plotSNP$loc+2 ) , ymin = -0.08*yscale, ymax = -0.02*yscale, alpha = .99, colour = \"red\")+
      annotate(\"text\", ,x=plotSNP$loc, y = -0.1*yscale, label=as.character(plotSNP$anno), alpha = .99, colour = \"blue\")"
      p <- paste(p1,p2,p3,sep = "+")
    }

  }

  eval(parse( text = p ))
}


## helper function to get average coverage of a gene of multiple samples
getAveCoverage <- function(geneModel,bamFiles,geneName,size.factor, libraryType = libraryType, center ,ZoomIn){
  locus <- as.data.frame( range(geneModel[geneName][[1]]) )
  if(is.null(ZoomIn)){
  }else{
    locus$start = ZoomIn[1]
    locus$end = ZoomIn[2]
    locus$width = ZoomIn[2] - ZoomIn[1] + 1
  }
  covs <- sapply(bamFiles,getCov,locus=locus, libraryType = libraryType)
  covs <- t( t(covs)/size.factor )
  ave.cov <- apply(covs,1, center)
  return(ave.cov)
}

getCov <- function(bf,locus, libraryType ){
  s_param <- ScanBamParam(which = GRanges(locus$seqnames,IRanges(locus$start,locus$end)))
  p_param <- PileupParam(max_depth=1000000,min_nucleotide_depth=0,distinguish_nucleotides=F)
  #get coverage from the bam file
  res <- pileup(bf,scanBamParam = s_param,pileupParam = p_param)
  if(libraryType == "opposite"){
    res <- res[res$strand!=locus$strand,]
  }else if (libraryType == "same"){
    res <- res[res$strand==locus$strand,]
  }else{
    stop("libraryType must be opposite or same... ")
  }
  cov <- vector(length = locus$width)
  names(cov) <- c(locus$start:locus$end)
  cov[1:locus$width] <- 0
  cov[res$pos-locus$start+1] <- res$count
  return(cov)
}

.getGeneModelAnno <- function(geneModel,geneName,gtf_grange,zoomIn = NULL){
  exon.current <- reduce( geneModel[geneName][[1]] )
  startCodon <-  reduce( gtf_grange[gtf_grange$type == "start_codon" & gtf_grange$gene_id == geneName] )
  stopCodon <- reduce( gtf_grange[gtf_grange$type == "stop_codon" & gtf_grange$gene_id == geneName] )
  if(as.logical(strand(exon.current)[1]=="-")){
    startCodon <- startCodon[which.max( start(startCodon) )]
    stopCodon <- stopCodon[which.min( start(stopCodon) )]
    cdsRange <- stopCodon
    end(cdsRange) <- end(startCodon)
    cds.current <- suppressWarnings( GenomicRanges::intersect(exon.current,cdsRange) )
  }else{
    startCodon <- startCodon[which.min( start(startCodon) )]
    stopCodon <- stopCodon[which.max( start(stopCodon) )]
    cdsRange <- startCodon
    end(cdsRange) <- end(stopCodon)
    cds.current <- suppressWarnings( GenomicRanges::intersect(exon.current,cdsRange) )
  }
  utr.current <- GenomicRanges::setdiff(exon.current,cds.current)
  exon.new <- sort( c(cds.current,utr.current) )

  if(is.null(zoomIn)){
    cds.id <- unique( queryHits( findOverlaps(exon.new, cds.current)) )
    df.exon <- as.data.frame(exon.new)
    anno.exon <- character(length = length(exon.new))
    anno.intron <- character(length = length(exon.new)-1 )
    for(i in 1:length(exon.new)){
      if( i %in% cds.id){
        anno.exon[i] <- paste0("annotate(\"rect\", xmin =",df.exon$start[i] ,", xmax = ",df.exon$end[i] ,", ymin = -0.08*yscale, ymax = -0.02*yscale, alpha = .99, colour = \"black\")" )
      }else{
        anno.exon[i] <- paste0("annotate(\"rect\",xmin =",df.exon$start[i] ,", xmax = ",df.exon$end[i] ,", ymin = -0.06*yscale, ymax = -0.04*yscale, alpha = .99, colour = \"black\")")
      }
    }
    if(length(anno.intron)>0){
      for(i in 1:length(anno.intron)){
        anno.intron[i] <- paste0("annotate(\"segment\", x =", df.exon$end[i] ,", xend =", df.exon$start[i+1] ,", y = -0.05*yscale, yend = -0.05*yscale, alpha = .99, colour = \"black\")")
      }
      p <- paste( paste(anno.exon,collapse = "+"), paste(anno.intron,collapse = "+"), sep = "+")
    }else{
      p <-paste(anno.exon,collapse = "+")
    }


    return(p)

  }else{
    zoomIn.gr <- exon.new[1]
    ranges(zoomIn.gr) <- IRanges(start = zoomIn[1],end = zoomIn[2])
    exon.zoom <- GenomicRanges::intersect(exon.new, zoomIn.gr)
    cds.current.zoom <- GenomicRanges::intersect(exon.zoom, cds.current)
    utr.current.zoom <- GenomicRanges::setdiff(exon.zoom,cds.current.zoom)
    exon.zoom.new <-  sort( c(cds.current.zoom,utr.current.zoom) )

    cds.id <- unique( queryHits( findOverlaps(exon.zoom.new, cds.current.zoom)) )
    df.exon <- as.data.frame(exon.zoom.new)
    anno.exon <- character(length = length(exon.zoom))
    ## add exon plot if # exon > 0
    if(length(exon.zoom.new) > 0){
      for(i in 1:length(exon.zoom.new)){
        if( i %in% cds.id){
          anno.exon[i] <- paste0("annotate(\"rect\", xmin =",df.exon$start[i] ,", xmax = ",df.exon$end[i] ,", ymin = -0.08*yscale, ymax = -0.02*yscale, alpha = .99, colour = \"black\")" )
        }else{
          anno.exon[i] <- paste0("annotate(\"rect\",xmin =",df.exon$start[i] ,", xmax = ",df.exon$end[i] ,", ymin = -0.06*yscale, ymax = -0.04*yscale, alpha = .99, colour = \"black\")")
        }
      }
    }

    ## plot intron when there are more than two exons
    anno.intron <- character(length = max( length(exon.zoom.new)-1, 0 )  )
    if(length(anno.intron)>0){
      for(i in 1:length(anno.intron)){
        anno.intron[i] <- paste0("annotate(\"segment\", x =", df.exon$end[i] ,", xend =", df.exon$start[i+1] ,", y = -0.05*yscale, yend = -0.05*yscale, alpha = .99, colour = \"black\")")
      }
    }
    ## When there is only one exon and zoomIn range spans intron
    if( length(exon.zoom.new) > 0 && start(zoomIn.gr)<start(exon.zoom)[1]){
      anno.intron <- c(paste0("annotate(\"segment\", x =", start(zoomIn.gr) ,", xend =", start(exon.zoom)[1] ,", y = -0.05*yscale, yend = -0.05*yscale, alpha = .99, colour = \"black\")"),
                       anno.intron)
    }
    if( length(exon.zoom.new) > 0 && end(zoomIn.gr) > end(exon.zoom)[length(exon.zoom)] ){
      anno.intron <- c(anno.intron,
                       paste0("annotate(\"segment\", x =", end(exon.zoom)[length(exon.zoom)] ,", xend =", end(zoomIn.gr) ,", y = -0.05*yscale, yend = -0.05*yscale, alpha = .99, colour = \"black\")") )
    }
    ## When there is no exon but zoomIn ranges is in intron
    if( length(exon.zoom.new) == 0 ){
      anno.intron <- c(anno.intron,
                       paste0("annotate(\"segment\", x =", start(zoomIn.gr) ,", xend =", end(zoomIn.gr) ,", y = -0.05*yscale, yend = -0.05*yscale, alpha = .99, colour = \"black\")") )
    }

    ## combine intron and exon plots
    if( length(anno.intron) > 0 & length(anno.exon) >0 ){
      p <- paste( paste(anno.exon,collapse = "+"), paste(anno.intron,collapse = "+"), sep = "+")
    }else if( length(anno.exon) >0 ){
      p <- paste(anno.exon,collapse = "+")
    }else{
      p <- paste(anno.intron,collapse = "+")
    }

    return(p)
  }

}
