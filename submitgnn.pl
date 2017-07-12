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


$result = GetOptions(
    "ssnin=s"           => \$ssnin,
    "n|nb-size=s"       => \$n,
    "warning-file=s"    => \$warningFile,
    "gnn=s"             => \$gnn,
    "ssnout=s"          => \$ssnout,
    "incfrac|cooc=i"    => \$incfrac,
    "stats=s"           => \$stats,
    "pfam=s"            => \$pfamhubfile,
    "pfam-dir=s"        => \$pfamDir,
    "pfam-zip=s"        => \$pfamZip, # only used for GNT calls, non batch
    "id-dir=s"          => \$idDir,
    "id-zip=s"          => \$idZip, # only used for GNT calls, non batch
    "id-out=s"          => \$idOutputFile,
    "none-dir=s"        => \$noneDir,
    "none-zip=s"        => \$noneZip, # only used for GNT calls, non batch
    "disable-nnm"       => \$dontUseNewNeighborMethod,
    "scheduler=s"       => \$scheduler,
    "dry-run"           => \$dryRun,
    "queue=s"           => \$queue,
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
    -id-out         path to a file to save the ID, cluster #, cluster color
    -config         configuration file for database info, etc.
    -scheduler      scheduler type (default to torque, but also can be slurm)
    -dry-run        only generate the scripts, don't submit to queue
    -queue          the cluster queue to use
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

print "gnn mod is:$efiGnnMod\n";
print "efidb mod is:$efiDbMod\n";
print "ssnin is $ssnin\n";
print "n|nb-size is $n\n";
print "warning-file is $warningFile\n";
print "gnn is $gnn\n";
print "ssnout is $ssnout\n";
print "incfrac|cooc is $incfrac\n";
print "stats is $stats\n";
print "distance is $n\n";
print "pfam is $pfamhubfile\n";
print "pfam-dir is $pfamDir\n";
print "pfam-zip is $pfamZip\n";
print "id-dir is $idDir\n";
print "id-zip is $idZip\n";
print "id-out is $idOutputFile\n";
print "none-dir is $noneDir\n";
print "none-zip is $noneZip\n";

unless($n>0){
    die "-n $n must be an integer greater than zero\n$usage";
}

$ssnin="$ENV{PWD}/$ssnin"                   unless $ssnin =~ /^\//;
$nomatch="$ENV{PWD}/$nomatch"               unless $nomatch =~ /^\//;
$noneigh="$ENV{PWD}/$noneigh"               unless $noneigh =~ /^\//;
$gnn="$ENV{PWD}/$gnn"                       unless $gnn =~ /^\//;
$ssnout="$ENV{PWD}/$ssnout"                 unless $ssnout =~ /^\//;
$stats="$ENV{PWD}/$stats"                   unless $stats =~ /^\//;
$pfamhubfile = "$ENV{PWD}/$pfamhubfile"     unless $pfamhubfile =~ /^\//;
$pfamDir = "$ENV{PWD}/$pfamDir"             unless $pfamDir =~ /^\//;
$pfamZip = "$ENV{PWD}/$pfamZip"             unless $pfamZip =~ /^\//;
$idDir = "$ENV{PWD}/$idDir"                 unless $idDir =~ /^\//;
$idZip = "$ENV{PWD}/$idZip"                 unless $idZip =~ /^\//;
$idOutputFile = "$ENV{PWD}/$idOutputFile"   unless $idOutputFile =~ /^\//;
$noneDir = "$ENV{PWD}/$noneDir"             unless $noneDir =~ /^\//;
$noneZip = "$ENV{PWD}/$noneZip"             unless $noneZip =~ /^\//;
$queue="efi"                                unless $queue =~ /\w/;

if($incfrac!~/^\d+$/){
    if(defined $incfrac){
        die "incfrac must be an integer\n";
    }
    $incfrac=20;  
}


unless(-s $ssnin){
    die "cannot open ssnin file $ssnin\n";
}

my $cmdString = "$toolpath/clustergnn.pl " .
    "-n $n " . 
    "-incfrac \"$incfrac\" " .
    "-ssnin \"$ssnin\" " . 
    "-ssnout \"$ssnout\" " . 
    "-gnn \"$gnn\" " . 
    "-stats \"$stats\" " .
    "-warning-file \"$warningFile\" " .
    "-pfam \"$pfamhubfile\" " .
    "-pfam-dir \"$pfamDir\" " .
    "-pfam-zip \"$pfamZip\" " .
    "-id-dir \"$idDir\" " .
    "-id-zip \"$idZip\" " .
    "-id-out \"$idOutputFile\" " .
    "-none-dir \"$noneDir\" " .
    "-none-zip \"$noneZip\"";


my $schedType = "torque";
$schedType = "slurm" if (defined($scheduler) and $scheduler eq "slurm") or (not defined($scheduler) and usesSlurm());
my $SS = new EFI::SchedulerApi(type => $schedType, queue => $queue, resource => [1, 1], dryrun => $dryRun);


my $B = $SS->getBuilder();
$B->addAction("module load $efiGnnMod");
$B->addAction("module load $efiDbMod");
$B->addAction($cmdString);
$B->addAction("touch gnn.completed");

$B->renderToFile("gnnqsub.sh");
my $gnnjob = $SS->submit("gnnqsub.sh");

print "Job to make gnn network is :\n $gnnjob";

