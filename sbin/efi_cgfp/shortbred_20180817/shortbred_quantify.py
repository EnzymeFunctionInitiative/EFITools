#!/usr/bin/env python
#####################################################################################
#Copyright (C) <2013> Jim Kaminski and the Huttenhower Lab
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of
#this software and associated documentation files (the "Software"), to deal in the
#Software without restriction, including without limitation the rights to use, copy,
#modify, merge, publish, distribute, sublicense, and/or sell copies of the Software,
#and to permit persons to whom the Software is furnished to do so, subject to
#the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies
#or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
#INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
#PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
#HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
#OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
#SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#
# This file is a component of ShortBRED (Short, Better REad Database)
# authored by the Huttenhower lab at the Harvard School of Public Health
# (contact Jim Kaminski, jjk451@mail.harvard.edu, Jingjing Tang, jatangne@gmail.com).
#####################################################################################

import sys
import argparse
import re
import os
import datetime
import tarfile
import gzip

import time
import math
import bz2

import src
import src.quantify_functions
sq = src.quantify_functions

from Bio import SeqIO

VERSION="0.9.5"


################################################################################
# Constants
c_iMaxSizeForDirectRun = 900 # File size in MB. Any WGS file smaller than this
							 # does not need to made into smaller WGS files.

c_iReadsForFile = 7000000 # Number of WGS reads to process at a time

################################################################################
# Args

parser = argparse.ArgumentParser(description='ShortBRED Quantify \n \
This program takes a set of protein family markers and wgs file as input, \
and produces a relative abundance table.')
parser.add_argument("--version", action="version", version="%(prog)s v"+VERSION)
#Input
grpInput = parser.add_argument_group('Input:')
grpInput.add_argument('--markers', type=str, dest='strMarkers',
help='Enter the path and name of the genes of interest file (protein seqs).')
grpInput.add_argument('--wgs', type=str, dest='strWGS',nargs='+',
help='Enter the path and name of the WGS file (nucleotide reads).')
grpInput.add_argument('--genome', type=str, dest='strGenome',
help='Enter the path and name of the genome file (faa expected).')


#Output
grpOutput = parser.add_argument_group('Output:')
grpOutput.add_argument('--results', type=str, dest='strResultsMedian', default = "results.tab",
help='Enter a name for your results file (median).')
grpOutput.add_argument('--results-mean', type=str, dest='strResultsMean', default = "",
help='Enter a name for your results file (mean).')
grpOutput.add_argument('--SBhits', type=str, dest='strHits',
help='ShortBRED will print the hits it considers positives to this file.', default="")
grpOutput.add_argument('--searchout', type=str, dest='strSearch', default="",
help='Enter the name of the blast/diamond-formatted output file from USEARCH/DIAMOND.')
grpOutput.add_argument('--marker_results', type=str, dest='strMarkerResults', default="",
help='Enter the name of the output for marker level results.')
grpOutput.add_argument('--tmp', type=str, dest='strTmp', default ="",help='Enter the path and name of the tmp directory.')

grpPrograms = parser.add_argument_group('Programs:')
grpPrograms.add_argument('--search_program', default ="diamond", type=str, dest='strSearchProg', help='Choose program for wgs and unannotated genome search. Default is \"usearch\".')
grpPrograms.add_argument('--usearch', default ="usearch", type=str, dest='strUSEARCH', help='Provide the path to usearch. Default call will be \"usearch\".')
grpPrograms.add_argument('--tblastn', default ="tblastn", type=str, dest='strTBLASTN', help='Provide the path to tblastn. Default call will be \"tblastn\".')
grpPrograms.add_argument('--makeblastdb', default ="makeblastdb", type=str, dest='strMakeBlastDB', help='Provide the path to makeblastdb. Default call will be \"makeblastdb\".')
grpPrograms.add_argument('--prerapsearch2', default ="prerapsearch", type=str, dest='strPrerapPath', help='Provide the path to prerapsearch2. Default call will be \"prerapsearch\".')
grpPrograms.add_argument('--rapsearch2', default ="rapsearch2", type=str, dest='strRap2Path', help='Provide the path to rapsearch2. Default call will be \"rapsearch2\".')
grpPrograms.add_argument('--diamond', default ="diamond", type=str, dest='strDIAMOND', help='Provide the path to  makeblastdb. Default call will be to \"diamond\".')

