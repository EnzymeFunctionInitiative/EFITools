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
use EFI::Util qw(usesSlurm);
use EFI::Config;
use EFI::GNN::Base;


my ($ssnIn, $nbSize, $warningFile, $gnn, $ssnOut, $cooc, $stats, $pfamHubFile);
my ($pfamDir, $pfamDirZip, $allPfamDir, $allPfamDirZip, $splitPfamDir, $splitPfamDirZip, $allSplitPfamDir, $allSplitPfamDirZip);
my ($uniprotIdZip, $uniref50IdZip, $uniref90IdZip, $idOutputFile, $fastaDir, $fastaZip, $noneDir, $noneZip);
my ($dontUseNewNeighborMethod);
my ($scheduler, $dryRun, $queue, $gnnOnly, $noSubmit, $jobId, $arrowDataFile, $coocTableFile);
my ($hubCountFile, $clusterSizeFile, $swissprotClustersDescFile, $swissprotSinglesDescFile, $parentDir, $configFile);
my $result = GetOptions(
    "ssnin=s"               => \$ssnIn,
    "n|nb-size=s"           => \$nbSize,
    "warning-file=s"        => \$warningFile,
    "gnn=s"                 => \$gnn,
    "ssnout=s"              => \$ssnOut,
    "incfrac|cooc=i"        => \$cooc,
    "stats=s"               => \$stats,
    "cluster-sizes=s"       => \$clusterSizeFile,
    "sp-clusters-desc=s"    => \$swissprotClustersDescFile,
    "sp-singletons-desc=s"  => \$swissprotSinglesDescFile,
    "pfam=s"                => \$pfamHubFile,
    "pfam-dir=s"            => \$pfamDir,
    "pfam-zip=s"            => \$pfamDirZip, # only used for GNT calls, non batch
    "all-pfam-dir=s"        => \$allPfamDir,
    "all-pfam-zip=s"        => \$allPfamDirZip, # only used for GNT calls, non batch
    "split-pfam-dir=s"      => \$splitPfamDir,
    "split-pfam-zip=s"      => \$splitPfamDirZip, # only used for GNT calls, non batch
    "split-pfam-dir=s"      => \$splitPfamDir,
    "split-pfam-zip=s"      => \$splitPfamDirZip, # only used for GNT calls, non batch
    "all-split-pfam-dir=s"  => \$allSplitPfamDir,
    "all-split-pfam-zip=s"  => \$allSplitPfamDirZip, # only used for GNT calls, non batch
    "uniprot-id-zip=s"      => \$uniprotIdZip, # only used for GNT calls, non batch
    "uniref50-id-zip=s"     => \$uniref50IdZip, # only used for GNT calls, non batch
    "uniref90-id-zip=s"     => \$uniref90IdZip, # only used for GNT calls, non batch
    "id-out=s"              => \$idOutputFile,
    "fasta-dir=s"           => \$fastaDir,
    "fasta-zip=s"           => \$fastaZip,
    "none-dir=s"            => \$noneDir,
    "none-zip=s"            => \$noneZip, # only used for GNT calls, non batch
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
    -pfam-dir           path to directory to output PFAM cluster data (one file/list per cluster number)
    -pfam-zip           path to a file to output zip file for PFAM cluster data
    -all-pfam-dir       path to directory to output PFAM cluster data (one file/list per cluster number), for all Pfams regardless of cooccurrence threshold
    -all-pfam-zip       path to a file to output zip file for PFAM cluster data, for all Pfams regardless of cooccurrence threshold
    -fasta-dir          path a directory output FASTA files
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


my $toolpath = $ENV{'EFIGNN'};
my $efiGnnMod = $ENV{'EFIGNNMOD'};
my $efiDbMod = $ENV{'EFIDBMOD'};
my $defaultDir = $ENV{'PWD'};

(my $inputFileBase = $ssnIn) =~ s%^.*/([^/]+)$%$1%;
$inputFileBase =~ s/\.zip$//;
$inputFileBase =~ s/\.xgmml$//;

my $fullGntRun = defined $gnnOnly ? 0 : 1;
$noSubmit = 0                                                               if not defined $noSubmit;
$nbSize = 10                                                                if not defined $nbSize;
$cooc = 20                                                                  if not defined $cooc;
$gnn = "$defaultDir/${inputFileBase}_ssn_cluster_gnn.xgmml"                 if not $gnn;
$ssnOut = "$defaultDir/${inputFileBase}_coloredssn.xgmml"                   if not $ssnOut;
$pfamHubFile = "$defaultDir/${inputFileBase}_pfam_family_gnn.xgmml"         if not $pfamHubFile;
$warningFile = "$defaultDir/${inputFileBase}_nomatches_noneighbors.txt"     if not $warningFile;
$arrowDataFile = ""                                                         if not defined $arrowDataFile;
$queue = "efi"                                                              if not defined $queue or not $queue;
$jobId = ""                                                                 if not defined $jobId;
$stats = "$defaultDir/${inputFileBase}_stats.txt"                           if not $stats;
$clusterSizeFile = "$defaultDir/${inputFileBase}_cluster_sizes.txt"         if not $clusterSizeFile;
$swissprotClustersDescFile = "$defaultDir/${inputFileBase}_swissprot_clusters_desc.txt" if not $swissprotClustersDescFile;
$swissprotSinglesDescFile = "$defaultDir/${inputFileBase}_swissprot_singles_desc.txt"   if not $swissprotSinglesDescFile;


if ($fullGntRun) {
    $pfamDir = "$defaultDir/pfam-data"                                      if not $pfamDir;
    $pfamDirZip = "$defaultDir/${inputFileBase}_pfam_mapping.zip"           if not $pfamDirZip;
    $allPfamDir = "$defaultDir/all-pfam-data"                               if not $allPfamDir;
    $allPfamDirZip = "$defaultDir/${inputFileBase}_all_pfam_mapping.zip"    if not $allPfamDirZip;
    $splitPfamDir = "$defaultDir/split-pfam-data"                                   if not $splitPfamDir;
    $splitPfamDirZip = "$defaultDir/${inputFileBase}_split_pfam_mapping.zip"        if not $splitPfamDirZip;
    $allSplitPfamDir = "$defaultDir/all-split-pfam-data"                            if not $allSplitPfamDir;
    $allSplitPfamDirZip = "$defaultDir/${inputFileBase}_all_split_pfam_mapping.zip" if not $allSplitPfamDirZip;
    $uniprotIdZip = "$defaultDir/${inputFileBase}_UniProt_IDs.zip"          if not $uniprotIdZip;
    $uniref50IdZip = "$defaultDir/${inputFileBase}_UniRef50_IDs.zip"        if not $uniref50IdZip;
    $uniref90IdZip = "$defaultDir/${inputFileBase}_UniRef90_IDs.zip"        if not $uniref90IdZip;
    $idOutputFile = "$defaultDir/${inputFileBase}_mapping_table.txt"        if not $idOutputFile;
    $fastaDir = "$defaultDir/fasta"                                         if not $fastaDir;
    $fastaZip = "$defaultDir/${inputFileBase}_FASTA.zip"                    if not $fastaZip;
    $noneDir = "$defaultDir/pfam-none"                                      if not $noneDir;
    $noneZip = "$defaultDir/${inputFileBase}_no_pfam_neighbors.zip"         if not $noneZip;
} else {
    $pfamDir = ""                                                           if not defined $pfamDir;
    $pfamDirZip = ""                                                        if not defined $pfamDirZip;
    $allPfamDir = ""                                                        if not defined $allPfamDir;
    $allPfamDirZip = ""                                                     if not defined $allPfamDirZip;
    $splitPfamDir = ""                                                      if not defined $splitPfamDir;
    $splitPfamDirZip = ""                                                   if not defined $splitPfamDirZip;
    $allSplitPfamDir = ""                                                   if not defined $allSplitPfamDir;
    $allSplitPfamDirZip = ""                                                if not defined $allSplitPfamDirZip;
    $uniprotIdZip = ""                                                      if not defined $uniprotIdZip;
    $uniref50IdZip = ""                                                     if not defined $uniref50IdZip;
    $uniref90IdZip = ""                                                     if not defined $uniref90IdZip;
    $idOutputFile = ""                                                      if not defined $idOutputFile;
    $fastaDir = ""                                                          if not defined $fastaDir;
    $fastaZip = ""                                                          if not defined $fastaZip;
    $noneDir = ""                                                           if not defined $noneDir;
    $noneZip = ""                                                           if not defined $noneZip;
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
print "uniref50-id-zip is $uniref50IdZip\n";
print "uniref90-id-zip is $uniref90IdZip\n";
print "id-out is $idOutputFile\n";
print "fasta-dir is $fastaDir\n";
print "fasta-zip is $fastaZip\n";
print "none-dir is $noneDir\n";
print "none-zip is $noneZip\n";
print "arrow-file is $arrowDataFile\n";
print "job-id is $jobId\n";

unless($nbSize>0){
    die "-n $nbSize must be an integer greater than zero\n$usage";
}

my $outputDir = $ENV{PWD};
my $clusterDataPath = "$outputDir/cluster-data";
my $uniprotNodeDataPath     = "$clusterDataPath/uniprot-nodes";
my $uniref50NodeDataPath    = "$clusterDataPath/uniref50-nodes";
my $uniref90NodeDataPath    = "$clusterDataPath/uniref90-nodes";

$ssnIn = "$outputDir/$ssnIn"                            unless $ssnIn =~ /^\//;
$gnn = "$outputDir/$gnn"                                unless $gnn =~ /^\//;
$ssnOut = "$outputDir/$ssnOut"                          unless $ssnOut =~ /^\//;
$stats = "$outputDir/$stats"                            unless $stats =~ /^\//;
$clusterSizeFile = "$outputDir/$clusterSizeFile"        unless $clusterSizeFile =~ /^\//;
$swissprotClustersDescFile = "$outputDir/$swissprotClustersDescFile"    unless $swissprotClustersDescFile =~ /^\//;
$swissprotSinglesDescFile = "$outputDir/$swissprotSinglesDescFile"      unless $swissprotSinglesDescFile =~ /^\//;
$pfamHubFile = "$outputDir/$pfamHubFile"                unless $pfamHubFile =~ /^\//;
if ($fullGntRun) {
    $pfamDir = "$outputDir/$pfamDir"                    unless $pfamDir =~ /^\//;
    $pfamDirZip = "$outputDir/$pfamDirZip"              unless $pfamDirZip =~ /^\//;
    $allPfamDir = "$outputDir/$allPfamDir"              unless $allPfamDir =~ /^\//;
    $allPfamDirZip = "$outputDir/$allPfamDirZip"        unless $allPfamDirZip =~ /^\//;
    $splitPfamDir = "$outputDir/$splitPfamDir"          unless $splitPfamDir =~ /^\//;
    $splitPfamDirZip = "$outputDir/$splitPfamDirZip"    unless $splitPfamDirZip =~ /^\//;
    $allSplitPfamDir = "$outputDir/$allSplitPfamDir"    unless $allSplitPfamDir =~ /^\//;
    $allSplitPfamDirZip = "$outputDir/$allSplitPfamDirZip"  unless $allSplitPfamDirZip =~ /^\//;
    $uniprotIdZip = "$outputDir/$uniprotIdZip"          unless $uniprotIdZip =~ /^\//;
    $uniref50IdZip = "$outputDir/$uniref50IdZip"        unless $uniref50IdZip =~ /^\//;
    $uniref90IdZip = "$outputDir/$uniref90IdZip"        unless $uniref90IdZip =~ /^\//;
    $idOutputFile = "$outputDir/$idOutputFile"          unless $idOutputFile =~ /^\//;
    $noneDir = "$outputDir/$noneDir"                    unless $noneDir =~ /^\//;
    $noneZip = "$outputDir/$noneZip"                    unless $noneZip =~ /^\//;
}


if($cooc!~/^\d+$/){
    if(defined $cooc){
        die "incfrac must be an integer\n";
    }
    $cooc=20;  
}


unless(-s $ssnIn){
    die "cannot open ssnin file $ssnIn\n";
}

my $ssnInZip = "";
if ($ssnIn =~ /\.zip$/i) {
    $ssnInZip = $ssnIn;
    $ssnIn =~ s/\.zip$/\.xgmml/i;
}

(my $ssnName = $ssnOut) =~ s%^.*/([^/]+)\.xgmml$%$1%i;
my $ssnOutZip = "$outputDir/$ssnName.zip";
(my $gnnZip = $gnn) =~ s/\.xgmml$/.zip/i;
(my $pfamHubFileZip = $pfamHubFile) =~ s/\.xgmml$/.zip/i;
my $allFastaFile = "$fastaDir/all.fasta";
(my $arrowZip = $arrowDataFile) =~ s/\.sqlite/.zip/i if $arrowDataFile;
my $singletonsFastaFile = "$fastaDir/singletons.fasta";

my $jobNamePrefix = $jobId ? "${jobId}_" : "";

if ($fullGntRun) {
    mkdir $clusterDataPath          or die "Unable to create output cluster data path $clusterDataPath: $!"     if not -d $clusterDataPath;
    mkdir $uniprotNodeDataPath      or die "Unable to create output node data path $uniprotNodeDataPath: $!"    if not -d $uniprotNodeDataPath;
    mkdir $uniref50NodeDataPath     or die "Unable to create output node data path $uniref50NodeDataPath: $!"   if not -d $uniref50NodeDataPath;
    mkdir $uniref90NodeDataPath     or die "Unable to create output node data path $uniref90NodeDataPath: $!"   if not -d $uniref90NodeDataPath;
    mkdir $fastaDir                 or die "Unable to create output fasta data path $fastaDir: $!"              if not -d $fastaDir;
}


my $cmdString = "$toolpath/cluster_gnn.pl " .
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
        "-uniprot-id-dir $uniprotNodeDataPath " .
        "-uniref50-id-dir $uniref50NodeDataPath " .
        "-uniref90-id-dir $uniref90NodeDataPath " .
        "-id-out \"$idOutputFile\" " .
        "-none-dir \"$noneDir\" ";
    $cmdString .= " -arrow-file \"$arrowDataFile\"" if $arrowDataFile;
    $cmdString .= " -cooc-table \"$coocTableFile\"" if $coocTableFile;
    $cmdString .= " -hub-count-file \"$hubCountFile\"" if $hubCountFile;
    $cmdString .= " -parent-dir \"$parentDir\"" if $parentDir;
}

my $info = {
    color_only => 0,
    uniprot_node_data_path => $uniprotNodeDataPath,
    uniprot_node_zip => $uniprotIdZip,
    uniref50_node_data_path => $uniref50NodeDataPath,
    uniref50_node_zip => $uniref50IdZip,
    uniref90_node_data_path => $uniref90NodeDataPath,
    uniref90_node_zip => $uniref90IdZip,
    fasta_data_path => $fastaDir,
    fasta_zip => $fastaZip,
    ssn_out => $ssnOut,
    ssn_out_zip => $ssnOutZip,
    config_file => $configFile,
    fasta_tool_path => "$toolpath/get_fasta.pl",
    cat_tool_path => "$toolpath/cat_files.pl",
    gnn => $gnn,
    gnn_zip => $gnnZip,
    pfamhubfile => $pfamHubFile,
    pfamhubfile_zip => $pfamHubFileZip,
    pfam_dir => $pfamDir,
    pfam_zip => $pfamDirZip,
    all_pfam_dir => $allPfamDir,
    all_pfam_zip => $allPfamDirZip,
    split_pfam_dir => $splitPfamDir,
    split_pfam_zip => $splitPfamDirZip,
    all_split_pfam_dir => $allSplitPfamDir,
    all_split_pfam_zip => $allSplitPfamDirZip,
    none_dir => $noneDir,
    none_zip => $noneZip,
    all_fasta_file => $allFastaFile,
    singletons_file => $singletonsFastaFile,
};

$info->{arrow_zip} = $arrowZip if $arrowZip;
$info->{arrow_file} = $arrowDataFile if $arrowDataFile;


my $schedType = "torque";
$schedType = "slurm" if (defined($scheduler) and $scheduler eq "slurm") or (not defined($scheduler) and usesSlurm());
my $SS = new EFI::SchedulerApi(type => $schedType, queue => $queue, resource => [1, 1], dryrun => $dryRun);


my $B = $SS->getBuilder();

$B->resource(1, 1, "150gb");
$B->addAction("source /etc/profile");
$B->addAction("module load $efiDbMod");
$B->addAction("module load $efiGnnMod");
$B->addAction("export BLASTDB=$outputDir/blast");
$B->addAction("$toolpath/unzip_file.pl -in $ssnInZip -out $ssnIn") if $ssnInZip =~ /\.zip/i;
$B->addAction($cmdString);
if ($fullGntRun) {
    EFI::GNN::Base::addFileActions($B, $info);
#    $B->addAction("\n\nmkdir \$BLASTDB");
#    $B->addAction("cd \$BLASTDB");
#    $B->addAction("formatdb -i $allFastaFile -n database -p T -o T");
}
$B->addAction("\n\n$toolpath/save_version.pl > $outputDir/gnn.completed");

$B->jobName("${jobNamePrefix}submit_gnn");
$B->renderToFile("submit_gnn.sh");

if (not $noSubmit) {
    my $gnnjob = $SS->submit("submit_gnn.sh");
    chomp $gnnjob;
    print "Job to make gnn network is :\n $gnnjob";
}

