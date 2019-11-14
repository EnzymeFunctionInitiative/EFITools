
package EFI::SchedulerApi::Builder::Pbs;

use strict;
use warnings;

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use lib dirname(abs_path(__FILE__)) . "/../../../";

use parent qw(EFI::SchedulerApi::Builder);


sub new {
    my $class = shift;
    my %args = @_;

    return $class->SUPER::new(%args);
}


1;

