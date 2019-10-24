#!/usr/bin/env perl

BEGIN {
    die "Please load efishared before runing this script" if not $ENV{EFISHARED};
    use lib $ENV{EFISHARED};
}

use strict;
use warnings;

use FindBin;
use Getopt::Long;
use lib $FindBin::Bin . "/lib";

use EFI::SchedulerApi;
use EFI::Util qw(usesSlurm checkNetworkType);
use EFI::Config;
use EFI::GNN::Base;
use EFI::GNN::Arrows;


my ($ssnIn, $nbSize, $warningFile, $gnn, $ssnOut, $cooc, $stats, $pfamHubFile, $baseDir);
my ($pfamDirZip, $allPfamDirZip, $splitPfamDirZip, $allSplitPfamDirZip);
my ($uniprotIdZip, $uniprotDomainIdZip, $uniRef50IdZip, $uniRef50DomainIdZip, $uniRef90IdZip, $uniRef90DomainIdZip, $idOutputFile, $idOutputDomainFile);
my ($fastaZip, $fastaDomainZip, $fastaUniRef90Zip, $fastaUniRef90DomainZip, $fastaUniRef50Zip, $fastaUniRef50DomainZip, $noneZip);
my ($dontUseNewNeighborMethod);
my ($scheduler, $dryRun, $queue, $gnnOnly, $noSubmit, $jobId, $arrowDataFile, $coocTableFile);
my ($hubCountFile, $clusterSizeFile, $swissprotClustersDescFile, $swissprotSinglesDescFile, $parentDir, $configFile);
my $result = GetOptions(
    "output-dir=s"          => \$baseDir,
    "ssnin|ssn-in=s"        => \$ssnIn,
    "n|nb-size=s"           => \$nbSize,
    "warning-file=s"        => \$warningFile,
    "gnn=s"                 => \$gnn,
    "ssnout|ssn-out=s"      => \$ssnOut,
    "incfrac|cooc=i"        => \$cooc,
    "stats=s"               => \$stats,
    "cluster-sizes=s"       => \$clusterSizeFile,
    "sp-clusters-desc=s"    => \$swissprotClustersDescFile,
    "sp-singletons-desc=s"  => \$swissprotSinglesDescFile,
    "pfam=s"                => \$pfamHubFile,
    "pfam-zip=s"            => \$pfamDirZip,
    "all-pfam-zip=s"        => \$allPfamDirZip,
    "split-pfam-zip=s"      => \$splitPfamDirZip,
    "split-pfam-zip=s"      => \$splitPfamDirZip,
    "all-split-pfam-zip=s"  => \$allSplitPfamDirZip,
    "uniprot-id-zip=s"      => \$uniprotIdZip,
    "uniprot-domain-id-zip=s"       => \$uniprotDomainIdZip,
    "uniref50-id-zip=s"     => \$uniRef50IdZip,
    "uniref50-domain-id-zip=s"      => \$uniRef50DomainIdZip,
    "uniref90-id-zip=s"     => \$uniRef90IdZip,
    "uniref90-domain-id-zip=s"      => \$uniRef90DomainIdZip,
    "id-out=s"              => \$idOutputFile,
    "id-out-domain=s"       => \$idOutputDomainFile,
    "fasta-zip=s"           => \$fastaZip,
    "fasta-domain-zip=s"    => \$fastaDomainZip,
    "fasta-uniref90-zip=s"          => \$fastaUniRef90Zip,
    "fasta-uniref90-domain-zip=s"   => \$fastaUniRef90DomainZip,
    "fasta-uniref50-zip=s"          => \$fastaUniRef50Zip,
    "fasta-uniref50-domain-zip=s"   => \$fastaUniRef50DomainZip,
    "none-zip=s"            => \$noneZip,
    "disable-nnm"           => \$dontUseNewNeighborMethod,
    "scheduler=s"           => \$scheduler,
    "dry-run"               => \$dryRun,
    "queue=s"               => \$queue,
    "gnn-only"              => \$gnnOnly,
    "no-submit"             => \$noSubmit,
    "job-id=s"              => \$jobId,
    "arrow-file=s"          => \$arrowDataFile,
    "cooc-table=s"          => \$coocTableFile,
    "hub-count-file=s"      => \$hubCountFile,
    "parent-dir=s"          => \$parentDir, # directory of parent job (if specified, the neighbor results are pulled from the storable files there).
    "config=s"              => \$configFile,
);

