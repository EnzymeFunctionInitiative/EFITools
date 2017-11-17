#!/usr/bin/env perl

BEGIN {
    die "Please load efishared before runing this script" if not $ENV{EFISHARED};
    use lib $ENV{EFISHARED};
}


use strict;

use Getopt::Long;
use EFI::GNN::NeighborUtil;
use EFI::GNN::Arrows;
use EFI::Database;
use EFI::GNN::ColorUtil;
use EFI::GNN::AnnotationUtil;


my ($idListFile, $dbFile, $nbSize, $noMatchFile, $noNeighborFile, $doIdMapping, $configFile);
my $result = GetOptions(
    "id-file=s"             => \$idListFile,
    "db-file=s"             => \$dbFile,
    "no-match-file=s"       => \$noMatchFile,
    "no-neighbor-file=s"    => \$noNeighborFile,
    "nb-size=n"             => \$nbSize,
    "do-id-mapping"         => \$doIdMapping,
    "config=s"              => \$configFile,
);

my $defaultNbSize = 10;

my $usage = <<USAGE;
usage: $0 -id-file <input_file> -db-file <output_file> [-no-match-file <output_file> -do-id-mapping]
        [-nb-size <neighborhood_size>] [-config <config_file>]
    -id-file            path to a file containing a list of IDs to retrieve neighborhoods for
    -db-file            path to an output file (sqlite) to put the arrow diagram data in
    -no-match-file      path to an output file to put a list of IDs that weren't matched
    -no-neighbor-file   path to an output file to put a list of IDs that didn't have neighbors or
                        weren't found in the ENA database
    -do-id-mapping      if this flag is present, then the IDs in the input file are reverse mapped
                        to the idmapping table
    -nb-size            number of neighbors on either side to retrieve; defaults to $defaultNbSize
    -config             configuration file to use; if not present looks for EFI_CONFIG env. var
USAGE


die "No -id-file provided: \n$usage" if not -f $idListFile;
die "No -db-file provided: \n$usage" if not $dbFile;

$nbSize = $defaultNbSize if not $nbSize;

my %dbArgs;
$dbArgs{config_file_path} = $configFile if $configFile and -f $configFile;

my $mysqlDb = new EFI::Database(%dbArgs);
my $mysqlDbh = $mysqlDb->getHandle();
my $colorUtil = new EFI::GNN::ColorUtil(dbh => $mysqlDbh);
my $annoUtil = new EFI::GNN::AnnotationUtil(dbh => $mysqlDbh);




my @inputIds = getInputIds($idListFile);

if ($doIdMapping) {
    @inputIds = reverseMapIds($mysqlDbh, $noMatchFile, @inputIds);
}

my $accessionData = findNeighbors($mysqlDbh, $nbSize, $noNeighborFile, @inputIds);

my $resCode = saveData($dbFile, $accessionData, $colorUtil);






sub saveData {
    my $dbFile = shift;
    my $data = shift;
    my $colorUtil = shift;

    my $arrowTool = new EFI::GNN::Arrows(color_util => $colorUtil);
    my $clusterCenters = {}; # For the future, we might use this for ordering
    $arrowTool->writeArrowData($data, $clusterCenters, $dbFile);

    return 1;
}


sub findNeighbors {
    my $dbh = shift;
    my $nbSize = shift;
    my $noNbFile = shift;
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
        my (undef, undef, undef, undef) = $nbFind->findNeighbors($id, $nbSize, $warningFh, $useCircTest, $noneFamily, $accessionData);
        getAnnotations($dbh, $id, $accessionData, $sortKey);
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

    my ($organism, $taxId, $annoStatus, $desc, $familyDesc) = $annoUtil->getAnnotations($accession, $accessionData->{$accession}->{attributes}->{family});
    $accessionData->{$accession}->{attributes}->{sort_order} = $sortKey;
    $accessionData->{$accession}->{attributes}->{organism} = $organism;
    $accessionData->{$accession}->{attributes}->{taxon_id} = $taxId;
    $accessionData->{$accession}->{attributes}->{anno_status} = $annoStatus;
    $accessionData->{$accession}->{attributes}->{desc} = $desc;
    $accessionData->{$accession}->{attributes}->{family_desc} = $familyDesc;
    $accessionData->{$accession}->{attributes}->{cluster_num} = 1;

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
    my $dbh = shift;
    my $noMatchFile = shift;
    my @ids = @_;

    #TODO: implement the reverse mapping

    return @ids;
}


sub getInputIds {
    my $file = shift;

    my @ids;

    open FILE, $file or die "Unable to open $file for reading: $!";
    while (<FILE>) {
        chomp;
        push @ids, $_;
    }
    close FILE;

    return @ids;
}