#Parameters - Matching Settings
grpParam = parser.add_argument_group('Parameters:')
grpParam.add_argument('--id', type=float, dest='dID', help='Enter the percent identity for the match', default = .95)
grpParam.add_argument('--pctlength', type=float, dest='dAlnLength', help='Enter the minimum alignment length. The default is .95', default = 0.95)
grpParam.add_argument('--minreadBP', type=float, dest='iMinReadBP', help='Enter the lower bound for read lengths that shortbred will process', default = 90)
grpParam.add_argument('--avgreadBP', type=float, dest='iAvgReadBP', help='Enter the average read length.', default = 100)
grpParam.add_argument('--maxhits', type=float, dest='iMaxHits', help='Enter the number of markers allowed to hit read.', default = 0)
grpParam.add_argument('--maxrejects', type=float, dest='iMaxRejects', help='Enter the number of markers allowed to hit read.', default = 32)
grpParam.add_argument('--unannotated', action='store_const',dest='bUnannotated', help='Indicates genome is unannotated. ShortBRED will use tblastn to \
search AA markers against the db of six possible translations of your genome data. ', const=True, default = False)
grpParam.add_argument('--pctmarker_thresh',dest='dPctMarkerThresh', type=float,help='Indicates the share of a familiy\'s markers that must map to ORF to be counted. ', default = 0.1)
grpParam.add_argument('--pctORFscore_thresh',dest='dPctORFScoreThresh', type=float,help='Indicates the share of total ORF score that a family must receive to be counted. ', default = 0.1)



grpParam.add_argument('--EM', action='store_const',dest='bEM', help='Indicates user would like to run EM algorithm \
 on the quasi-markers. ', const=True, default = False)
grpParam.add_argument('--bayes', type=str,dest='strBayes', help='Output files for Bayes Results', default = "")
#parser.add_argument('--tmid', type=float, dest='dTMID', help='Enter the percent identity for a TM match', default = .95)
#parser.add_argument('--qmid', type=float, dest='dQMID', help='Enter the percent identity for a QM match', default = .95)
#parser.add_argument('--alnTM', type=int, dest='iAlnMax', help='Enter a bound for TM alignments, such that aln must be>= min(markerlength,alnTM)', default = 20)

#Parameters - Matching Various
grpParam.add_argument('--bz2', type=bool, dest='fbz2file', help='Set to True if using a tar.bz2 file', default = False)
grpParam.add_argument('--threads', type=int, dest='iThreads', help='Enter the number of CPUs available for USEARCH.', default=1)
grpParam.add_argument('--notmarkers', type=str, dest='strCentroids',default="N", help='This flag is used when testing centroids for evaluation purposes.')
grpParam.add_argument('--cent_match_length', type=int, dest='iAlnCentroids',default=30, help='This flag is used when working with centroids. It sets the minimum matching length.')
grpParam.add_argument('--small', type=bool, dest='bSmall',default=False, help='This flag is used to indicate the input file is small enough for USEARCH.')

#parser.add_argument('--length', type=int, dest='iLength', help='Enter the minimum length of the markers.')

# Check for args.
if len(sys.argv)==1:
    parser.print_help()
    sys.stderr.write("\nNo arguments were supplied to ShortBRED. Please see the usage information above to determine what to pass to the program.\n")
    sys.exit(1)
    
############################################################################
# Check Dependencies
args = parser.parse_args()
if (args.strSearchProg=="usearch"):
    src.CheckDependency(args.strUSEARCH,"","usearch")
    strVersionUSEARCH = sq.CheckUSEARCH(args.strUSEARCH)
    print("Using this version of usearch: ",strVersionUSEARCH)
elif (args.strSearchProg=="rapsearch2"):
    src.CheckDependency(args.strRap2Path,"","rapsearch2")
    src.CheckDependency(args.strPrerapPath,"","prerapsearch")
elif (args.strSearchProg=="diamond"):
    src.CheckDependency(args. strDIAMOND,"-h","diamond")


if (args.strMarkers == "" or args.strWGS==""):
    parser.print_help( )
    raise Exception( "Command line arguments incorrect, must provide:\n" +
                    "\t--markers AND --wgs, \n")


################################################################################
#Make temp directory
dirTmp = args.strTmp
if(dirTmp==""):
    # dirTmp gets a pid and timestamp. (This is to avoid overwriting files if
    # someone launches multiple instances of the program.)
    dirTmp = ("tmp" + str(os.getpid()) + '%.0f' % round((time.time()*1000), 1))

dirTmp = src.check_create_dir( dirTmp )
dirTmp = os.path.abspath(dirTmp)

# Assign file names
if args.strHits != "":
    strHitsFile = args.strHits
else:
    strHitsFile = ( dirTmp + os.sep + "SBhits.txt" )

if args.strResultsMean != "":
    strResultsMean = args.strResultsMean
else:
    strResultsMean = args.strResultsMedian + ".mean"

# Delete SBhits.txt file if it already exists.
if os.path.isfile(strHitsFile):
    os.remove(strHitsFile)


strMarkerResults = args.strMarkerResults
if strMarkerResults == "":
    strMarkerResults = dirTmp + os.sep + "markers.tab"

