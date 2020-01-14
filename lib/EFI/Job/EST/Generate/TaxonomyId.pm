
package EFI::Job::EST::Generate::TaxonomyId;

use strict;
use warnings;

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use lib dirname(abs_path(__FILE__)) . "/../../../../";

use parent qw(EFI::Job::EST::Generate);

use Getopt::Long qw(:config pass_through);

use constant JOB_TYPE => "taxid";


sub new {
    my $class = shift;
    my %args = @_;

    my $self = $class->SUPER::new(%args);

    my $parms = {};
    my $result = GetOptions(
        $parms,
        "taxonomy-id|taxid=s",
    );

    my ($conf, $errors) = validateOptions($parms, $self);

    $self->{conf}->{taxonomy} = $conf;
    $self->{TYPE} = JOB_TYPE;

    push @{$self->{startup_errors}}, @$errors;

    return $self;
}


sub validateOptions {
    my $parms = shift;
    my $self = shift;

    my @errors;

    my $conf = {};
    $conf->{id} = $parms->{"taxonomy-id"} // 0;

    push @errors, "Invalid --taxonomy-id argument" if not $conf->{id};

    return $conf, \@errors;
}


sub getInitialImportJob {
    my $self = shift;
    my $S = shift;
    my $conf = $self->{conf}->{generate};

    $B->addAction("module load oldapps") if $oldapps;
    $B->addAction("module load $dbMod");
    $B->addAction("module load $toolMod");
    $B->addAction("cd $outputDir");
    $B->addAction("$toolPath/get_sequences_by_tax_id.pl -fasta allsequences.fa -struct $structFile -taxid $taxid -config=$configFile");
    if ($fastaFile=~/\w+/) {
        $fastaFile=~s/^-userfasta //;
        $B->addAction("cat $fastaFile >> allsequences.fa");
    }
    #TODO: handle the header file for this case....
    if ($metadataFile=~/\w+/) {
        $metadataFile=~s/^-userdat //;
        $B->addAction("cat $metadataFile >> $structFile");
    }
    $B->jobName("${jobNamePrefix}initial_import");
    $B->renderToFile("$scriptDir/initial_import.sh");

    my $importjob = $S->submit("$scriptDir/initial_import.sh");
    chomp $importjob;

    print "import job is:\n $importjob\n";
    ($prevJobId) = split /\./, $importjob;
}


1;

