
package EFI::Job::EST::Generate::FASTA;

use strict;
use warnings;

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use lib dirname(abs_path(__FILE__)) . "/../../../../";

use parent qw(EFI::Job::EST::Generate::FamilyShared);

use Getopt::Long qw(:config pass_through);

use EFI::Config;

use constant JOB_TYPE => "fasta";


sub new {
    my $class = shift;
    my %args = @_;

    my $self = $class->SUPER::new(%args);

    my $parms = {};
    my $result = GetOptions(
        $parms,
        "fasta-file|userfasta=s",
        "use-fasta-headers",
    );

    my ($conf, $errors) = validateOptions($parms, $self);

    $self->{conf}->{fasta} = $conf;
    $self->{TYPE} = JOB_TYPE;

    push @{$self->{startup_errors}}, @$errors;

    return $self;
}


sub validateOptions {
    my $parms = shift;
    my $self = shift;

    my @errors;

    my $conf = {};

    my $file = $parms->{"fasta-file"} // "";
    $conf->{use_headers} = $parms->{"use-fasta-headers"} ? 1 : 0;

    $conf->{zipped_file} = $file if $file =~ m/\.zip$/i;
    $file =~ s/\.zip$//i;
    $conf->{fasta_file} = abs_path($file);
    $conf->{no_match_file} = $parms->{"no-match-file"} // EFI::Config::NO_ACCESSION_MATCHES_FILENAME;

    push @errors, "No --fasta-file parameter provided." if not -f $conf->{fasta_file};

    return $conf, \@errors;
}


sub getJobInfo {
    my $self = shift;
    my $info = $self->SUPER::getJobInfo();
    my $conf = $self->{conf}->{fasta};

    push @$info, [fasta_file => $conf->{fasta_file}];
    push @$info, [use_fasta_headers => $conf->{use_fasta_headers}];

    return $info;
}

sub getUsage {
    my $self = shift;
    
    # All family args are optional
    my ($famMandatory, $famOptional, $famDescs) = $self->getSharedUsage(); # From FamilyShared
    my @mandatory = ("--fasta-file <FASTA_FILE_PATH>");
    my @optional = ("--use-fasta-headers");
    my @descs = (
        ["--fasta-file", "file containing FASTA-format sequences with FASTA headers"],
        ["--use-fasta-headers", "parse FASTA headers for UniProt or RefSeq IDs"],
    );

    return $self->outputSharedUsage(\@mandatory, [@optional, @$famMandatory, @$famOptional], [@descs, @$famDescs]);
}


sub getInitialImportArgs {
    my $self = shift;
    my $numFams = shift;
    my $conf = $self->{conf}->{fasta};

    my $outputDir = $self->getOutputDir();

    my @args;
    push @args, "--fasta-file $conf->{fasta_file}";
    push @args, "--use-fasta-headers" if $conf->{use_headers};

    my $noMatchFile = $conf->{no_match_file};
    $noMatchFile = "$outputDir/$noMatchFile" if $noMatchFile !~ m/^[\/~]/;
    push @args, "--no-match-file $noMatchFile";

    return @args;
}


# For overloading
sub getRetrievalScriptSuffix {
    return "c";
}


sub addInitialImportFileActions {
    my $self = shift;
    my $B = shift;

    my $file = $self->{conf}->{fasta}->{fasta_file};
    $B->addAction("unzip -p $self->{conf}->{fasta}->{zipped_file} > $file") if $self->{conf}->{fasta}->{zipped_file};
    #$B->addAction("dos2unix -q $file");
    #$B->addAction("mac2unix -q $file");
}


1;