##############################################################################
# Determine if profiling WGS or Genome
if args.strGenome!="" and args.strWGS==None and args.bUnannotated==False:
    strMethod = "annotated_genome"
    #We assume that genomes will be a single fasta file, and that they will be
    # smaller than 900 MB, the upper bound for passing a single file to usearch.
    strSize = "small"
    strFormat = "fasta"
    sys.stderr.write("Treating input as an annotated genome...\n")
    sys.stderr.write("NOTE: When running against an annotated bug genome, ShortBRED makes a \
                     usearch database from the bug genome and then searches the markers against it. \
                     Please remember to increase \"maxhits\" and \"maxrejects\" to a large number, so that multiple \
                     markers can hit each bug sequence. Setting these values to 0 will search the full database.\n\n")
    dictFamCounts = sq.MakeDictFamilyCounts(args.strMarkers,"")

elif args.strGenome!="" and args.strWGS==None and args.bUnannotated==True:
    strMethod = "unannotated_genome"
    
    src.CheckDependency(args.strTBLASTN,"","tblastn")
    src.CheckDependency(args.strMakeBlastDB,"","makeblastdb")
    #We assume that genomes will be a single fasta file, and that they will be
    # smaller than 900 MB, the upper bound for passing a single file to usearch.
    strSize = "small"
    strFormat = "fasta"
    sys.stderr.write("Treating input as an unannotated genome...\n")
    sys.stderr.write("NOTE: When running against an unannotated bug genome, ShortBRED makes a \n\
                     tblastn database from the genome and then blasts the markers against it. \n\
                     Please remember to increase \"maxhits\" to a large number, so that multiple \n\
                     markers can hit each bug sequence. \n")
    dictFamCounts = sq.MakeDictFamilyCounts(args.strMarkers,"")

else:
    strMethod = "wgs"
    sys.stderr.write("Treating input as a wgs file...\n")


##############################################################################
# Log the parameters
log = open(dirTmp + os.sep + "quantify_log.txt", "w")
log.write("ShortBRED_quantify log \n" + time.strftime("%Y-%m-%d %H:%M:%S") + "\n SEARCH PARAMETERS \n")
log.write("Match ID:" + str(args.dID) + "\n")
log.write("Pct Length for Match:" + str(args.dAlnLength) + "\n")
if args.strCentroids=="Y":
    log.write("Sequences: Centroids\n")
else:
    log.write("Sequences: Markers\n")
if strMethod=="annotated_genome":
    log.write("Ran against the genome " + args.strGenome + "\n")


##############################################################################
#Initialize Dictionaries, Some Output Files

dictMarkerLen = {}
dictCountsForMarker = {}  # sum of read lengths in valid hits for each marker
dictMarkerCount = {}
dictHitsForMarker = {}
dictQMPossibleOverlap = {}
dictType = {}


if (args.strSearch == ""):
    strSearch = str(dirTmp) + os.sep + strMethod+ "full_results.tab"
else:
    strSearch = args.strSearch

###############################################################################
#Step 1: Prepare markers.
# Sum up the marker lengths by family, put them in a dictionary.
# Make them into a USEARCH/DIAMOND database.

astrQMs = []
for seq in SeqIO.parse(args.strMarkers, "fasta"):
    #For Cenrtoids...
    if args.strCentroids=="Y":
        strStub = seq.id
    
    #For ShortBRED Markers
    else:
        mtchStub = re.search(r'(.*)_([TJQ]M)[0-9]*_\#([0-9]*)',seq.id)
        strStub = mtchStub.group(1)
        strType = mtchStub.group(2)
    
    dictMarkerCount[strStub] = dictMarkerCount.get(strStub,0) + 1
    dictHitsForMarker[seq.id] = 0
    dictCountsForMarker[seq.id] = 0
    dictMarkerLen[seq.id] = len(seq)    # record the length of each marker
    
    if args.strCentroids!="Y":
        dictType[strStub] = strType
        
        if strType == "QM":
            astrQMs.append(seq.id)
            astrAllFams = re.search(r'\__\[(.*)\]',seq.id).group(1).split(",")
	       
            # Example: __[ZP_04174269_w=0.541,ZP_04300309_w=0.262,NP_242644_w=0.098]
            iQM = 0
            iJM = 0
            iTM = 0
            
            astrFams =[]
            # Only retain those families which could validly map to this QM at the given settings.
            for strFam in astrAllFams:
                #print strFam
                mtchFam = re.search(r'(.*)_w=(.*)',strFam)
                strID = mtchFam.group(1)
                dProp = float(mtchFam.group(2))
                
                if strID == strStub:
                    dMainFamProp = dProp
                dLenOverlap = (dProp/dMainFamProp) * len(seq)
                
                # Reads from current family can map to the QM if overlap is as long
                # as the minimum accepted read length. Or if it nearly overlaps
                # the entire marker
                if (dLenOverlap >= (args.iMinReadBP/3)) or (dProp/dMainFamProp) >= args.dAlnLength:
                    astrFams.append(strID)
            
            dictQMPossibleOverlap[seq.id] = astrFams

