#!/usr/bin/env perl

use strict;
use warnings;

use Getopt::Long;
use XML::LibXML;
use XML::Parser;


my $inputXmlFile;
my $outputTabFile;
my $verbose = 0;
my $result = GetOptions(
    "input=s"       => \$inputXmlFile, #taxonomy xml file
    "output=s"      => \$outputTabFile,
    "verbose"       => \$verbose,
);

my $usage = <<USAGE;
usage: $0 -input input_taxonomy_xml_file -output output_tab_file [-verbose]
USAGE

die "No valid input file provided.\n$usage" if not $inputXmlFile or not -f $inputXmlFile;
die "No output file provided.\n$usage" if not $outputTabFile;




my $parser = XML::LibXML->new();

my $doc = $parser->parse_file($inputXmlFile);
$doc->indexElements();


my %nodes;

foreach my $taxon ($doc->findnodes("/taxonSet/taxon")) {

    my $rank = $taxon->getAttribute("rank");
    my $taxId = $taxon->getAttribute("taxId");
    my $taxDiv = $taxon->getAttribute("taxonomicDivision");
    my $taxName = $taxon->getAttribute("scientificName");


    my ($childrenNode) = grep { $_->nodeName eq "children" } $taxon->nonBlankChildNodes();
    my @children = $childrenNode ? $childrenNode->nonBlankChildNodes() : ();

    foreach my $child (@children) {
        my $childRank = $child->getAttribute("rank");
        my $childId = $child->getAttribute("taxId");
        if ($childRank) {
            $nodes{$childId}->{rank} = $childRank;
        } else {
            $nodes{$childId}->{rank} = getDescendentRank($rank);
        }
        $nodes{$childId}->{name} = $child->getAttribute("scientificName");
        $nodes{$childId}->{division} = $taxDiv;
    }

    $nodes{$taxId}->{rank} = $rank if $rank;
    $nodes{$taxId}->{division} = $taxDiv if $taxDiv;
    $nodes{$taxId}->{name} = $taxName if $taxName;

    my ($lineageNode) = grep { $_->nodeName eq "lineage" } $taxon->nonBlankChildNodes();
    my @lineage = $lineageNode ? $lineageNode->nonBlankChildNodes() : ();

    if (scalar @lineage == 0 and $verbose) {
        print "[WARNING] lineage not found for species $taxName: $taxId\n" if $verbose;
        next;
    }

    my $genus = "";
    my $family = "";
    my $order = "";
    my $subclass = "";
    my $class = "";
    my $phylum = "";

    foreach my $lineageTaxon (@lineage) {
        my $lineageTaxId = $lineageTaxon->getAttribute('taxId');
        my $lineageType = $lineageTaxon->getAttribute("rank");
        $lineageType = $nodes{$lineageTaxId}->{rank} if not $lineageType;
        if ($lineageType) {
            $nodes{$taxId}->{lineage}->{$lineageType} = $lineageTaxon->getAttribute('scientificName');
            $nodes{$taxId}->{lineage_id}->{$lineageType} = $lineageTaxId;
        }
    }
}



open OUT, "> $outputTabFile";

# Don't print header, since it's going into its own database table.
#print out join("\t", getTabHeader()), "\n";
foreach my $taxId (keys %nodes) { #grep { exists $nodes{$_}->{rank} and $nodes{$_}->{rank} eq "species" } keys %nodes) {
    print OUT join("\t", $taxId, getTabLine($nodes{$taxId})), "\n";
}

close OUT;



sub getTabHeader {
    return ("NCBI TAXON ID", "DOMAIN", "KINGDOM", "PHYLUM", "CLASS", "ORDER", "FAMILY", "GENUS", "SPECIES");
}


sub getTabLine {
    my $node = shift;

    my $superKingdom = $node->{lineage}->{domain} // ($node->{lineage}->{superkingdom} // ($node->{lineage}->{"acellular root"} // "NA"));
    my $kingdom = $node->{lineage}->{kingdom} // "NA";
    $kingdom = "NA-$superKingdom" if ($kingdom eq "NA" and $superKingdom ne "NA");
    return (
            $superKingdom,
            $kingdom,
            $node->{lineage}->{phylum} // "NA",
            $node->{lineage}->{class} // "NA",
            $node->{lineage}->{order} // "NA",
            $node->{lineage}->{family} // "NA",
            $node->{lineage}->{genus} // "NA",
            $node->{name} // "NA",
        );
}



sub getDescendentRank {
    my $rank = shift;

    if ($rank eq "genus") {
        return "species";
    } elsif ($rank eq "family") {
        return "genus";
    } elsif ($rank eq "order") {
        return "family";
    } elsif ($rank eq "class") {
        return "order";
    } elsif ($rank eq "phylum") {
        return "class";
    } elsif ($rank eq "kingdom") {
        return "phylum";
    } elsif ($rank eq "domain" or $rank eq "superkingdom") {
        return "kingdom";
    } else {
        return $rank;
    }

}


