#!/usr/bin/env perl

BEGIN {
    die "The efishared and efignn environments must be loaded before running this script" if not exists $ENV{EFISHARED} or not exists $ENV{EFIGNN};
    use lib $ENV{EFISHARED};
}

use strict;
use warnings;

use Getopt::Long;
use FindBin;
use lib $FindBin::Bin . "/lib";

use EFI::Database;
use EFI::SchedulerApi;
use EFI::Util qw(usesSlurm);
use EFI::Config;
use EFI::GNN::Base;


my ($ssnIn, $nbSize, $ssnOut, $cooc, $outputDir, $scheduler, $dryRun, $queue, $jobId);
my ($statsFile, $clusterSizeFile, $swissprotClustersDescFile, $swissprotSinglesDescFile);
my ($jobConfigFile, $domainMapFileName, $mapFileName, $extraRam);
my $result = GetOptions(
    "ssn-in=s"                  => \$ssnIn,
    "ssn-out=s"                 => \$ssnOut,
    "out-dir=s"                 => \$outputDir,
    "scheduler=s"               => \$scheduler,
    "dry-run"                   => \$dryRun,
    "queue=s"                   => \$queue,
    "job-id=s"                  => \$jobId,
    "map-file-name=s"           => \$mapFileName,
    "domain-map-file-name=s"    => \$domainMapFileName,
    "stats=s"                   => \$statsFile,
    "cluster-sizes=s"           => \$clusterSizeFile,
    "sp-clusters-desc=s"        => \$swissprotClustersDescFile,
    "sp-singletons-desc=s"      => \$swissprotSinglesDescFile,
    "job-config=s"              => \$jobConfigFile,
    "extra-ram"                 => \$extraRam,
);

my $usage = <<USAGE
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
    -extra-ram          use increased amount of memory

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

$ssnIn = "$ENV{PWD}/$ssnIn" if $ssnIn and $ssnIn !~ m/^\//;
if (not $ssnIn or not -s $ssnIn) {
    $ssnIn = "" if not $ssnIn;
    die "-ssnin $ssnIn does not exist or has a zero size\n$usage";
}

die "$usage\nERROR: missing -queue parameter" if not $queue;





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

$outputDir                  = "output"                          if not $outputDir;
$mapFileName                = "mapping_table.txt"               if not $mapFileName;
$domainMapFileName          = "domain_mapping_table.txt"        if not $domainMapFileName;
$jobId                      = ""                                if not $jobId;
$statsFile                  = "stats.txt"                       if not $statsFile;
$clusterSizeFile            = "cluster_sizes.txt"               if not $clusterSizeFile;
$swissprotClustersDescFile  = "swissprot_clusters_desc.txt"     if not $swissprotClustersDescFile;
$swissprotSinglesDescFile   = "swissprot_singletons_desc.txt"   if not $swissprotSinglesDescFile;

my $jobNamePrefix = $jobId ? "${jobId}_" : "";


my $outputPath                  = $ENV{PWD} . "/$outputDir";
my $clusterDataPath             = "cluster-data";
my $uniprotNodeDataDir          = "$clusterDataPath/uniprot-nodes";
my $uniprotDomainNodeDataDir    = "$clusterDataPath/uniprot-domain-nodes";
my $uniref50NodeDataDir         = "$clusterDataPath/uniref50-nodes";
my $uniref90NodeDataDir         = "$clusterDataPath/uniref90-nodes";
my $fastaDataDir                = "$clusterDataPath/fasta";
my $fastaDomainDataDir          = "$clusterDataPath/fasta-domain";

my $uniprotNodeDataZip = "$outputPath/${ssnName}_UniProt_IDs.zip";
my $uniprotDomainNodeDataZip = "$outputPath/${ssnName}_UniProt_Domain_IDs.zip";
my $uniref50NodeDataZip = "$outputPath/${ssnName}_UniRef50_IDs.zip";
my $uniref90NodeDataZip = "$outputPath/${ssnName}_UniRef90_IDs.zip";
my $fastaZip = "$outputPath/${ssnName}_FASTA.zip";
my $fastaDomainZip = "$outputPath/${ssnName}_FASTA_Domain.zip";

# The if statements apply to the mkdir cmd, not the die().
my $mkPath = sub {
   my $dir = "$outputPath/$_[0]";
   mkdir $dir or die "Unable to create output dir $dir: $!" if not -d $dir;
};
mkdir $outputPath or die "Unable to create output directory $outputPath: $!" if not -d $outputPath;
&$mkPath($clusterDataPath);
&$mkPath($uniprotNodeDataDir);
&$mkPath($uniprotDomainNodeDataDir);
&$mkPath($uniref50NodeDataDir);
&$mkPath($uniref90NodeDataDir);
&$mkPath($fastaDataDir);
&$mkPath($fastaDomainDataDir);


my $fileSize = 0;
if ($ssnInZip !~ m/\.zip/) { # If it's a .zip we can't predict apriori what the size will be.
    $fileSize = -s $ssnIn;
}

# Y = MX+B, M=emperically determined, B = safety factor; X = file size in MB; Y = RAM reservation in GB
my $ramReservation = defined $extraRam ? 500 : 150;
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

my $absPath = sub {
    return $_[0] =~ m/^\// ? $_[0] : "$outputPath/$_[0]";
};

my $fileInfo = {
    color_only => 1,
    config_file => $configFile,
    tool_path => $gntPath,
    fasta_tool_path => "$gntPath/get_fasta.pl",
    cat_tool_path => "$gntPath/cat_files.pl",

    uniprot_node_data_dir => &$absPath($uniprotNodeDataDir),
    uniprot_domain_node_data_dir => &$absPath($uniprotDomainNodeDataDir),
    uniref50_node_data_dir => &$absPath($uniref50NodeDataDir),
    uniref90_node_data_dir => &$absPath($uniref90NodeDataDir),
    fasta_data_dir => &$absPath($fastaDataDir),
    fasta_domain_data_dir => &$absPath($fastaDomainDataDir),
    
    uniprot_node_zip => $uniprotNodeDataZip,
    uniprot_domain_node_zip => $uniprotDomainNodeDataZip,
    uniref50_node_zip => $uniref50NodeDataZip,
    uniref90_node_zip => $uniref90NodeDataZip,
    fasta_zip => $fastaZip,
    fasta_domain_zip => $fastaDomainZip,

    ssn_out => "$outputPath/$ssnOut",
    ssn_out_zip => "$outputPath/$ssnOutZip",
};

my $scriptArgs = 
    "-output-dir $outputPath " .
    "-ssnin $ssnIn " .
    "-ssnout $ssnOut " .
    "-uniprot-id-dir $uniprotNodeDataDir " .
    "-uniprot-id-domain-dir $uniprotDomainNodeDataDir " .
    "-uniref50-id-dir $uniref50NodeDataDir " .
    "-uniref90-id-dir $uniref90NodeDataDir " .
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

my $jobName = "${jobNamePrefix}color_ssn";
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