##################################################################################
#Step 2: Get information on WGS file(s), put it into aaFileInfo.
sys.stderr.write( "\nExamining WGS data:")
"""
aaFileInfo is array of string arrays, each with details on the file so ShortBRED
knows how to process it efficiently. Each line has the format:
	[filename, format, "large" or "small", extract method, and corresponding tarfile (if needed)]

An example:
    ['SRS011397/SRS011397.denovo_duplicates_marked.trimmed.1.fastq', 'fastq', 'large', 'r:bz2', '/n/CHB/data/hmp/wgs/samplesfqs/SRS011397.tar.bz2']
"""
if strMethod=="wgs":
    
    astrWGS = args.strWGS
    
    sys.stderr.write( "\nList of files in WGS set:")
    for strWGS in astrWGS:
        sys.stderr.write( strWGS + "\n")
    
    aaWGSInfo = []
    
    for strWGS in astrWGS:
        strExtractMethod= sq.CheckExtract(strWGS)
        
        # If tar file, get details on members, and note corresponding tarfile
        # Remember that a tarfile has a header block, and then data blocks
        if (strExtractMethod== 'r:bz2' or strExtractMethod=='r:gz'):
            tarWGS = tarfile.open(strWGS,strExtractMethod)
            atarinfoFiles = tarWGS.getmembers() #getmembers() returns tarInfo objects
            tarWGS.close()
            
            for tarinfoFile in atarinfoFiles:
                if tarinfoFile.isfile(): # This condition confirms that it is a file, not a header.
                    strFormat = sq.CheckFormat(tarinfoFile.name)
                    strSize = sq.CheckSize(tarinfoFile.size, c_iMaxSizeForDirectRun)
                    astrFileInfo = [tarinfoFile.name, strFormat, strSize,strExtractMethod, strWGS ]
                    aaWGSInfo.append(astrFileInfo)
        
        elif (strExtractMethod== 'bz2'):
            strWGSOut = strWGS.replace(".bz2","")
            strFormat = sq.CheckFormat(strWGSOut)
            # It is not possible to get bz2 filesize in advance, so we just assume it is large.
            strSize = "large"
            astrFileInfo = [strWGSOut, strFormat, strSize,strExtractMethod, strWGS ]
            aaWGSInfo.append(astrFileInfo)
            
        # Otherwise, get file details directly
        else:
            strFormat = sq.CheckFormat(strWGS)
            strSize = sq.CheckSize(os.path.getsize(strWGS), c_iMaxSizeForDirectRun)
            astrFileInfo = [strWGS, strFormat, strSize,strExtractMethod, "no_tar" ]
            aaWGSInfo.append(astrFileInfo)
    
    sys.stderr.write( "\nList of files in WGS set (after unpacking tarfiles):")
    for astrWGS in aaWGSInfo:
        sys.stderr.write( astrWGS[0]+" ")
    
    sys.stderr.write("\n\n")
##################################################################################
# Step 3: Call USEARCH on each WGS file, (break into smaller files if needed), store hit counts.
#         OR run USEARCH on each individual genome.
# Initialize values for the sample
iTotalReadCount = 0
dAvgReadLength  = 0.0
iMin = 999 #Can be any large integer. Just a value to initialize iMin before calculations begin.
iWGSFileCount = 1


if strMethod=="annotated_genome":
    
    # If running on an *annotated_genome*, use usearch.
    if args.strSearchProg=="usearch":  
        strDBName = str(dirTmp) + os.sep + os.path.basename(os.path.splitext(str(args.strMarkers))[0]) + ".udb"
        strDBName = os.path.abspath(strDBName)
        log.write(time.strftime("%Y-%m-%d %H:%M:%S") + " Making USEARCH database for the annotated_genome reads \n")
        sq.MakedbUSEARCH (args.strMarkers, strDBName,args.strUSEARCH)
        log.write( time.strftime("%Y-%m-%d %H:%M:%S") + " USEARCHing the markers against the annotated_genome reads \n")
        sq.RunUSEARCHGenome(strGenome=args.strGenome, strDB=strDBName, strSearchOut = strSearch,iThreads=args.iThreads,dID=args.dID, dirTmp=dirTmp,
                            iAccepts=args.iMaxHits, iRejects=args.iMaxRejects,strUSEARCH=args.strUSEARCH )
        sq.StoreHitCounts(strSearchOut=strSearch,strValidHits=strHitsFile,dictHitsForMarker=dictHitsForMarker,
                          dictMarkerLen=dictMarkerLen,dictCountsForMarker=dictCountsForMarker,dID=args.dID,
                          strCentCheck=args.strCentroids,dAlnLength=args.dAlnLength,
                          iMinReadBP=args.iMinReadBP,iAvgMarkerAA=int(math.floor(args.iAvgReadBP/3)),
                          strShortBREDMode=strMethod,iAlnCentroids=args.iAlnCentroids,strSearchMethod = args.strSearchProg,
                          version_control = strVersionUSEARCH)
        
    elif args.strSearchProg=="diamond":
        strDBName = str(dirTmp) + os.sep + os.path.basename(os.path.splitext(str(args.strMarkers))[0]) + ".diamdb"
        strDBName = os.path.abspath(strDBName)
        log.write(time.strftime("%Y-%m-%d %H:%M:%S") + " Making DIAMOND database for the annotated_genome reads \n")
        sq.MakedbDIAMOND ( args.strMarkers, strDBName, args.strDIAMOND)
        log.write( time.strftime("%Y-%m-%d %H:%M:%S") + " DIAMONDing the markers against the annotated_genome reads database \n")
        sq.RunDIAMONDp (strDIAMOND = args.strDIAMOND, strDB=strDBName, strGenome=args.strGenome, strDiamondOut = strSearch,iThreads=args.iThreads)
        sq.StoreHitCounts(strSearchOut=strSearch,strValidHits=strHitsFile,dictHitsForMarker=dictHitsForMarker,
                          dictMarkerLen=dictMarkerLen,dictCountsForMarker=dictCountsForMarker,dID=args.dID,
                          strCentCheck=args.strCentroids,dAlnLength=args.dAlnLength,
                          iMinReadBP=args.iMinReadBP,iAvgMarkerAA=int(math.floor(args.iAvgReadBP/3)),
                          strShortBREDMode=strMethod,iAlnCentroids=args.iAlnCentroids,strSearchMethod = args.strSearchProg)
        
    
    iWGSReads = 0
    for seq in SeqIO.parse(args.strGenome, "fasta"):
        iWGSReads+=1
        iTotalReadCount+=1
        dAvgReadLength = ((dAvgReadLength * (iTotalReadCount-1)) + len(seq))/float(iTotalReadCount)
        iMin = min(iMin,len(seq))

