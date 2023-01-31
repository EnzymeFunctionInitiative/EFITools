
package EFI::JobManager::Info::PathData::Quantify;

use strict;
use warnings;

use parent qw(EFI::JobManager::Info::PathData);


sub new {
    my $class = shift;
    my %args = @_;
    return $class->SUPER::new(%args);
}


# Input is a quantify ID
sub getJobDir {
    my $self = shift;
    my $jobId = shift;

    my $sql = "SELECT quantify_identify_id FROM quantify WHERE quantify_id = ?";
    my $sth = $self->{dbh}->prepare($sql);
    $sth->execute($jobId);
    my $row = $sth->fetchrow_hashref;
    die "Invalid db row given to path data for $jobId $self->{type}" if not $row;

    my $identifyId = $row->{quantify_identify_id};
    my $identifyPath = $self->getJobDirShared($identifyId);

    return $identifyPath;
}


sub getResultsPath {
    my $self = shift;
    my $jobId = shift;

    # something like /.../identify_id
    my $jobDir = $self->getJobDir($jobId);

    my $identifyPath = $self->getResultsPathShared($jobDir);
    my $quantifyPath = "$identifyPath/quantify-$jobId";

    return $quantifyPath;
}


1;

