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
use EFI::EST::FASTA;


my ($inputConfig, $dbh, $configFile, $seqObj, $accObj, $metaObj, $statsObj) = setupConfig();

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
my $familyObject;

if (exists $inputConfig->{data}) {
    my $famData = new EFI::EST::Family(dbh => $dbh, db_version => $inputConfig->{db_version});
    $famData->configure($inputConfig);
    $famData->retrieveFamilyAccessions();
    $familyIds = $famData->getSequenceIds();
    $familyMetadata = $famData->getMetadata();
    $familyStats = $famData->getStatistics();
    $unirefMap = $famData->getUniRefMapping();
    $familyObject = $famData;
}


my $fastaArgs = EFI::EST::FASTA::loadParameters($inputConfig);
my $fastaData = new EFI::EST::FASTA(dbh => $dbh, config_file_path => $configFile);
$fastaData->configure($fastaArgs);
$fastaData->parseFile();


my $userIds = $fastaData->getSequenceIds();
my $userMetadata = $fastaData->getMetadata();
my $userStats = $fastaData->getStatistics();
my $userSeq = $fastaData->getUnmatchedSequences();

$seqObj->retrieveAndSaveSequences($familyIds, $userIds, $userSeq, $unirefMap); # file path is configured by setupConfig
$accObj->saveSequenceIds($familyIds, $userIds, $unirefMap); # file path is configured by setupConfig
my $mergedMetadata = $metaObj->saveSequenceMetadata($familyMetadata, $userMetadata, $unirefMap);
$statsObj->saveSequenceStatistics($mergedMetadata, $userMetadata, $familyStats, $userStats);

$fastaData->setFamilySunburstIds($familyObject) if $familyObject;
$fastaData->saveSunburstIdsToFile($fastaArgs->{sunburst_tax_output});

