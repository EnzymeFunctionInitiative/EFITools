#!/usr/bin/env perl

BEGIN {
    die "Please load efishared before runing this script" if not $ENV{EFISHARED};
    use lib $ENV{EFISHARED};
}


use strict;
use DBI;
use Getopt::Long;
use FindBin;

use lib $FindBin::Bin . "/lib";
use EFI::GNN::Arrows;

my ($inputFile, $outputDir, $metaFile, $window);
my $result = GetOptions(
    "diagram-file=s"        => \$inputFile,
    "output-dir=s"          => \$outputDir,
    "metadata-file=s"       => \$metaFile,
    "window=i"              => \$window,
);

my $usage = <<USAGE;
$0 -diagram-file INPUT_FILE -output-dir OUTPUT_FILE -metadata-file METADATA_FILE

    -diagram-file       path to input diagram file
    -output-dir         path to directory to store FASTA files in
    -metadata-file      name of the file to store metadata for the BGC clusters (for BiG-SCAPE)
                        (one file per cluster in each cluster dir)
    -window             number of genes to collect around each query gene

USAGE

die "$usage" if not -f $inputFile or not $outputDir;


$window = 1000 if not defined $window or $window < 1;


exportIdInfo($inputFile, $outputDir, $metaFile);


sub exportIdInfo {
    my $sqliteFile = shift;
    my $outDir = shift;
    my $metaFileName = shift;

    my $dbh = DBI->connect("dbi:SQLite:dbname=$sqliteFile","","");
    
    my $sql = "SELECT * FROM attributes";
    my $sth = $dbh->prepare($sql);
    $sth->execute();

    my %groupData;

    while (my $row = $sth->fetchrow_hashref()) {
        $groupData{$row->{cluster_num}}->{$row->{accession}} = {
            gene_id => $row->{id},
            seq_len => $row->{seq_len},
            product => "",
            organism => $row->{strain},
            taxonomy => "",
            description => "",
            contig_edge => 0, #TODO: compute this correctly
            gene_key => $row->{sort_key},
            cluster_num => $row->{cluster_num},
            neighbors => [],
            position => $row->{num},
            start => $row->{start},
            stop => $row->{stop},
            direction => $row->{direction} eq "normal" ? "+" : "-",
        };
    }

    foreach my $clusterNum (sort keys %groupData) {

        my @ids = sort keys %{$groupData{$clusterNum}};

        next if scalar @ids < 3;

        my $clusterDir = "$outDir/cluster_$clusterNum";
        mkdir($clusterDir);

        my $metaFile = "$clusterDir/$metaFileName";
        open META, ">$metaFile" or die "Unable to write to metadata file $metaFile: $!";
        print META "cluster\tgene_id\tseq_len\tproduct\torganism\ttaxonomy\tdescription\tcontig_edge\n";
    
        foreach my $id (@ids) {
            next if not $id;
    
            my $data = $groupData{$clusterNum}->{$id};

            $sql = "SELECT * FROM neighbors WHERE gene_key = " . $data->{gene_key} . " ORDER BY num";
            $sth = $dbh->prepare($sql);
            $sth->execute();
    
            my $outputCenter = 0;
            my $queryNum = $data->{position};
    
            my @idList;
            my $count = 0;
    
            while (my $row = $sth->fetchrow_hashref()) {
                my $num = $row->{num};
                # Exclude anything outside the requested gene window around the query gene.
                next if $num < ($queryNum - $window) or $num > ($queryNum + $window); 

                # Insert the main query/cluster ID into the middle of the neighbors where it belongs.
                if (not $outputCenter and $queryNum < $num) {
                    $outputCenter = 1;
                    my $queryHdr = join(":", "${id}_ORF$queryNum", "gid", $data->{gene_id}, "pid", $id,
                                              "loc", $data->{start}, $data->{stop}, "strand", $data->{direction});
                    push @idList, join("\t", $id, $queryHdr);
                    $count++;
                }
                my $direction = $row->{direction} eq "normal" ? "+" : "-";
                my $customHdr = join(":", "$row->{accession}_ORF$row->{num}", "gid", $row->{id}, "pid", $id,
                                          "loc", $row->{start}, $row->{stop}, "strand", $direction);
                push @idList, join("\t", $row->{accession}, $customHdr);
                $count++;
            }
    
            if (scalar @idList > 0) {
                print META join("\t", $id,
                    $data->{gene_id},
                    $data->{seq_len},
                    $data->{product},
                    $data->{organism},
                    $data->{taxonomy},
                    $data->{description},
                    $data->{contig_edge}), "\n";
        
                my $outFile = "$clusterDir/$id.txt";
                open OUT, ">$outFile" or die "Unable to open output id list file $outFile: $!";
                print OUT join("\n", @idList), "\n";
                close OUT;
            }
        }
    
        close META;
    }
}

