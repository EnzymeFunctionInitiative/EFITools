#!/usr/bin/env perl

use warnings;
use strict;

use Getopt::Long;


my ($statsFile, $htmlFile);
my $result = GetOptions(
    "stats-file=s"      => \$statsFile,
    "html-file=s"       => \$htmlFile,
);


die "Invalid --stats-file" if not $statsFile or not -f $statsFile;
die "Invalid --html-file" if not $htmlFile;



my ($full, @repnodes) = parseStatsFile($statsFile);



open my $fh, ">", $htmlFile or die "Unable to write to $htmlFile: $!";

print $fh <<HTML;
<!DOCTYPE html>
<html lang="en">

<head>
    <title>EFI-EST Download Network Files</title>
    <style>
    <style>
        table.pretty { border-collapse: collapse; margin-bottom: 20px; border-top: 1px solid #aaa; border-bottom: 1px solid #aaa; border-right: 1px solid #aaa; width: 100%; } table.pretty td, th { border-left: 1px solid #aaa; margin: 0; padding: 7px; } table.pretty th { background-color: #bbb; } table.pretty tr:nth-of-type(even) td { background-color: #eee; } table.no-stretch tr td:first-child { width: 1%; white-space: nowrap; } td { overflow-wrap: break-word; padding: 10px; text-align: center; } td.button-col { width: 25%; } td.right-align { text-align: right; }
        *+*{box-sizing:border-box;margin:.5em 0}\@media(min-width:35em){.col{display:table-cell}.\31{width:5%}.\33{width:22%}.\34{width:30%}.\35{width:40%}.\32{width:15%}.row{display:table;border-spacing:1em 0}}.row,.w-100{width:100%}.card:focus,hr{outline:0;border:solid #7a0026}.card,pre{padding:1em;border:solid #eee}.btn:hover,a:hover{opacity:.6}.c{max-width:60em;padding:1em;margin:auto;font:1em/1.6 Arial}h6{font:300 1em Arial}h5{font:300 1.2em Arial}h3{font:300 2em Arial}h4{font:300 1.5em Arial}h2{font:300 2.2em Arial}h1{font:300 2.5em Arial}a{color:#7a0026;text-decoration:none}.btn.primary{color:#fff;background:#7a0026;border:solid #7a0026}pre{overflow:auto}td,th{padding:1em;text-align:left;border-bottom:solid #eee}.btn{cursor:pointer;padding:1em;letter-spacing:.1em;text-transform:uppercase;background:#fff;border:solid;font:.7em Arial}
        button.mini {     font-size: 90%;     padding: 2px 9px;     margin: 0;     border: 1px solid #bbb;     border-radius: 0px;     background-color: #ddd; }
    </style>
</head>

<body class="m0">
    <div class="c">
        <header class="mb3">
            <h1 class="tc mb0">EFI-EST Download Network Files</h1>
            <div class="tc"></div>
            <hr>
        </header>
        <div class="row">
            <div class="row b-accent">
                The panels below provide files for full and representative node
                SSNs for download with the indicated numbers of nodes and edges. As an
                approximate guide, SSNs with ~2M edges can be opened with 16 GB RAM, ~4M edges
                can be opened with 32 GB RAM, ~8M edges can be opened with 64 GB RAM, ~15M
                edges can be opened with 128 GB RAM, and ~30M edges can be opened with 256 GB
                RAM.
            </div>
HTML

print $fh <<FULL;
            <div class="row">
                <h2>Full Network</h2>
                <div class="row">
                    <p>Each node in the network represents a single protein sequence. Large files (&gt;500MB) may not open in Cytoscape.</p>
                    <table width="100%" class="pretty">
                    <thead>
                    <tr>
                        <th></th>
                        <th># Nodes</th>
                        <th># Edges</th>
                        <th>File Size (MB)</th>
                    </thead>
                    <tbody>
                        <tr>
                            <td><a href='$full->{file}'><button class='mini'>Download</button></a>  <a href='$full->{file}.zip'><button class='mini'>Download ZIP</button></a></td>
                            <td>$full->{nodes}</td>
                            <td>$full->{edges}</td>
                            <td>$full->{size} MB</td>
                        </tr>
                    </tbody>
                    </table>
                </div>
            </div>
FULL


print $fh <<REPNODEHDR;
            <div class="row">
                <h2>Representative Node Networks</h2>
                <div class="row">
                    <p>
                        In representative node (RepNode) networks, each node in the network represents a collection of proteins grouped according to percent identity. For example, for a 75% identity RepNode network, all connected sequences that share 75% or more identity are grouped into a single node (meta node). Sequences are collapsed together to reduce the overall number of nodes, making for less complicated networks easier to load in Cytoscape.
                        The cluster organization is not changed, and the clustering of sequences remains identical to the full network.
                    </p>
                    <table width="100%" class="pretty">
                    <thead>
                    <tr>
                        <th></th>
                        <th>% ID</th>
                        <th># Nodes</th>
                        <th># Edges</th>
                        <th>File Size (MB)</th>
                    </thead>
                    <tbody>
REPNODEHDR

foreach my $repnode (@repnodes) {
    (my $pid = $repnode->{file}) =~ s/^.*-(1?\.\d+)_ssn.*$/$1/;
    $pid = $pid * 100;
    print $fh <<REPNODE;
                        <tr>
                            <td><a href='$repnode->{file}'><button class='mini'>Download</button></a>  <a href='$repnode->{file}.zip'><button class='mini'>Download ZIP</button></a></td>
                            <td>$pid</td>
                            <td>$repnode->{nodes}</td>
                            <td>$repnode->{edges}</td>
                            <td>$repnode->{size} MB</td>
                        </tr>
REPNODE
}


print $fh <<HTML;
                    </tbody>
                    </table>
                </div>
            </div>
        </div>
    </div>
</body>

HTML


close $fh;


sub parseStatsFile {
    my $statsFile = shift;

    open my $fh, $statsFile or die "Unable to read --stats-file $statsFile: $!";
    
    my $full;
    my @reps;

    # discard header
    scalar <$fh>;

    while (<$fh>) {
        chomp;
        my @parts = split(m/\t/);
        if (scalar @parts > 4) {
            my $size = int($parts[4]/1048576 + 0.5);
            $full = formatNum({file => $parts[0], nodes => $parts[2], edges => $parts[3], size => $size});
        } else {
            my $size = int($parts[3]/1048576 + 0.5);
            push @reps, formatNum({file => $parts[0], nodes => $parts[1], edges => $parts[2], size => $size});
        }
    }
    
    close $fh;

    return ($full, @reps);
}


sub formatNum {
    my $s = shift;
    $s->{nodes} = commify($s->{nodes});
    $s->{edges} = commify($s->{edges});
    $s->{size} = commify($s->{size});
    return $s;
}


# Perl cookbook
sub commify {
    my $text = reverse $_[0];
    $text =~ s/(\d\d\d)(?=\d)(?!\d*\.)/$1,/g;
    return scalar reverse $text
}


