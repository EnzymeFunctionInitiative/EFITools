
package EFI::Job::EST::Generate::BLAST;

use strict;
use warnings;

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use lib dirname(abs_path(__FILE__)) . "/../../../../";

use parent qw(EFI::Job::EST::Generate::FamilyShared);

use Getopt::Long qw(:config pass_through);

use EFI::Util::BLAST;

use constant JOB_TYPE => "blast";
use constant DEFAULT_BLAST_EVALUE => 5;


sub new {
    my $class = shift;
    my %args = @_;

    my $self = $class->SUPER::new(%args);

    my $parms = {};
    my $result = GetOptions(
        $parms,
        "blast-evalue=i",
        "max-blast-results|nresults=i",
        "blast-input-id=s",
        "db-type=s",
        "sequence|seq=s",
        "sequence-file=s",
    );

    my ($conf, $errors) = validateOptions($parms, $self);

    $self->{conf}->{blast} = $conf;
    $self->{conf}->{blast}->{temp_blast_file} = "initialblast.tab";
    $self->{conf}->{blast}->{query_file} = "query.fa";

    push @{$self->{startup_errors}}, @$errors;

    return $self;
}


sub validateOptions {
    my $parms = shift;
    my $self = shift;

    my @errors;

    my $defaultSeqId = "zINPUTSEQ";

    my $conf = {};
    $conf->{evalue} = "1e-" . ($parms->{"blast-evalue"} // DEFAULT_BLAST_EVALUE);
    $conf->{max_results} = $parms->{"max-blast-results"} // 1000;
    $conf->{input_id} = $parms->{"blast-input-id"} // $defaultSeqId;
    $conf->{sequence} = $parms->{"sequence"} // "";
    $conf->{sequence_file} = $parms->{"sequence-file"} // "";

    $conf->{max_results} = 1000 if not $conf->{max_results};

    #TODO: possibly fix these hard-coded strings.
    my $dbType = $parms->{"db-type"} // "";
    $conf->{db_name} = $dbType eq "uniref50" ? "uniref50" : ($dbType eq "uniref90" ? "uniref90" : "combined");
    $conf->{db_name} .= "_nf" if $self->{conf}->{generate}->{exclude_fragments};
    $conf->{db_name} .= ".fasta";

    push @errors, "A sequence must be specified through --sequence or --sequence-file" if not $conf->{sequence} and not -f $conf->{sequence_file};

    if ($conf->{sequence_file} and not $conf->{sequence}) {
        open my $fh, $conf->{sequence_file} or die "Unable to read input file sequence $conf->{sequence_file}: $!";
        my $seq = "";
        while (<$fh>) {
            s/[^A-Z\-]//g;
            $seq .= $_;
        }
        close $fh;
        $conf->{sequence} = $seq;
    }

    return $conf, \@errors;
}


sub getJobInfo {
    my $self = shift;
    my $info = $self->SUPER::getJobInfo();
    my $conf = $self->{conf}->{blast};

    (my $evalue = $conf->{evalue}) =~ s/^1e-//;
    push @$info, [blast_evalue => $evalue] if $evalue != DEFAULT_BLAST_EVALUE;
    push @$info, [max_results => $conf->{max_results}];
    push @$info, [input_id => $conf->{input_id}];
    push @$info, [sequence => $conf->{sequence}] if $conf->{sequence};
    push @$info, [sequence_file => $conf->{sequence_file}] if $conf->{sequence_file};

    return $info;
}

sub getUsage {
    my $self = shift;
    
    # All family args are optional
    my ($famMandatory, $famOptional, $famDescs) = $self->getSharedUsage(); # From FamilyShared
    my @mandatory = ("--sequence \"SEQUENCE\"", "  OR  ", "--sequence-file <PATH_TO_FILE>");
    my @optional = (
        "--blast-evalue #", "--max-blast-results #", "--blast-input-id ID",
        #"--db-type uniprot|uniref90|uniref50",
    );
    my @descs = (
        ["--sequence", "amino acid sequence to use as input for the BLAST"],
        ["--sequence-file", "path to file containing a single amino acid sequence; equivalent to --sequence, just taking the sequence from the file instead"],
        ["--blast-evalue", "numeric value indicating the negative log of the e-value to use for retrieving similar sequences; defaults to 5"],
        ["--max-blast-results", "numeric value to limit the number sequences retrieved; defaults to 1000"],
        ["--blast-input-id", "the ID to include in the SSN that represents the input sequence; defaults to zINPUTSEQ"],
    );

    return $self->outputSharedUsage(\@mandatory, [@optional, @$famMandatory, @$famOptional], [@descs, @$famDescs]);
}


# For overloading
sub getRetrievalScriptSuffix {
    return "a";
}


sub getPrecursorJobs {
    my $self = shift;
    my $S = shift;

    my @jobs;
    
    my $job1 = $self->getInitialBlastJob($S);
    push @jobs, {job => $job1, deps => [], name => "initial_blast"};

    return @jobs;
}


sub getInitialBlastJob {
    my $self = shift;
    my $S = shift;
    my $conf = $self->{conf}->{blast};

    my $outputDir = $self->getOutputDir();
    my $queryFile = "$outputDir/$conf->{query_file}";
    my $blastDir = $self->getBlastDbDir();
    my $blastDb = "$blastDir/$conf->{db_name}";

    EFI::Util::BLAST::save_input_sequence($queryFile, $conf->{sequence}, $conf->{input_id});
    
    my $B = $S->getBuilder();
    $self->requestResources($B, 1, 1, 70);

    $self->addStandardEnv($B);
    $self->addBlastEnvVars($B);

    $B->addAction("cd $outputDir");
    $B->addAction("blastall -p blastp -i $queryFile -d $blastDb -m 8 -e $conf->{evalue} -b $conf->{max_results} -o $outputDir/initialblast.out");
    $B->addAction("OUT=\$?");
    $B->addAction("if [ \$OUT -ne 0 ]; then");
    $B->addAction("    echo \"BLAST failed; likely due to file format.\"");
    $B->addAction("    echo \$OUT > $outputDir/1.out.failed");
    $B->addAction("    exit 1");
    $B->addAction("fi");
    $B->addAction("cat $outputDir/initialblast.out |grep -v '#'|cut -f 1,2,3,4,12 |sort -k5,5nr > $outputDir/$conf->{temp_blast_file}");
    $B->addAction("SZ=`stat -c%s $outputDir/$conf->{temp_blast_file}`");
    $B->addAction("if [[ \$SZ == 0 ]]; then");
    $B->addAction("    echo \"BLAST Failed. Check input sequence.\"");
    $B->addAction("    touch $outputDir/1.out.failed");
    $B->addAction("    exit 1");
    $B->addAction("fi");

    return $B;
}


sub getInitialImportArgs {
    my $self = shift;
    my $numFams = shift;
    my $conf = $self->{conf}->{blast};

    my $outputDir = $self->getOutputDir();

    my @args;
    push @args, "--blast-file $outputDir/$conf->{temp_blast_file}";
    push @args, "--query-file $outputDir/$conf->{query_file}";
    push @args, "--max-results $conf->{max_results}";

    return @args;
}


########################################################################################################################
# Break sequenes.fa into parts so we can run blast in parallel.
# Overrides the version in FamilyShared
#TODO: share this code with FamilyShared?
sub getFracFileJob {
    my $self = shift;
    my $S = shift;
    my $conf = $self->{conf}->{generate};

    my $np = $self->getNp();
    my $toolPath = $self->getToolPath();

    my $B = $S->getBuilder();
    $self->requestResources($B, 1, 1, 4); 
    
    $B->addAction("NP=$np");
    $B->addAction("sleep 10"); # Here to avoid a possible FS syncing issue with the grep on the next line.
    $B->addAction("NSEQ=`grep \\> $conf->{filt_seq_file} | wc -l`");
    $B->addAction("if [ \$NSEQ -le 50 ]; then");
    $B->addAction("    NP=1");
    $B->addAction("elif [ \$NSEQ -le 200 ]; then");
    $B->addAction("    NP=4");
    $B->addAction("elif [ \$NSEQ -le 400 ]; then");
    $B->addAction("    NP=8");
    $B->addAction("elif [ \$NSEQ -le 800 ]; then");
    $B->addAction("    NP=12");
    $B->addAction("elif [ \$NSEQ -le 1200 ]; then");
    $B->addAction("    NP=16");
    $B->addAction("fi");
    $B->addAction("echo \"Using \$NP parts with \$NSEQ sequences\"");
    $B->addAction("mkdir -p $conf->{frac_dir}");
    $B->addAction("$toolPath/split_fasta.pl --parts \$NP --tmp $conf->{frac_dir} --source $conf->{filt_seq_file}");

    return $B;
}


########################################################################################################################
# Generate job array to blast files from fracfile step
# Overrides the version in FamilyShared
#TODO: implement this
sub getBlastJob {
    my $self = shift;
    my $S = shift;
    my $conf = $self->{conf}->{generate};

    mkdir $conf->{blast_output_dir};
    
    my $np = $self->getNp();
    my $outputDir = $self->getOutputDir();
    my $blasthits = $conf->{max_blast_hits};
    my $evalue = $conf->{evalue};

    my $B = $S->getBuilder();
    $B->setScriptAbortOnError(0); # Disable SLURM aborting on errors, since we want to catch the BLAST error and report it to the user nicely
    $B->jobArray("1-$np") if $conf->{blast_type} eq "blast";
    $self->requestResources($B, 1, 1, 10); 
    
    $B->addAction("export BLASTDB=$outputDir");
    $self->addStandardEnv($B);

    $B->addAction("INFILE=\"$conf->{frac_dir}/fracfile-{JOB_ARRAYID}.fa\"");
    $B->addAction("if [[ -f \$INFILE && -s \$INFILE ]]; then");
    $B->addAction("    blastall -p blastp -i \$INFILE -d $outputDir/database -m 8 -e $evalue -b $blasthits -o $conf->{blast_output_dir}/blastout-{JOB_ARRAYID}.fa.tab");
    $B->addAction("fi");

    return $B;
}


1;

