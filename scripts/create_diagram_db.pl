#!/usr/bin/env perl

use strict;
use warnings;

use Getopt::Long;
use FindBin;
use Data::Dumper;
use Time::HiRes qw(time);

use lib $FindBin::Bin . "/../lib";

use EFI::GNN::NeighborUtil;
use EFI::GNN::Arrows;
use EFI::Database;
use EFI::Annotations;
use EFI::GNN::ColorUtil;
use EFI::GNN::AnnotationUtil;
use EFI::IdMapping;
use EFI::IdMapping::Util;


my ($idListFile, $dbFile, $nbSize, $noNeighborFile, $doIdMapping, $configFile, $title, $blastSeq, $jobType, $uniRefVersion, $clusterMapFile, $debugLimit);
my $result = GetOptions(
    "id-file=s"             => \$idListFile,
    "db-file=s"             => \$dbFile,

    "no-neighbor-file=s"    => \$noNeighborFile,

    "nb-size=n"             => \$nbSize,
    "blast-seq-file=s"      => \$blastSeq,
    "title=s"               => \$title,
    "job-type=s"            => \$jobType,

    "do-id-mapping"         => \$doIdMapping,
    "uniref=i"              => \$uniRefVersion,
    "config=s"              => \$configFile,

    "debug-limit=i"         => \$debugLimit,

    "cluster-map=s"         => \$clusterMapFile,
);

my $defaultNbSize = 10;

my $usage = <<USAGE;
usage: $0 -id-file <input_file> -db-file <output_file> [-no-match-file <output_file> -do-id-mapping]
        [-no-neighbor-file <output_file>] [-nb-size <neighborhood_size>] [-config <config_file>]

    --id-file           path to a file containing a list of IDs to retrieve neighborhoods for
    --db-file           path to an output file (sqlite) to put the arrow diagram data in

                        step (e.g. FASTA parse)
    --no-neighbor-file  path to an output file to put a list of IDs that didn't have neighbors or
                        weren't found in the ENA database

    --do-id-mapping     if this flag is present, then the IDs in the input file are reverse mapped
                        to the idmapping table
    --uniref            if this flag is present, collect the number of IDs in each UniRef cluster
                        and save it for display on the GND viewer later

    --nb-size           number of neighbors on either side to retrieve; defaults to $defaultNbSize
    --config            configuration file to use; if not present looks for EFI_CONFIG env. var
USAGE


die "Invalid --id-file provided: \n$usage" if not $idListFile or not -f $idListFile;
die "No --db-file provided: \n$usage" if not $dbFile;
die "No configuration file found in environment or as argument: \n$usage" if (not $configFile or not -f $configFile) and not exists $ENV{EFI_CONFIG} and not -f $ENV{EFI_CONFIG};

$configFile = $ENV{EFI_CONFIG} if not $configFile or not -f $configFile;

$nbSize = $defaultNbSize if not $nbSize;
$title = "" if not $title;
$blastSeq = "" if not $blastSeq;
$jobType = "" if not $jobType;

my %dbArgs;
$dbArgs{config_file_path} = $configFile;

my $mysqlDb = new EFI::Database(%dbArgs);
my $mysqlDbh = $mysqlDb->getHandle();
my $colorUtil = new EFI::GNN::ColorUtil(dbh => $mysqlDbh);
my $annoUtil = new EFI::GNN::AnnotationUtil(dbh => $mysqlDbh, efi_anno => new EFI::Annotations);

my $clusterMap = {}; # Map UniProt ID to cluster number
my $clusterNumMap = {}; # Map cluster number, which is a numeric value assigned when reading, to cluster ID 
if ($clusterMapFile and -f $clusterMapFile) {
    # Tabular file, first column is cluster number/ID and second column is accession ID
    ($clusterMap, $clusterNumMap) = parseClusterMapFile($clusterMapFile);
}




my ($inputIdsRef, $evalues, $uniRef50, $uniRef90) = getInputIds($idListFile);
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


my $accessionData = findNeighbors($mysqlDbh, $nbSize, $noNeighborFile, $evalues, \@inputIds, $uniRef50, $uniRef90, $debugLimit);

