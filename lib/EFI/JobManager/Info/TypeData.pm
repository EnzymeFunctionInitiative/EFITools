
package EFI::JobManager::Info::TypeData;

use strict;
use warnings;


sub new {
    my $class = shift;
    my %args = @_;

    my $self = {path_info => $args{path_info}};
    bless $self, $class;

    return $self;
}


sub getFinishFile {
    my $self = shift;
    my $jobId = shift;
    my $row = shift;

    my $subDir = $self->{path_info}->getResultsPath($jobId, $row);
    my $finishFile = "$subDir/$self->{finish_file}";
    return $finishFile;
}


sub getType {
    my $self = shift;
    return $self->{type};
}


sub getTableName {
    my $self = shift;
    return $self->{table};
}


1;

