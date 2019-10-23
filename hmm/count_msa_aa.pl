#!/usr/bin/env perl

use strict;
use warnings;

use Getopt::Long;
use Data::Dumper;


my ($searchAa, $msaDir, $logoDir, $countFile, $pctFile, $conThreshold);
my $result = GetOptions(
    "msa-dir=s"         => \$msaDir,
    "logo-dir=s"        => \$logoDir,
    "aa=s"              => \$searchAa,
    "count-file=s"      => \$countFile,
    "pct-file=s"        => \$pctFile,
    "threshold=s"       => \$conThreshold,
);


die "Need msa-dir" if not $msaDir or not -d $msaDir;
die "Need logo-dir" if not $logoDir or not -d $logoDir;
die "Need aa" if not $searchAa;
die "Need count-file" if not $countFile;
die "Need pct-file (% cons)" if not $pctFile;

$conThreshold = 1 if not $conThreshold;

my @files = glob("$msaDir/*.afa");

my @data;

foreach my $msa (@files) {
    my $numSeq = `grep \\> $msa | wc -l`;
    chomp $numSeq;

    print "WARNING: $msa had no sequences in it\n" and next if not $numSeq;

    (my $name = $msa) =~ s/^.*?([^\/]+)\.afa$/$1/;
    my $logo = "$logoDir/$name.txt";
    my $logoData = parseLogo($logo, $numSeq, $conThreshold);

    (my $clusterNum = $name) =~ s/^.*?(\d+).*?$/$1/;
    push @data, {cluster_num => $clusterNum, num_seq => $numSeq, num_residue => scalar @$logoData, num_uniprot => 0, data => $logoData};
}


open my $countFh, ">", $countFile or die "Unable to write to count file $countFile: $!";
open my $pctFh, ">", $pctFile or die "Unable to write to pct file $pctFile: $!";

print $countFh join("\t", "Cluster Number", "#Residues", "#Sequences", "#UniProt", "#Positions..."), "\n";
print $pctFh join("\t", "Cluster Number", "#Residues", "#Sequences", "#UniProt", "#Percentages..."), "\n";

my @sorted = sort { $b->{num_residue} <=> $a->{num_residue} or $a->{cluster_num} <=> $b->{cluster_num} } @data;

foreach my $row (@sorted) {
    my @idx = map { $_->[0] } @{$row->{data}};
    my @vals = map { $_->[1] } @{$row->{data}};
    # If you change the number of cols here you need to modify collect_aa_ids.pl as well.
    print $countFh join("\t", $row->{cluster_num}, $row->{num_residue}, $row->{num_seq}, $row->{num_uniprot}, @idx), "\n";
    print $pctFh join("\t", $row->{cluster_num}, $row->{num_residue}, $row->{num_seq}, $row->{num_uniprot}, @vals), "\n";
}

close $countFh;
close $pctFh;



sub parseLogo {
    my $file = shift;
    my $numSeq = shift;
    my $conThresh = shift;

    my @data;

    open my $fh, $file or die "Unable to read logo $file: $!";

    my @aas = ("A", "C", "D", "E", "F", "G", "H", "I", "K", "L", "M", "N", "P", "Q", "R", "S", "T", "V", "W", "Y");
    my $idx = 0;
    for (my $i = 0; $i < scalar @aas; $i++) {
        $idx = $i and last if $aas[$i] eq $searchAa;
    }

    # col# AAs Entropy Low High Weight
    while (<$fh>) {
        chomp;
        next if m/^#/;
        my ($colNum, @parts) = split(m/\t/);
        $colNum =~ s/\D//g;
        @parts = @parts[0..19];
        
        my $colVal = $parts[$idx];
        my $pctVal = int($colVal * 100 / $numSeq + 0.5);
        if ($pctVal >= $conThresh) {
            push @data, [$colNum, $pctVal];
        }

        #my ($max, $idx, $sum) = getMaxIndex(\@parts);
        #if ($aas[$idx] eq $searchAa) {
        #    my $val = int($max * 100 / $numSeq + 0.5);
        #    print "$file $max $numSeq $val\n";
        #    if ($val >= $conThresh) {
        #        push @data, [$colNum, $val];
        #    }
        #}
    }

    close $fh;

    return \@data;
}



sub getMaxIndex {
    my $p = shift;
    my @parts = @$p;
    my $max = -1;
    my $maxIdx = 0;
    my $sum = 0;
    for (my $i = 0; $i < scalar @parts; $i++) {
        if ($parts[$i] > $max) {
            $maxIdx = $i;
            $max = $parts[$i];
        }
        $sum += $parts[$i];
    }
    return ($max, $maxIdx, $sum);
}