my %arrowMeta;
$arrowMeta{neighborhood_size} = $nbSize;
$arrowMeta{title} = $title;
$arrowMeta{type} = $jobType;
$arrowMeta{sequence} = readBlastSequence($blastSeq) if $blastSeq;

my $resCode = saveData($dbFile, $accessionData, $colorUtil, \%arrowMeta, \@unmatchedIds, $idsMapped, \@inputIds, $uniRef50, $uniRef90, $clusterNumMap);







sub saveData {
    my $dbFile = shift;
    my $data = shift;
    my $colorUtil = shift;
    my $metadata = shift;
    my $unmatched = shift;
    my $idsMapped = shift;
    my $idsInOrder = shift;
    my $uniRef50 = shift || {};
    my $uniRef90 = shift || {};
    my $clusterNumMap = shift || {};

    my %args = (color_util => $colorUtil);
    $args{uniref_version} = $uniRefVersion if $uniRefVersion;
    my $arrowTool = new EFI::GNN::Arrows(%args);
    my $clusterCenters = {}; # For the future, we might use this for ordering
    $arrowTool->writeArrowData($data, $clusterCenters, $dbFile, $metadata, $idsInOrder, $uniRef50, $uniRef90);
    $arrowTool->writeUnmatchedIds($dbFile, $unmatched);
    $arrowTool->writeMatchedIds($dbFile, $idsMapped);

    $arrowTool->writeClusterMapping($dbFile, $clusterNumMap);

    return 1;
}


sub findNeighbors {
    my $dbh = shift;
    my $nbSize = shift;
    my $noNbFile = shift;
    my $evalues = shift;
    my $ids = shift;
    my $uniRef50 = shift || {};
    my $uniRef90 = shift || {};
    my $debugLimit = shift || 0;

    my @ids = @$ids;

    my $nbFind = new EFI::GNN::NeighborUtil(dbh => $dbh, use_nnm => 1, efi_anno => new EFI::Annotations);

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
    my $printProgress = sub {
        print "$sortKey / " . $#ids . " completed\n";
    };
    my $timeData = {};

    my $fnTime = 0;
    my $gaTime = 0;

    foreach my $id (@ids) {
        my $checkProgress = ($sortKey % 50) == 0;

        my $localData = {};

        $fnTime += timer("findNeighbors", $timeData) if $checkProgress;

        my (undef, undef, undef, undef) = $nbFind->findNeighbors($id, $nbSize, $warningFh, $useCircTest, $noneFamily, $localData);

        $fnTime += timer("findNeighbors", $timeData) if $checkProgress;

        $accessionData->{$id} = $localData;

        $gaTime += timer("getAnnotations", $timeData) if $checkProgress;

        getAnnotations($dbh, $id, $accessionData, $sortKey, $evalues, $uniRef50, $uniRef90);

        $gaTime += timer("getAnnotations", $timeData) if $checkProgress;

        $sortKey++;
        &$printProgress if $checkProgress;
        last if ($debugLimit and $sortKey > $debugLimit);
    }

    print "NB=$fnTime GA=$gaTime\n";

    close NO_NB_WARN;

    return $accessionData;
}


sub timer {
    my $id = shift;
    my $data = shift;
    if (exists $data->{$id}) {
        my $diff = time - $data->{$id};
        delete $data->{$id};
        $diff;
    } else {
        $data->{$id} = time;
        return 0;
    }
}



sub printTime {
    my ($t1, $name) = @_;
    $name = $name // "t";
    printf("$name=%.6f s\n", (time - $t1));
    return time;
}

