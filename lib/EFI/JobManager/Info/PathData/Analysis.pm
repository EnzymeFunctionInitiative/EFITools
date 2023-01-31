
package EFI::JobManager::Info::PathData::Analysis;

use strict;
use warnings;

use parent qw(EFI::JobManager::Info::PathData);

use JSON;


sub new {
    my $class = shift;
    my %args = @_;
    return $class->SUPER::new(%args);
}


sub getJobDir {
    my $self = shift;
    my $aid = shift;
    my ($generateId, $params) = $self->getJobDirInfo($aid);
    my $generatePath = $self->getJobDirShared($generateId);
    # returns /.../generate_id
    return $generatePath;
}


sub getJobDirInfo {
    my $self = shift;
    my $aid = shift;

    my $sql = "SELECT * FROM analysis WHERE analysis_id = ?";
    my $sth = $self->{dbh}->prepare($sql);
    $sth->execute($aid);
    my $row = $sth->fetchrow_hashref;
    die "Invalid db row given to path data for $aid $self->{type}" if not $row;

    my $generateId = $row->{analysis_generate_id};
    my $params = decode_json($row->{analysis_params});

    return ($generateId, $params, $row);
}


sub getResultsPath {
    my $self = shift;
    my $aid = shift;
    my $isSource = shift || 0;
    # If $isSource is true, then this function is being executed to get the source of an SSN (for input to GNT, for example).
    # If not, then it is a destination for a new analysis job.

    my ($generateId, $params, $dbRow) = $self->getJobDirInfo($aid);

    # something like /.../generate_id
    my $jobDir = $self->getJobDirShared($generateId);

    # something like /.../generate_id/output
    my $generatePath = $self->getResultsPathShared($jobDir);

    # Actual results location
    my $resultsPath = "$generatePath/$aid";

    print "$aid $resultsPath $isSource\n";
    if ($isSource and not -d $resultsPath) {
        my $aDir = $self->makeAnalysisDirName($dbRow, $params);
        $resultsPath = "$generatePath/$aDir";
    }

    return $resultsPath;
}


sub makeAnalysisDirName {
    my $self = shift;
    my $dbRow = shift;
    my $params = shift;

    my $taxSearch = $params->{tax_search_hash} ? "-" . $params->{tax_search_hash} : "";
    my $ncSuffix = $params->{compute_nc} ? "-nc" : "";
    my $nfSuffix = $params->{remove_fragments} ? "-nf" : "";
    my $aDir = $dbRow->{analysis_filter} . "-" .
        $dbRow->{analysis_evalue} . "-" .
        $dbRow->{analysis_min_length} . "-" .
        $dbRow->{analysis_max_length} . $taxSearch . $ncSuffix . $nfSuffix;

    return $aDir;
}


1;

