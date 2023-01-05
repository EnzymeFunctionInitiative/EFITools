
package EFI::Job::GNT::GND;

use strict;
use warnings;

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use lib dirname(abs_path(__FILE__)) . "/../../../";

use parent qw(EFI::Job::GNT);

use EFI::GNN::Arrows;

use constant JOB_TYPE => "gnd";


sub new {
    my $class = shift;
    my %args = @_;

    my $self = $class->SUPER::new(%args);

    my $parms = {};
    my $result = $self->GetEfiOptions(
        $parms,
        "output=s",                 # output file name (should be job_id.sqlite)
        "title=s",                  # title stored inside of the GND
        "job-type=s",               # unzip, BLAST, ID_LOOKUP, FASTA, TAXONOMY

        # Mode 1
        "upload-file=s",

        # Mode 2
        "seq-file=s",
        "evalue=n",
        "max-seq=n",

        # Mode 3 and 4
        "id-file=s",
        "fasta-file=s",

        # Mode 5
        "tax-file=s",
        "tax-tree-id=s",
        "tax-id-type=s",

        "seq-db-type=s",
        "reverse-uniref",
        "nb-size=n",
    );

    my $conf = {};
    my $err = $self->validateOptions($parms, $conf);
    
    push @{$self->{startup_errors}}, $err if $err;

    if (not $err) {
        $self->setupDefaults($conf);
    }

    $self->{conf}->{gnd} = $conf;
    $self->{TYPE} = JOB_TYPE;

    return $self;
}



sub ok {
    my $val = shift;
    my $default = shift || "";
    if (not defined $val) {
        return $default;
    } elsif (not $val) {
        return $default;
    } else {
        return $val;
    }
}
sub validateOptions {
    my $self = shift;
    my $parms = shift;
    my $conf = shift;

    my $outputDir = $self->getOutputDir();

    $conf->{title} = $parms->{"title"} // "Untitled";

    my $defaultOutputFile = "$outputDir/" . $self->getJobId();
    my $defaultEvalue = 5;
    my $defaultMaxSeq = 200;
    my $defaultNbSize = 10;

    $conf->{title} = "\"$conf->{title}\"";
    $conf->{output} = $parms->{"output"} // $defaultOutputFile;
    $conf->{job_type} = $parms->{"job-type"} // "";
    $conf->{output} = "$outputDir/$conf->{output}" if $conf->{output} !~ m%^/%;

    # Mode 1
    $conf->{upload_file} = $parms->{"upload-file"} // "";

    # Mode 2
    $conf->{blast_seq_file} = $parms->{"seq-file"} // "";
    $conf->{evalue} = $parms->{"evalue"} // $defaultEvalue;
    $conf->{max_seq} = $parms->{"max-seq"} // $defaultMaxSeq;
    $conf->{nb_size} = ok($parms->{"nb-size"}, $defaultNbSize);

    # Mode 3 and 4
    $conf->{id_file} = $parms->{"id-file"} // "";
    $conf->{fasta_file} = $parms->{"fasta-file"} // "";

    $conf->{tax_file} = $parms->{"tax-file"} // "";
    $conf->{tax_tree_id} = $parms->{"tax-tree-id"} // "";
    $conf->{tax_id_type} = $parms->{"tax-id-type"} // "";

    $conf->{seq_db_type} = $parms->{"seq-db-type"} // "";
    $conf->{reverse_uniref} = $parms->{"reverse-uniref"} ? 1 : 0;

    my $mode = $conf->{job_type};

    return "Requires job-type" if not $mode;

    if ($mode eq "unzip" and (not $conf->{upload_file} or not -f $conf->{upload_file})) {
        return "--job-type unzip requires --upload-file";
    } elsif ($mode eq "BLAST" and (not $conf->{blast_seq_file} or not -f $conf->{blast_seq_file})) {
        return "--job-type BLAST requires --seq-file";
    } elsif ($mode eq "ID_LOOKUP" and (not $conf->{id_file} or not -f $conf->{id_file})) {
        return "--job-type ID_LOOKUP requires --id-file";
    } elsif ($mode eq "FASTA" and (not $conf->{fasta_file} or not -f $conf->{fasta_file})) {
        return "--job-type FASTA requires --fasta-file";
    } elsif ($mode eq "TAXONOMY" and (not $conf->{tax_file} or not -f $conf->{tax_file} or not $conf->{tax_tree_id} or not $conf->{tax_id_type})) {
        return "--job-type TAXONOMY requires --tax-file --tax-tree-id and --tax-id-type";
    } else {
        #return "Requires one of --blast-seq, --id-file, --fasta-file, --upload-file, or --tax-file";
        return "";
    }
}


