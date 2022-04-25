#!/usr/bin/env perl

use strict;
use warnings;

use XML::LibXML;
use XML::Twig;
use Getopt::Long;
use Data::Dumper;


my ($outputDir, $inputDir, $uniref50File, $uniref90File, $gene3dFile, $pfamFile, $ssfFile, $interproFile, $debugCount);
my ($familyTypesFile, $treeFile, $interproInfoFile, $tigrFamFile);

my $result = GetOptions(
    "outdir=s"          => \$outputDir,
    "indir=s"           => \$inputDir,
    "uniref50=s"        => \$uniref50File,      # tab file that maps clustered UniProt IDs to representative UniRef ID
    "uniref90=s"        => \$uniref90File,      # tab file that maps clustered UniProt IDs to representative UniRef ID
    "gene3d=s"          => \$gene3dFile,        # CATH/GENE3D output file (shows up as CATHGENE3D in match_complete.xml)
    "pfam=s"            => \$pfamFile,          # PFAM output file
    "ssf=s"             => \$ssfFile,           # SSF output file
    "interpro=s"        => \$interproFile,      # INTERPRO output file
    "tigrfam=s"         => \$tigrFamFile,       # TIGRFAMs output file
    "debug=i"           => \$debugCount,        # number of iterations to perform for debugging purposes
    "interpro-info=s"   => \$interproInfoFile,  # INTERPRO info output file
    "types=s"           => \$familyTypesFile,
    "tree=s"            => \$treeFile,
);

die "No output directory provided" if not defined $outputDir or not -d $outputDir;
die "No input directory provided" if not defined $inputDir or not -d $inputDir;

# Key to this hash must match the dbname attribute in the match tag.
my %files;
$files{CATHGENE3D} = $gene3dFile if $gene3dFile;
$files{PFAM} = $pfamFile if $pfamFile;
$files{SSF} = $ssfFile if $ssfFile;
$files{INTERPRO} = $interproFile if $interproFile;
$files{TIGRFAMs} = $tigrFamFile if $tigrFamFile;


my $verbose=0;

# Key to this hash must match the dbname attribute in the match tag.
my %databases = ();
if (not $gene3dFile and not $pfamFile and not $ssfFile and not $interproFile and not $interproInfoFile and not $tigrFamFile) {
    # Default to all
    %databases = (
        CATHGENE3D      => 1,
        PFAM        => 1,
        SSF         => 1,
        INTERPRO    => 1,
        TIGRFAMs     => 1,
    );
} else {
    $databases{CATHGENE3D} = 1 if $gene3dFile;
    $databases{PFAM} = 1 if $pfamFile;
    $databases{SSF} = 1 if $ssfFile;
    $databases{INTERPRO} = 1 if $interproFile;
    $databases{TIGRFAMs} = 1 if $tigrFamFile;
}


my %filehandles = ();

foreach my $database (keys %databases) {
    local *FILE;
    my $file = "$outputDir/$database.tab";
    $file = $files{$database} if exists $files{$database};
    open(FILE, ">$file") or die "could not write to $file\n";
    $filehandles{$database} = *FILE;
}


# InterPro family types
my $ipTypes = loadFamilyTypes($familyTypesFile) if (defined $familyTypesFile and -f $familyTypesFile);
# InterPro family tree (maps IPR family to structure pointing to list of children and parents)
my $tree = loadFamilyTree($treeFile) if (defined $treeFile and -f $treeFile);
if ($familyTypesFile and $treeFile and $interproInfoFile) {
    open IPINFO, ">", $interproInfoFile or die "Unable to open $interproInfoFile for writing: $!";
    foreach my $fam (sort keys %$ipTypes) {
        my @parts = ($fam, $ipTypes->{$fam}, "", 1);
        if (exists $tree->{$fam}) {
            $parts[2] = $tree->{$fam}->{parent};
            $parts[3] = (scalar @{$tree->{$fam}->{children}}) ? 0 : 1;
        }
        print IPINFO join("\t", @parts), "\n";
    }
    close IPINFO;
}

exit(0) if not scalar keys %databases;


my $uniref50 = {};
$uniref50 = loadUniRefFile($uniref50File) if ($uniref50File and -f $uniref50File);
my $uniref90 = {};
$uniref90 = loadUniRefFile($uniref90File) if ($uniref90File and -f $uniref90File);

my $iter = 0;
$| = 1;