elif strMethod=="unannotated_genome":
    # If running on *unannotated_genome*, use tblastn.
    
    if args.strSearchProg=="tblastn":    
        strDBName = str(dirTmp) + os.sep + os.path.basename(os.path.splitext(str(args.strMarkers))[0]) + ".blastdb"
        strDBName = os.path.abspath(strDBName)
        log.write(time.strftime("%Y-%m-%d %H:%M:%S") + " Making BLAST database for the unannotated_genome reads \n")
        sq.MakedbBLASTnuc( args.strMakeBlastDB, strDBName,args.strMarkers,dirTmp)
        log.write( time.strftime("%Y-%m-%d %H:%M:%S") + " BLASTing the markers against the unannotated_genome reads database \n")
        sq.RunTBLASTN (args.strTBLASTN, strDBName,args.strWGS, strSearch, args.iThreads)
    
    elif args.strSearchProg=="diamond":
        strDBName = str(dirTmp) + os.sep + os.path.basename(os.path.splitext(str(args.strMarkers))[0]) + ".diamdb"
        strDBName = os.path.abspath(strDBName)
        log.write(time.strftime("%Y-%m-%d %H:%M:%S") + " Making DIAMOND database for the unannotated_genome reads \n")
        sq.MakedbDIAMOND ( args.strMarkers, strDBName, args.strDIAMOND)
        log.write( time.strftime("%Y-%m-%d %H:%M:%S") + " DIAMONDing the markers against the unannotated_genome reads database \n")
        sq.RunDIAMONDx (strDIAMOND = args.strDIAMOND, strDB=strDBName, strWGS=args.strWGS, strDiamondOut = strSearch,iThreads=args.iThreads)
        
    
    sq.StoreHitCounts(strSearchOut=strSearch,strValidHits=strHitsFile,dictHitsForMarker=dictHitsForMarker,
                      dictMarkerLen=dictMarkerLen,dictCountsForMarker=dictCountsForMarker,dID=args.dID,
                      strCentCheck=args.strCentroids,dAlnLength=args.dAlnLength,
                      iMinReadBP=args.iMinReadBP,iAvgMarkerAA=int(math.floor(args.iAvgReadBP/3)),
                      strShortBREDMode=strMethod,iAlnCentroids=args.iAlnCentroids,strSearchMethod = args.strSearchProg)

    iWGSReads = 0
    for seq in SeqIO.parse(args.strMarkers, "fasta"):
        iWGSReads+=1
        iTotalReadCount+=1
        dAvgReadLength = ((dAvgReadLength * (iTotalReadCount-1)) + len(seq))/float(iTotalReadCount)
        iMin = min(iMin,len(seq))

