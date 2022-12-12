#!/usr/bin/env perl

use warnings;
use strict;

use Getopt::Long;


my ($resultsDir, $htmlFile, $unirefVer);
my $result = GetOptions(
    "results-dir=s"     => \$resultsDir,
    "html-file=s"       => \$htmlFile,
    "uniref-version=i"  => \$unirefVer,
);


die "Invalid --results-dir" if not $resultsDir or not -d $resultsDir;
die "Invalid --html-file" if not $htmlFile;

$unirefVer = "" if not $unirefVer;


my $lenFile = "length_histogram";

open my $fh, ">", $htmlFile or die "Unable to write to $htmlFile: $!";

print $fh <<HTML;
<!DOCTYPE html>
<html lang="en">

<head>
    <title>EFI-EST Dataset Generation Results</title>
    <style>
    <style>
    *+*{box-sizing:border-box;margin:.5em 0}\@media(min-width:35em){.col{display:table-cell}.\31{width:5%}.\33{width:22%}.\34{width:30%}.\35{width:40%}.\32{width:15%}.row{display:table;border-spacing:1em 0}}.row,.w-100{width:100%}.card:focus,hr{outline:0;border:solid #7a0026}.card,pre{padding:1em;border:solid #eee}.btn:hover,a:hover{opacity:.6}.c{max-width:60em;padding:1em;margin:auto;font:1em/1.6 Arial}h6{font:300 1em Arial}h5{font:300 1.2em Arial}h3{font:300 2em Arial}h4{font:300 1.5em Arial}h2{font:300 2.2em Arial}h1{font:300 2.5em Arial}a{color:#7a0026;text-decoration:none}.btn.primary{color:#fff;background:#7a0026;border:solid #7a0026}pre{overflow:auto}td,th{padding:1em;text-align:left;border-bottom:solid #eee}.btn{cursor:pointer;padding:1em;letter-spacing:.1em;text-transform:uppercase;background:#fff;border:solid;font:.7em Arial}
    </style>
</head>

<body class="m0">
    <div class="c">
        <header class="mb3">
            <h1 class="tc mb0">EFI-EST Dataset Generation Results</h1>
            <div class="tc"></div>
            <hr>
        </header>
        <div class="row b-accent">The descriptions for the histograms and plots guide the choice of the values for the "Alignment Score Threshold" and the Minimum and Maximum "Sequence Length Restrictions" that are applied to the sequences and edges to generate the SSN. These values are entered using the "SSN Finalization" tab on this page.</div>
        <div class="row">
HTML

my $useDomain = -f "$resultsDir/${lenFile}_uniprot_domain.png";
my $useUniref = -f "$resultsDir/${lenFile}_uniref.png";
my $lenText = $useDomain ? "Domain" : "Full";
my $lenSuffix = $useDomain ? "_domain" : "";

print $fh <<HTML;
            <h2>Sequences as a Function of $lenText Length Histogram (First Step for Alignment Score Threshold Selection)</h2>
            <div class="row">
                <a href="${lenFile}_uniprot${lenSuffix}.png"><img src="${lenFile}_uniprot${lenSuffix}_sm.png" /></a>
            </div>
HTML

if ($useDomain and $useUniref) {
    print $fh <<HTML;
            <div>
                <p>This histogram describes the length distribution for all trimmed domains
                (from all UniProt IDs) in the input dataset.</p>
                <p>Inspection of the histogram permits identification of fragments and
                full-length domains.  This histogram is used to select Minimum and Maximum
                "Sequence Length Restrictions" in the "SSN Finalization" tab to remove
                fragments and select desired domain lengths in the input UniRef dataset.  The
                sequences in the "Sequences as a Function of Domain-Length Histogram (UniRef90
                Cluster IDs)" (last plot) are used to calculate the edges.</p>
            </div>
HTML
} elsif ($useDomain) {
    print $fh <<HTML;
            <div>
                <p>This histogram describes the length distribution for all of the trimmed
                domains (from all UniProt IDs) in the input dataset; the sequences in this
                histogram are used to calculate the edges. </p>
                <p>Inspection of the histogram permits identification of fragments and
                full-length domains.  The domain dataset for the BLAST can be length-filtered
                using the Minimum and Maximum "Sequence Length Restrictions" in the "SSN
                Finalization" tab to select desired domain lengths. </p>
            </div>
HTML
} elsif ($useUniref) {
    print $fh <<HTML;
            <div>
                <p>This histogram describes the length distribution for all sequences (UniProt
                    IDs) in the input dataset.  </p>
                <p>Inspection of the histogram permits identification of fragments, single
                domain proteins, and multidomain fusion proteins. This histogram is used to
                select Minimum and Maximum "Sequence Length Restrictions" in the "SSN
                Finalization" tab to remove fragments, select only single domain proteins, or
                select multidomain proteins.  The sequences in the "Sequences as a Function of
                Full-Length Histogram (UniRef90 Cluster IDs)" (last histogram) are used to
                calculate the edges.</p>
            </div>
HTML
} else {
    print $fh <<HTML;
            <div>
                <p>This histogram describes the length distribution for all sequences (UniProt
                    IDs) in the input dataset; the sequences in this histogram are used to
                calculate the edges.  </p>
                <p>Inspection of the histogram permits identification of fragments, single
                domain proteins, and multidomain fusion proteins. The dataset can be
                length-filtered using the Minimum and Maximum "Sequence Length Restrictions" in
                the "SSN Finalization" tab to remove fragments, select single domain proteins,
                or select multidomain fusion proteins. </p>
            </div>
HTML
}

