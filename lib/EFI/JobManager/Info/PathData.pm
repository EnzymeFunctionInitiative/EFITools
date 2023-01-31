
package EFI::JobManager::Info::PathData;

use strict;
use warnings;


sub new {
    my $class = shift;
    my %args = @_;

    my $self = {config => $args{config}, type => $args{type}, dbh => $args{dbh}};
    bless $self, $class;

    return $self;
}


sub getJobDir {
    my $self = shift;
    my $jobId = shift;
    return $self->getJobDirShared($jobId);
}


sub getJobDirShared {
    my $self = shift;
    my $jobId = shift;
    my $rootPath = $self->{config}->getBaseOutputDirPath($self->{type});
    my $jobPath = "$rootPath/$jobId";
    return $jobPath;
}


# This would be the job_dir + results_dir_name
sub getResultsPath {
    my $self = shift;
    my $jobId = shift;
    my $jobPath = $self->getJobDirShared($jobId);
    my $resultsPath = $self->getResultsPathShared($jobPath);
    return $resultsPath;
}


# Returns the job_dir + results_dir_name
sub getResultsPathShared {
    my $self = shift;
    my $jobPath = shift;

    my $resultDir = $self->{config}->getResultsDirName($self->{type});
    my $resultPath = "$jobPath/$resultDir";

    return $resultPath;
}


1;