sub getAnnotations {
    my $dbh = shift;
    my $accession = shift;
    my $accessionData = shift;
    my $sortKey = shift;
    my $evalues = shift;
    my $uniRef50 = shift || {};
    my $uniRef90 = shift || {};

    my $attr = $accessionData->{$accession}->{attributes};

#    my $t1 = time;
    my ($organism, $taxId, $annoStatus, $desc, $familyDesc, $iproFamilyDesc) = $annoUtil->getAnnotations($accession, $attr->{family}, $attr->{ipro_family});
    $attr->{sort_order} = $sortKey;
    $attr->{organism} = $organism;
    $attr->{taxon_id} = $taxId;
    $attr->{anno_status} = $annoStatus;
    $attr->{desc} = $desc;
    $attr->{family_desc} = $familyDesc;
    $attr->{ipro_family_desc} = $iproFamilyDesc;
    $attr->{cluster_num} = $clusterMap->{$accession} // 1;
    $attr->{evalue} = $evalues->{$accession} if exists $evalues->{$accession} and $evalues->{$accession};
    if ($uniRefVersion) {
        if ($uniRefVersion == 50) {
            my $size = 0;
            $size = scalar @{$uniRef50->{$accession}} if $uniRef50->{$accession};
            $attr->{uniref50_size} = $size;
        }
        if ($uniRefVersion >= 50) {
            my $size = 0;
            $size = scalar @{$uniRef90->{$accession}} if $uniRef90->{$accession};
            $attr->{uniref90_size} = $size;
        }
    }
#    $t1 = printTime($t1, "main");

#    $t1 = time;
    foreach my $nbObj (@{ $accessionData->{$accession}->{neighbors} }) {
        my ($nbOrganism, $nbTaxId, $nbAnnoStatus, $nbDesc, $nbFamilyDesc, $ipFamilyDesc) =
            $annoUtil->getAnnotations($nbObj->{accession}, $nbObj->{family}, $nbObj->{ipro_family});
        $nbObj->{taxon_id} = $nbTaxId;
        $nbObj->{anno_status} = $nbAnnoStatus;
        $nbObj->{desc} = $nbDesc;
        $nbObj->{family_desc} = $nbFamilyDesc;
        $nbObj->{ipro_family_desc} = $ipFamilyDesc;
    }
#    $t1 = printTime($t1, "nb");
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
    my %uniRef90;
    my %uniRef5090;

    open FILE, $file or die "Unable to open $file for reading: $!";
    while (<FILE>) {
        s/[\r\n]+$//;
        my @lineIds = split(/,+/, $_);
        foreach my $idLine (@lineIds) {
            my @parts = split(m/\t/, $idLine);
            my $id = $parts[0];
            my $evalue;
            if ($id =~ m/\|/) {
                ($id, $evalue) = split(m/\|/, $id);
                $evalues{$id} = $evalue;
            }
            if ($uniRefVersion and scalar @parts > 2) {
                push @{$uniRef90{$parts[1]}}, $id;
                $uniRef5090{$parts[2]}->{$parts[1]}++; # UniRef50 -> UniRef90
#                push @ids, $parts[1] if $uniRefVersion == 90;
#                push @ids, $parts[2] if $uniRefVersion == 50;
#            } else {
#                push @ids, $id;
            }
                push @ids, $id;
        }
    }
    close FILE;

    my %uniRef50;
    foreach my $ur50 (keys %uniRef5090) {
        foreach my $ur90 (keys %{$uniRef5090{$ur50}}) {
            push @{$uniRef50{$ur50}}, $ur90;
        }
    }

    return (\@ids, \%evalues, \%uniRef50, \%uniRef90);
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


sub parseClusterMapFile {
    my $file = shift;

    my $mapping = {};
    my $clusterNum = 1;
    my $clusterNums = {};

    open my $fh, "<", $file or die "Unable to read cluster mapping file $file: $!";
    while (<$fh>) {
        chomp;
        my @parts = split(m/\t/);
        my $clusterId = $parts[0];
        if (not $clusterNums->{$clusterId}) {
#            my $d = {cluster_num => $clusterNum++};
#            $d->{ascore} = $parts[1] if $#parts >= 2;
#            $clusterNums->{$clusterId} = $d;
            $clusterNums->{$clusterId} = $clusterNum++;
        }
        if ($#parts >= 1) {
            $mapping->{$parts[$#parts]} = $clusterNums->{$clusterId};
        }
    }
    close $fh;

    return $mapping, $clusterNums;
}