my $usage = <<USAGE
usage: $0
    -ssnin              name of original ssn network to process
    -nb-size            distance (+/-) to search for neighbors
    -gnn                filename of genome neighborhood network output file
    -ssnout             output filename for colorized sequence similarity network
    -warning-file       output file that contains sequences without neighbors or matches
    -cooc               co-occurrence
    -stats              file to output tabular statistics to
    -clusters-sizes     file to output cluster sizes to
    -sp-clusters-desc   file to output SwissProt descriptions to for any nodes that have
                        SwissProt annotations (or any metanodes with children that have
                        SwissProt annotations)
    -sp-singletons-desc file to output SwissProt descriptions to for any singleton node that have
                        SwissProt annotations
    -pfam               file to output PFAM hub GNN to
    -id-zip             path to a file to zip all of the output lists
    -pfam-zip           path to a file to output zip file for PFAM cluster data
    -all-pfam-zip       path to a file to output zip file for PFAM cluster data, for all Pfams regardless of cooccurrence threshold
    -fasta-zip          path to a file to create compressed all FASTA files
    -id-out             path to a file to save the ID, cluster #, cluster color
    -config             configuration file for database info, etc.
    -scheduler          scheduler type (default to torque, but also can be slurm)
    -dry-run            only generate the scripts, don't submit to queue [boolean]
    -queue              the cluster queue to use
    -arrow-file         the file to output data to use for arrow data
    -cooc-table         the file to output co-occurrence (pfam v cluster) data to
    -hub-count-file     the file to output #sequences for each hub cluster in the GNN
    -no-submit          don't submit the job to the cluster, only create the job script [boolean]
    -gnn-only           only create the GNN, don't obtain FASTA or create diagrams, etc. [boolean]

For GNN only, this script can be run as follows, for example:

$0 -ssnin <input_filename> -gnn-only

This will create files for the gnn, warning, pfam hub, stats, and colored ssn outputs in the current
directory.  They will be named the same as the base name of the input ssn file.  The output name
and/or location can be overridden by using the various options above.

USAGE
;


die $usage if not $ssnIn;

if ((not defined $configFile or not -f $configFile) and not exists $ENV{EFICONFIG}) {
    die "Either the configuration file or the EFICONFIG environment variable must be set\n$usage";
} elsif (not $configFile) {
    $configFile = $ENV{EFICONFIG};
}

my $fullGntRun = defined $gnnOnly ? 0 : 1;

die $usage . "\nERROR: missing queue parameter" if not $queue and $fullGntRun;


my $toolpath = $ENV{'EFIGNN'};
my $efiGnnMod = $ENV{'EFIGNNMOD'};
my $efiDbMod = $ENV{'EFIDBMOD'};
my $outputDir = $baseDir ? $baseDir : $ENV{'PWD'};

(my $inputFileBase = $ssnIn) =~ s%^.*/([^/]+)$%$1%;
$inputFileBase =~ s/\.zip$//;
$inputFileBase =~ s/\.xgmml$//;

die "cannot open ssnin file $ssnIn" if not $ssnIn or not -f $ssnIn or not -s $ssnIn;
my $ssnInZip = $ssnIn;
if ($ssnIn =~ /\.zip$/i) {
    $ssnIn =~ s/\.zip$/\.xgmml/i;
}

my ($ssnType, $isDomain) = checkNetworkType($ssnInZip);

$noSubmit = 0                                                               if not defined $noSubmit;
$nbSize = 10                                                                if not defined $nbSize;
$cooc = 20                                                                  if not defined $cooc;
$gnn = "${inputFileBase}_ssn_cluster_gnn.xgmml"                             if not $gnn;
$ssnOut = "${inputFileBase}_coloredssn.xgmml"                               if not $ssnOut;
$pfamHubFile = "${inputFileBase}_pfam_family_gnn.xgmml"                     if not $pfamHubFile;
$warningFile = "${inputFileBase}_nomatches_noneighbors.txt"                 if not $warningFile;
$arrowDataFile = "${inputFileBase}_arrow_data.sqlite"                       if not $arrowDataFile;
$coocTableFile = "${inputFileBase}_cooc_table.txt"                          if not $coocTableFile;
$hubCountFile = "${inputFileBase}_hub_count.txt"                            if not $hubCountFile;
$jobId = "000"                                                              if not defined $jobId;
$stats = "${inputFileBase}_stats.txt"                                       if not $stats;
$clusterSizeFile = "${inputFileBase}_cluster_sizes.txt"                     if not $clusterSizeFile;
$swissprotClustersDescFile = "${inputFileBase}_swissprot_clusters_desc.txt" if not $swissprotClustersDescFile;
$swissprotSinglesDescFile = "${inputFileBase}_swissprot_singles_desc.txt"   if not $swissprotSinglesDescFile;


