#!/bin/env perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Data::Dumper;

use EFI::Job::Factory;


my $jobType = shift @ARGV;

if (not $jobType) {
    my $jobTypes = join("|", EFI::Job::Factory::get_available_types());
    print <<HELP;
usage: $0 <$jobTypes> [command line arguments}
HELP
    exit(1);
}


my $job = EFI::Job::Factory::create_est_job($jobType);

die "Invalid job type $jobType" if not $job;


my $dir = $job->getJobDir();

if (not -d $dir) {
    print "WARNING: no --job-dir specified.  Use the current directory? [y/n] ";
    my $yn = <STDIN>;
    exit(1) if $yn !~ m/^\s*y/i;
    $dir = $ENV{PWD};
    $job->setJobDir($dir);
}


print "Job Dir: $dir\n";

my $S = $job->getScheduler();
my $doSubmit = $job->getSubmitStatus();

my ($scriptDir, $logDir, $outputDir) = ("", "", "");
($scriptDir, $logDir, $outputDir) = $job->createJobStructure() if not ($doSubmit & EFI::Job::DRY_RUN);

my @jobs = $job->createJobs();
my $jobId = $job->getJobId();
my $jobNamePrefix = $jobId ? "${jobId}_" : "";

my $lastJobId = 0;
my %jobIds;
foreach my $jobInfo (@jobs) {
    my $jobName = $jobInfo->{name};
    my $jobFile = "$scriptDir/$jobName.sh";
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
    if ($doSubmit & EFI::Job::RUN) {
        $jobId = $S->submit($jobFile);
        chomp $jobId;
        ($jobId) = split(m/\./, $jobId);
    }
    print "$jobId\t$jobName\n";
    $jobIds{$jobObj} = $jobId;
    $lastJobId = $jobId;
}

# For EFI tools web UI
print "$lastJobId.for_web_ui\n";