sub setupDefaults {
    my $self = shift;
    my $conf = shift;

    my $outputDir = $self->getOutputDir();

    my $seq = "";
    my $result = open my $fh, "<", $conf->{blast_seq_file};
    if ($result) {
        while (<$fh>) {
            s/^\s*(.*?)[\s\r\n]*$/$1/s;
            $seq .= $_;
        }
        close $fh;
    }
    $conf->{blast_seq} = $seq;

    #$conf->{job_type} = "BLAST" if $conf->{blast_seq_file};
    #$conf->{job_type} = "ID_LOOKUP" if $conf->{id_file};
    #$conf->{job_type} = "FASTA" if $conf->{fasta_file};
    #$conf->{job_type} = "unzip" if $conf->{upload_file};

    $conf->{error_file} = "$outputDir/stderr.log";
    $conf->{completed_file} = "$outputDir/$self->{completed_name}";
    $conf->{job_error_file} = "$outputDir/ERROR";
}


sub getUsage {
    my $self = shift;

    my $usage = <<USAGE;
--output <OUTPUT_FILE> [--title "JOB_TITLE" --job-type BLAST|ID_LOOKUP|FASTA|unzip|TAXONOMY --nb-size #]
    [--seq-file <FILE> [--evalue # --max-seq #]] [--id-file <FILE>] [--fasta-file <FILE>]
    [--upload-file <FILE>] [--tax-file <FILE> --tax-tree-id NODE_ID --tax-id-type uniprot|uniref50|uniref90]

    --job-type          specifies the job type, as well as the string to put in for the
                        job type (used by the web app)

    # MODE 1: upload a .sqlite file (optionally .zip'ped) for viewing in GND viewer
    --upload-file       the file to unzip/prep for viewing in GND

    # MODE 2: provide a FASTA sequence and retrievel related sequences for GND viewer
    --seq-file          the sequence for Option A, which uses BLAST to get similar sequences
    --evalue            the evalue to use for BLAST; default 5
    --max-seq           the maximum number of sequences to return from the BLAST; default 200

    # MODE 3: provide a file containing a list of IDs for GND viewer
    --id-file           file containing a list of IDs to use to generate the diagrams

    # MODE 4: provide a file containing a list of IDs in FASTA format for GND viewer
    --fasta-file        file containing FASTA sequences with headers; we extract the IDs from
                        the headers and use those IDs to generate the diagrams

    # MODE 5: extract IDs from the taxonomy tree
    --tax-file          path to the taxonomy json file
    --tax-tree-id       node ID
    --tax-id-type       ID type to use (uniprot|uniref90|uniref50)

    --output            output sqlite file for Options A-D
    --title             the job title to save in the output file; shows up in GND viewer
    --nb-size           the neighborhood window on either side of the query sequences; default 10
    --seq-db-type       uniprot [default], uniprot-nf, uniref{50,90}[-nf]
    --reverse-uniref    if --seq-db-type is uniref##[-nf], then assume input ID list is
                        UniProt; otherwise assume input ID list are UniRef cluster IDs

USAGE

    return $usage;
}


sub getJobInfo {
    my $self = shift;
    my $info = $self->SUPER::getJobInfo();
    my $conf = $self->{conf}->{gnd};

    push @$info, [title => $conf->{title}];
    push @$info, [output => $conf->{output}];
    push @$info, [job_type => $conf->{job_type}];
    push @$info, [nb_size => $conf->{nb_size}];

    # First mode
    if ($conf->{blast_seq}) {
        push @$info, [blast_seq => $conf->{blast_seq}];
        push @$info, [evalue => $conf->{evalue}];
        push @$info, [max_seq => $conf->{max_seq}];
    }

    # Second and third mode
    push @$info, [id_file => $conf->{id_file}] if $conf->{id_file};
    push @$info, [fasta_file => $conf->{fasta_file}] if $conf->{fasta_file};

    # Fourth mode
    push @$info, [upload_file => $conf->{upload_file}] if $conf->{upload_file};

    push @$info, [tax_file => $conf->{tax_file}] if $conf->{tax_file};
    push @$info, [tax_tree_id => $conf->{tax_tree_id}] if $conf->{tax_tree_id};
    push @$info, [tax_id_type => $conf->{tax_id_type}] if $conf->{tax_id_type};

    return $info;
}


sub makeJobs {
    my $self = shift;
    my $conf = $self->{conf}->{gnd};
    
    my @jobs;
    my $B;

    my $mode = $conf->{job_type};

    if ($mode eq "upload") {
        my $job = $self->getUploadFileJob();
        push @jobs, {job => $job, deps => [], name => "diagram_upload"};
    } elsif ($mode eq "BLAST") {
        my $job = $self->getBlastJob();
        push @jobs, {job => $job, deps => [], name => "diagram_blast"};
    } elsif ($mode eq "ID_LOOKUP") {
        my $job = $self->getIdLookupJob();
        push @jobs, {job => $job, deps => [], name => "diagram_id_lookup"};
    } elsif ($mode eq "FASTA") {
        my $job = $self->getFastaFileJob();
        push @jobs, {job => $job, deps => [], name => "diagram_fasta"};
    } elsif ($mode eq "TAXONOMY") {
        my $job = $self->getTaxonomyJob();
        push @jobs, {job => $job, deps => [], name => "diagram_taxonomy"};
    }

    return @jobs;
}


sub getBlastJob {
    my $self = shift;
    my $conf = $self->{conf}->{gnd};

    my $outputDir = $self->getOutputDir();
    my $blastDb = $self->getBlastDbPath("uniprot");

    my $B = $self->getBuilder();

    my $seqFile = "$outputDir/query.fa";
    my $blastOutFile = "$outputDir/blast.raw";
    my $blastIdListFile = "$outputDir/blast.ids";

    open QUERY, "> $seqFile" or die "Unable to open $outputDir/query.fa for writing: $!";
    print QUERY $conf->{blast_seq};
    close QUERY;

    $self->requestResourcesByName($B, 1, 1, "diagram_blast");
    map { $B->addAction($_); } $self->getEnvironment("gnt");

    my @acts;
    push @acts, "blastall -p blastp -i $seqFile -d $blastDb -m 8 -e $conf->{evalue} -b $conf->{max_seq} -o $blastOutFile";
    push @acts, "grep -v '#' $blastOutFile | cut -f 2,11,12 | sort -k3,3nr | sed 's/[\t ]\\{1,\\}/|/g' | cut -d'|' -f2,4 > $blastIdListFile";

    my $action = sub {
        return (\@acts, $blastIdListFile, ["--file $seqFile"], 0);
    };

    return $self->getSharedJob($action);
}


sub getIdLookupJob {
    my $self = shift;

    my $action = sub {
        return ([], $self->{conf}->{gnd}->{id_file}, ["--do-id-mapping"]);
    };
    return $self->getSharedJob($action);
}


sub getSharedJob {
    my $self = shift;
    my $extraActions = shift;
    my $conf = $self->{conf}->{gnd};

    my $configFile = $self->getConfigFile();
    my $outputDir = $self->getOutputDir();
    my $toolPath = $self->getToolPath();
    my $diagramVersion = $EFI::GNN::Arrows::Version;

    my $B = $self->getBuilder();

    $self->requestResourcesByName($B, 1, 1, "diagram");

    my $idFile = $conf->{id_file};
    my $extraArgs = "";

    if ($extraActions and ref $extraActions eq "CODE") {
        my ($extra, $extraIdFile, $createArgs)= &$extraActions();
        map { $B->addAction("$_"); } @$extra;
        $idFile = $extraIdFile;
        $extraArgs = ($createArgs and ref $createArgs eq "ARRAY") ? join(" ", @$createArgs) : "";
    }

    $B->addAction("$toolPath/create_diagram_db.pl --id-file $idFile --db-file $conf->{output} --job-type $conf->{job_type} --title $conf->{title} --nb-size $conf->{nb_size} $extraArgs --config $configFile");
    $B->addAction("echo $diagramVersion > $outputDir/diagram.version");

    addBashErrorCheck($conf, $B, 0, $conf->{output});

    return $B;
}


sub getTaxonomyJob {
    my $self = shift;
    my $conf = $self->{conf}->{gnd};

    my $toolPath = $self->getToolPath();

    my $tempIdFile = "$conf->{output}.temp-ids";
    my $act = "$toolPath/extract_taxonomy_tree.pl --json-file $conf->{tax_file} --output-file $tempIdFile --id-type $conf->{tax_id_type} --tree-id $conf->{tax_tree_id}";

    my $action = sub {
        return ([$act], $tempIdFile, []);
    };

    return $self->getSharedJob($action);
}


sub getFastaFileJob {
    my $self = shift;
    my $conf = $self->{conf}->{gnd};

    my $toolPath = $self->getToolPath();
    my $configFile = $self->getConfigFile();

    my $tempIdFile = "$conf->{output}.temp-ids";
    my $action = sub {
        my $act = "$toolPath/extract_ids_from_fasta.pl --fasta-file $conf->{fasta_file} --output-file $tempIdFile --config $configFile";
        return ([$act], $tempIdFile, ["--do-id-mapping"]);
    };

    return $self->getSharedJob($action);
}


sub getUploadFileJob {
    my $self = shift;
    my $conf = $self->{conf}->{gnd};

    my $outputDir = $self->getOutputDir();
    my $toolPath = $self->getToolPath();
    my $diagramVersion = $EFI::GNN::Arrows::Version;

    my $B = $self->getBuilder();
    
    $self->requestResourcesByName($B, 1, 1, "diagram");
    if ($conf->{upload_file} =~ m/\.zip$/i) {
        $B->addAction("$toolPath/unzip_file.pl --in $conf->{upload_file} --out $conf->{output} --out-ext sqlite 2> $conf->{error_file}");
    }
    $B->addAction("$toolPath/check_diagram_version.pl --db-file $conf->{output} --version $diagramVersion --version-file $outputDir/diagram.version");

    addBashErrorCheck($conf, $B, 1, $conf->{output});

    return $B;
}


sub addBashErrorCheck {
    my $conf = shift;
    my ($B, $markAbort, $outputFile) = @_;

    if ($markAbort) {
        $B->addAction("if [ \$? -ne 0 ]; then");
        $B->addAction("    touch $conf->{job_error_file}");
        $B->addAction("fi");
    }
    $B->addAction("if [ ! -f \"$outputFile\" ]; then");
    $B->addAction("    touch $conf->{job_error_file}");
    $B->addAction("fi");
    $B->addAction("touch $conf->{completed_file}");

    $B->addAction("");
}


1;