my ($pfamDir, $allPfamDir, $splitPfamDir, $allSplitPfamDir, $noneDir);
my ($fastaDir, $fastaUniProtDomainDataDir, $fastaUniRef90DataDir, $fastaUniRef90DomainDataDir, $fastaUniRef50DataDir, $fastaUniRef50DomainDataDir);
my ($uniprotNodeDataDir, $uniprotDomainNodeDataDir, $uniRef50NodeDataDir, $uniRef50DomainNodeDataDir, $uniRef90NodeDataDir, $uniRef90DomainNodeDataDir);
my $clusterDataDir = "cluster-data"; #relative for simplicity
if ($fullGntRun) {
    $pfamDir = "$clusterDataDir/pfam-data";
    $allPfamDir = "$clusterDataDir/all-pfam-data";
    $splitPfamDir = "$clusterDataDir/split-pfam-data";
    $allSplitPfamDir = "$clusterDataDir/all-split-pfam-data";
    $noneDir = "$clusterDataDir/pfam-none";
    
    $uniprotNodeDataDir = "$clusterDataDir/uniprot-nodes";
    $uniprotDomainNodeDataDir = "$clusterDataDir/uniprot-domain-nodes";
    $fastaDir = "$clusterDataDir/fasta";
    $fastaUniProtDomainDataDir = "$clusterDataDir/fasta-domain";
    
    $uniRef90NodeDataDir = "$clusterDataDir/uniref90-nodes";
    $uniRef90DomainNodeDataDir = "$clusterDataDir/uniref90-domain-nodes";
    $fastaUniRef90DataDir = "$clusterDataDir/fasta-uniref90";
    $fastaUniRef90DomainDataDir = "$clusterDataDir/fasta-uniref90-domain";
    
    $uniRef50NodeDataDir = "$clusterDataDir/uniref50-nodes";
    $uniRef50DomainNodeDataDir = "$clusterDataDir/uniref50-domain-nodes";
    $fastaUniRef50DataDir = "$clusterDataDir/fasta-uniref50";
    $fastaUniRef50DomainDataDir = "$clusterDataDir/fasta-uniref50-domain";

    $pfamDirZip = "$outputDir/${inputFileBase}_pfam_mapping.zip"                    if not $pfamDirZip;
    $allPfamDirZip = "$outputDir/${inputFileBase}_all_pfam_mapping.zip"             if not $allPfamDirZip;
    $splitPfamDirZip = "$outputDir/${inputFileBase}_split_pfam_mapping.zip"         if not $splitPfamDirZip;
    $allSplitPfamDirZip = "$outputDir/${inputFileBase}_all_split_pfam_mapping.zip"  if not $allSplitPfamDirZip;
    $noneZip = "$outputDir/${inputFileBase}_no_pfam_neighbors.zip"                  if not $noneZip;
    
    $uniprotIdZip = "$outputDir/${inputFileBase}_UniProt_IDs.zip"                   if not $uniprotIdZip;
    $uniprotDomainIdZip = "$outputDir/${inputFileBase}_UniProt_Domain_IDs.zip"      if not $uniprotDomainIdZip;
    $fastaZip = "$outputDir/${inputFileBase}_FASTA.zip"                             if not $fastaZip;
    $fastaDomainZip = "$outputDir/${inputFileBase}_FASTA_Domain.zip"                if not $fastaDomainZip;
    
    $uniRef50IdZip = "$outputDir/${inputFileBase}_UniRef50_IDs.zip"                 if not $uniRef50IdZip;
    $uniRef50DomainIdZip = "$outputDir/${inputFileBase}_UniRef50_Domain_IDs.zip"    if not $uniRef50DomainIdZip;
    $fastaUniRef50Zip = "$outputDir/${inputFileBase}_FASTA_UniRef50.zip"            if not $fastaUniRef50Zip;
    $fastaUniRef50DomainZip = "$outputDir/${inputFileBase}_FASTA_UniRef50_Domain.zip"   if not $fastaUniRef50DomainZip;
    
    $uniRef90IdZip = "$outputDir/${inputFileBase}_UniRef90_IDs.zip"                 if not $uniRef90IdZip;
    $uniRef90DomainIdZip = "$outputDir/${inputFileBase}_UniRef90_Domain_IDs.zip"    if not $uniRef90DomainIdZip;
    $fastaUniRef90Zip = "$outputDir/${inputFileBase}_FASTA_UniRef90.zip"            if not $fastaUniRef90Zip;
    $fastaUniRef90DomainZip = "$outputDir/${inputFileBase}_FASTA_UniRef90_Domain.zip"   if not $fastaUniRef90DomainZip;
    
    $idOutputFile = "${inputFileBase}_mapping_table.txt"                            if not $idOutputFile;
    $idOutputDomainFile = "${inputFileBase}_mapping_table_domain.txt"               if not $idOutputDomainFile;
    
    # Since we're passing relative paths to the cluster_gnn script we need to create the directories with absolute paths.
    my $mkPath = sub {
        my $dir = "$outputDir/$_[0]";
        if ($dryRun) {
            print "mkdir $dir\n";
        } else {
            mkdir $dir or die "Unable to create output dir $dir: $!" if not -d $dir;
        }
    };

    &$mkPath($clusterDataDir);
    &$mkPath($pfamDir);
    &$mkPath($allPfamDir);
    &$mkPath($splitPfamDir);
    &$mkPath($allSplitPfamDir);
    &$mkPath($noneDir);

    &$mkPath($uniprotNodeDataDir);
    &$mkPath($uniprotDomainNodeDataDir) if not $ssnType or $ssnType eq "UniProt" and $isDomain;
    &$mkPath($fastaDir);
    &$mkPath($fastaUniProtDomainDataDir) if not $ssnType or $ssnType eq "UniProt" and $isDomain;

    &$mkPath($uniRef90NodeDataDir);
    &$mkPath($uniRef90DomainNodeDataDir) if not $ssnType or $ssnType eq "UniRef90" and $isDomain;
    &$mkPath($fastaUniRef90DataDir);
    &$mkPath($fastaUniRef90DomainDataDir) if not $ssnType or $ssnType eq "UniRef90" and $isDomain;
    
    &$mkPath($uniRef50NodeDataDir);
    &$mkPath($uniRef50DomainNodeDataDir) if not $ssnType or $ssnType eq "UniRef50" and $isDomain;
    &$mkPath($fastaUniRef50DataDir);
    &$mkPath($fastaUniRef50DomainDataDir) if not $ssnType or $ssnType eq "UniRef50" and $isDomain;
} else {
    $pfamDir = "";
    $allPfamDir = "";
    $splitPfamDir = "";
    $allSplitPfamDir = "";
    $noneDir = "";

    $uniprotNodeDataDir = "";
    $uniprotDomainNodeDataDir = "";
    $fastaDir = "";
    $fastaUniProtDomainDataDir = "";
    
    $uniRef50NodeDataDir = "";
    $uniRef50DomainNodeDataDir = "";
    $fastaUniRef90DataDir = "";
    $fastaUniRef90DomainDataDir = "";
    
    $uniRef90NodeDataDir = "";
    $uniRef90DomainNodeDataDir = "";
    $fastaUniRef50DataDir = "";
    $fastaUniRef50DomainDataDir = "";
    
    $pfamDirZip = ""                                                                if not defined $pfamDirZip;
    $allPfamDirZip = ""                                                             if not defined $allPfamDirZip;
    $splitPfamDirZip = ""                                                           if not defined $splitPfamDirZip;
    $allSplitPfamDirZip = ""                                                        if not defined $allSplitPfamDirZip;
    $noneZip = ""                                                                   if not defined $noneZip;
    
    $uniprotIdZip = ""                                                              if not defined $uniprotIdZip;
    $uniprotDomainIdZip = ""                                                        if not defined $uniprotDomainIdZip;
    $uniRef50IdZip = ""                                                             if not defined $uniRef50IdZip;
    $uniRef90IdZip = ""                                                             if not defined $uniRef90IdZip;
    
    $fastaZip = ""                                                                  if not defined $fastaZip;
    $fastaDomainZip = ""                                                            if not defined $fastaDomainZip;
    $fastaUniRef90Zip = ""                                                          if not defined $fastaUniRef90Zip;
    $fastaUniRef90DomainZip = ""                                                    if not defined $fastaUniRef90DomainZip;
    $fastaUniRef50Zip = ""                                                          if not defined $fastaUniRef50Zip;
    $fastaUniRef50DomainZip = ""                                                    if not defined $fastaUniRef50DomainZip;

    $idOutputFile = ""                                                              if not defined $idOutputFile;
    $idOutputDomainFile = ""                                                        if not defined $idOutputDomainFile;
}


