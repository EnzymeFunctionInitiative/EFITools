
package EFI::EST::Setup;

use strict;
use warnings;

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use lib dirname(abs_path(__FILE__)) . "/../..";
use lib dirname(abs_path(__FILE__)) . "/../../../lib";

use EFI::Database;
use EFI::EST::Sequence;
use EFI::EST::Metadata;
use EFI::EST::IdList;
use EFI::EST::Statistics;
use EFI::EST::Family;

use EFI::Options;


use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

$VERSION     = 1.00;
@ISA         = qw(Exporter);
@EXPORT      = qw(setupConfig);
@EXPORT_OK   = qw();


sub setupConfig {
    my $optionConfigType = shift || "getopt";
    my $optionConfigData = shift || {};

    my %options = (
        "config" => "s",
        "accession-output" => "s",
        "out|sequence-output" => "s",
        "min-seq-len" => "i",
        "max-seq-len" => "i",
        "seq-retr-batch-size" => "i",
        "meta-file|metadata-output" => "s",
        "seq-count-file|seq-count-output" => "s",
        "uniprot-dom-len-output" => "s",
        "uniref-dom-len-output" => "s",
    );
    my $optionParser = new EFI::Options(type => $optionConfigType, config => $optionConfigData);
    my $parms = $optionParser->getOptions(\%options);
    my $configFile = $parms->{config} // "";
    
    if ((not $configFile or not -f $configFile) and exists $ENV{EFI_CONFIG} and -f $ENV{EFI_CONFIG}) {
        $configFile = $ENV{EFI_CONFIG};
    }

    my $pwd = $ENV{PWD};
    my $accOutput = $parms->{"accession-output"} // "$pwd/getseq.default.accession";
    my $seqOutput = $parms->{"out"} // "$pwd/getseq.default.fasta";
    my $metaOutput = $parms->{"meta-file"} // "$pwd/getseq.default.metadata";
    my $statsOutput = $parms->{"seq-count-file"} // "$pwd/getseq.default.stats";
    
    unlink($accOutput);
    unlink($seqOutput);
    unlink($metaOutput);
    unlink($statsOutput);
    
    die "Invalid configuration file provided" if not $configFile;
    #die "Require output sequence ID file" if not $accOutput;
    #die "Require output FASTA sequence file" if not $seqOutput;
    #die "Require output sequence metadata file" if not $metaOutput;
    #die "Require output sequence stats file" if not $statsOutput;
    
    my $config = EFI::Config::parseConfigFile($configFile);
    my $db = new EFI::Database(config_file_path => $config);
    my $dbh = $db->getHandle();
    
    my $familyConfig = EFI::EST::Family::loadFamilyParameters($optionParser);

    my $fastaDb = "$ENV{EFI_DB_DIR}/$ENV{EFI_UNIPROT_DB}";

    my $defaultBatchSize = 1000;
    my $defaultMaxSeqLen = 1000000;
    my $batchSize = $parms->{"seq-retr-batch-size"} // $defaultBatchSize;
    my $minSeqLen = $parms->{"min-seq-len"} // 0;
    my $maxSeqLen = $parms->{"max-seq-len"} // $defaultMaxSeqLen;

    my %seqArgs = (
        seq_output_file => $seqOutput,
        use_domain => $familyConfig->{config}->{use_domain} ? 1 : 0,
        min_seq_len => $minSeqLen,
        max_seq_len => $maxSeqLen,
        fasta_database => $fastaDb,
        batch_size => $batchSize,
        use_user_domain => ($familyConfig->{config}->{use_domain} and $familyConfig->{config}->{domain_family}) ? 1 : 0,
    );
    my $unirefDomLenOutput = $parms->{"uniref-dom-len-output"} // "";
    my $uniprotDomLenOutput = $parms->{"uniprot-dom-len-output"} // "";
    $seqArgs{domain_length_file} = $unirefDomLenOutput if $unirefDomLenOutput;
    $seqArgs{domain_length_file} = $uniprotDomLenOutput if $uniprotDomLenOutput and not $unirefDomLenOutput;

    my %accArgs = (
        seq_id_output_file => $accOutput,
    );

    my %metaArgs = (
        meta_output_file => $metaOutput,
    );

    my %statsArgs = (
        stats_output_file => $statsOutput,
    );

    my %otherConfig;
    $otherConfig{uniprot_domain_length_file} = $uniprotDomLenOutput if $uniprotDomLenOutput and $unirefDomLenOutput;
    $otherConfig{db_version} = $db->getVersion($dbh);

    my $accObj = new EFI::EST::IdList(%accArgs);
    my $seqObj = new EFI::EST::Sequence(%seqArgs);
    my $metaObj = new EFI::EST::Metadata(%metaArgs);
    my $statsObj = new EFI::EST::Statistics(%statsArgs);

    return ($familyConfig, $dbh, $configFile, $seqObj, $accObj, $metaObj, $statsObj, \%otherConfig);
}


1;

