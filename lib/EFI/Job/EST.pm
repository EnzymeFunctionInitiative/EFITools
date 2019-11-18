
package EFI::Job::EST;

use strict;
use warnings;

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use lib dirname(abs_path(__FILE__)) . "/../../";

use parent qw(EFI::Job);


sub new {
    my $class = shift;
    my %args = @_;

    return $class->SUPER::new(%args);
}


sub createJobStructure {
    my $self = shift;
    my $dir = $self->{conf}->{job_dir};
    my $outputDir = "$dir/output";
    mkdir $outputDir;
    my $scriptDir = "$dir/scripts";
    mkdir $scriptDir;
    my $logDir = "$dir/log";
    mkdir $logDir;
    return ($scriptDir, $logDir, $outputDir);
}


1;

