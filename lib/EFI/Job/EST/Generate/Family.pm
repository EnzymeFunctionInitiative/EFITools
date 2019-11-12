
package EFI::Job::EST::Generate::Family;

use strict;
use warnings;

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use lib dirname(abs_path(__FILE__)) . "/../../../../";

use parent qw(EFI::Job::EST::Generate::FamilyShared);

use Getopt::Long qw(:config pass_through);

use constant JOB_TYPE => "family";


sub new {
    my $class = shift;
    my %args = @_;

    my $self = $class->SUPER::new(%args);

    my $parms = {};
    my $result = GetOptions(
        $parms,
        "domain:s", # Also in Accession
    );

    validateOptions($parms, $self);

    return $self;
}


sub validateOptions {
    my $parms = shift;
    my $self = shift;

    my $conf = $self->{conf}->{family};  # already set in FamilyShared
    $self->{conf}->{domain} = {} if lc($parms->{"domain"} // "off") eq "on"; # If this hash is present, then domains are turned on.
}


sub getInitialImportArgs {
    my $self = shift;
    my @args;
    return @args;
}


# For overloading
sub getRetrievalScriptSuffix {
    return "b";
}


1;

