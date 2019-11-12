
package Setup;

use strict;
use warnings;

use Exporter qw(import);

use File::Temp;
use Data::Dumper;

use lib "$FindBin::Bin/../../lib";


our @EXPORT =
    qw(
        $WDIR
        $DATADIR
        $SSN_UNIPROT_DOMAIN
        $SSN_UNIREF50_DOMAIN
        $SSN_UNIREF90_DOMAIN
        $SSN_UNIPROT
        $SSN_UNIREF50
        $SSN_UNIREF90
        $TMP
        make_test_dir
        run_test
        );


our $WDIR = $ENV{PWD};
our $DATADIR = "$WDIR/data";
our $SSN_UNIPROT_DOMAIN = "$DATADIR/ssn_uniprot_domain.xgmml";
our $SSN_UNIREF50_DOMAIN = "$DATADIR/ssn_uniprot_domain.xgmml";
our $SSN_UNIREF90_DOMAIN = "$DATADIR/ssn_uniprot_domain.xgmml";
our $SSN_UNIPROT = "$DATADIR/ssn_uniprot.xgmml";
our $SSN_UNIREF50 = "$DATADIR/ssn_uniprot.xgmml";
our $SSN_UNIREF90 = "$DATADIR/ssn_uniprot.xgmml";

our $TMP = "$WDIR/tmp";


my @tmps;



sub new {
    my $class = shift;
    my @args = @_;
    
    my $dryRun = grep m/dry\-?run/, @ARGV;
    my $noSubmit = grep m/no\-?submit/, @ARGV;

    my $dir = make_test_dir();
    @ARGV = @args;
    push @ARGV,
        "--job-dir", $dir,
        "--config", "/home/n-z/noberg/dev/EFITools/conf/efi.conf";
    push @ARGV, "--dry-run" if $dryRun;
    push @ARGV, "--no-submit" if $noSubmit;

    my $self = {job_dir => $dir};

    return bless $self, $class;
}


sub make_test_dir {
    #my $dir = File::Temp->newdir(TEMPLATE => "tmpXXXXXX", DIR => "$TMP", SUFFIX => ".txt", CLEANUP => 0);
    #my $dir = "$TMP/test";
    (my $dirName = $0) =~ s%^.*?([^/]+)\.pl$%$1%;
    my $dir = "$TMP/$dirName";
    `rm -rf $dir`;
    mkdir $dir;
    push @tmps, $dir;
    return $dir;
}


sub runTest {
    my $self = shift;

    my $jobBuilder = shift;

    $jobBuilder->createJobStructure();
    my $S = $jobBuilder->createScheduler();
    
    my $doSubmit = $jobBuilder->getSubmitStatus();
    
    my @jobs = $jobBuilder->createJobs();
    
    my $jobId = $jobBuilder->getJobId();
    my $jobNamePrefix = $jobId ? "${jobId}_" : "";
    
    my $lastJobId = 0;
    my %jobIds;
    foreach my $jobInfo (@jobs) {
        my $jobName = $jobInfo->{name};
        my $jobFile = "$self->{job_dir}/scripts/$jobName.sh";
        my $jobObj = $jobInfo->{job};
        my @jobDeps = @{$jobInfo->{deps}};
    
        foreach my $dep (@jobDeps) {
            my $isArray = 0;
            if (ref($dep) eq "HASH") {
                $dep = $dep->{obj};
                $isArray = $dep->{is_job_array};
            }
            if ($jobIds{$dep}) {
                $jobObj->dependency($isArray, $jobIds{$dep});
            }
        }
    
        $jobObj->jobName("$jobNamePrefix$jobName");
        $jobObj->renderToFile($jobFile);
        my $jobId = 1;
        if ($doSubmit) {
            $jobId = $S->submit($jobFile);
            chomp $jobId;
            ($jobId) = split(m/\./, $jobId);
        }
        print "$jobId\t$jobName\n";
        $jobIds{$jobObj} = $jobId;
        $lastJobId = $jobId;
    }
    # For EFI tools web UI
    print "$lastJobId\n";
}


1;

