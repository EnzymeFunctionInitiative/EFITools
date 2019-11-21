
package EFI::Job::GNT;

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


1;