# Otherwise, profile wgs data with usearch or rapsearch2 or diamond
else:
    log.write('\t'.join(["# FileName","size","format","extract method","tar file (if part of one)"]) + '\n')
    #log.write("Reads processed" + "\n")
    
    for astrFileInfo in aaWGSInfo:
        strWGS,strFormat,strSize,strExtractMethod,strMainTar = astrFileInfo
        log.write(str(iWGSFileCount) + ": " + '\t'.join(astrFileInfo) + '\n')
        
        iWGSReads = 0
        sys.stderr.write( "Working on file " + str(iWGSFileCount) + " of " + str(len(aaWGSInfo)) + "\n")
        
        #If it's a small fasta file, just give it to USEARCH or rapsearch or DIAMOND directly.
        
        if args.strSearchProg=="diamond":
            strDBName = str(dirTmp) + os.sep + os.path.basename(os.path.splitext(str(args.strMarkers))[0]) + ".diamdb"
            strDBName = os.path.abspath(strDBName)
            log.write(time.strftime("%Y-%m-%d %H:%M:%S") + " Making DIAMOND database for the wgs reads \n")
            sq.MakedbDIAMOND ( args.strMarkers, strDBName, args.strDIAMOND)
            log.write( time.strftime("%Y-%m-%d %H:%M:%S") + " DIAMONDing the markers against the wgs reads database \n")
            sq.RunDIAMONDx(strDIAMOND = args.strDIAMOND, strDB=strDBName, strWGS=strWGS, strDiamondOut = strSearch,iThreads=args.iThreads)
            sq.StoreHitCounts(strSearchOut=strSearch,strValidHits=strHitsFile,dictHitsForMarker=dictHitsForMarker,
                              dictMarkerLen=dictMarkerLen,dictCountsForMarker=dictCountsForMarker,dID=args.dID,
                              strCentCheck=args.strCentroids,dAlnLength=args.dAlnLength,
                              iMinReadBP=args.iMinReadBP,iAvgMarkerAA=int(math.floor(args.iAvgReadBP/3)),
                              strShortBREDMode=strMethod,iAlnCentroids=args.iAlnCentroids,strSearchMethod = args.strSearchProg)
           
            for seq in SeqIO.parse(strWGS, "fasta"):
                iWGSReads+=1
                iTotalReadCount+=1
                dAvgReadLength = ((dAvgReadLength * (iTotalReadCount-1)) + len(seq))/float(iTotalReadCount)
                iMin = min(iMin,len(seq))
                
        elif strFormat=="fasta" and strSize=="small":
            if args.strSearchProg=="rapsearch2":
                strDBName = str(dirTmp) + os.sep + os.path.basename(os.path.splitext(str(args.strMarkers))[0]) + ".rap2db"
                strDBName = os.path.abspath(strDBName)
                log.write(time.strftime("%Y-%m-%d %H:%M:%S") + " Making RAPSEARCH2 database for the small wgs reads \n")
                sq.MakedbRapsearch2(args.strMarkers, strDBName,args.strPrerapPath)
                log.write( time.strftime("%Y-%m-%d %H:%M:%S") + " RAPSEARCHing the markers against the wgs reads database \n")
                sq.RunRAPSEARCH2(strWGS=strWGS,strDB=strDBName, strSearchOut  = strSearch,iThreads=args.iThreads,dID=args.dID, dirTmp=dirTmp,
                                 iAccepts=args.iMaxHits, iRejects=args.iMaxRejects,strRAPSEARCH2=args.strRap2Path )
                sq.StoreHitCounts(strSearchOut=strSearch,strValidHits=strHitsFile,dictHitsForMarker=dictHitsForMarker,
                                  dictMarkerLen=dictMarkerLen,dictCountsForMarker=dictCountsForMarker,dID=args.dID,
                                  strCentCheck=args.strCentroids,dAlnLength=args.dAlnLength,
                                  iMinReadBP=args.iMinReadBP,iAvgMarkerAA=int(math.floor(args.iAvgReadBP/3)),
                                  strShortBREDMode=strMethod,iAlnCentroids=args.iAlnCentroids,strSearchMethod = args.strSearchProg)
         
            elif args.strSearchProg=="usearch":
                strDBName = str(dirTmp) + os.sep + os.path.basename(os.path.splitext(str(args.strMarkers))[0]) + ".udb"
                strDBName = os.path.abspath(strDBName)
                log.write(time.strftime("%Y-%m-%d %H:%M:%S") + " Making USEARCH database for the small wgs reads \n")
                sq.MakedbUSEARCH(args.strMarkers, strDBName,args.strUSEARCH)
                log.write( time.strftime("%Y-%m-%d %H:%M:%S") + " USEARCHing the markers against the wgs reads databse \n")
                sq.RunUSEARCH(strWGS=strWGS, strDB=strDBName, strSearchOut  = strSearch,iThreads=args.iThreads,dID=args.dID, dirTmp=dirTmp,
                              iAccepts=args.iMaxHits, iRejects=args.iMaxRejects,strUSEARCH=args.strUSEARCH )
                sq.StoreHitCounts(strSearchOut=strSearch,strValidHits=strHitsFile,dictHitsForMarker=dictHitsForMarker,
                                  dictMarkerLen=dictMarkerLen,dictCountsForMarker=dictCountsForMarker,dID=args.dID,
                                  strCentCheck=args.strCentroids,dAlnLength=args.dAlnLength,
                                  iMinReadBP=args.iMinReadBP,iAvgMarkerAA=int(math.floor(args.iAvgReadBP/3)),
                                  strShortBREDMode=strMethod,iAlnCentroids=args.iAlnCentroids,strSearchMethod = args.strSearchProg,
                                  version_control = strVersionUSEARCH)
                       
            for seq in SeqIO.parse(strWGS, "fasta"):
                iWGSReads+=1
                iTotalReadCount+=1
                dAvgReadLength = ((dAvgReadLength * (iTotalReadCount-1)) + len(seq))/float(iTotalReadCount)
                iMin = min(iMin,len(seq))
            
            """
            #Skip the file if the format is unknown.
            elif strFormat == "unknown":
                sys.stderr.write("WARNING: Skipped file with unknown format: " + strWGS + "\n")
                with open(str(dirTmp + os.sep + os.path.basename(args.strMarkers)+ ".log"), "a") as log:
                    log.write("WARNING: Skipped file with unknown format: " + strWGS + "\n")
            """
        
        #Otherwise, convert the file as needed into small fasta files. Call USEARCH and store the counts for each small file.
        else:
            strDBName = str(dirTmp) + os.sep + os.path.basename(os.path.splitext(str(args.strMarkers))[0]) + ".udb"
            strDBName = os.path.abspath(strDBName)
            log.write(time.strftime("%Y-%m-%d %H:%M:%S") + " Making USEARCH database for the large wgs reads \n")
            sq.MakedbUSEARCH(args.strMarkers, strDBName,args.strUSEARCH)
            
            iReadsInSmallFile = 0
            iFileCount = 1
            
            strFASTAName = str(dirTmp) + os.sep + 'fasta.fna'
            #Unpack file with appropriate extract method
            if (strExtractMethod== 'r:bz2' or strExtractMethod=='r:gz'):
                sys.stderr.write("Unpacking tar file... this often takes several minutes. ")
                tarWGS = tarfile.open(strMainTar,strExtractMethod)
                streamWGS = tarWGS.extractfile(strWGS)
            elif strExtractMethod== 'gz':
                sys.stderr.write("Unpacking gz file... this may take several minutes. ")
                streamWGS = gzip.open(strWGS, 'rb')
            elif strExtractMethod== 'bz2':
                sys.stderr.write("Unpacking bz2 file... this may take several minutes. ")
                sys.stderr.write(strMainTar)
                #tarWGS = tarfile.open(strMainTar,'r|bz2')
                streamWGS = bz2.BZ2File(strMainTar,'r')
                #streamWGS = tarWGS.extractfile(strWGS)
            else:
                streamWGS = open(strWGS,'r')
                
            
            #Open file for writing
            fileFASTA = open(strFASTAName, 'w')
            
            """
            if strFormat=="unknown":
                strFormat="fastq"
            if streamWGS==None:
                log.write("File was empty." + '\n')
            """
            
            #Start the main loop to get everything in streamWGS -> small fasta file -> counted and stored
            for seq in SeqIO.parse(streamWGS, strFormat):
                #Added to keep usearch from hitting seqs that are too long.
                if len(seq)< 50000:
                    SeqIO.write(seq,fileFASTA,"fasta")
                    iReadsInSmallFile+=1
                    iTotalReadCount+=1
                    iWGSReads+=1
                    
                    # Have a running average of the read length. This covers all of the reads in the original input file.
                    dAvgReadLength = ((dAvgReadLength * (iTotalReadCount-1)) + len(seq))/float(iTotalReadCount)
                    iMin = min(len(seq),iMin)
                
                #Close the temp fasta file once it has enough reads.
                if (iReadsInSmallFile>=c_iReadsForFile):
                    fileFASTA.close()
                    
                    strOutputName = str(dirTmp) + os.sep + "wgs_" + str(iWGSFileCount).zfill(2) + "out_" + str(iFileCount).zfill(2) + ".out"
                    #Run Usearch, store results
                    if args.strSearchProg=="usearch":
                        sq.RunUSEARCH(strWGS=strFASTAName,strDB=strDBName, strSearchOut  = strOutputName,dirTmp=dirTmp,
                                      iThreads=args.iThreads,dID=args.dID, iAccepts=args.iMaxHits, iRejects=args.iMaxRejects,strUSEARCH=args.strUSEARCH  )
                        sq.StoreHitCounts(strSearchOut=strOutputName,strValidHits=strHitsFile,dictHitsForMarker=dictHitsForMarker,
                                          dictMarkerLen=dictMarkerLen,dictCountsForMarker=dictCountsForMarker,dID=args.dID,
                                          strCentCheck=args.strCentroids,dAlnLength=args.dAlnLength,
                                          iMinReadBP=args.iMinReadBP,iAvgMarkerAA=int(math.floor(args.iAvgReadBP/3)),
                                          strShortBREDMode=strMethod,iAlnCentroids=args.iAlnCentroids,strSearchMethod = "usearch",
                                          version_control = strVersionUSEARCH)

                    #Reset count, make new file
                    iReadsInSmallFile = 0
                    iFileCount+=1
                    fileFASTA = open(strFASTAName, 'w')
            
            if(iReadsInSmallFile>0):
                fileFASTA.close()
                
                #Run Usearch, store results
                strOutputName = str(dirTmp) + os.sep + "wgs_" + str(iWGSFileCount).zfill(2) + "out_" + str(iFileCount).zfill(2) + ".out"
                sq.RunUSEARCH(strWGS=strFASTAName,strDB=strDBName, strSearchOut  = strOutputName,dirTmp=dirTmp,
                              iThreads=args.iThreads,dID=args.dID,iAccepts=args.iMaxHits, iRejects=args.iMaxRejects,strUSEARCH=args.strUSEARCH )
                sq.StoreHitCounts(strSearchOut=strOutputName,strValidHits=strHitsFile,dictHitsForMarker=dictHitsForMarker,
                                  dictMarkerLen=dictMarkerLen,dictCountsForMarker=dictCountsForMarker,dID=args.dID,
                                  strCentCheck=args.strCentroids,dAlnLength=args.dAlnLength,
                                  iMinReadBP=args.iMinReadBP,iAvgMarkerAA=int(math.floor(args.iAvgReadBP/3)),
                                  strShortBREDMode=strMethod,iAlnCentroids=args.iAlnCentroids,strSearchMethod = "usearch",
                                  version_control = strVersionUSEARCH)
                os.remove(strFASTAName)
            
            log.write(str(iWGSReads) + '\n')
        
            iWGSFileCount += 1
            if (strFormat != "fasta" or strSize != "small"):
                streamWGS.close()
            
            #Close the tarfile if you had one open.
            if (strExtractMethod== 'r:bz2' or strExtractMethod=='r:gz'):
                tarWGS.close()

