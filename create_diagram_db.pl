#!/usr/bin/env perl

BEGIN {
    die "Please load efishared before runing this script" if not $ENV{EFISHARED};
    use lib $ENV{EFISHARED};
}


use strict;

use Getopt::Long;
use FindBin;
use lib $FindBin::Bin . "/lib";


use EFI::GNN::NeighborUtil;
use EFI::GNN::Arrows;
use EFI::Database;
use EFI::GNN::ColorUtil;
use EFI::GNN::AnnotationUtil;
use EFI::IdMapping;
use EFI::IdMapping::Util;


my ($idListFile, $dbFile, $nbSize, $noNeighborFile, $doIdMapping, $configFile, $title, $blastSeq, $jobType);
my $result = GetOptions(
    "id-file=s"             => \$idListFile,
    "db-file=s"             => \$dbFile,

    "no-neighbor-file=s"    => \$noNeighborFile,

    "nb-size=n"             => \$nbSize,
    "blast-seq-file=s"      => \$blastSeq,
    "title=s"               => \$title,
    "job-type=s"            => \$jobType,

    "do-id-mapping"         => \$doIdMapping,
    "config=s"              => \$configFile,
);

my $defaultNbSize = 10;

my $usage = <<USAGE;
usage: $0 -id-file <input_file> -db-file <output_file> [-no-match-file <output_file> -do-id-mapping]
        [-no-neighbor-file <output_file>] [-nb-size <neighborhood_size>] [-config <config_file>]

    -id-file            path to a file containing a list of IDs to retrieve neighborhoods for
    -db-file            path to an output file (sqlite) to put the arrow diagram data in

                        step (e.g. FASTA parse)
    -no-neighbor-file   path to an output file to put a list of IDs that didn't have neighbors or
                        weren't found in the ENA database

    -do-id-mapping      if this flag is present, then the IDs in the input file are reverse mapped
                        to the idmapping table

    -nb-size            number of neighbors on either side to retrieve; defaults to $defaultNbSize
    -config             configuration file to use; if not present looks for EFI_CONFIG env. var
USAGE


die "Invalid -id-file provided: \n$usage" if not -f $idListFile;
die "No -db-file provided: \n$usage" if not $dbFile;
die "No configuration file found in environment or as argument: \n$usage" if not -f $configFile and not exists $ENV{EFICONFIG} and not -f $ENV{EFICONFIG};

$configFile = $ENV{EFICONFIG} if not -f $configFile;

$nbSize = $defaultNbSize if not $nbSize;
$title = "" if not $title;
$blastSeq = "" if not $blastSeq;
$jobType = "" if not $jobType;

my %dbArgs;
$dbArgs{config_file_path} = $configFile;

my $mysqlDb = new EFI::Database(%dbArgs);
my $mysqlDbh = $mysqlDb->getHandle();
my $colorUtil = new EFI::GNN::ColorUtil(dbh => $mysqlDbh);
my $annoUtil = new EFI::GNN::AnnotationUtil(dbh => $mysqlDbh);




my ($inputIdsRef, $evalues) = getInputIds($idListFile);
my @inputIds = @$inputIdsRef;
my @unmatchedIds;
my $idsMapped = {};

if ($doIdMapping) {
    my $mapper = new EFI::IdMapping(%dbArgs);
    my ($ids, $unmatched, $mapData) = reverseMapIds($mapper, @inputIds);
    @inputIds = @$ids;
    $idsMapped = $mapData;
    push @unmatchedIds, @$unmatched;
} else {
    map { push(@{$idsMapped->{$_}}, $_); } @inputIds;
}



my $accessionData = findNeighbors($mysqlDbh, $nbSize, $noNeighborFile, $evalues, @inputIds);

my %arrowMeta;
$arrowMeta{neighborhood_size} = $nbSize;
$arrowMeta{title} = $title;
$arrowMeta{type} = $jobType;
$arrowMeta{sequence} = readBlastSequence($blastSeq) if $blastSeq;

my $resCode = saveData($dbFile, $accessionData, $colorUtil, \%arrowMeta, \@unmatchedIds, $idsMapped);





sub saveData {
    my $dbFile = shift;
    my $data = shift;
    my $colorUtil = shift;
    my $metadata = shift;
    my $unmatched = shift;
    my $idsMapped = shift;

    my $arrowTool = new EFI::GNN::Arrows(color_util => $colorUtil);
    my $clusterCenters = {}; # For the future, we might use this for ordering
    $arrowTool->writeArrowData($data, $clusterCenters, $dbFile, $metadata);
    $arrowTool->writeUnmatchedIds($dbFile, $unmatched);
    $arrowTool->writeMatchedIds($dbFile, $idsMapped);

    return 1;
}


