#!/usr/bin/env perl

BEGIN {
    die "The efishared and efignn environments must be loaded before running this script" if not exists $ENV{EFISHARED} or not exists $ENV{EFIGNN};
    use lib $ENV{EFISHARED};
}

use Getopt::Long;

use EFI::Database;
use EFI::SchedulerApi;
use EFI::Util qw(usesSlurm);
use EFI::Config;
use EFI::GNN::Base;
use EFI::JobConfig;


my ($ssnIn, $nbSize, $ssnOut, $cooc, $outputDir, $scheduler, $dryRun, $queue, $mapDirName, $jobId);
my ($statsFile, $clusterSizeFile, $swissprotClustersDescFile, $swissprotSinglesDescFile);
my ($jobConfigFile, $domainMapFileName, $mapFileName);
my $result = GetOptions(
    "ssn-in=s"                  => \$ssnIn,
    "ssn-out=s"                 => \$ssnOut,
    "out-dir=s"                 => \$outputDir,
    "scheduler=s"               => \$scheduler,
    "dry-run"                   => \$dryRun,
    "queue=s"                   => \$queue,
    "job-id=s"                  => \$jobId,
    "map-dir-name=s"            => \$mapDirName,
    "map-file-name=s"           => \$mapFileName,
    "domain-map-file-name=s"    => \$domainMapFileName,
    "stats=s"                   => \$statsFile,
    "cluster-sizes=s"           => \$clusterSizeFile,
    "sp-clusters-desc=s"        => \$swissprotClustersDescFile,
    "sp-singletons-desc=s"      => \$swissprotSinglesDescFile,
    "job-config=s"              => \$jobConfigFile,
);

$usage=<<USAGE
usage: $0 -ssnin <filename>

    -ssn-in             path to file of original ssn network to process
    -ssn-out            output filename (not path) for colorized sequence similarity network
    -out-dir            output directory
    -scheduler          scheduler type (default to torque, but also can be slurm)
    -dry-run            only generate the scripts, don't submit to queue
    -queue              the cluster queue to use
    -map-dir-name       the name of the sub-directory to use to output the list of uniprot IDs for each cluster (one file per cluster)
    -map-file-name      the name of the map file that lists uniprot ID, cluster #, and cluster color
    -stats              file to output tabular statistics to
    -clusters-sizes     file to output cluster sizes to
    -sp-clusters-desc   file to output SwissProt descriptions to for any clusters/nodes that have
                        SwissProt annotations (or any metanodes with children that have
                        SwissProt annotations)
    -sp-singletons-desc file to output SwissProt descriptions to for any singleton node that have
                        SwissProt annotations
    -job-config         file specifying the parameters and files to use as input output for this job

The only required argument is -ssnin, all others have defaults.
USAGE
;

my $dbModule = $ENV{EFIDBMOD};
my $gntPath = $ENV{EFIGNN};
my $gntModule = $ENV{EFIGNNMOD};

#my $JC = LoadJobConfig($jobConfigFile, getDefaults());

if (not exists $ENV{EFICONFIG}) {
    die "Either the configuration file or the EFICONFIG environment variable must be set\n$usage";
}
my $configFile = $ENV{EFICONFIG};

if (not $ssnIn or not -s $ssnIn) {
    $ssnIn = "" if not $ssnIn;
    die "-ssnin $ssnIn does not exist or has a zero size\n$usage";
}





if (not $ssnOut) {
    ($ssnOut = $ssnIn) =~ s/^.*?([^\/]+)$/$1/;
    $ssnOut =~ s/\.(xgmml|zip)$/_colored.xgmml/i;
}
(my $ssnName = $ssnOut) =~ s/\.xgmml$//i;
my $ssnOutZip = "$ssnName.zip";

my $ssnInZip = $ssnIn;
if ($ssnInZip =~ /\.zip$/i) {
    $ssnIn =~ s/\.zip$/.xgmml/i;
}

$mapDirName                 = "cluster-data"                    if not $mapDirName;
$mapFileName                = "mapping_table.txt"               if not $mapFileName;
$domainMapFileName          = "domain_mapping_table.txt"        if not $domainMapFileName;
$jobId                      = ""                                if not $jobId;
$statsFile                  = "stats.txt"                       if not $statsFile;
$clusterSizeFile            = "cluster_sizes.txt"               if not $clusterSizeFile;
$swissprotClustersDescFile  = "swissprot_clusters_desc.txt"     if not $swissprotClustersDescFile;
$swissprotSinglesDescFile   = "swissprot_singletons_desc.txt"   if not $swissprotSinglesDescFile;

my $jobNamePrefix = $jobId ? "${jobId}_" : "";


my $outputPath              = $ENV{PWD} . "/$outputDir";
my $clusterDataPath         = "$outputPath/$mapDirName";
my $uniprotNodeDataPath     = "$clusterDataPath/uniprot-nodes";
my $uniref50NodeDataPath    = "$clusterDataPath/uniref50-nodes";
my $uniref90NodeDataPath    = "$clusterDataPath/uniref90-nodes";
my $fastaDataPath           = "$clusterDataPath/fasta";
my $allFastaFile            = "$fastaDataPath/all.fasta";
my $singletonsFastaFile     = "$fastaDataPath/singletons.fasta";
my $inputSeqsFile           = "$clusterDataPath/sequences.fasta";