print "gnn mod is:$efiGnnMod\n";
print "efidb mod is:$efiDbMod\n";
print "ssnin is $ssnIn\n";
print "n|nb-size is $nbSize\n";
print "warning-file is $warningFile\n";
print "gnn is $gnn\n";
print "ssnout is $ssnOut\n";
print "incfrac|cooc is $cooc\n";
print "stats is $stats\n";
print "cluster-sizes is $clusterSizeFile\n";
print "sp-clusters-desc is $swissprotClustersDescFile\n";
print "sp-singletons-desc is $swissprotSinglesDescFile\n";
print "distance is $nbSize\n";
print "pfam is $pfamHubFile\n";
print "pfam-dir is $pfamDir\n";
print "pfam-zip is $pfamDirZip\n";
print "all-pfam-dir is $allPfamDir\n";
print "all-pfam-zip is $allPfamDirZip\n";
print "split-pfam-dir is $splitPfamDir\n";
print "split-pfam-zip is $splitPfamDirZip\n";
print "all-split-pfam-dir is $allSplitPfamDir\n";
print "all-split-pfam-zip is $allSplitPfamDirZip\n";
print "uniprot-id-zip is $uniprotIdZip\n";
print "uniprot-id-zip is $uniprotDomainIdZip\n";
print "uniref50-id-zip is $uniRef50IdZip\n";
print "uniref90-id-zip is $uniRef90IdZip\n";
print "id-out is $idOutputFile\n";
print "id-out-domain is $idOutputDomainFile\n";
print "fasta-dir is $fastaDir\n";
print "fasta-domain-dir is $fastaUniProtDomainDataDir\n";
print "fasta-uniref90-zip is $fastaUniRef90Zip\n";
print "fasta-uniref90-domain-zip is $fastaUniRef90DomainZip\n";
print "fasta-uniref50-zip is $fastaUniRef50Zip\n";
print "fasta-uniref50-domain-zip is $fastaUniRef50DomainZip\n";
print "none-dir is $noneDir\n";
print "none-zip is $noneZip\n";
print "arrow-file is $arrowDataFile\n";
print "cooc-table is $coocTableFile\n";
print "hub-count-file is $hubCountFile\n";
print "job-id is $jobId\n";

