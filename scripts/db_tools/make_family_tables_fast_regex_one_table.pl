#!/usr/bin/env perl

use strict;
use warnings;

use XML::LibXML;
use XML::Twig;
use Getopt::Long;
use Data::Dumper;


my ($inputFile, $outputFile, $interproMetaFile, $familyTypesFile, $familyTreeFile);
my ($databaseTypes, $debugCount);

my $result = GetOptions(
    "input-file=s"      => \$inputFile,
    "output-file=s"     => \$outputFile,
    "database-types=s"  => \$databaseTypes,
    "debug=i"           => \$debugCount,        # number of iterations to perform for debugging purposes
    "interpro-types=s"  => \$familyTypesFile,   # input
    "interpro-tree=s"   => \$familyTreeFile,    # input
    "interpro-meta=s"   => \$interproMetaFile,  # output
);


die "No database types provided" if not $databaseTypes;
die "No output file provided" if not $outputFile;
die "No input file provided" if not $inputFile or not -f $inputFile;




# Save the metadata (InterPro family -> family type, leaf)
saveInterproTypes($interproMetaFile, $familyTypesFile, $familyTreeFile) if $interproMetaFile and $familyTypesFile and $familyTreeFile;




my $dbTypes = getDatabaseTypes($databaseTypes);

parseFile($inputFile, $outputFile, $dbTypes);















sub parseFile {
    my $inputFile = shift;
    my $outputFile = shift;
    my $dbTypes = shift;

    my $iter = 0;

    open my $inputFh, "<", $inputFile or die "Unable to load input file '$inputFile': $!";
    open my $outputFh, ">", $outputFile or die "Unable to write to output file '$outputFile': $!";

    my @block;
    my $accession = "";

    while (my $line = <$inputFh>) {
        $line =~ s/^\s*(.*?)\s*$/$1/s;

        if ($line =~ m/<protein.* id="([^"]+)"/) {
            $accession = $1;
        } elsif ($line =~ m/<\/protein/) {
            my $data = processProteinBlock(@block);
            saveOutputProteinBlock($outputFh, $dbTypes, $accession, $data);
            @block = ();
            $accession = "";

            # Terminate after a certain amount of lines if we're in debug mode
            last if ($debugCount and $iter++ > $debugCount);
        } else {
            push @block, $line;
        }
    }

    close $outputFh;
    close $inputFh;
}


sub processProteinBlock {
    my @lines = @_;

    my @matchBlock;

    my $proteinData = {};

    while (my $line = shift @lines) {
        if ($line =~ m/<(match|ipr|lcn)/) {
            push @matchBlock, $line;
        } elsif ($line =~ m/<\/match/) {
            my $data = processMatchBlock(@matchBlock);
            @matchBlock = ();
            next if not $data;
            #push @{ $proteinData->{$data->{db}} }, $data;
            push @{ $proteinData->{$data->{db}}->{$data->{family}} }, @{ $data->{domain} };
            push @{ $proteinData->{INTERPRO}->{$data->{interpro}} }, @{ $data->{domain} } if $data->{interpro};
        }
    }

    return $proteinData;
}


sub processMatchBlock {
    my @lines = @_;

    my $dbName = "";
    my $familyId = "";
    my $interpro = "";
    my @domains;

    my $line = shift @lines;
    if ($line =~ m/dbname="([^"]+)"/) {
        $dbName = $1;
    }
    if ($line =~ m/id="([^"]+)"/) {
        $familyId = $1;
    }

    return if not $dbName or not $familyId;

    while (my $line = shift @lines) {
        # Parse the InterPro ID
        if ($line =~ m/<ipr.* id="([^"]+)"/) {
            $interpro = $1;

        # Parse the domain location
        } elsif ($line =~ m/<lcn.* start="(\d+)"/) {
            my $s = $1;
            my $e = $line =~ s/^.+end="(\d+)".*$/$1/r;
            push @domains, [$s, $e];
        }
    }

    my $data = {
        family => $familyId,
        db => uc($dbName),
        domain => \@domains,
        interpro => $interpro,
    };

    return $data;
}