my $uniprotNodeDataZip = "$outputPath/${ssnName}_UniProt_IDs.zip";
my $uniref50NodeDataZip = "$outputPath/${ssnName}_UniRef50_IDs.zip";
my $uniref90NodeDataZip = "$outputPath/${ssnName}_UniRef90_IDs.zip";
my $fastaZip = "$outputPath/${ssnName}_FASTA.zip";

# The if statements apply to the mkdir cmd, not the die().
mkdir $outputPath               or die "Unable to create output directory $outputPath: $!"                  if not -d $outputPath;
mkdir $clusterDataPath          or die "Unable to create output cluster data path $clusterDataPath: $!"     if not -d $clusterDataPath;
mkdir $uniprotNodeDataPath      or die "Unable to create output node data path $uniprotNodeDataPath: $!"    if not -d $uniprotNodeDataPath;
mkdir $uniref50NodeDataPath     or die "Unable to create output node data path $uniref50NodeDataPath: $!"   if not -d $uniref50NodeDataPath;
mkdir $uniref90NodeDataPath     or die "Unable to create output node data path $uniref90NodeDataPath: $!"   if not -d $uniref90NodeDataPath;
mkdir $fastaDataPath            or die "Unable to create output fasta data path $fastaDataPath: $!"         if not -d $fastaDataPath;


my $fileSize = 0;
if ($ssnInZip !~ m/\.zip/) { # If it's a .zip we can't predict apriori what the size will be.
    $fileSize = -s $ssnIn;
}

# Y = MX+B, M=emperically determined, B = safety factor; X = file size in MB; Y = RAM reservation in GB
my $ramReservation = 150;
if ($fileSize) {
    my $ramPredictionM = 0.02;
    my $ramSafety = 10;
    $fileSize = $fileSize / 1024 / 1024; # MB
    $ramReservation = $ramPredictionM * $fileSize + $ramSafety;
    $ramReservation = int($ramReservation + 0.5);
}

my $schedType = "torque";
$schedType = "slurm" if (defined($scheduler) and $scheduler eq "slurm") or (not defined($scheduler) and usesSlurm());
my $SS = new EFI::SchedulerApi(type => $schedType, queue => $queue, resource => [1, 1], dryrun => $dryRun);


my $fileInfo = {
    color_only => 1,
    uniprot_node_data_path => $uniprotNodeDataPath,
    uniprot_node_zip => $uniprotNodeDataZip,
    uniref50_node_data_path => $uniref50NodeDataPath,
    uniref50_node_zip => $uniref50NodeDataZip,
    uniref90_node_data_path => $uniref90NodeDataPath,
    uniref90_node_zip => $uniref90NodeDataZip,
    fasta_data_path => $fastaDataPath,
    fasta_zip => $fastaZip,
    fasta_tool_path => "$gntPath/get_fasta.pl",
    cat_tool_path => "$gntPath/cat_files.pl",
    ssn_out => "$outputPath/$ssnOut",
    ssn_out_zip => "$outputPath/$ssnOutZip",
    config_file => $configFile,
    tool_path => $gntPath,
    all_fasta_file => $allFastaFile,
    singletons_file => $singletonsFastaFile,
    input_seqs_file => $inputSeqsFile,
};

my $scriptArgs = 
    "-ssnin $ssnIn " .
    "-ssnout $outputPath/$ssnOut " .
    "-uniprot-id-dir $uniprotNodeDataPath " .
    "-uniref50-id-dir $uniref50NodeDataPath " .
    "-uniref90-id-dir $uniref90NodeDataPath " .
    "-id-out ${ssnName}_$mapFileName " .
    "-id-out-domain ${ssnName}_$domainMapFileName " .
    "-config $configFile " .
    "-stats \"$statsFile\" " .
    "-cluster-sizes \"$clusterSizeFile\" " .
    "-sp-clusters-desc \"$swissprotClustersDescFile\" " .
    "-sp-singletons-desc \"$swissprotSinglesDescFile\" " .
    ""
    ;

my $B = $SS->getBuilder();

$B->resource(1, 1, "${ramReservation}gb");
$B->addAction("module load $dbModule");
$B->addAction("module load $gntModule");
$B->addAction("cd $outputPath");
$B->addAction("$gntPath/unzip_file.pl -in $ssnInZip -out $ssnIn") if $ssnInZip =~ /\.zip/i;
$B->addAction("$gntPath/cluster_gnn.pl $scriptArgs");
EFI::GNN::Base::addFileActions($B, $fileInfo);
$B->addAction("touch $outputPath/1.out.completed");

my $jobName = "${jobNamePrefix}colorgnn";
my $jobScript = "$outputPath/$jobName.sh";
$B->jobName($jobName);
$B->renderToFile($jobScript);

$jobId = $SS->submit($jobScript);
print "Color SSN job is:\n $jobId";



sub getDefaults {
    my $defaults = {
        mapDirName                  => "cluster-data",
        mapFileName                 => "mapping_table.txt",
        jobId                       => "",
        statsFile                   => "stats.txt",
        clusterSizeFile             => "cluster_sizes.txt",
        swissprotClustersDescFile   => "swissprot_clusters_desc.txt",
        swissprotSinglesDescFile    => "swissprot_singletons_desc.txt",
    };
    return $defaults;
}