sub findNeighbors {
    my $dbh = shift;
    my $nbSize = shift;
    my $noNbFile = shift;
    my $evalues = shift;
    my @ids = @_;

    my $nbFind = new EFI::GNN::NeighborUtil(dbh => $dbh, use_nnm => 1);

    my $useCircTest = 1;
    my $noneFamily = {};
    my $accessionData = {};

    if ($noNbFile) {
        open NO_NB_WARN, "> $noNbFile" or die "Unable to open no neighbor file $noNbFile: $!";
    } else {
        open NO_NB_WARN, "> /dev/null";
    }
    my $warningFh = \*NO_NB_WARN;

    my $sortKey = 0;
    foreach my $id (@ids) {
        my $localData = {};
        my (undef, undef, undef, undef) = $nbFind->findNeighbors($id, $nbSize, $warningFh, $useCircTest, $noneFamily, $localData);
        $accessionData->{$id} = $localData;
        getAnnotations($dbh, $id, $accessionData, $sortKey, $evalues);
        $sortKey++;
    }

    close NO_NB_WARN;

    return $accessionData;
}


sub getAnnotations {
    my $dbh = shift;
    my $accession = shift;
    my $accessionData = shift;
    my $sortKey = shift;
    my $evalues = shift;

    my ($organism, $taxId, $annoStatus, $desc, $familyDesc) = $annoUtil->getAnnotations($accession, $accessionData->{$accession}->{attributes}->{family});
    $accessionData->{$accession}->{attributes}->{sort_order} = $sortKey;
    $accessionData->{$accession}->{attributes}->{organism} = $organism;
    $accessionData->{$accession}->{attributes}->{taxon_id} = $taxId;
    $accessionData->{$accession}->{attributes}->{anno_status} = $annoStatus;
    $accessionData->{$accession}->{attributes}->{desc} = $desc;
    $accessionData->{$accession}->{attributes}->{family_desc} = $familyDesc;
    $accessionData->{$accession}->{attributes}->{cluster_num} = 1;
    $accessionData->{$accession}->{attributes}->{evalue} = $evalues->{$accession}
        if exists $evalues->{$accession} and $evalues->{$accession};

    foreach my $nbObj (@{ $accessionData->{$accession}->{neighbors} }) {
        my ($nbOrganism, $nbTaxId, $nbAnnoStatus, $nbDesc, $nbFamilyDesc) =
            $annoUtil->getAnnotations($nbObj->{accession}, $nbObj->{family});
        $nbObj->{taxon_id} = $nbTaxId;
        $nbObj->{anno_status} = $nbAnnoStatus;
        $nbObj->{desc} = $nbDesc;
        $nbObj->{family_desc} = $nbFamilyDesc;
    }
}


sub reverseMapIds {
    my $mapper = shift;
    my @inputIds = @_;

    my @ids;
    my @unmatched;
    my %mapData;

    foreach my $id (@inputIds) {
        my $idType = check_id_type($id);
        next if ($idType eq EFI::IdMapping::Util::UNKNOWN);

        if ($idType ne EFI::IdMapping::Util::UNIPROT) {
            my ($uniprotId, $noMatch, $revMap) = $mapper->reverseLookup($idType, $id);
            if (defined $uniprotId and $#$uniprotId >= 0) {
                foreach my $upId (@$uniprotId) {
                    push @ids, $upId;
                    push @{$mapData{$upId}}, @{$revMap->{$upId}};
                }
                push @ids, @$uniprotId;
            }
            push @unmatched, @$noMatch;
        } else {
            $id =~ s/\..+$//;
            push @ids, $id;
            push @{$mapData{$id}}, $id;
        }
    }

    return \@ids, \@unmatched, \%mapData;
}


sub getUnmatchedIds {
    my $noMatchFile = shift;

    my @ids;

    open NOMATCH, $noMatchFile;
    while (<NOMATCH>) {
        chomp;
        push @ids, $_;
    }
    close NOMATCH;

    return @ids;
}



sub getInputIds {
    my $file = shift;

    my @ids;
    my %evalues;

    open FILE, $file or die "Unable to open $file for reading: $!";
    while (<FILE>) {
        s/[\r\n]+$//;
        my @lineIds = split(/,+/, $_);
        foreach my $idLine (@lineIds) {
            my ($id, $evalue);
            if ($idLine =~ m/\|/) {
                ($id, $evalue) = split(m/\|/, $idLine);
                $evalues{$id} = $evalue;
            } else {
                $id = $idLine;
            }
            push @ids, $id;
        }
    }
    close FILE;

    return (\@ids, \%evalues);
}


sub readBlastSequence {
    my $blastSeqFile = shift;

    return "" if not -f $blastSeqFile;

    my $seq = "";

    open SEQ, $blastSeqFile or die "Unable to open BLAST sequence file for reading: $!";
    while (<SEQ>) {
        $seq .= $_;
    }
    close SEQ;

    return $seq;
}