log.write(time.strftime("%Y-%m-%d %H:%M:%S") + " Finish Searching \n \n")  
##################################################################################
# Step 4: Calculate ShortBRED Counts, print results, print log info.
if strMethod=="annotated_genome":
    strInputFile = args.strGenome
elif strMethod=="unannotated_genome":
    strInputFile = args.strGenome
elif strMethod=="wgs":
    strInputFile=args.strWGS
	

if strMethod=="wgs":
    atupCounts = sq.CalculateCounts(strResultsMedian = args.strResultsMedian, strResultsMean = strResultsMean, strMarkerResults=strMarkerResults,
                                    dictHitsForMarker = dictHitsForMarker, dictCountsForMarker=dictCountsForMarker,dictMarkerLen=dictMarkerLen, 
                                    iWGSReads = iTotalReadCount, strCentCheck=args.strCentroids,
                                    dAlnLength=args.dAlnLength,strFile = strInputFile)

	# Row of atupCounts = (strProtFamily,strMarker, dCount,dictHitsForMarker[strMarker],dictMarkerLen[strMarker],dReadLength,iPossibleHitSpace)




###########################################################################
# Added to produce counts of bug genomes 
##########################################################################

if strMethod=="annotated_genome":
    dictFinalCounts = sq.NormalizeGenomeCounts(strHitsFile,dictFamCounts,bUnannotated=False,dPctMarkerThresh=args.dPctMarkerThresh)
    sys.stderr.write("Normalizing hits to genome... \n")

