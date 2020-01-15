
package EFI::SchedulerApi::Builder::Serial;

use strict;
use warnings;

use constant TYPE => "serial";
use constant SUBMIT_CMD => "";

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use lib dirname(abs_path(__FILE__)) . "/../../../";

use parent qw(EFI::SchedulerApi::Builder);


sub new {
    my ($class, %args) = @_;

    my $self = $class->SUPER::new(%args);

    $self->{sched_prefix} = "";
    $self->{output_file_seq_num} = "";
    $self->{output_file_seq_num_array} = "";
    $self->{arrayid_var_name} = "";

    return $self;
}


1;

