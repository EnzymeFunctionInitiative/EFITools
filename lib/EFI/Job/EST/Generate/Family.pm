
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

    $args{family_mandatory} = 1;
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


sub getJobInfo {
    my $self = shift;
    my $info = $self->SUPER::getJobInfo();

    push @$info, [domain => "yes"] if $self->{conf}->{domain};

    return $info;
}

sub getUsage {
    my $self = shift;
    
    my ($junk, $optional, $descs) = $self->getSharedUsage(); # From FamilyShared
    my @mandatory = ("--pfam PF#####|CL####", "AND/OR", "--interpro IPR######");
    my @localDescs = (["--domain", "use the sequence domain specified by the family(s)"]);
    my @localOptional = ("--domain");

    return $self->outputSharedUsage(\@mandatory, [@$optional, @localOptional], [@$descs, @localDescs]);
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

