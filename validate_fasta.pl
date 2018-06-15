#!/usr/bin/env perl

#BEGIN {
#    die "Please load efishared before runing this script" if not $ENV{EFISHARED};
#    use lib $ENV{EFISHARED};
#}


use strict;
#use DBI;
use Getopt::Long;
#use EFI::GNN::Arrows;

my ($inputDir, $metaFile);
my $result = GetOptions(
    "input-dir=s"           => \$inputDir,
    "metadata-file=s"       => \$metaFile,
);

my $usage = <<USAGE;
$0 -input-dir INPUT_DIR -metadata-file METADATA_FILE

    -input-dir          path to directory that contains FASTA files
    -metadata-file      name of the file to read metadata for the BGC clusters (for BiG-SCAPE)
                        (one file per cluster in each cluster dir). We remove entries from this
                        file that have no corresponding entry in the FASTA files.

USAGE

die "$usage" if not -d $inputDir or not -f $metaFile;


my @metadata;

open META, $metaFile or die "Unable to open metadata file $metaFile: $!";

chomp(my $header = <META>); #header line
while (my $line = <META>) {
    chomp($line);
    my ($id, @other) = split(m/\t/, $line);
    push @metadata, [$id, $line];
}

close META;


open METANEW, ">$metaFile.new" or die "Unable to open new metadata file $metaFile.new: $!";
#open METANEW, ">/home/n-z/noberg/junk/meta.new" or die "Unable to open new metadata file $metaFile.new: $!";
print METANEW $header, "\tbgc_size\trecord_count\n";

foreach my $meta (@metadata) {
    my $clusterId = $meta->[0];
    my $file = "$inputDir/$clusterId.txt";

    if (not -f $file) {
        print "Skipping $file because it doesn't exist\n";
        next;
    }
    
    my %ids;
    open IDLIST, $file or die "Unable to scan ID list file $file: $!";
    while (<IDLIST>) {
        chomp;
        my ($id, $other) = split(m/\t/);
        $ids{$id} = 1;
    }
    close IDLIST;

    my @found;
    my $fastaFile = "$inputDir/$clusterId.fasta";

    if (not -f $fastaFile) {
        print "Skipping $fastaFile because it doesn't exist\n";
        next;
    }

    my $bgcSize = 0;
    my $recordCount = 0;
    open FASTA, $fastaFile or die "Unable to scan FASTA file $fastaFile: $!";
    while (my $line = <FASTA>) {
        chomp $line;
        if ($line =~ m/^>([A-Z0-9]{6,10})/) {
            my $id = $1;
            push @found, $id if exists $ids{$id};
            $recordCount++;
        } else {
            $bgcSize += length($line);
        }
    }
    close FASTA;

    my $foundCount = scalar @found;
    my $origCount = scalar keys %ids;

    if ($foundCount > 2) { # more than two IDs must be present in the FASTA file in order to run
        print METANEW $meta->[1], "\t$bgcSize\t$recordCount\n";
    } else {
        print "Removing $fastaFile\n";
        unlink($fastaFile);
        unlink($file);
    }
}

close METANEW;

rename($metaFile, "$metaFile.old");
rename("$metaFile.new", $metaFile);