elif strMethod=="unannotated_genome":
    dictFinalCounts = sq.NormalizeGenomeCounts(strHitsFile,dictFamCounts,bUnannotated=True,dPctMarkerThresh=args.dPctMarkerThresh)
    sys.stderr.write("Normalizing hits to genome... \n")


if strMethod=="annotated_genome" or strMethod=="unannotated_genome":
    with open(args.strResultsMedian,'w') as fileBugCounts:
        fileBugCounts.write("Family" + "\t" + "Count" + "\n")
        for strFam in sorted(dictFinalCounts.keys()):
            fileBugCounts.write(strFam + "\t" + str(dictFinalCounts[strFam]) + "\n")

# Add final details to log
log.write(time.strftime("%Y-%m-%d %H:%M:%S") +  "\nProcessing complete! \n\n")
log.write("Total Reads Processed: " + str(iTotalReadCount) + "\n")
log.write("Average Read Length Specified by User: " + str(args.iAvgReadBP) + "\n")
log.write("Average Read Length Calculated by ShortBRED: " + str(dAvgReadLength) + "\n")
log.write("Min Read Length: " + str(iMin) + "\n")


sys.stderr.write("Processing complete. \n")
########################################################################################
# This is part of a possible EM application that is not fully implemented yet.
########################################################################################
#if (args.strBayes != ""):
#    sq.BayesUpdate(atupCounts=atupCounts,strBayesResults=args.strBayes,strBayesLog=strQMOut,astrQMs=astrQMs,
#                   dictQMPossibleOverlap=dictQMPossibleOverlap,dictType=dictType)

