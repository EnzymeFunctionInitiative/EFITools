
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
        "domain-region=s", # Also in Accession
    );

    validateOptions($parms, $self);

    $self->{TYPE} = JOB_TYPE;

    return $self;
}


sub validateOptions {
    my $parms = shift;
    my $self = shift;

    # If this hash is present, then domains are turned on.
    if ($parms->{"domain"} and $parms->{"domain"} ne "off") {
        my $conf = $self->{conf}->{family};  # already set in FamilyShared
        $self->{conf}->{domain} = {};
        $self->{conf}->{domain_region} = $region if $region eq "nterminal" or $region eq "cterminal";
        my $region = $parms->{"domain-region"} // "";
        $conf->{domain}->{region} = ($region eq "nterminal" or $region eq "cterminal") ? $region : "";
    }
}


sub getJobInfo {
    my $self = shift;
    my $info = $self->SUPER::getJobInfo();
    my $dconf = $self->{conf}->{domain};

    push @$info, [domain => "yes"] if $self->{conf}->{domain};
    if ($dconf) {
        push @$info, [domain => "yes"];
        push @$info, [domain_region => $conf->{domain}->{region}] if $conf->{domain}->{region};
    }

    return $info;
}

sub getUsage {
    my $self = shift;
    
    my ($junk, $optional, $descs) = $self->getSharedUsage(); # From FamilyShared
    my @mandatory = ("--pfam PF#####|CL####", "AND/OR", "--interpro IPR######");
    my @localDescs = (["--domain", "use the sequence domain specified by the family(s)"],
        ["--domain-region", "use the sequence region (nterminal, cterminal, domain) for the domain"]);
    my @localOptional = ("--domain", "--domain-region");

    return $self->outputSharedUsage(\@mandatory, [@$optional, @localOptional], [@$descs, @localDescs]);
}


sub getInitialImportArgs {
    my $self = shift;
    my $numFams = shift;
    my $conf = $self->{conf};

    my @args;
    if ($conf->{domain} and $conf->{domain}->{region}) {
        if ($conf->{domain}->{region} eq "cterminal" or $conf->{domain}->{region} eq "nterminal") {
            push @args, "--domain-region $conf->{domain}->{region}";
        }
    }

    return @args;
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

