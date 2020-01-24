
package EFI::Job::GNT::GND;

use strict;
use warnings;

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use lib dirname(abs_path(__FILE__)) . "/../../../";

use EFI::GNN::Arrows;
use EFI::Job::GNT::Shared;

use parent qw(EFI::Job::GNT);

use Getopt::Long qw(:config pass_through);

use constant JOB_TYPE => "gnd";


sub new {
    my $class = shift;
    my %args = @_;

    my $self = $class->SUPER::new(%args);

    my $parms = {};
    my $result = GetOptions(
        $parms,
        "output=s",
        "title=s",
        "job-type=s",

        # First mode
        "blast-seq|blast=s",
        "evalue=n",
        "max-seq=n",
        "nb-size=n",

        # Second and third mode
        "id-file=s",
        "fasta-file=s",

        # Fourth mode
        "upload-file=s",
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


sub validateOptions {
    my $self = shift;
    my $parms = shift;
    my $conf = shift;

    my $outputDir = $self->getOutputDir();

    $conf->{title} = $parms->{"title"} // "Untitled";

    my $defaultOutputFile = "$outputDir/$conf->{title}.sqlite";
    my $defaultEvalue = 5;
    my $defaultMaxSeq = 200;
    my $defaultNbSize = 10;

    $conf->{title} = "\"$conf->{title}\"";
    $conf->{output} = $parms->{"output"} // $defaultOutputFile;
    $conf->{job_type} = $parms->{"job-type"} // "";

    # First mode
    $conf->{blast_seq} = $parms->{"blast-seq"} // "";
    $conf->{evalue} = $parms->{"evalue"} // $defaultEvalue;
    $conf->{max_seq} = $parms->{"max-seq"} // $defaultMaxSeq;
    $conf->{nb_size} = $parms->{"nb-size"} // $defaultNbSize;
    # Second and third mode
    $conf->{id_file} = $parms->{"id-file"} // "";
    $conf->{fasta_file} = $parms->{"fasta-file"} // "";
    # Fourth mode
    $conf->{upload_file} = $parms->{"upload-file"} // "";

    $conf->{output} = "$outputDir/$conf->{output}" if $conf->{output} !~ m%^/%;

    if ($conf->{blast_seq} and -f $conf->{blast_seq}) {
        my $seq = "";
        my $result = open my $fh, "<", $conf->{blast_seq};
        if ($result) {
            while (<$fh>) {
                s/^\s*(.*?)[\s\r\n]*$/$1/s;
                $seq .= $_;
            }
            close $fh;
        }
        $conf->{blast_seq} = $seq;
    }

    return "Requires one of --blast-seq, --id-file, --fasta-file, or --upload-file" if not -f $conf->{upload_file} and not $conf->{blast_seq} and not -f $conf->{id_file} and not -f $conf->{fasta_file};
    return "";
}


sub setupDefaults {
    my $self = shift;
    my $conf = shift;

    my $outputDir = $self->getOutputDir();

    $conf->{job_type} = "BLAST" if $conf->{blast_seq};
    $conf->{job_type} = "ID_LOOKUP" if $conf->{id_file};
    $conf->{job_type} = "FASTA" if $conf->{fasta_file};
    $conf->{job_type} = "unzip" if $conf->{upload_file};

    $conf->{error_file} = "$outputDir/stderr.log";
    $conf->{completed_file} = "$outputDir/$self->{completed_name}";
    $conf->{job_error_file} = "$outputDir/ERROR";
}


sub getUsage {
    my $self = shift;

    my $usage = <<USAGE;
--output <OUTPUT_FILE> [--title "JOB_TITLE" --job-type BLAST|ID_LOOKUP|FASTA|unzip --nb-size #]
    [--blast-seq <SEQ> [--evalue # --max-seq #]] [--id-file <FILE>] [--fasta-file <FILE>]
    [--upload-file <FILE>]

    --output            the file to output arrow/diagram data to

    # OPTION 1: provide a FASTA sequence and retrievel related sequences for GND viewer
    --blast-seq         the sequence for Option A, which uses BLAST to get similar sequences
    --evalue            the evalue to use for BLAST; default 5
    --max-seq           the maximum number of sequences to return from the BLAST; default 200

    # OPTION 2: provide a file containing a list of IDs for GND viewer
    --id-file           file containing a list of IDs to use to generate the diagrams

    # OPTION 3: provide a file containing a list of IDs in FASTA format for GND viewer
    --fasta-file        file containing FASTA sequences with headers; we extract the IDs from
                        the headers and use those IDs to generate the diagrams

    # OPTION 4: upload a .sqlite file (optionally .zip'ped) for viewing in GND viewer
    --upload-file       the file to unzip/prep for viewing in GND

    --output            output sqlite file for Options A-D
    --title             the job title to save in the output file; shows up in GND viewer
    --job-type          the string to put in for the job type (used by the web app)
    --nb-size           the neighborhood window on either side of the query sequences; default 10
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

    return $info;
}


sub makeJobs {
    my $self = shift;
    my $conf = $self->{conf}->{gnd};
    
    my @jobs;
    my $B;

    if ($conf->{blast_seq}) {
        my $job = $self->getBlastJob();
        push @jobs, {job => $job, deps => [], name => "diagram_blast"};
    } elsif ($conf->{id_file}) {
        my $job = $self->getIdLookupJob();
        push @jobs, {job => $job, deps => [], name => "diagram_id_lookup"};
    } elsif ($conf->{fasta_file}) {
        my $job = $self->getFastaFileJob();
        push @jobs, {job => $job, deps => [], name => "diagram_fasta"};
    } elsif ($conf->{upload_file}) {
        my $job = $self->getUploadFileJob();
        push @jobs, {job => $job, deps => [], name => "diagram_upload"};
    }

    return @jobs;
}


sub getBlastJob {
    my $self = shift;
    my $conf = $self->{conf}->{gnd};

    my $configFile = $self->getConfigFile();
    my $outputDir = $self->getOutputDir();
    my $toolPath = $self->getToolPath();
    my $blastDb = $self->getBlastDbPath("uniprot");
    my $diagramVersion = $EFI::GNN::Arrows::Version;

    my $B = $self->getBuilder();

    my $seqFile = "$outputDir/query.fa";
    my $blastOutFile = "$outputDir/blast.raw";
    my $blastIdListFile = "$outputDir/blast.ids";

    open QUERY, "> $seqFile" or die "Unable to open $outputDir/query.fa for writing: $!";
    print QUERY $conf->{blast_seq};
    close QUERY;

    $self->requestResourcesByName($B, 1, 1, "diagram_blast");
    map { $B->addAction($_); } $self->getEnvironment("gnt");

    $B->addAction("blastall -p blastp -i $seqFile -d $blastDb -m 8 -e $conf->{evalue} -b $conf->{max_seq} -o $blastOutFile");
    $B->addAction("grep -v '#' $blastOutFile | cut -f 2,11,12 | sort -k3,3nr | sed 's/[\t ]\\{1,\\}/|/g' | cut -d'|' -f2,4 > $blastIdListFile");
    $B->addAction("$toolPath/create_diagram_db.pl --id-file $blastIdListFile --db-file $conf->{output} --blast-seq-file $seqFile --job-type $conf->{job_type} --title $conf->{title} --nb-size $conf->{nb_size} --config $configFile");
    $B->addAction("echo $diagramVersion > $outputDir/diagram.version");

    addBashErrorCheck($conf, $B, 1, $conf->{output});

    return $B;
}


sub getIdLookupJob {
    my $self = shift;
    my $conf = $self->{conf}->{gnd};

    my $configFile = $self->getConfigFile();
    my $outputDir = $self->getOutputDir();
    my $toolPath = $self->getToolPath();
    my $diagramVersion = $EFI::GNN::Arrows::Version;

    my $B = $self->getBuilder();

    $self->requestResourcesByName($B, 1, 1, "diagram");
    $B->addAction("$toolPath/create_diagram_db.pl --id-file $conf->{id_file} --db-file $conf->{output} --job-type $conf->{job_type} --title $conf->{title} --nb-size $conf->{nb_size} --do-id-mapping --config $configFile");
    $B->addAction("echo $diagramVersion > $outputDir/diagram.version");

    addBashErrorCheck($conf, $B, 0, $conf->{output});

    return $B;
}


sub getFastaFileJob {
    my $self = shift;
    my $conf = $self->{conf}->{gnd};

    my $configFile = $self->getConfigFile();
    my $outputDir = $self->getOutputDir();
    my $toolPath = $self->getToolPath();
    my $diagramVersion = $EFI::GNN::Arrows::Version;

    my $B = $self->getBuilder();

    my $tempIdFile = "$conf->{output}.temp-ids";

    $self->requestResourcesByName($B, 1, 1, "diagram");
    $B->addAction("$toolPath/extract_ids_from_fasta.pl --fasta-file $conf->{fasta_file} --output-file $tempIdFile --config $configFile");
    $B->addAction("$toolPath/create_diagram_db.pl --id-file $tempIdFile --db-file $conf->{output} --job-type $conf->{job_type} --title $conf->{title} --nb-size $conf->{nb_size} --do-id-mapping --config $configFile");
    $B->addAction("echo $diagramVersion > $outputDir/diagram.version");

    addBashErrorCheck($conf, $B, 0, $conf->{output});

    return $B;
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

