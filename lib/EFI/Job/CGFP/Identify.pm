
package EFI::Job::CGFP::Identify;

use strict;
use warnings;

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use lib dirname(abs_path(__FILE__)) . "/../../../";

use parent qw(EFI::Job::CGFP);

use Getopt::Long qw(:config pass_through);

use constant JOB_TYPE => "cgfp-identify";


sub new {
    my $class = shift;
    my %args = @_;

    my $self = $class->SUPER::new(%args);

    my $parms = {};
    my $result = GetOptions(
        $parms,
        "min-seq-len=i",
        "max-seq-len=i",
        "search-type=s",
        "cdhit-sid=i",
        "cons-thresh=i",
        "ref-db=s",
        "diamond-sens=s",
        "parent-job-id=i",
    );

    my $conf = $self->{conf}->{sb}; # Already exists
    my $err = validateOptions($parms, $conf);
    
    push @{$self->{startup_errors}}, $err if $err;

    if (not $err) {
        setupDefaults($self, $conf);
    }
    
    $self->{TYPE} = JOB_TYPE;

    return $self;
}


sub validateOptions {
    my $parms = shift;
    my $conf = shift;

    $conf->{min_seq_len} = $parms->{"min-seq-len"} // 0;
    $conf->{max_seq_len} = $parms->{"max-seq-len"} // 0;
    $conf->{search_type} = $parms->{"search-type"} // "";
    $conf->{cdhit_sid} = $parms->{"cdhit-sid"} // "";
    $conf->{cons_thresh} = $parms->{"cons-thresh"} // "";
    $conf->{ref_db} = $parms->{"ref-db"} // "uniprot";
    $conf->{diamond_sens} = $parms->{"diamond-sens"} // "";

    $conf->{cdhit_sid} = substr($conf->{cdhit_sid} / 100, 0, 4) if $conf->{cdhit_sid} and $conf->{cdhit_sid} > 1;
    $conf->{cons_thresh} = substr($conf->{cons_thresh} / 100, 0, 4) if $conf->{cons_thresh} and $conf->{cons_thresh} > 1;
    $conf->{ref_db} = ($conf->{ref_db} ne "uniref90" and $conf->{ref_db} ne "uniref50") ? "uniprot" : $conf->{ref_db};

    return "";
}


sub setupDefaults {
    my $self = shift;
    my $conf = shift;

    my $srcDir = $conf->{identify_src_dir}; # read stuff from here (which is the parent identify job) for child jobs
    my $realDir = $conf->{identify_real_dir}; # output goes here both for regular and child jobs

    $conf->{ssn_error_dir} = $realDir;
    $conf->{ssn_accession_file} = "$realDir/accession";
    $conf->{ssn_sequence_file} = "$srcDir/ssn-sequences.fa";
    $conf->{fasta_file} = "$srcDir/sequences.fa";
    $conf->{sb_output_dir} = "$srcDir/id-temp";
    $conf->{cdhit_file} = "$conf->{sb_output_dir}/clust/clust.faa.clstr";
    $conf->{color_file} = "";
    #$conf->{color_file} = -f "$dbSupport/colors.tab" ? "$dbSupport/colors.tab" : "";
    $conf->{cluster_size_file} = "$realDir/cluster.sizes";
    $conf->{metadata_file} = "$realDir/metadata.tab";
    $conf->{meta_cluster_size_file} = "$realDir/cluster_sizes.tab";
    $conf->{meta_sp_cluster_file} = "$realDir/swissprot_clusters.tab";
    $conf->{meta_sp_single_file} = "$realDir/swissprot_singletons.tab";
    $conf->{ssn_marker} = "$realDir/$conf->{ssn_out_name}";

    if ($conf->{ssn_in} =~ m/\.zip$/) {
        $conf->{zipped_ssn_in} = $conf->{ssn_in};
        $conf->{ssn_in} =~ s/(\.xgmml)?\.zip$/.xgmml/;
    }

    $conf->{use_diamond} = $self->getConfigValue("cgfp", "type") ne "blast";
}