my $diagramVersion = $EFI::GNN::Arrows::Version; #TODO: put this somewhere else



unless($nbSize>0){
    die "-n $nbSize must be an integer greater than zero\n$usage";
}

if ($fullGntRun) {
    # Full path on these, because they are used by the zip tool.    
    $pfamDirZip = "$outputDir/$pfamDirZip"                  unless $pfamDirZip =~ /^\//;
    $allPfamDirZip = "$outputDir/$allPfamDirZip"            unless $allPfamDirZip =~ /^\//;
    $splitPfamDirZip = "$outputDir/$splitPfamDirZip"        unless $splitPfamDirZip =~ /^\//;
    $allSplitPfamDirZip = "$outputDir/$allSplitPfamDirZip"  unless $allSplitPfamDirZip =~ /^\//;
    $noneZip = "$outputDir/$noneZip"                        unless $noneZip =~ /^\//;
    
    $uniprotIdZip = "$outputDir/$uniprotIdZip"              unless $uniprotIdZip =~ /^\//;
    $uniprotDomainIdZip = "$outputDir/$uniprotDomainIdZip"  unless $uniprotDomainIdZip =~ /^\//;
    $uniRef50IdZip = "$outputDir/$uniRef50IdZip"            unless $uniRef50IdZip =~ /^\//;
    $uniRef90IdZip = "$outputDir/$uniRef90IdZip"            unless $uniRef90IdZip =~ /^\//;
}


if($cooc!~/^\d+$/){
    if(defined $cooc){
        die "incfrac must be an integer\n";
    }
    $cooc=20;  
}


