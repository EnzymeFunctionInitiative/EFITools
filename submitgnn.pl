#!/usr/bin/env perl

BEGIN {
    die "Please load efishared before runing this script" if not $ENV{EFISHARED};
    use lib $ENV{EFISHARED};
}


use FindBin;
use Getopt::Long;
use lib $FindBin::Bin . "/lib";

use EFI::SchedulerApi;
use EFI::Util qw(usesSlurm);
use EFI::Config;
use EFI::GNNShared;


$result = GetOptions(
    "ssnin=s"           => \$ssnIn,
    "n|nb-size=s"       => \$n,
    "warning-file=s"    => \$warningFile,
    "gnn=s"             => \$gnn,
    "ssnout=s"          => \$ssnOut,
    "incfrac|cooc=i"    => \$incfrac,
    "stats=s"           => \$stats,
    "pfam=s"            => \$pfamhubfile,
    "pfam-dir=s"        => \$pfamDir,
    "pfam-zip=s"        => \$pfamZip, # only used for GNT calls, non batch
    "id-dir=s"          => \$idDir,
    "id-zip=s"          => \$idZip, # only used for GNT calls, non batch
    "id-out=s"          => \$idOutputFile,
    "fasta-dir=s"       => \$fastaDir,
    "fasta-zip=s"       => \$fastaZip,
    "none-dir=s"        => \$noneDir,
    "none-zip=s"        => \$noneZip, # only used for GNT calls, non batch
    "disable-nnm"       => \$dontUseNewNeighborMethod,
    "scheduler=s"       => \$scheduler,
    "dry-run"           => \$dryRun,
    "queue=s"           => \$queue,
    "arrow-file=s"      => \$arrowDataFile,
    "config=s"          => \$configFile,
);

$usage = <<USAGE
usage: $0 -ssnin <filename> -n <positive integer> -nomatch <filename> -gnn <filename> -ssnout <filename>
    -ssnin          name of original ssn network to process
    -nb-size        distance (+/-) to search for neighbors
    -gnn            filename of genome neighborhood network output file
    -ssnout         output filename for colorized sequence similarity network
    -warning-file   output file that contains sequences without neighbors or matches
    -cooc           co-occurrence
    -stats          file to output tabular statistics to
    -pfam           file to output PFAM hub GNN to
    -id-dir         path to directory to output lists of IDs (one file/list per cluster number)
    -id-zip         path to a file to zip all of the output lists
    -pfam-dir       path to directory to output PFAM cluster data (one file/list per cluster number)
    -pfam-zip       path to a file to output zip file for PFAM cluster data
    -fasta-dir      path a directory output FASTA files
    -fasta-zip      path to a file to create compressed all FASTA files
    -id-out         path to a file to save the ID, cluster #, cluster color
    -config         configuration file for database info, etc.
    -scheduler      scheduler type (default to torque, but also can be slurm)
    -dry-run        only generate the scripts, don't submit to queue
    -queue          the cluster queue to use
    -arrow-file     the file to output data to use for arrow data
USAGE
;

$batchMode = 0 if not defined $batchMode;

if (not -f $configFile and not exists $ENV{EFICONFIG}) {
    die "Either the configuration file or the EFICONFIG environment variable must be set\n$usage";
} elsif (not -f $configFile) {
    $configFile = $ENV{EFICONFIG};
}

$toolpath=$ENV{'EFIGNN'};
$efiGnnMod=$ENV{'EFIGNNMOD'};
$efiDbMod=$ENV{'EFIDBMOD'};


die "ssnin is  not specified"  if not $ssnIn;
die "nb-size is  not specified"  if not $n;
die "warning-file is  not specified"  if not $warningFile;
die "gnn is  not specified"  if not $gnn;
die "ssnout is  not specified"  if not $ssnOut;
die "cooc is  not specified"  if not $incfrac;
die "stats is  not specified"  if not $stats;
die "pfam is  not specified"  if not $pfamhubfile;
die "pfam-dir is  not specified"  if not $pfamDir;
die "pfam-zip is  not specified"  if not $pfamZip;
die "id-dir is  not specified"  if not $idDir;
die "id-zip is  not specified"  if not $idZip;
die "id-out is  not specified"  if not $idOutputFile;
die "fasta-dir is  not specified"  if not $fastaDir;
die "fasta-zip is  not specified"  if not $fastaZip;
die "none-dir is  not specified"  if not $noneDir;
die "none-zip is  not specified"  if not $noneZip;