sub getUsage {
    my $self = shift;

    my $showDevSiteOpts = 0;

    my $usage = <<USAGE;
--ssn-in <PATH_TO_SSN_FILE> --ssn-out-name <FILE_NAME> [--min-seq-len #
    --max-seq-len # --search-type diamond|blast --ref-db uniprot|uniref50|uniref90 --cdhit-sid]

    --ssn-in            path to input SSN file (relative or absolute)
    --ssn-out-name      what to name the output xgmml file (not a path)

    --min-seq-len       minimum sequence length to use (to exclude fragments from UniRef90 SSNs)
    --max-seq-len       maximim sequence length to use (to exclude sequences from UniRef90 SSNs)
    --search-type       type of search to use (diamond or blast)
    --cdhit-sid         Sequence identity to use for CD-HIT clustering proteins into families for consensus
                        sequence determination; defaults to ShortBRED's default value
    --cons-thresh       Consensus threshold for assigning AA's in the family alignments to the consensus
                        sequences; defaults to ShortBRED's default value
    --ref-db            Which type of reference database to use (uniprot = full UniProt, uniref50 =
                        UniRef50, uniref90 = UniRef90); default uniprot

ADVANCED OPTIONS
    --diamond-sens      The type of DIAMOND sensitivity to use (normal, sensitive, more-sensitive). If not
                        specified, ShortBRED defaults to sensitive.
    --parent-identify-id    the ID of the parent job (for using previously-computed markers with a new SSN
USAGE
    return $usage;
}


sub getJobInfo {
    my $self = shift;
    my $info = $self->SUPER::getJobInfo();
    my $conf = $self->{conf}->{sb};

    push @$info, [ssn_in => $conf->{ssn_in}];
    push @$info, [ssn_out_name => $conf->{ssn_out_name}];
    push @$info, [min_seq_len => $conf->{min_seq_len}];
    push @$info, [max_seq_len => $conf->{max_seq_len}];
    push @$info, [search_type => $conf->{search_type}];
    push @$info, [cdhit_sid => $conf->{cdhit_sid}];
    push @$info, [cons_thresh => $conf->{cons_thresh}];
    push @$info, [ref_db => $conf->{ref_db}];
    push @$info, [diamond_sens => $conf->{diamond_sens}];

    return $info;
}


sub makeJobs {
    my $self = shift;
    my $conf = $self->{conf}->{sb};
    
    my @jobs;
    my $job;

    my $job1 = $self->getGetClustersJob();
    push @jobs, {job => $job1, deps => [], name => "get_clusters"};

    my $job2 = $self->getFastaJob();
    push @jobs, {job => $job2, deps => [$job1], name => "get_fasta"};

    my $job3 = $self->getIdentifyJob();
    push @jobs, {job => $job3, deps => [$job2], name => "identify"};

    my $job4 = $self->getXgmmlJob();
    push @jobs, {job => $job4, deps => [$job3], name => "make_xgmml"};

    return @jobs;
}


sub getGetClustersJob {
    my $self = shift;
    my $conf = $self->{conf}->{sb};

    # Path to generic EFITools scripts
    my $toolPath = $self->getToolPath();

    my $minSeqLenArg = $conf->{min_seq_len} ? "--min-seq-len $conf->{min_seq_len}" : "";
    my $maxSeqLenArg = $conf->{max_seq_len} ? "--max-seq-len $conf->{max_seq_len}" : "";

    my $B = $self->getBuilder();
    $B->setScriptAbortOnError(0); # grep causes the script to abort if we have set -e in the script.
    $self->requestResources($B, 1, 1, $self->getMemorySize("sb_get_clusters"));
    $self->addStandardEnv($B);

    $B->addAction("$toolPath/unzip_file.pl --in $conf->{zipped_ssn_in} --out $conf->{ssn_in}") if $conf->{zipped_ssn_in};
    $B->addAction("HASCLUSTERNUM=`head -2000 $conf->{ssn_in} | grep -m1 -e \"Cluster Number\" -e \"Singleton Number\"`");
    $B->addAction("if [[ \$HASCLUSTERNUM == \"\" ]]; then");
    $B->addAction("    echo \"ERROR: Cluster Number is not present in SSN\"");
    $B->addAction("    touch $conf->{ssn_error_dir}/ssn_cl_num.failed");
    $B->addAction("    exit 1");
    $B->addAction("fi");
    $B->addAction("$conf->{tool_path}/get_clusters.pl --ssn $conf->{ssn_in} --accession-file $conf->{ssn_accession_file} --cluster-file $conf->{ssn_cluster_file} --sequence-file $conf->{ssn_sequence_file} $minSeqLenArg $maxSeqLenArg");
    # Add this check because we disable set -e above for grep.
    $B->addAction("if [ $? != 0 ]; then");
    $B->addAction("    echo \"ERROR: in get_clusters.pl\"");
    $B->addAction("    exit 1");
    $B->addAction("fi");

    return $B;
}


sub getFastaJob {
    my $self = shift;
    my $conf = $self->{conf}->{sb};

    my $outputDir = $self->getOutputDir();
    my $sequenceDbPath = $self->getBlastDbPath("uniprot");

    my $minSeqLenArg = $conf->{min_seq_len} ? "--min-seq-len $conf->{min_seq_len}" : "";
    my $maxSeqLenArg = $conf->{max_seq_len} ? "--max-seq-len $conf->{max_seq_len}" : "";

    # CD-HIT params
    my $lenDiffCutoff = "1";
    my $seqIdCutoff = "1";
    my $tempAcc = "$conf->{ssn_accession_file}.cdhit100";
    my $tempCluster = "$conf->{ssn_cluster_file}.cdhit100";
    my $sortedAcc = "$conf->{ssn_accession_file}.sorted";
    my $cdhit100Fasta = "$conf->{fasta_file}.cdhit100";

    #######################################################################################################################
    # Get the FASTA files from the database
    
    my $B = $self->getBuilder();
    $self->requestResources($B, 1, 1, $self->getMemorySize("sb_get_fasta"));
    $self->addStandardEnv($B);

    $B->addAction("sort $conf->{ssn_accession_file} > $sortedAcc");
    $B->addAction("$conf->{tool_path}/get_fasta.pl --id-file $sortedAcc --output $conf->{fasta_file} --blast-db $sequenceDbPath $minSeqLenArg $maxSeqLenArg");
    $B->addAction("SZ=`stat -c%s $conf->{ssn_sequence_file}`");
    $B->addAction("if [[ \$SZ != 0 ]]; then");
    $B->addAction("    cat $conf->{ssn_sequence_file}>> $conf->{fasta_file}");
    $B->addAction("fi");
    $B->addAction("cd-hit -c $seqIdCutoff -s $lenDiffCutoff -i $conf->{fasta_file} -o $cdhit100Fasta -M 14900");
    $B->addAction("$conf->{tool_path}/remove_redundant_sequences.pl --id-in $sortedAcc --cluster-in $conf->{ssn_cluster_file} --id-out $tempAcc --cluster-out $tempCluster --cdhit-file $cdhit100Fasta.clstr");
    $B->addAction("mv $conf->{fasta_file} $conf->{fasta_file}.full");
    $B->addAction("mv $conf->{ssn_accession_file} $conf->{ssn_accession_file}.full");
    $B->addAction("mv $conf->{ssn_cluster_file} $conf->{ssn_cluster_file}.full");
    $B->addAction("mv $cdhit100Fasta $conf->{fasta_file}");
    $B->addAction("mv $tempAcc $conf->{ssn_accession_file}");
    $B->addAction("mv $tempCluster $conf->{ssn_cluster_file}");
    $B->addAction("SZ=`stat -c%s $conf->{ssn_accession_file}`");
    $B->addAction("if [[ \$SZ == 0 ]]; then");
    $B->addAction("    echo \"Unable to find any FASTA sequences. Check input file.\"");
    $B->addAction("    touch $outputDir/get_fasta.failed");
    $B->addAction("    exit 1");
    $B->addAction("fi");

    return $B;
}


sub getIdentifyJob {
    my $self = shift;
    my $conf = $self->{conf}->{sb};
    
    my $np = $self->getNodeNp();
    my $seqDbPath = $conf->{use_diamond} ? $self->getDiamondDbPath($conf->{ref_db}) : $self->getBlastDbPath($conf->{ref_db});

    #######################################################################################################################
    # Run ShortBRED-Identify

    my $sbAppRepo = $self->getShortBREDRepo();
    my $sbIdentifyApp = "$sbAppRepo/shortbred_identify.py";

    my $searchTypeArg = "";
    $searchTypeArg = "--search_program diamond" if not $conf->{use_diamond} and $conf->{search_type} eq "diamond";
    $searchTypeArg = "--search_program blast" if $conf->{use_diamond} and $conf->{search_type} eq "blast";
    my $cdhitSidArg = $conf->{cdhit_sid} ? "--clustid $conf->{cdhit_sid}" : "";
    my $consThreshArg = $conf->{cons_thresh} ? "--consthresh $conf->{cons_thresh}" : "";
    my $diamondSensArg = ($conf->{use_diamond} and $conf->{diamond_sens}) ? "--diamond-sensitivity $conf->{diamond_sens} " : "";
    
    my $B = $self->getBuilder();
    $self->requestResources($B, 1, $np, $self->getMemorySize("sb_identify"));
    $self->addStandardEnv($B);

    $B->addAction("python $sbIdentifyApp --threads $np --goi $conf->{fasta_file} --refdb $seqDbPath --markers $conf->{sb_marker_file} --tmp $conf->{sb_output_dir} $searchTypeArg $cdhitSidArg $consThreshArg $diamondSensArg");

    return $B;
}


sub getXgmmlJob {
    my $self = shift;
    my $conf = $self->{conf}->{sb};

    #######################################################################################################################
    # Build the XGMML file with the marker attributes added
    
    my @metaParams = ("--ssn $conf->{ssn_in}", "--cluster $conf->{ssn_cluster_file}", "--metadata $conf->{metadata_file}",
                      "--cluster-size $conf->{meta_cluster_size_file}", "--swissprot-cluster $conf->{meta_sp_cluster_file}", "--swissprot-single $conf->{meta_sp_single_file}");
    if (not $conf->{parent_id}) {
        push(@metaParams, "--sequence-full $conf->{fasta_file}.full", "--accession-unique $conf->{ssn_accession_file}", "--cdhit-sb $conf->{cdhit_file}",
                          "--markers $conf->{sb_marker_file}", "--accession-full $conf->{ssn_accession_file}.full");
    } else {
        push(@metaParams, "--accession-full $conf->{ssn_accession_file}");
    }
    
    my $colorFileArg = $conf->{color_file} ? "--color-file $conf->{color_file}" : "";
    my $B = $self->getBuilder();
    $self->requestResources($B, 1, 1, $self->getMemorySize("sb_xgmml"));
    $self->addStandardEnv($B);

    $B->addAction("$conf->{tool_path}/create_metadata.pl " . join(" ", @metaParams));
    $B->addAction("$conf->{tool_path}/make_cdhit_table.pl --cdhit-file $conf->{cdhit_file} --cluster-map $conf->{ssn_cluster_file} --table-file $conf->{cdhit_table_file} $colorFileArg");
    $B->addAction("$conf->{tool_path}/make_ssn.pl --ssn-in $conf->{ssn_in} --ssn-out $conf->{ssn_marker} --marker-file $conf->{sb_marker_file} --cluster-map $conf->{ssn_cluster_file} --cdhit-file $conf->{cdhit_table_file}");
    $B->addAction("zip -j $conf->{ssn_marker}.zip $conf->{ssn_marker}");
    # We keep this around in case another Identify job can use the results
    #if ($self->getRemoveTemp()) {
    #    $B->addAction("rm -rf $conf->{sb_output_dir}");
    #}
    $B->addAction("touch $conf->{identify_real_dir}/$self->{completed_name}");

    return $B;
}


1;

