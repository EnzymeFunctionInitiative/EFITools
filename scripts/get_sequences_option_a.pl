#!/bin/env perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";

use EFI::Annotations;
use EFI::EST::Setup;
use EFI::EST::Family;
use EFI::EST::BLAST;


my ($inputConfig, $dbh, $configFile, $seqObj, $accObj, $metaObj, $statsObj) = setupConfig();

$metaObj->configureSourceTypes(
    EFI::Annotations::FIELD_SEQ_SRC_VALUE_FAMILY,
    EFI::Annotations::FIELD_SEQ_SRC_VALUE_BLASTHIT,
    EFI::Annotations::FIELD_SEQ_SRC_VALUE_BLASTHIT_FAMILY,
);
$statsObj->configureSourceTypes(
    EFI::Annotations::FIELD_SEQ_SRC_VALUE_FAMILY,
    EFI::Annotations::FIELD_SEQ_SRC_VALUE_BLASTHIT,
    EFI::Annotations::FIELD_SEQ_SRC_VALUE_BLASTHIT_FAMILY,
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



my $blastArgs = EFI::EST::BLAST::loadParameters($inputConfig);
my $blastData = new EFI::EST::BLAST(dbh => $dbh);
$blastData->configure($blastArgs);
$blastData->parseFile();

my $userIds = $blastData->getSequenceIds();
my $userMetadata = $blastData->getMetadata(); # Looks up UniRef IDs if using UniRef, so may take some time.
my $userStats = $blastData->getStatistics();
my $userSeq = $blastData->getQuerySequence();


my $inputIdSource = {};
$inputIdSource->{$EFI::EST::BLAST::INPUT_SEQ_ID} = $EFI::EST::BLAST::INPUT_SEQ_TYPE;


#map { print "B\t$_\n"; } keys %$userIds;
#map { print "F\t$_\n"; } keys %$familyIds;
$seqObj->retrieveAndSaveSequences($familyIds, $userIds, $userSeq, $unirefMap); # file path is configured by setupConfig
$accObj->saveSequenceIds($familyIds, $userIds, $unirefMap); # file path is configured by setupConfig
my $mergedMetadata = $metaObj->saveSequenceMetadata($familyMetadata, $userMetadata, $unirefMap, $inputIdSource);
$statsObj->saveSequenceStatistics($mergedMetadata, $userMetadata, $familyStats, $userStats);

$blastData->setFamilySunburstIds($familyObject) if $familyObject;
$blastData->saveSunburstIdsToFile($blastArgs->{sunburst_tax_output});