(my $ssnName = $ssnOut) =~ s%^.*/([^/]+)\.xgmml$%$1%i;
my $ssnOutZip = "$outputDir/$ssnName.zip";
(my $gnnZip = $gnn) =~ s/\.xgmml$/.zip/i;
(my $pfamHubFileZip = $pfamHubFile) =~ s/\.xgmml$/.zip/i;
(my $arrowZip = $arrowDataFile) =~ s/\.sqlite/.zip/i if $arrowDataFile;

my $jobNamePrefix = $jobId ? "${jobId}_" : "";


my $cmdString = "$toolpath/cluster_gnn.pl " .
    "-output-dir \"$outputDir\" " .
    "-nb-size $nbSize " . 
    "-cooc \"$cooc\" " .
    "-ssnin \"$ssnIn\" " . 
    "-ssnout \"$ssnOut\" " . 
    "-gnn \"$gnn\" " . 
    "-stats \"$stats\" " .
    "-cluster-sizes \"$clusterSizeFile\" " .
    "-sp-clusters-desc \"$swissprotClustersDescFile\" " .
    "-sp-singletons-desc \"$swissprotSinglesDescFile\" " .
    "-warning-file \"$warningFile\" " .
    "-pfam \"$pfamHubFile\" "
    ;
if ($fullGntRun) {
    $cmdString .= 
        "-pfam-dir \"$pfamDir\" " .
        "-all-pfam-dir \"$allPfamDir\" " .
        "-split-pfam-dir \"$splitPfamDir\" " .
        "-all-split-pfam-dir \"$allSplitPfamDir\" " .
        "-id-out \"$idOutputFile\" " .
        "-id-out-domain \"$idOutputDomainFile\" " .
        "-none-dir \"$noneDir\" " .
        "-uniprot-id-dir \"$uniprotNodeDataDir\" " .
        "-uniprot-domain-id-dir \"$uniprotDomainNodeDataDir\" " .
        "-uniref50-id-dir \"$uniRef50NodeDataDir\" " .
        "-uniref50-domain-id-dir \"$uniRef50DomainNodeDataDir\" " .
        "-uniref90-id-dir \"$uniRef90NodeDataDir\" " .
        "-uniref90-domain-id-dir \"$uniRef90DomainNodeDataDir\" " .
        "-arrow-file \"$arrowDataFile\" " .
        "-cooc-table \"$coocTableFile\" " .
        "-hub-count-file \"$hubCountFile\" ";
    $cmdString .= " -parent-dir \"$parentDir\"" if $parentDir;
}

my $absPath = sub {
    return $_[0] =~ m/^\// ? $_[0] : "$outputDir/$_[0]";
};

my $fileInfo = {
    color_only => 0,

    output_path => $outputDir,
    config_file => $configFile,
    fasta_tool_path => "$toolpath/get_fasta.pl",
    cat_tool_path => "$toolpath/cat_files.pl",

    none_dir => &$absPath($noneDir),
    pfam_dir => &$absPath($pfamDir),
    all_pfam_dir => &$absPath($allPfamDir),
    split_pfam_dir => &$absPath($splitPfamDir),
    all_split_pfam_dir => &$absPath($allSplitPfamDir),
    
    none_zip => $noneZip,
    pfam_zip => $pfamDirZip,
    all_pfam_zip => $allPfamDirZip,
    split_pfam_zip => $splitPfamDirZip,
    all_split_pfam_zip => $allSplitPfamDirZip,
    
    ssn_out => &$absPath($ssnOut),
    ssn_out_zip => &$absPath($ssnOutZip),
    gnn => &$absPath($gnn),
    gnn_zip => &$absPath($gnnZip),
    pfamhubfile => &$absPath($pfamHubFile),
    pfamhubfile_zip => &$absPath($pfamHubFileZip),
    arrow_file => $arrowDataFile,
    arrow_zip => $arrowZip,

    uniprot_node_data_dir => &$absPath($uniprotNodeDataDir),
    fasta_data_dir => &$absPath($fastaDir),
    uniprot_node_zip => $uniprotIdZip,
    fasta_zip => $fastaZip,
};

# In some cases we can't determine the type of the file in advance, so we write out all possible cases.
# The 'not $ssnType or' statement ensures that this happens.
if (not $ssnType or $ssnType eq "UniProt" and $isDomain) {
    $fileInfo->{uniprot_domain_node_data_dir} = &$absPath($uniprotDomainNodeDataDir);
    $fileInfo->{fasta_domain_data_dir} = &$absPath($fastaUniProtDomainDataDir);
    $fileInfo->{uniprot_domain_node_zip} = $uniprotDomainIdZip;
    $fileInfo->{fasta_domain_zip} = $fastaDomainZip;
}

