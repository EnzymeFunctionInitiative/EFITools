#!/bin/env perl

use strict;
use warnings;

use FindBin;
use Getopt::Long;
use File::Basename qw(dirname);

use lib "$FindBin::Bin/../lib";


my $appDir = dirname($FindBin::Bin);


my ($jobOutputDir, $jobOutputScript, $toolBase, $configFile);
#$jobOutputScript = "serial_test.sh";


my ($jobType, $isDebug, $scheduler);
my ($outputPath, $oldGraphs, $maxFullFam, $jobId);
my ($np, $evalue, $tmp, $maxSequence, $queue, $memQueue);

# Family shared
my ($pfam, $ipro, $unirefVersion, $fraction, $minSeqLen, $maxSeqLen, $excludeFragments, $domain, $domainRegion, $seqCountFile, $lengthDif, $sim, $multiplex);
# Accession
my ($userAccession, $noMatchFile, $domainFamily);
# FASTA
my ($userFasta, $useFastaHeaders, $userDat);
# Color SSN
my ($ssnIn, $ssnOut, $mapDirName, $mapFileName, $domainMapFileName, $outDir, $stats, $clusterSizes, $convRatio, $spClustersDec, $spSingletonsDesc, $extraRam, $cleanup, $skipFasta);
# Conv ratio
my ($ascore, $convRatioRam);
# BLAST
my ($seq, $blastEvalue, $nResults, $blastDbType, $maxBlastHits);
# Cluster analysis
my ($msaOption, $msaAa, $msaThreshold, $msaMin, $msaMax);
# Neighborhood connectivity
my ($outputName, $nbRam);


my $result = GetOptions(
    "job-type=s"        => \$jobType,
    "job-dir=s"         => \$jobOutputDir,
    "tool-base=s"       => \$toolBase,
    "config-file=s"     => \$configFile,
    "debug"             => \$isDebug,
    "scheduler=s"       => \$scheduler, #Ignired

    # EST shared (Family shared, Color SSN)
    "oldgraphs"         => \$oldGraphs,
    "max-full-family=s" => \$maxFullFam,
    "job-id=s"          => \$jobId,
    "np=s"              => \$np,
    "evalue=s"          => \$evalue,
    "tmp=s"             => \$tmp,
    "maxsequence=s"     => \$maxSequence,
    "queue=s"           => \$queue,
    "memqueue=s"        => \$memQueue,

    # Family shared (Accession, Family, FASTA, BLAST)
    "pfam=s"            => \$pfam,
    "ipro=s"            => \$ipro,
    "uniref-version=s"  => \$unirefVersion,
    "fraction"          => \$fraction,
    "min-seq-len=s"     => \$minSeqLen,
    "max-seq-len=s"     => \$maxSeqLen,
    "exclude-fragments" => \$excludeFragments,
    "domain"            => \$domain,
    "domain-region=s"   => \$domainRegion,
    "seq-count-file=s"  => \$seqCountFile,
    "lengthdif=s"       => \$lengthDif,
    "sim=s"             => \$sim,
    "multiplex=s"       => \$multiplex,

    # Accession (ACCESSION)
    "useraccession=s"   => \$userAccession,
    "no-match-file=s"   => \$noMatchFile,
    "domain-family=s"   => \$domainFamily,

    # FASTA (FASTA)
    "userfasta=s"       => \$userFasta,
    "use-fasta-headers" => \$useFastaHeaders,
    "userdat=s"         => \$userDat,

    # Family (FAMILIES)

    # ColorSSN (COLORSSN)
    "ssn-in=s"                  => \$ssnIn,
    "ssn-out=s"                 => \$ssnOut,
    "map-dir-name=s"            => \$mapDirName,
    "map-file-name=s"           => \$mapFileName,
    "domain-map-file-name=s"    => \$domainMapFileName,
    "out-dir=s"                 => \$outDir,
    "stats=s"                   => \$stats,
    "cluster-sizes=s"           => \$clusterSizes,
    "conv-ratio=s"              => \$convRatio,
    "sp-clusters-desc=s"        => \$spClustersDec,
    "sp-singletons-desc=s"      => \$spSingletonsDesc,
    "extra-ram"                 => \$extraRam,
    "cleanup"                   => \$cleanup,
    "skip-fasta"                => \$skipFasta,

    # Cluster Analysis (CLUSTER)
    "output-path=s"     => \$outputPath,
    "opt-msa-option=s"          => \$msaOption,
    "opt-aa-list=s"             => \$msaAa,
    "opt-aa-threshold=s"        => \$msaThreshold,
    "opt-min-seq-msa=s"         => \$msaMin,
    "opt-max-seq-msa=s"         => \$msaMax,

    # Conv Ratio (CONVRATIO)
    "output-path=s"     => \$outputPath,
    "ascore=s"          => \$ascore,
    "ram=s"             => \$convRatioRam,

    # BLAST (BLAST)
    "seq=s"             => \$seq,
    "blast-evalue=s"    => \$blastEvalue,
    "nresults=s"        => \$nResults,
    "seq-count-file=s"  => \$seqCountFile,
    "db-type=s"         => \$blastDbType,
    "max-blast-hits=s"  => \$maxBlastHits,

    # Neighborhood connectivity (NBCONN)
    "output-name=s"     => \$outputName,
    "ram=s"             => \$nbRam,
);



$jobOutputDir = $ENV{PWD} if not $jobOutputDir;
$appDir = "$toolBase/bin" if $toolBase;
$configFile = "$appDir/../conf/efi.conf" if not $configFile;



my $cmd = "";

if ($jobType eq "FAMILIES") {
    $cmd = processFamilyJob();
}

if ($isDebug) {
    print $cmd, "\n";
} else {
    print `$cmd`;
}
















sub getSharedJobArgs {
    my %args;
    $args{"job-id"} = $jobId if $jobId;
    $args{"tmp"} = $tmp if $tmp;
    $args{"job-dir"} = $jobOutputDir if $jobOutputDir;
    $args{"serial-script"} = "$jobOutputDir/$jobOutputScript" if $jobOutputScript;
    $args{"graph-version"} = "1" if $oldGraphs;
    $args{"config"} = $configFile;
    return %args;
}


sub getSharedFamilyArgs {
    my %args = getSharedJobArgs();
    $args{"evalue"} = $evalue if $evalue;
    $args{"max-sequence"} = $maxSequence if $maxSequence;
    #$args{"inc-frac"} = $incFrac if $incFrac;
    $args{"seq-count-file"} = $seqCountFile if $seqCountFile;
    $args{"length-diff"} = $lengthDif if $lengthDif;
    $args{"seq-id-threshold"} = $sim if $sim;
    $args{"multiplex"} = $multiplex if $multiplex;
    #$args{"blast-type"} = $blastType if $blastType;
    $args{"exclude-fragments"} = $excludeFragments if $excludeFragments;
    #$args{"no-demux"} = $noDemux if $noDemux;
    $args{"domain"} = $domain if $domain;
    $args{"pfam"} = $pfam if $pfam;
    $args{"interpro"} = $ipro if $ipro;
    $args{"fraction"} = $fraction if $fraction;
    $args{"uniref-version"} = $unirefVersion if $unirefVersion;

    return %args;
}


sub processFamilyJob {
    my %args = getSharedFamilyArgs();
    my $args = join(" ", map { "--$_ " . $args{$_} } keys %args);
    my $cmd = "$appDir/efi.pl family $args";
    return $cmd;
    #return %args;
}




