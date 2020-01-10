
package EFI::Job::EST::Generate::Accession;

use strict;
use warnings;

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use lib dirname(abs_path(__FILE__)) . "/../../../../";

use parent qw(EFI::Job::EST::Generate::FamilyShared);

use Getopt::Long qw(:config pass_through);

use EFI::Config;

use constant JOB_TYPE => "accession";


sub new {
    my $class = shift;
    my %args = @_;

    my $self = $class->SUPER::new(%args);

    my $parms = {};
    my $result = GetOptions(
        $parms,
        #uniref-version is also used from the family structure
        "domain:s", # Also in Family
        "domain-family=s",
        "domain-region=s",
        "accession-file|useraccession=s",
        "no-match-file=s",
    );

    my ($conf, $errors) = validateOptions($parms, $self);

    $self->{conf}->{accession} = $conf->{accession};
    $self->{conf}->{domain} = $conf->{domain} if $conf->{domain};

    push @{$self->{startup_errors}}, @$errors;

    return $self;
}


sub validateOptions {
    my $parms = shift;
    my $self = shift;

    my @errors;

    my $conf = {accession => {}};
    if (defined $parms->{domain} and $parms->{domain} ne "off") {
        $conf->{domain}->{family} = $parms->{"domain-family"} // "";
        $conf->{domain}->{region} = $parms->{"domain-region"} // "";
    }
    my $file = $parms->{"accession-file"} // "";
    $conf->{accession}->{no_match_file} = $parms->{"no-match-file"} // EFI::Config::NO_ACCESSION_MATCHES_FILENAME;

    $conf->{accession}->{file_is_zipped} = $file =~ m/\.zip$/i;
    $file =~ s/\.zip$//i;
    $conf->{accession}->{accession_file} = $file;

    push @errors, "No --accession-file parameter provided." if not -f $conf->{accession}->{accession_file};

    return $conf, \@errors;
}


sub getJobInfo {
    my $self = shift;
    my $info = $self->SUPER::getJobInfo();
    my $conf = $self->{conf}->{accession};
    my $dconf = $self->{conf}->{domain};

    push @$info, [accession_file => $conf->{accession_file}];
    if ($dconf) {
        push @$info, [domain => "yes"];
        push @$info, [domain_family => $conf->{domain_family}] if $conf->{domain_family};
        push @$info, [domain_region => $conf->{domain_region}] if $conf->{domain_region};
    }

    return $info;
}

sub getUsage {
    my $self = shift;
    
    # All family args are optional
    my ($famMandatory, $famOptional, $famDescs) = $self->getSharedUsage(); # From FamilyShared
    my @mandatory = ("--accession-file <ID_FILE_PATH>");
    my @optional = (
        "--no-match-file <NO_MATCHING_ID_FILE_PATH>",
        #"--domain", "--domain-family FAMILY", "--domain-region nterminal|cterminal",
    );
    my @descs = (
        ["--accession-file", "file containing list of sequence IDs, UniProt or NCBI RefSeq IDs are supported"],
        #["--domain", "use the domain given by the family specified by --domain-family instead of the full-length sequence"],
        #["--domain-family", "family to obtain domain from"],
        #["--domain-region", "if specified, the N-terminal or N-terminal to the family domain is used instead of the domain itself"],
    );

    return $self->outputSharedUsage(\@mandatory, [@optional, @$famMandatory, @$famOptional], [@descs, @$famDescs]);
}


sub getInitialImportArgs {
    my $self = shift;
    my $numFams = shift;
    my $conf = $self->{conf};

    my $outputDir = $self->getOutputDir();

    my @args;
    if ($conf->{domain} and $conf->{domain}->{family}) {
        push @args, "--domain-family $conf->{domain}->{family}";
        if ($conf->{domain}->{region} eq "cterminal" or $conf->{domain}->{region} eq "nterminal") {
            push @args, "--domain-region $conf->{domain}->{region}";
        }
    }

    push @args, "--accession-file $conf->{accession}->{accession_file}";

    my $noMatchFile = $conf->{accession}->{no_match_file};
    $noMatchFile = "$outputDir/$noMatchFile" if $noMatchFile !~ m/^[\/~]/;
    push @args, "--no-match-file $noMatchFile";

    my $unirefVersion = $self->getUniRefVersion();
    push @args, "--uniref-version $unirefVersion" if $unirefVersion and not $numFams; # Don't add this arg if the family is included, because the arg is already included in the family section

    return @args;
}


# For overloading
sub getRetrievalScriptSuffix {
    return "d";
}


sub addInitialImportFileActions {
    my $self = shift;
    my $B = shift;

    my $file = $self->{conf}->{accession}->{accession_file};
    $B->addAction("unzip -p $file.zip > $file") if $self->{conf}->{accession}->{file_is_zipped};
    #$B->addAction("dos2unix -q $file");
    #$B->addAction("mac2unix -q $file");
}


1;