sub saveOutputProteinBlock {
    my $outputFh = shift;
    my $dbTypes = shift;
    my $accession = shift;
    my $proteinData = shift;

    my $writer = sub {
        my $fh = shift;
        my ($familyId, $domains) = @_;
        foreach my $domain (@$domains) {
            $fh->print(join("\t", $familyId, $accession, @$domain), "\n");
        }
    };

    # Only save the databases for the output files that were specified by the user, by using the
    # $handles hash
    foreach my $dbName (keys %$proteinData) {
        if ($dbTypes->{$dbName}) {
            # Hash ref { family => "", domain => [[], []] }
            foreach my $familyId (sort keys %{ $proteinData->{$dbName} }) {
                foreach my $domain (@{ $proteinData->{$dbName}->{$familyId} }) {
                    $outputFh->print(join("\t", $familyId, $accession, @$domain), "\n");
                    #$outputFh->print(join("\t", $dbName, $familyId, $accession, @$domain), "\n");
                }
            }
        }
    }
}


sub getDatabaseTypes {
    my $databaseTypes = shift;
    my @dbTypes = split(m/,/, uc($databaseTypes));
    my %dbTypes = map { $_ => 1 } @dbTypes;
    return \%dbTypes;
}


sub saveInterproTypes {
    my $metaFile = shift;
    my $typesFile = shift;
    my $treeFile = shift;

    # InterPro family types
    my $interproTypes = loadFamilyTypes($typesFile);

    # InterPro family tree (maps IPR family to structure pointing to list of children and parents)
    my $interproTree = loadFamilyTree($treeFile);

    open my $fh, ">", $metaFile or die "Unable to write to InterPro meta table file '$metaFile': $!";

    foreach my $familyId (sort keys %$interproTypes) {
        my $type = $interproTypes->{$familyId};
        my $parent = $interproTree->{$familyId} ? $interproTree->{$familyId}->{parent} : "";
        my $isLeaf = ($parent and @{ $interproTree->{$familyId}->{children} }) ? 0 : 1;

        $fh->print(join("\t", $familyId, $type, $parent, $isLeaf), "\n");
    }

    close $fh;
}


sub loadFamilyTypes {
    my $file = shift;

    my %types;

    open my $fh, "<", $file or die "Unable to load interpro family types file '$file': $!";
    my $header = <$fh>;

    while (my $line = <$fh>) {
        chomp $line;
        my ($fam, $type) = split m/\t/, $line;
        if ($fam and $type) {
            $types{$fam} = $type;
        }
    }

    close $fh;

    return \%types;
}


sub loadFamilyTree {
    my $file = shift;

    my %tree;

    open my $fh, "<", $file or die "Unable to load InterPro family tree file '$file': $!";

    my @hierarchy;
    my $curDepth = 0;
    my $lastFam = "";

    while (my $line = <$fh>) {
        chomp $line;
        (my $fam = $line) =~ s/^\-*(IPR\d+)::.*$/$1/;
        (my $depthDash = $line) =~ s/^(\-*)IPR.*$/$1/;
        my $depth = length $depthDash;
        if ($depth > $curDepth) {
            push @hierarchy, $lastFam;
        } elsif ($depth < $curDepth) {
            for (my $i = 0; $i < ($curDepth - $depth) / 2; $i++) {
                pop @hierarchy;
            }
        }

        my $parent = scalar @hierarchy ? $hierarchy[$#hierarchy] : "";

        $tree{$fam}->{parent} = $parent;
        $tree{$fam}->{children} = [];
        if ($parent) {
            push @{$tree{$parent}->{children}}, $fam;
        }

        $curDepth = $depth;
        $lastFam = $fam;
    }

    close $fh;

    return \%tree;
}


