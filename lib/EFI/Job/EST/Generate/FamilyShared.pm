
package EFI::Job::EST::Generate::FamilyShared;

use strict;
use warnings;

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use lib dirname(abs_path(__FILE__)) . "/../../../../";

use parent qw(EFI::Job::EST::Generate);

use Getopt::Long qw(:config pass_through);


sub new {
    my $class = shift;
    my %args = @_;

    my $self = $class->SUPER::new(%args);

    my $parms = {};
    my $result = GetOptions(
        $parms,
        "pfam=s@",
        "interpro|ipro=s@",
        "gene3d=s@",
        "ssf=s@",
        "fraction=i",
        "uniref-version=s",
        "no-demux",
    );
    
    my ($conf, $errors) = validateOptions($parms, $self, $args{family_mandatory});

    $self->{conf}->{family} = $conf;

    push @{$self->{startup_errors}}, @$errors;

    return $self;
}


sub validateOptions {
    my $parms = shift;
    my $self = shift;
    my $familyMandatory = shift;

    my @errors;

    my $conf = {};
    $conf->{pfam} = $parms->{pfam} // [];
    $conf->{interpro} = $parms->{interpro} // [];
    $conf->{gene3d} = $parms->{gene3d} // [];
    $conf->{ssf} = $parms->{ssf} // [];
    $conf->{fraction} = ($parms->{fraction} // 1) or 1;
    $conf->{uniref_version} = $parms->{"uniref-version"} // "";
    $conf->{no_demux} = $parms->{"no-demux"} // 0;

    my $famCount = scalar @{$conf->{pfam}} + scalar @{$conf->{interpro}} + scalar @{$conf->{gene3d}} + scalar @{$conf->{ssf}};
    push @errors, "At least one of --pfam, --interpro, --gene3d, or --ssf arguments are required."
        if not $famCount and $familyMandatory;
    push @errors, "--uniref-version must be either 50 or 90"
        if $conf->{uniref_version} and $conf->{uniref_version} ne "50" and $conf->{uniref_version} ne "90";

    return $conf, \@errors;
}


sub getJobInfo {
    my $self = shift;
    my $info = $self->SUPER::getJobInfo();
    my $conf = $self->{conf}->{family};

    push @$info, [pfam => join(" ", map { "--pfam $_" } @{$conf->{pfam}})] if scalar @{$conf->{pfam}};
    push @$info, [interpro => join(" ", map { "--pfam $_" } @{$conf->{interpro}})] if scalar @{$conf->{interpro}};
    push @$info, [uniref_version => $conf->{uniref_version}] if $conf->{uniref_version};
    push @$info, [fraction => $conf->{fraction}] if $conf->{fraction} > 1;

    return $info;
}


sub getSharedUsage {
    my @mandatory = ();
    my @optional = ("--pfam PF#####|CL####", "--interpro IPR######", "--fraction #", "--uniref-version 50|90");
    my @desc = (
        ["--pfam", "Pfam family; can also be Pfam clan; multiple families can be used by including the --pfam arg multiple times"],
        ["--interpro", "InterPro family; multiple families can be used by using the --interpro arg multiple times"],
        ["--fraction", "A numeric value that is the fraction of sequences to include from the family; by default all sequences are used"],
        ["--uniref-version", "Uses the UniRef50 or UniRef90 cluster ID sequences instead of the full family"],
    );
    return \@mandatory, \@optional, \@desc;
}


sub getUniRefVersion {
    my $self = shift;
    return $self->{conf}->{family}->{uniref_version};
}


sub createJobs {
    my $self = shift;

    my @jobs;
    my $B;
    my $job;

    @jobs = $self->getPrecursorJobs();

    my $job1 = $self->getInitialImportJob();
    my $imp = {job => $job1, deps => [], name => "initial_import"};
    $imp->{deps} = [$jobs[$#jobs]->{job}] if scalar @jobs;
    push @jobs, $imp;

    my $job2 = $self->getMultiplexJob();
    push @jobs, {job => $job2, deps => [$job1], name => "multiplex"};

    my $job3 = $self->getFracFileJob();
    push @jobs, {job => $job3, deps => [$job2], name => "fracfile"};

    my $job4 = $self->getCreateDbJob();
    push @jobs, {job => $job4, deps => [$job3], name => "createdb"};

    my $job5 = $self->getBlastJob();
    push @jobs, {job => $job5, deps => [$job4], name => "blastqsub"};
    
    my $job6 = $self->getCatJob();
    push @jobs, {job => $job6, deps => [{obj => $job5, is_job_array => 1}], name => "catjob"};
    
    my $job7 = $self->getBlastReduceJob();
    push @jobs, {job => $job7, deps => [$job6], name => "blastreduce"};

    my $job8 = $self->getDemuxJob();
    push @jobs, {job => $job8, deps => [$job7], name => "demux"};

    my $job9 = $self->getConvergenceRatioJob();
    push @jobs, {job => $job9, deps => [$job8], name => "conv_ratio"};

    my $job10 = $self->getGraphJob();
    $self->addRemoveTempFiles($job10);
    push @jobs, {job => $job10, deps => [$job8], name => "graphs"};

    return @jobs;
}
sub getPrecursorJobs {
    my $self = shift;
    return ();
}


########################################################################################################################
# Get sequences and annotations.  This creates fasta and struct.out files.
sub getInitialImportJob {
    my $self = shift;
    my $conf = $self->{conf}->{family};
    my $gconf = $self->{conf}->{generate};

    my $toolPath = $self->getToolPath();
    my $outputDir = $self->getOutputDir();
    my $unirefVersion = $self->getUniRefVersion();
    my $metaFile = "$outputDir/" . EFI::Config::FASTA_META_FILENAME;
    my $configFile = $self->getConfigFile();

    my $B = $self->getBuilder();
    $self->requestResources($B, 1, 1, $self->getMemorySize("initial_import"));

    $B->addAction("cd $outputDir");

    # Add unzip file, etc if necessary
    $self->addInitialImportFileActions($B);
    $self->addStandardEnv($B);
    $self->addDatabaseEnvVars($B) if not $configFile;
    $self->addBlastEnvVars($B);

    my @args;
    push @args, "--config $configFile" if $configFile;
    push @args, "--error-file $gconf->{error_file}";
    push @args, "--seq-count-output $gconf->{seq_count_file}";
    push @args, "--sequence-output $gconf->{all_seq_file}";
    push @args, "--accession-output $gconf->{acc_list_file}";
    push @args, "--meta-file $metaFile";

    my @famArgs;
    map { push @famArgs, "--$_ " . join(",", @{$conf->{$_}}) if scalar @{$conf->{$_}}; } ("pfam", "interpro", "ssf", "gene3d");
    push @args, @famArgs;

    if (scalar @famArgs) {
        push @args, "--uniref-version $unirefVersion" if $unirefVersion;
        push @args, "--fraction $conf->{fraction}" if $conf->{fraction};
    }

    if ($self->{conf}->{domain}) {
        push @args, "--domain on";
        push @args, "--uniprot-dom-len-output $gconf->{len_uniprot_dom_file}";
        push @args, "--uniref-dom-len-output $gconf->{len_uniref_dom_file}" if $unirefVersion;
    }

    my $option = $self->getRetrievalScriptSuffix();
    my $retrScript = "get_sequences_option_$option.pl";

    push @args, "--exclude-fragments" if $gconf->{exclude_fragments};

    my @specificArgs = $self->getInitialImportArgs(scalar @famArgs);
    push @args, @specificArgs;

    $B->addAction("$toolPath/$retrScript " . join(" ", @args));

    my @lenUniprotArgs = ("--struct $metaFile");
    push @lenUniprotArgs, "--config $configFile" if $configFile;
    push @lenUniprotArgs, "--output $gconf->{len_uniprot_file}";
    push @lenUniprotArgs, "--expand-uniref" if $unirefVersion;
    $B->addAction("$toolPath/get_lengths_from_anno.pl " . join(" ", @lenUniprotArgs));
    
    if ($unirefVersion) {
        my @lenUnirefArgs = ("--struct $metaFile");
        push @lenUnirefArgs, "--config $configFile" if $configFile;
        push @lenUnirefArgs, "--output $gconf->{len_uniref_file}";
        $B->addAction("$toolPath/get_lengths_from_anno.pl " . join(" ", @lenUnirefArgs));
    }

    $B->addAction("touch $gconf->{uniref_flag_file}") if $unirefVersion;

    # Annotation retrieval (getannotations.pl) now happens in the SNN/analysis step.
    #
    return $B;
}


# For overloading
sub getRetrievalScriptSuffix {
    return "";
}

# For overloading
sub addInitialImportFileActions {
    my $self = shift;
    my $B = shift;
}


#######################################################################################################################
# Try to reduce the number of sequences to speed up computation.
# If multiplexing is on, run an initial cdhit to get a reduced set of "more" unique sequences.
# If not, just copy allsequences.fa to sequences.fa so next part of program is set up right.
sub getMultiplexJob {
    my $self = shift;
    my $conf = $self->{conf}->{generate};
    
    my $domain = $self->{conf}->{domain} ? "on" : "off";
    my $toolPath = $self->getToolPath();

    my $B = $self->getBuilder();
    $self->requestResources($B, 1, 1, $self->getMemorySize("multiplex"));

    $self->addStandardEnv($B);

    my $manualCdHit = 0;
    $manualCdHit = 1 if ($conf->{cdhit_seq_id_threshold} < 1 or $conf->{cdhit_length_diff} < 1) and not $self->{conf}->{option_e}->{cd_hit_file} and $self->{conf}->{family}->{no_demux};

    if ($conf->{multiplex}) {
        my $nParm = ($conf->{cdhit_seq_id_threshold} < 1 and $conf->{cdhit_length_diff} < 1) ? "-n 2" : "";
        $B->addAction("cd-hit -d 0 $nParm -c $conf->{cdhit_seq_id_threshold} -s $conf->{cdhit_length_diff} -i $conf->{all_seq_file} -o $conf->{filt_seq_file} -M 10000");
        if ($manualCdHit) {
            $B->addAction(<<CMDS
if $toolPath/check_seq_count.pl -max-seq $conf->{max_sequence} -error-file $conf->{error_file} -cluster $conf->{filt_seq_file}.clstr
then
    echo "Sequence count OK"
else
    echo "Sequence count not OK"
    exit 1
fi
CMDS
            );
            $B->addAction("mv $conf->{all_seq_file} $conf->{all_seq_file}.before_demux");
            $B->addAction("cp $conf->{filt_seq_file} $conf->{all_seq_file}");
        }
        if ($conf->{no_demux}) {
            $B->addAction("$toolPath/get_demux_ids.pl -struct $conf->{struct_file} -cluster $conf->{filt_seq_file}.clstr -domain $domain");
        }
    } else {
        $B->addAction("cp $conf->{all_seq_file} $conf->{filt_seq_file}");
    }

    return $B;
}


########################################################################################################################
# Break sequenes.fa into parts so we can run blast in parallel.
sub getFracFileJob {
    my $self = shift;
    my $conf = $self->{conf}->{generate};

    my $np = $self->getNp();
    my $toolPath = $self->getToolPath();

    my $B = $self->getBuilder();
    $self->requestResources($B, 1, 1, $self->getMemorySize("fracfile"));
    $self->addStandardEnv($B);
    
    $B->addAction("mkdir -p $conf->{frac_dir}");
    $B->addAction("$toolPath/split_fasta.pl --parts $np --tmp $conf->{frac_dir} --source $conf->{filt_seq_file}");

    return $B;
}


########################################################################################################################
# Make the blast database and put it into the temp directory
sub getCreateDbJob {
    my $self = shift;
    my $conf = $self->{conf}->{generate};

    my $outputDir = $self->getOutputDir();

    my $B = $self->getBuilder();
    $self->requestResources($B, 1, 1, $self->getMemorySize("createdb"));
    $self->addStandardEnv($B);

    $B->addAction("cd $outputDir");
    if ($conf->{blast_type} eq 'diamond' or $conf->{blast_type} eq 'diamondsensitive') {
        map { $B->addAction($_); } $self->getEnvironment("est-diamond");
        $B->addAction("diamond makedb --in $conf->{filt_seq_file} -d database");
    } else {
        $B->addAction("formatdb -i $conf->{filt_seq_file} -n database -p T -o T ");
    }

    return $B;
}


########################################################################################################################
# Generate job array to blast files from fracfile step
sub getBlastJob {
    my $self = shift;
    my $conf = $self->{conf}->{generate};

    mkdir $conf->{blast_output_dir};
    
    my $np = $self->getNp();
    my $outputDir = $self->getOutputDir();
    my $blasthits = $conf->{max_blast_hits};
    my $evalue = $conf->{evalue};

    my $B = $self->getBuilder();
    $B->setScriptAbortOnError(0); # Disable SLURM aborting on errors, since we want to catch the BLAST error and report it to the user nicely
    $B->jobArray("1-$np") if $conf->{blast_type} eq "blast";
    $self->requestResources($B, 1, 1, $self->getMemorySize("blastqsub"));
    $B->resource(1, 24, "14G") if $conf->{blast_type} =~ /diamond/i;
    $B->resource(1, 24, "14G") if $conf->{blast_type} =~ /blast\+/i;
    
    $B->addAction("export BLASTDB=$outputDir");
    $self->addStandardEnv($B);

    if ($conf->{blast_type} eq "blast") {
        if ($self->getSerialScript()) {
            my $scriptDir = $outputDir;
            open my $fh, ">", "$scriptDir/blast.sh";
            print $fh "#!/bin/bash\n";
            $self->addStandardEnv(sub { $fh->print(shift); });
            print $fh "blastall -p blastp -d $outputDir/database -m 8 -e $evalue -b $blasthits -o $conf->{blast_output_dir}/blastout-\$1.fa.tab -i $conf->{frac_dir}/fracfile-\$1.fa\n";
            close $fh;
            chmod 0755, "$scriptDir/blast.sh";
            $B->addAction("echo {1..$np} | xargs -n 1 -P $np $scriptDir/blast.sh");
        } else {
            $B->addAction("blastall -p blastp -i $conf->{frac_dir}/fracfile-{JOB_ARRAYID}.fa -d $outputDir/database -m 8 -e $evalue -b $blasthits -o $conf->{blast_output_dir}/blastout-\${PBS_ARRAY_INDEX}.fa.tab");
        }
    } elsif ($conf->{blast_type} eq "blast+") {
        map { $B->addAction($_); } $self->getEnvironment("est-blast+");
        $B->addAction("blastp -query $conf->{filt_seq_file} -num_threads $np -db $outputDir/database -gapopen 11 -gapextend 1 -comp_based_stats 2 -use_sw_tback -outfmt \"6\" -max_hsps 1 -num_descriptions $blasthits -num_alignments $blasthits -out $conf->{blast_final_file} -evalue $evalue");
    } elsif ($conf->{blast_type} eq "blast+simple") {
        map { $B->addAction($_); } $self->getEnvironment("est-blast+");
        $B->addAction("blastp -query $conf->{filt_seq_file} -num_threads $np -db $outputDir/database -outfmt \"6\" -num_descriptions $blasthits -num_alignments $blasthits -out $conf->{blast_final_file} -evalue $evalue");
    } elsif ($conf->{blast_type} eq "diamond") {
        map { $B->addAction($_); } $self->getEnvironment("est-diamond");
        $B->addAction("diamond blastp -p 24 -e $evalue -k $blasthits -C $blasthits -q $conf->{filt_seq_file} -d $outputDir/database -a $conf->{blast_output_dir}/blastout.daa");
        $B->addAction("diamond view -o $conf->{blast_final_file} -f tab -a $conf->{blast_output_dir}/blastout.daa");
    } elsif ($conf->{blast_type} eq "diamondsensitive") {
        map { $B->addAction($_); } $self->getEnvironment("est-diamond");
        $B->addAction("diamond blastp --sensitive -p 24 -e $evalue -k $blasthits -C $blasthits -q $conf->{frac_dir}/fracfile-{JOB_ARRAYID}.fa -d $outputDir/database -a $conf->{blast_output_dir}/blastout.daa");
        $B->addAction("diamond view -o $conf->{blast_final_file} -f tab -a $conf->{blast_output_dir}/blastout.daa");
    } else {
        die "Blast control not set properly.  Can only be blast, blast+, or diamond.\n";
    }
    $B->addAction("OUT=\$?");
    $B->addAction("if [ \$OUT -ne 0 ]; then");
    $B->addAction("    echo \"BLAST failed; likely due to file format.\"");
    $B->addAction("    echo \$OUT > $outputDir/blast.failed");
    $B->addAction("    exit 1");
    $B->addAction("fi");

    return $B;
}


########################################################################################################################
# Join all the blast outputs back together
sub getCatJob {
    my $self = shift;
    my $conf = $self->{conf}->{generate};

    my $outputDir = $self->getOutputDir();

    my $B = $self->getBuilder();
    $self->requestResources($B, 1, 1, $self->getMemorySize("catjob"));
    $self->addStandardEnv($B);

    $B->addAction("cat $conf->{blast_output_dir}/blastout-*.tab |grep -v '#'|cut -f 1,2,3,4,12 >$conf->{blast_final_file}")
        if $conf->{blast_type} eq "blast";
    $B->addAction("SZ=`stat -c%s $conf->{blast_final_file}`");
    $B->addAction("if [[ \$SZ == 0 ]]; then");
    $B->addAction("    echo \"BLAST Failed. Check input file.\"");
    $B->addAction("    touch $outputDir/blast.failed");
    $B->addAction("    exit 1");
    $B->addAction("fi");

    return $B;
}


########################################################################################################################
# Remove like vs like and reverse matches
sub getBlastReduceJob {
    my $self = shift;
    my $conf = $self->{conf}->{generate};

    my $outputDir = $self->getOutputDir();
    my $toolPath = $self->getToolPath();
    my $sortdir = $self->getScratchDir();

    my $B = $self->getBuilder();
    # Bounces to high memory queue automatically
    $self->requestResources($B, 1, 1, $self->getMemorySize("blastreduce"));
    $self->addStandardEnv($B);

    $B->addAction("$toolPath/alphabetize_blast_output.pl -in $conf->{blast_final_file} -out $outputDir/alphabetized.blastfinal.tab -fasta $conf->{filt_seq_file}");
    $B->addAction("sort -T $sortdir -k1,1 -k2,2 -k5,5nr -t\$\'\\t\' $outputDir/alphabetized.blastfinal.tab > $outputDir/sorted.alphabetized.blastfinal.tab");
    $B->addAction("$toolPath/reduce_blast_output.pl -blast $outputDir/sorted.alphabetized.blastfinal.tab -out $outputDir/unsorted.1.out");
    $B->addAction("sort -T $sortdir -k5,5nr -t\$\'\\t\' $outputDir/unsorted.1.out >$outputDir/1.out");

    return $B;
}


########################################################################################################################
# If multiplexing is on, demultiplex sequences back so all are present
sub getDemuxJob {
    my $self = shift;
    my $conf = $self->{conf}->{generate};

    my $outputDir = $self->getOutputDir();
    my $toolPath = $self->getToolPath();
    
    my $normalCdHit = ($conf->{cdhit_seq_id_threshold} == 1 and $conf->{cdhit_length_diff} == 1);
    my $B = $self->getBuilder();
    $self->requestResources($B, 1, 1, $self->getMemorySize("demux"));
    $self->addStandardEnv($B);

    if ($conf->{multiplex} and $normalCdHit and not $conf->{no_demux}) {
        $B->addAction("mv $outputDir/1.out $outputDir/mux.out");
        $B->addAction("$toolPath/demux.pl -blastin $outputDir/mux.out -blastout $outputDir/1.out -cluster $conf->{filt_seq_file}.clstr");
    } else {
        $B->addAction("mv $outputDir/1.out $outputDir/mux.out");
        $B->addAction("$toolPath/remove_duplicates.pl -in $outputDir/mux.out -out $outputDir/1.out");
    }

    return $B;
}


########################################################################################################################
# Compute convergence ratio
sub getConvergenceRatioJob {
    my $self = shift;
    my $conf = $self->{conf}->{generate};

    my $outputDir = $self->getOutputDir();
    my $toolPath = $self->getToolPath();

    my $B = $self->getBuilder();
    $self->requestResources($B, 1, 1, $self->getMemorySize("conv_ratio"));
    $self->addStandardEnv($B);

    $B->addAction("$toolPath/calc_blast_stats.pl -edge-file $outputDir/1.out -seq-file $conf->{all_seq_file} -unique-seq-file $conf->{filt_seq_file} -seq-count-output $conf->{seq_count_file}");

    return $B;
}


########################################################################################################################
# Create information for R to make graphs and then have R make them
sub getGraphJob {
    my $self = shift;
    my $conf = $self->{conf}->{generate};

    my $resultsDir = $self->getResultsDir();
    my $outputDir = $self->getOutputDir();
    my $toolPath = $self->getToolPath();
    my $jobId = $self->getJobId();
    my $domain = $self->{conf}->{domain} ? "on" : "off";
    my $unirefVersion = $self->{conf}->{family}->{uniref_version};

    my $B = $self->getBuilder();

    my ($smallWidth, $smallHeight) = (700, 315);
    
    $B->mailEnd();
    $B->setScriptAbortOnError(0); # don't abort on error
    $self->addStandardEnv($B);

    if ($conf->{graph_version} == 1) {
        my $evalueFile = "$outputDir/evalue.tab";
        my $defaultLengthFile = "$outputDir/length.tab";

        $self->requestResources($B, 1, 1, $self->getMemorySize("graphs"));

        map { $B->addAction($_); } $self->getEnvironment("est-graphs");
        $B->addAction("mkdir -p $outputDir/rdata");
        # Lengths are retrieved in a previous step.
        $B->addAction("$toolPath/make_graph_data.pl -blastout $outputDir/1.out -rdata  $outputDir/rdata -edges  $outputDir/edge.tab -fasta  $conf->{all_seq_file} -incfrac $conf->{inc_frac} -evalue-file $evalueFile");
        $B->addAction("FIRST=`ls $outputDir/rdata/perid* 2>/dev/null | head -1`");
        $B->addAction("if [ -z \"\$FIRST\" ]; then");
        $B->addAction("    echo \"Graphs failed, there were no edges. Continuing without graphs.\"");
        $B->addAction("    touch $outputDir/graphs.failed");
        $B->addAction("    touch  $outputDir/1.out.completed");
        $B->addAction("    exit 0 #Exit with no error");
        $B->addAction("fi");
        $B->addAction("FIRST=`head -1 \$FIRST`");
        $B->addAction("LAST=`ls $outputDir/rdata/perid*| tail -1`");
        $B->addAction("LAST=`head -1 \$LAST`");
        $B->addAction("MAXALIGN=`head -1 $outputDir/rdata/maxyal`");
        $B->addAction("Rscript $toolPath/R/quart-align.r legacy $outputDir/rdata $resultsDir/alignment_length.png \$FIRST \$LAST \$MAXALIGN $jobId");
        $B->addAction("Rscript $toolPath/R/quart-align.r legacy $outputDir/rdata $resultsDir/alignment_length_sm.png \$FIRST \$LAST \$MAXALIGN $jobId $smallWidth $smallHeight");
        $B->addAction("Rscript $toolPath/R/quart-perid.r legacy $outputDir/rdata $resultsDir/percent_identity.png \$FIRST \$LAST $jobId");
        $B->addAction("Rscript $toolPath/R/quart-perid.r legacy $outputDir/rdata $resultsDir/percent_identity_sm.png \$FIRST \$LAST $jobId $smallWidth $smallHeight");
        $B->addAction("Rscript $toolPath/R/hist-edges.r legacy $outputDir/edge.tab $resultsDir/number_of_edges.png $jobId");
        $B->addAction("Rscript $toolPath/R/hist-edges.r legacy $outputDir/edge.tab $resultsDir/number_of_edges_sm.png $jobId $smallWidth $smallHeight");
        my %lenFiles = ($conf->{len_uniprot_file} => {title => "", file => "length_histogram_uniprot"});
        $lenFiles{$conf->{len_uniprot_file}}->{title} = "UniProt, Full Length" if $unirefVersion or $domain eq "on";
        $lenFiles{$conf->{len_uniprot_dom_file}} = {title => "UniProt, Domain", file => "length_histogram_uniprot_domain"} if $domain eq "on";
        $lenFiles{$conf->{len_uniref_file}} = {title => "UniRef$unirefVersion Cluster IDs, Full Length", file => "length_histogram_uniref"} if $unirefVersion;
        $lenFiles{$conf->{len_uniref_dom_file}} = {title => "UniRef$unirefVersion Cluster IDs, Domain", file => "length_histogram_uniref_domain"} if $unirefVersion and $domain eq "on";
        foreach my $file (keys %lenFiles) {
            my $title = $lenFiles{$file}->{title} ? "\"(" . $lenFiles{$file}->{title} . ")\"" : "\"\"";
            $B->addAction("Rscript $toolPath/R/hist-length.r legacy $file $resultsDir/$lenFiles{$file}->{file}.png $jobId $title");
            $B->addAction("Rscript $toolPath/R/hist-length.r legacy $file $resultsDir/$lenFiles{$file}->{file}_sm.png $jobId $title $smallWidth $smallHeight");
        }
        my $unirefArg = $unirefVersion ? "--uniref-version $unirefVersion" : "";
        $B->addAction("$toolPath/create_graphs_html_table.pl --results-dir $resultsDir --html-file $resultsDir/graphs.html $unirefArg");
    } else {
        map { $B->addAction($_); } $self->getEnvironment("est-graphs-v2");
        $B->addAction("$toolPath/make_hdf5_graph_data.py -b $outputDir/1.out -f $outputDir/rdata.hdf5 -a $conf->{all_seq_file} -i $conf->{inc_frac}");
        $B->addAction("Rscript $toolPath/R/quart-align.r hdf5 $outputDir/rdata.hdf5 $resultsDir/alignment_length.png $jobId");
        $B->addAction("Rscript $toolPath/R/quart-align.r hdf5 $outputDir/rdata.hdf5 $resultsDir/alignment_length_sm.png $jobId $smallWidth $smallHeight");
        $B->addAction("Rscript $toolPath/R/quart-perid.r hdf5 $outputDir/rdata.hdf5 $resultsDir/percent_identity.png $jobId");
        $B->addAction("Rscript $toolPath/R/quart-perid.r hdf5 $outputDir/rdata.hdf5 $resultsDir/percent_identity_sm.png $jobId $smallWidth $smallHeight");
        $B->addAction("Rscript $toolPath/R/hist-length.r hdf5 $outputDir/rdata.hdf5 $resultsDir/length_histogram.png $jobId");
        $B->addAction("Rscript $toolPath/R/hist-length.r hdf5 $outputDir/rdata.hdf5 $resultsDir/length_histogram_sm.png $jobId $smallWidth $smallHeight");
        $B->addAction("Rscript $toolPath/R/hist-edges.r hdf5 $outputDir/rdata.hdf5 $resultsDir/number_of_edges.png $jobId");
        $B->addAction("Rscript $toolPath/R/hist-edges.r hdf5 $outputDir/rdata.hdf5 $resultsDir/number_of_edges_sm.png $jobId $smallWidth $smallHeight");
    }
    $B->addAction("touch  $outputDir/1.out.completed");

    return $B;
}


1;

