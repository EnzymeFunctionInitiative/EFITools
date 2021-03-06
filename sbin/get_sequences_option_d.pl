#!/bin/env perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Getopt::Long;
use Data::Dumper;

use EFI::Annotations;
use EFI::EST::Setup;
use EFI::EST::Family;
use EFI::EST::Accession;
use EFI::LengthHistogram;


my ($familyConfig, $dbh, $configFile, $seqObj, $accObj, $metaObj, $statsObj, $otherConfig) = setupConfig();

$metaObj->configureSourceTypes(
    EFI::Annotations::FIELD_SEQ_SRC_VALUE_FAMILY,
    EFI::Annotations::FIELD_SEQ_SRC_VALUE_FASTA,
    EFI::Annotations::FIELD_SEQ_SRC_VALUE_BOTH,
);
$statsObj->configureSourceTypes(
    EFI::Annotations::FIELD_SEQ_SRC_VALUE_FAMILY,
    EFI::Annotations::FIELD_SEQ_SRC_VALUE_FASTA,
    EFI::Annotations::FIELD_SEQ_SRC_VALUE_BOTH,
);

my $familyIds = {};
my $familyMetadata = {};
my $familyStats = {};
my $unirefMap = {};
my $familyFullDomainIds = undef; # Used when domain and uniref are enabled

if (exists $familyConfig->{data}) {
    my $famData = new EFI::EST::Family(dbh => $dbh);
    $famData->configure($familyConfig);
    $famData->retrieveFamilyAccessions();
    $familyIds = $famData->getSequenceIds();
    $familyMetadata = $famData->getMetadata();
    $familyStats = $famData->getStatistics();
    $unirefMap = $famData->getUniRefMapping();
    $familyFullDomainIds = $famData->getFullFamilyDomain();
}


my %accessionArgs = EFI::EST::Accession::getAccessionCmdLineArgs();
$accessionArgs{domain_family} = $familyConfig->{config}->{domain_family};
$accessionArgs{domain_region} = $familyConfig->{config}->{domain_region};
$accessionArgs{uniref_version} = $familyConfig->{config}->{uniref_version};
$accessionArgs{exclude_fragments} = $familyConfig->{config}->{exclude_fragments};
my $accessionData = new EFI::EST::Accession(dbh => $dbh, config_file_path => $configFile);
$accessionData->configure(%accessionArgs);
$accessionData->parseFile();


my $userIds = $accessionData->getSequenceIds();
my $userMetadata = $accessionData->getMetadata();
my $userStats = $accessionData->getStatistics();

$seqObj->retrieveAndSaveSequences($familyIds, $userIds, {}, $unirefMap, $familyFullDomainIds); # file path is configured by setupConfig
$accObj->saveSequenceIds($familyIds, $userIds, $unirefMap); # file path is configured by setupConfig
my $mergedMetadata = $metaObj->saveSequenceMetadata($familyMetadata, $userMetadata, $unirefMap);
$statsObj->saveSequenceStatistics($mergedMetadata, $userMetadata, $familyStats, $userStats);

if ($otherConfig->{uniprot_domain_length_file}) {
    my $histo = new EFI::EST::LengthHistogram;
    my $userUnirefIds = $accessionData->getUserUniRefIds(); # This structure includes the UniRef cluster IDs in addition to cluster members.
    my $ids = EFI::EST::IdList::mergeIds($familyFullDomainIds, $userUnirefIds);
    $histo->addData($ids);
    $histo->saveToFile($otherConfig->{uniprot_domain_length_file});
}

if ($accessionArgs{no_match_file}) {
    my $noMatches = $accessionData->getNoMatches();
    open my $fh, ">", $accessionArgs{no_match_file} or warn "Unable to write to $accessionArgs{no_match_file}: $!" and exit(0);
    foreach my $id (@$noMatches) {
        $fh->print("$id\n");
    }
    close $fh;
}


