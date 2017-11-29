#!/usr/bin/env perl

BEGIN {
    die "Please load efishared before runing this script" if not $ENV{EFISHARED};
    use lib $ENV{EFISHARED};
}


use strict;
use Getopt::Long;
use EFI::Fasta::Headers;


my ($inputFile, $outputFile, $unmatchedFile, $configFile);
my $result = GetOptions(
    "fasta-file=s"          => \$inputFile,
    "output-file=s"         => \$outputFile,
    "unmatched-id-file=s"   => \$unmatchedFile,
    "config=s"              => \$configFile,
);

my $usage = <<USAGE;
$0 -fasta-file INPUT_FILE -output-file OUTPUT_FILE [-unmatched-id-file FILE] [-config CONFIG_FILE]

    -fasta-file         path to input FASTA file
    -output-file        path to output file containing a list of UniProt IDs detected;
                        if non-UniProt IDs are detected, they are reverse mapped to UniProt IDs
    -unmatched-id-file  path to an output file to put a list of IDs that are not matched to a UniProt ID
    -config             path to config file; taken from environment if not present
USAGE

die "$usage" if not -f $inputFile or not $outputFile;
die "Config file required in environment or as a parameter.\n$usage"
    if not -f $configFile and not exists $ENV{EFICONFIG} and not -f $ENV{EFICONFIG};

$configFile = $ENV{EFICONFIG} if not -f $configFile;



my $parser = new EFI::Fasta::Headers(config_file_path => $configFile);

open INFASTA, $inputFile;
open OUTPUT, ">$outputFile";
if ($unmatchedFile) {
    open UNMATCHED, ">$unmatchedFile";
} else {
    open UNMATCHED, ">/dev/null";
}


my $id;
while (my $line = <INFASTA>) {
    $line =~ s/[\r\n]+$//;

    my $headerLine = 0;
    my $writeSeq = 0;

    my $result = $parser->parse_line_for_headers($line);

    next if ($result->{state} ne EFI::Fasta::Headers::FLUSH);
        
    if (scalar @{ $result->{uniprot_ids} }) {
        map { print OUTPUT $_->{uniprot_id} . "\n"; } @{ $result->{uniprot_ids} };
    } elsif (scalar @{ $result->{other_ids} }) {
        print UNMATCHED join(",", @{ $result->{other_ids} }), "\n";
    }
}

close UNMATCHED;
close OUTPUT;
close INFASTA;

$parser->finish();