foreach my $xmlfile (glob("$inputDir/*.xml")){
    print "Parsing $xmlfile\n";

    open my $fh, "<", $xmlfile;

    my ($ipro, $dbname, $familyId, $start, $end) = ("", "", "", 0, 0);
    my $accession = "";
    while (my $line = <$fh>) {
        chomp $line;
        if ($line =~ m/<protein.* id="([^"]+)"/) {
            $accession = $1;
        } elsif ($line =~ m/<\/match/) {
            if ($ipro) {
                writeOutputLine("INTERPRO", $ipro, $accession, $start, $end);
            }
            if (not $databases{$dbname}) {
                ($ipro, $dbname, $familyId, $start, $end) = ("", "", "", 0, 0);
                next;
            }
            if ($familyId) {
                writeOutputLine($dbname, $familyId, $accession, $start, $end);
            }
            ($ipro, $dbname, $familyId, $start, $end) = ("", "", "", 0, 0);
        } elsif ($line =~ m/<match.* dbname="([^"]+)"/) {
            $dbname = $1;
            if (not $databases{$dbname}) {
                ($ipro, $dbname, $familyId, $start, $end) = ("", "", "", 0, 0);
                next;
            }
            ($familyId = $line) =~ s/^.* id="([^"]+)".*$/$1/;
        #} elsif ($line =~ m/<ipr.* id="([^"]+)"/ and $dbname) {
        } elsif ($line =~ m/<ipr.* id="([^"]+)"/) {
            $ipro = $1;
        #} elsif ($line =~ m/<lcn.* start="(\d+)"/ and $dbname) {
        } elsif ($line =~ m/<lcn.* start="(\d+)"/) {
            $start = $1;
            ($end = $line) =~ s/^.* end="(\d+)".*$/$1/;
        } elsif ($line =~ m/<\/protein/) {
        }
    }

    close $fh;


    #XML::Twig->new(
    #    twig_roots => {
    #        'protein' =>
    #            sub {
    #                my ($t, $ent) = @_;
    #                my $accession = $ent->{att}->{id};
    #                my $matchTag = $ent->{first_child};

    #                # For every child <match> tag
    #                while ($matchTag) {
    #                    if (not $databases{$matchTag->{att}->{dbname}}) {
    #                        $matchTag = $matchTag->{next_sibling};
    #                        next;
    #                    }
    #                    processMatchTag($accession, $matchTag);
    #                    $matchTag = $matchTag->{next_sibling};
    #                }
    #            }
    #        })->parsefile($xmlfile);

    last if ($debugCount and $iter++ > $debugCount);
}


foreach my $key (keys %filehandles) {
    close $filehandles{$key};
}






sub processMatchTag {
    my $accession = shift;
    my $matchTag = shift;

    my $familyId = $matchTag->{att}->{id};
    my $dbname = $matchTag->{att}->{dbname};

    # Look at every child tag of <match>
    my $kid = $matchTag->{first_child};
    my ($ipro, $start, $end) = ("", 0, 0);
    while ($kid) {
        if ($kid->{att}->{id} and $kid->{att}->{id} =~ m/^IPR/i) {
            $ipro = $kid->{att}->{id};
        } elsif ($kid->{att}->{start}) {
            $start = $kid->{att}->{start};
            $end = $kid->{att}->{end};
        }
        $kid = $kid->{next_sibling};
    }

    writeOutputLine("INTERPRO", $ipro, $accession, $start, $end) if $ipro;
    writeOutputLine($dbname, $familyId, $accession, $start, $end);
}


sub writeOutputLine {
    my ($dbname, $familyId, $accession, $start, $end) = @_;
    my @parts = ($familyId, $accession, $start, $end);
    my $ur50 = exists $uniref50->{$accession} ? $uniref50->{$accession} : "";
    my $ur90 = exists $uniref90->{$accession} ? $uniref90->{$accession} : "";
    if ($uniref50File or $uniref90File) {
        push(@parts, $ur50);
        push(@parts, $ur90);
    }

    my @famInfo;
    if ($dbname eq "INTERPRO" and $familyTypesFile and $treeFile) {
        push @famInfo, (exists $ipTypes->{$familyId} ? $ipTypes->{$familyId} : "") ;
        push @famInfo, (exists $tree->{$familyId} ? $tree->{$familyId}->{parent} : "");
        push @famInfo, ((not exists $tree->{$familyId} or not scalar @{$tree->{$familyId}->{children}}) ? 1 : 0); # 1 if it's a leaf node (e.g. it has no interpro parent family)
    }

    print {$filehandles{$dbname}} join("\t", @parts, @famInfo), "\n";
}



sub loadUniRefFile {
    my $filePath = shift;

    open URF, $filePath;

    my %data;

    while (<URF>) {
        chomp;
        my ($refId, $upId) = split(m/\t/);
        $data{$upId} = $refId;
    }

    close URF;

    return \%data;
}


sub loadFamilyTypes {
    my $file = shift;

    my %types;

    open FILE, $file;
    my $header = <FILE>;

    while (<FILE>) {
        chomp;
        my ($fam, $type) = split m/\t/;
        if ($fam and $type) {
            $types{$fam} = $type;
        }
    }

    close FILE;

    return \%types;
}


sub loadFamilyTree {
    my $file = shift;

    my %tree;

    open FILE, $file;

    my @hierarchy;
    my $curDepth = 0;
    my $lastFam = "";

    while (<FILE>) {
        chomp;
        (my $fam = $_) =~ s/^\-*(IPR\d+)::.*$/$1/;
        (my $depthDash = $_) =~ s/^(\-*)IPR.*$/$1/;
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

    close FILE;

    return \%tree;
}


