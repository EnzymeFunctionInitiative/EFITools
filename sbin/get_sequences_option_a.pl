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
use EFI::EST::BLAST;


my ($familyConfig, $dbh, $configFile, $seqObj, $accObj, $metaObj, $statsObj) = setupConfig();

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

if (exists $familyConfig->{data}) {
    my $famData = new EFI::EST::Family(dbh => $dbh);
    $famData->configure($familyConfig);
    $famData->retrieveFamilyAccessions();
    $familyIds = $famData->getSequenceIds();
    $familyMetadata = $famData->getMetadata();
    $familyStats = $famData->getStatistics();
    $unirefMap = $famData->getUniRefMapping();
}


my %blastArgs = EFI::EST::BLAST::getBLASTCmdLineArgs();
$blastArgs{uniref_version} = $familyConfig->{config}->{uniref_version};
my $blastData = new EFI::EST::BLAST(dbh => $dbh);
$blastData->configure(%blastArgs);
$blastData->parseFile();


my $userIds = $blastData->getSequenceIds();
my $userMetadata = $blastData->getMetadata();
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

