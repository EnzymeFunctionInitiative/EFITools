#!/bin/env perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Data::Dumper;

use EFI::Job::Factory;


my $jobType = shift @ARGV;

# The user can request general app help here, either by not providing any arguments or by providing the
# --help flag.
if (not $jobType or $jobType =~ m/help/) {
    print getHelp();
    exit(1);
}


# Option validation is done here.  If the user requests a valid job type, plus --help, then the usage is printed out
# If there are validation errors, the usage is printed out.
my $job = EFI::Job::Factory::create_est_job($jobType);

# If an invalid job type is specified, then the app usage is printed out.
if (not $job) {
    print getHelp("Invalid job type '$jobType'.");
    exit(1);
}
if ($job->getWantsHelp()) {
    print getHelp("", $job, $jobType);
    exit(1);
}
if ($job->hasErrors()) {
    my $msg = join("\n", $job->getErrors());
    print getHelp($msg, $job, $jobType);
    exit(1);
}


my $dir = $job->getJobDir();

if (not $job->getJobDirArgumentSet() and not($job->getSubmitStatus() & EFI::Job::DRY_RUN)) {
    if ($job->getHasResults() and not $job->getUseResults()) {
        my $msg = "Results already exist in the current directory.  Please use the --job-dir flag to use this\ndirectory, or remove the results.";
        print getHelp($msg, $job, $jobType);
        exit(1);
    } else {
        print "WARNING: no --job-dir specified.  Use the current directory? [y/n] ";
        my $yn = <STDIN>;
        exit(1) if $yn !~ m/^\s*y/i;
    }
}

mkdir $dir if not -d $dir;


my $S = $job->getScheduler();
my $doSubmit = $job->getSubmitStatus();

my ($scriptDir, $logDir, $outputDir) = ("", "", "");
($scriptDir, $logDir, $outputDir) = $job->createJobStructure() if not ($doSubmit & EFI::Job::DRY_RUN);
saveJobInfo($job);

my @jobs = $job->createJobs();
my $jobId = $job->getJobId();
my $jobNamePrefix = $jobId ? "${jobId}_" : "";
my $serialMode = $job->getSerialMode();
my $serialFile = $serialMode ? $job->getSerialScript() : "";

my $lastJobId = 0;
my %jobIds;
foreach my $jobInfo (@jobs) {
    my $jobName = $jobInfo->{name};
    my $jobFile = $serialMode ? $serialFile : "$scriptDir/$jobName.sh";
    my $jobObj = $jobInfo->{job};
    my @jobDeps = @{$jobInfo->{deps}};

    foreach my $dep (@jobDeps) {
        my $isArray = 0;
        if (ref($dep) eq "HASH") {
            $isArray = $dep->{is_job_array};
            $dep = $dep->{obj};
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
        $jobId = "undefined-failure" if not $jobId;
        chomp $jobId;
        ($jobId) = split(m/\./, $jobId);
    }
    print "$jobId\t$jobName\n" if not $serialMode;
    $jobIds{$jobObj} = $jobId;
    $lastJobId = $jobId;
}

print "Job script created for serial execution at $serialFile\n" if $serialMode;


sub saveJobInfo {
    my $job = shift;
    my $dir = $job->getJobDir();
    my $info = $job->getJobInfo();

    my $file = "$dir/job_parameters.txt";
    open my $fh, ">", $file or die "Unable to save job info to $file: $!\n";
    foreach my $row (@$info) {
        print $fh join("\t", map { defined($_) ? $_ : "" } @$row), "\n";
    }
    close $fh;
}


# Man this getHelp stuff is more complicated than the relationship between Thor and Loki.
sub getHelp {
    my $msg = shift || "";
    my $job = shift;
    my $jobType = shift;

    (my $script = $0) =~ s%^.*/([^/]+)$%$1%;
    $msg = "$msg\n\n" if $msg;
    my $jobTypes = "<" . join("|", EFI::Job::Factory::get_available_types()) . ">";

    my $globalArgs = "\n    " . EFI::Job::getGlobalUsageArgs();
    my $globalUsage = EFI::Job::getGlobalUsage(not $job);
    my $jobUsage = "\n";
    if ($job and $jobType) {
        $jobTypes = $jobType;
        $jobUsage = $job->getUsage();
        $globalArgs = "";
    }

    return "${msg}usage: $script $jobTypes $globalArgs${jobUsage}\nGLOBAL OPTIONS:\n$globalUsage\n";
}


