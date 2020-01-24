
package EFI::Job::EST::Generate::OptionE;

use strict;
use warnings;

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use lib dirname(abs_path(__FILE__)) . "/../../../../";

use parent qw(EFI::Job::EST::Generate::Family);

use Getopt::Long qw(:config pass_through);

use constant JOB_TYPE => "family+e";


sub new {
    my $class = shift;
    my %args = @_;

    my $self = $class->SUPER::new(%args);

    my $parms = {};
    my $result = GetOptions(
        $parms,
        "min-seq-len=i",
        "max-seq-len=i",
        "cd-hit-output-file|cd-hit=s",
    );

    my $conf = validateOptions($parms);

    $self->{conf}->{option_e} = $conf;
    $self->{TYPE} = JOB_TYPE;

    return $self;
}


sub validateOptions {
    my $parms = shift;
    my $self = shift;

    my $conf = {};
    $conf->{min_seq_len} = $parms->{"min-seq-len"} // 0;
    $conf->{max_seq_len} = $parms->{"max-seq-len"} // 0;
    $conf->{cdhit_output_file} = $parms->{"cd-hit-output-file"} // "";

    return $gen;
}


sub getMultiplexJobExtra {
    my $self = shift;
    my $B = shift;
    my $conf = shift;
    my $econf = $self->{conf}->{option_e};

    my $toolPath = $self->getToolPath();

    # Add in CD-HIT attributes to SSN
}


# For overloading
sub getRetrievalScriptSuffix {
    return "b";
}


1;