if (not $ssnType or $ssnType eq "UniRef90" or $ssnType eq "UniRef50") {
    $fileInfo->{uniref90_node_data_dir} = &$absPath($uniRef90NodeDataDir);
    $fileInfo->{fasta_uniref90_data_dir} = &$absPath($fastaUniRef90DataDir);
    $fileInfo->{uniref90_node_zip} = $uniRef90IdZip;
    $fileInfo->{fasta_uniref90_zip} = $fastaUniRef90Zip;
    if (not $ssnType or $isDomain and $ssnType eq "UniRef90") {
        $fileInfo->{uniref90_domain_node_data_dir} = &$absPath($uniRef90DomainNodeDataDir);
        $fileInfo->{fasta_uniref90_domain_data_dir} = &$absPath($fastaUniRef90DomainDataDir);
        $fileInfo->{uniref90_domain_node_zip} = $uniRef90DomainIdZip;
        $fileInfo->{fasta_uniref90_domain_zip} = $fastaUniRef90DomainZip;
    }
}

if (not $ssnType or $ssnType eq "UniRef50") {
    $fileInfo->{uniref50_node_data_dir} = &$absPath($uniRef50NodeDataDir);
    $fileInfo->{fasta_uniref50_data_dir} = &$absPath($fastaUniRef50DataDir);
    $fileInfo->{uniref50_node_zip} = $uniRef50IdZip;
    $fileInfo->{fasta_uniref50_zip} = $fastaUniRef50Zip;
    if (not $ssnType or $isDomain) {
        $fileInfo->{uniref50_domain_node_data_dir} = &$absPath($uniRef50DomainNodeDataDir);
        $fileInfo->{fasta_uniref50_domain_data_dir} = &$absPath($fastaUniRef50DomainDataDir);
        $fileInfo->{uniref50_domain_node_zip} = $uniRef50DomainIdZip;
        $fileInfo->{fasta_uniref50_domain_zip} = $fastaUniRef50DomainZip;
    }
}


my $fileSize = 0;
if ($ssnInZip !~ m/\.zip/) { # If it's a .zip we can't predict apriori what the size will be.
    my $hasUniref = `grep -m1 UniRef $ssnIn`;
    # If the file is a UniRef network, we also can't predict the RAM reservation since it depends on the number of UniRef IDs.
    # Unfortunately we can't check here how many nodes there are, since this script should return quickly and submit
    # the hard work to the cluster.
    if (not $hasUniref) { 
        $fileSize = -s $ssnIn;
    }
}

# Y = MX+B, M=emperically determined, B = safety factor; X = file size in MB; Y = RAM reservation in GB
my $ramReservation = "150";
if ($fileSize) {
    my $ramPredictionM = 0.023;
    my $ramSafety = 10;
    $fileSize = $fileSize / 1024 / 1024; # MB
    $ramReservation = $ramPredictionM * $fileSize + $ramSafety;
    $ramReservation = int($ramReservation + 0.5);
}

my $schedType = "torque";
$schedType = "slurm" if (defined($scheduler) and $scheduler eq "slurm") or (not defined($scheduler) and usesSlurm());
my $SS = new EFI::SchedulerApi(type => $schedType, queue => $queue, resource => [1, 1], dryrun => $dryRun);


my $B = $SS->getBuilder();

$B->resource(1, 1, "${ramReservation}gb");
$B->addAction("source /etc/profile");
$B->addAction("module load $efiDbMod");
$B->addAction("module load $efiGnnMod");
$B->addAction("export BLASTDB=$outputDir/blast");
$B->addAction("$toolpath/unzip_file.pl -in $ssnInZip -out $ssnIn") if $ssnInZip =~ /\.zip/i;
$B->addAction($cmdString);
if ($fullGntRun) {
    EFI::GNN::Base::addFileActions($B, $fileInfo);
}
$B->addAction("\n\n$toolpath/save_version.pl > $outputDir/gnn.completed");
$B->addAction("echo $diagramVersion > $outputDir/diagram.version");

$B->jobName("${jobNamePrefix}submit_gnn");
$B->renderToFile("$outputDir/submit_gnn.sh");

if (not $noSubmit) {
    my $gnnjob = $SS->submit("$outputDir/submit_gnn.sh");
    chomp $gnnjob;
    print "Job to make gnn network is :\n $gnnjob";
}



