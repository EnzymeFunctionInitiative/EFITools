#!/usr/bin/env perl

use strict;
use warnings;

use Getopt::Long;
use Data::Dumper;


my ($countFile, $idMappingFile, $outputDir);
my $result = GetOptions(
    "aa-count-file=s"   => \$countFile,
    "id-mapping=s"      => \$idMappingFile,
    "output-dir=s"      => \$outputDir,
);


die "Need input aa-count-file file " if not $countFile or not -f $countFile;
die "Need input id-mapping file" if not $idMappingFile or not -f $idMappingFile;
die "Need output-dir" if not $outputDir or not -d $outputDir;



my $groupCounts = parseCountGroup($countFile);

getIdListFiles($idMappingFile, $groupCounts);






sub getIdListFiles {
    my $file = shift;
    my $counts = shift;

    my %rev;
    foreach my $count (keys %$counts) {
        open my $fh, ">", "$outputDir/count_$count.txt" or die "unable to write to output $outputDir/count_$count.txt: $!";
        map { $rev{$_} = $fh } @{$counts->{$count}};
    }

    open my $fh, "<", $file or die "Unable to read id mapping file $file: $!";

    while (<$fh>) {
        chomp;
        my ($id, $clId, @junk) = split(m/\t/);
        $id =~ s/:\d+:\d+$//;
        if (exists $rev{$clId}) {
            $rev{$clId}->print($id, "\n");
        }
    }

    close $fh;
}





sub parseCountGroup {
    my $file = shift;

    open my $fh, "<", $file or die "Unable to read input count file $file: $!";

    my %counts;

    scalar <$fh>;
    while (<$fh>) {
        chomp;
        my ($clId, $size, $numSeq, $numUniprot, @pos) = split(m/\t/);
        push @{$counts{scalar @pos}}, $clId;
    }

    close $fh;

    return \%counts;
}