print "gnn mod is:$efiGnnMod\n";
print "efidb mod is:$efiDbMod\n";
print "ssnin is $ssnIn\n";
print "n|nb-size is $n\n";
print "warning-file is $warningFile\n";
print "gnn is $gnn\n";
print "ssnout is $ssnOut\n";
print "incfrac|cooc is $incfrac\n";
print "stats is $stats\n";
print "distance is $n\n";
print "pfam is $pfamhubfile\n";
print "pfam-dir is $pfamDir\n";
print "pfam-zip is $pfamZip\n";
print "id-dir is $idDir\n";
print "id-zip is $idZip\n";
print "id-out is $idOutputFile\n";
print "fasta-dir is $fastaDir\n";
print "fasta-zip is $fastaZip\n";
print "none-dir is $noneDir\n";
print "none-zip is $noneZip\n";

unless($n>0){
    die "-n $n must be an integer greater than zero\n$usage";
}

my $outputDir = $ENV{PWD};


$ssnIn = "$outputDir/$ssnIn"                unless $ssnIn =~ /^\//;
$gnn = "$outputDir/$gnn"                    unless $gnn =~ /^\//;
$ssnOut = "$outputDir/$ssnOut"              unless $ssnOut =~ /^\//;
$stats = "$outputDir/$stats"                unless $stats =~ /^\//;
$pfamhubfile = "$outputDir/$pfamhubfile"    unless $pfamhubfile =~ /^\//;
$pfamDir = "$outputDir/$pfamDir"            unless $pfamDir =~ /^\//;
$pfamZip = "$outputDir/$pfamZip"            unless $pfamZip =~ /^\//;
$idDir = "$outputDir/$idDir"                unless $idDir =~ /^\//;
$idZip = "$outputDir/$idZip"                unless $idZip =~ /^\//;
$idOutputFile = "$outputDir/$idOutputFile"  unless $idOutputFile =~ /^\//;
$noneDir = "$outputDir/$noneDir"            unless $noneDir =~ /^\//;
$noneZip = "$outputDir/$noneZip"            unless $noneZip =~ /^\//;
$queue = "efi"                              unless $queue =~ /\w/;


if($incfrac!~/^\d+$/){
    if(defined $incfrac){
        die "incfrac must be an integer\n";
    }
    $incfrac=20;  
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
(my $pfamhubfileZip = $pfamhubfile) =~ s/\.xgmml$/.zip/i;


mkdir $fastaDir or die "Unable to create output fasta data path $fastaDir: $!" if not -d $fastaDir;


my $cmdString = "$toolpath/clustergnn.pl " .
    "-n $n " . 
    "-incfrac \"$incfrac\" " .
    "-ssnin \"$ssnIn\" " . 
    "-ssnout \"$ssnOut\" " . 
    "-gnn \"$gnn\" " . 
    "-stats \"$stats\" " .
    "-warning-file \"$warningFile\" " .
    "-pfam \"$pfamhubfile\" " .
    "-pfam-dir \"$pfamDir\" " .
#    "-pfam-zip \"$pfamZip\" " .
    "-id-dir \"$idDir\" " .
#    "-id-zip \"$idZip\" " .
    "-id-out \"$idOutputFile\" " .
    "-none-dir \"$noneDir\" "
#    "-none-zip \"$noneZip\""
    ;
$cmdString .= " -arrow-file \"$arrowDataFile\"" if $arrowDataFile;

my $info = {
    color_only => 0,
    node_data_path => $idDir,
    node_zip => $idZip,
    fasta_data_path => $fastaDir,
    fasta_zip => $fastaZip,
    ssn_out => $ssnOut,
    ssn_out_zip => $ssnOutZip,
    config_file => $configFile,
    tool_path => $toolpath,
    gnn => $gnn,
    gnn_zip => $gnnZip,
    pfamhubfile => $pfamhubfile,
    pfamhubfile_zip => $pfamhubfileZip,
    pfam_dir => $pfamDir,
    pfam_zip => $pfamZip,
    none_dir => $noneDir,
    none_zip => $noneZip,
};


my $schedType = "torque";
$schedType = "slurm" if (defined($scheduler) and $scheduler eq "slurm") or (not defined($scheduler) and usesSlurm());
my $SS = new EFI::SchedulerApi(type => $schedType, queue => $queue, resource => [1, 1], dryrun => $dryRun);


my $B = $SS->getBuilder();
$B->addAction("module load $efiDbMod");
$B->addAction("module load $efiGnnMod");
$B->addAction("$toolpath/unzip_ssn.pl -in $ssnInZip -out $ssnIn") if $ssnInZip =~ /\.zip/i;
$B->addAction($cmdString);
EFI::GNNShared::addFileActions($B, $info);
$B->addAction("$toolpath/save_version.pl > $outputDir/gnn.completed");

$B->renderToFile("gnnqsub.sh");
my $gnnjob = $SS->submit("gnnqsub.sh");

print "Job to make gnn network is :\n $gnnjob";