print $fh <<HTML;
        </div>
        <div class="row">
            <h2>Alignment Length vs Alignment Score Box Plot (Second Step for Alignment Score Threshold Selection)</h2>
            <div class="row">
                <a href="alignment_length.png"><img src="alignment_length_sm.png" /></a>
            </div>
            <div>
                This box plot describes the relationship between the query-subject alignment lengths used by BLAST (y-axis) to calculate the alignment scores (x-axis).
                This plot shows a monophasic increase in alignment length to a constant value for single domain proteins; this plot shows multiphasic increases in alignment length for datasets with multidomain proteins (one phase for each fusion length). The value of the "Alignment Score Threshold" for generating the SSN (entered in the "SSN Finalization" tab) should be selected (from the "Percent Identity vs Alignment Score Box Plot"; next box plot) at an alignment length ≥ the minimum length of single domain proteins in the dataset (determined by inspection of the "Sequences as a Function of Full-Length Histogram"; previous histogram). In that region, the "Alignment Length" should be independent of the "Alignment Score".
            </div>
        </div>
        <div class="row">
            <h2>Percent Identity vs Alignment Score Box Plot (Third Step for Alignment Score Threshold Selection)</h2>
            <div class="row">
                <a href="percent_identity.png"><img src="percent_identity_sm.png" /></a>
            </div>
            <div>
                This box plot describes the pairwise percent sequence identity as a function of alignment score.
                Complementing the "Alignment Length vs Alignment Score Box Plot" (previous box plot), this box plot describes a monophasic increase in sequence identity for single domain proteins or a multiphasic increase in sequence identity for datasets with multidomain proteins (one phase for each fusion length). In the "Alignment Length vs Alignment Score" box plot (previous box plot), a monophasic increase in sequence identity occurs as the alignment score increases at a constant alignment length; multiphasic increases occur as the alignment score increases at additional longer constant alignment lengths.
                For the initial SSN, we recommend that an alignment score corresponding to 35 to 40% pairwise identity be entered in the "SSN Finalization" tab (for the first phase in multiphasic plots).
            </div>
        </div>
        <div class="row">
            <h2>Edges as a Function of Alignment Score Histogram (Preview of SSN Diversity)</h2>
            <div class="row">
                <a href="number_of_edges.png"><img src="number_of_edges_sm.png" /></a>
            </div>
            <div>
                This histogram describes the number of edges calculated at each alignment score. This plot is not used to select the alignment score for the initial SSN; however, it provides an overview of the functional diversity within the input dataset.
                In the histogram, edges with low alignment scores typically are those between isofunctional clusters; edges with large alignment scores typically are those connecting nodes within isofunctional clusters.
                The histogram for a dataset with a single isofunctional SSN cluster is single distribution centered at a "large" alignment score; the histogram for a dataset with many isofunctional SSN clusters will be dominated by the edges that connect the clusters, with the number of edges decreasing as the alignment score increases.
            </div>
        </div>
HTML

if ($useDomain) {
    print $fh <<HTML;
            <h2>Sequences as a Function of Full Length Histogram (UniProt IDs)<h2>
            <div class="row">
                <a href="${lenFile}_uniprot.png"><img src="${lenFile}_uniprot_sm.png" /></a>
            </div>
            <div>
                <p>This histogram describes the length distribution of all sequences (UniProt
                    IDs) in the input dataset.  Inspection of this histogram permits identification
                of fragments and the lengths of both single domain and multidomain fusion
                proteins in the input dataset before domain trimming. </p>
            </div>
HTML
}
if ($useUniref) {
    print $fh <<HTML;
            <h2>Sequences as a Function of Full Length Histogram (UniRef${unirefVer} Cluster IDs)</h2>
            <div class="row">
                <a href="${lenFile}_uniref.png"><img src="${lenFile}_uniref_sm.png" /></a>
            </div>
            <div>
                <p>This histogram describes the distribution of the full-length UniRef cluster
                IDs in the input dataset. The sequences of the cluster IDs displayed do not
                accurately reflect the distribution of fragments, single domain proteins, and
                multidomain full-length proteins in the input dataset. </p>
            </div>
HTML
}
if ($useDomain and $useUniref) {
    print $fh <<HTML;
            <h2>Sequences as a Function of Domain Length Histogram (UniRef${unirefVer} Cluster IDs)</h2>
            <div class="row">
                <a href="${lenFile}_uniref_domain.png"><img src="${lenFile}_uniref_domain_sm.png" /></a>
            </div>
            <div>
                <p>This histogram describes the domain length distribution of the UniRef
                cluster IDs in the input dataset; the sequences in this histogram are used to
                calculate the edges. </p>
                <p>The domains of the cluster IDs displayed do not accurately reflect the
                distribution of domains in the input dataset (diverse sequences and lengths are
                    over-represented).  Therefore, this histogram is not used to determine the
                lengths of full-length domains in the input dataset; these are determined from
                the "Sequences as a Function of Domain Length Histogram for UniProt IDs" (first
                    histogram).</p>
            </div>
HTML
}

print $fh <<HTML;
    </div>
</body>

HTML


close $fh;


