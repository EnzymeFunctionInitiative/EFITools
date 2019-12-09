
package EFI::Job::EST::Analyze;

use strict;
use warnings;

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use lib dirname(abs_path(__FILE__)) . "/../../../";

use parent qw(EFI::Job::EST);

use Getopt::Long qw(:config pass_through);

use EFI::Config;

use constant JOB_TYPE => "analyze";


sub new {
    my $class = shift;
    my %args = @_;

    my $self = $class->SUPER::new(%args);

    my $parms = {};
    my $result = GetOptions(
        $parms,
        "filter=s",
        "minval=s",
        "maxlen=i",
        "minlen=i",
        "title=s",
        "maxfull=i",
        "custom-cluster-file=s",
        "custom-cluster-dir=s",
        "parent-id=s",
        "parent-dir=s",
        "include-sequences",
        "uniref-version=s",
        "use-anno-spec",
        "use-min-edge-attr",
    );

    my $conf = {};
    my $err = validateOptions($parms, $conf);
    push @{$self->{startup_errors}}, $err if $err;

    $self->setupDefaults($conf);

    my $flagFile = $self->getOutputDir() . "/1.out.completed";
    push @{$self->{startup_errors}}, "Output directory and results must exist to run analyze." if not -f $flagFile;

    $self->{conf}->{analyze} = $conf;

    return $self;
}


sub getJobType {
    my $self = shift;
    return JOB_TYPE;
}
sub getUseResults {
    my $self = shift;
    return 1;
}


sub getUsage {
    my $self = shift;
    my $usage = <<USAGE;
--minval ALIGNMENT_SCORE [--filter eval|bit --minlen MIN_SEQ_LEN --maxlen MAX_SEQ_LEN
    --title "<TITLE>" --uniref-version 90|50]

    --minval            minimum alignment score to use for separating nodes into clusters
    --filter            eval = group on alignment score; bit = group on bitscore
    --minlen            minimum sequence length to include node in network
    --maxlen            maximum sequence length to include node in network
    --title             title of the file; goes into the filename; defaults to Untitled
    --uniref-version    this should be set if the generate step was created using
                        UniRef settings
USAGE
    return $usage;
}


sub addStandardEnv {
    my $self = shift;
    my $B = shift;

    my @mods = $self->getEnvironment("est-std");
    map { $B->addAction($_); } @mods;
}


sub validateOptions {
    my $parms = shift;
    my $conf = shift;

    my $defaultMaxLen = 50000;
    my $defaultFilter = "eval";
    my $defaultTitle = "Untitled";
    my $defaultMaxfull = 10000000;

    $conf->{filter} = $parms->{"filter"} // $defaultFilter;
    $conf->{minval} = $parms->{"minval"} // 0;
    $conf->{maxlen} = $parms->{"maxlen"} // $defaultMaxLen;
    $conf->{minlen} = $parms->{"minlen"} // 0;
    $conf->{title} = $parms->{"title"} // $defaultTitle;
    $conf->{maxfull} = $parms->{"maxfull"} // $defaultMaxfull;
    $conf->{custom_cluster_file} = $parms->{"custom-cluster-file"} // "";
    $conf->{custom_cluster_dir} = $parms->{"custom-cluster-dir"} // "";
    $conf->{parent_id} = $parms->{"parent-id"} // 0;
    $conf->{parent_dir} = $parms->{"parent-dir"} // "";
    $conf->{include_sequences} = defined $parms->{"include-sequences"} ? 1 : 0;
    $conf->{uniref_version} = $parms->{"uniref-version"} // 0;
    $conf->{use_anno_spec} = defined $parms->{"use-anno-spec"} ? 1 : 0;
    $conf->{use_min_edge_attr} = defined $parms->{"use-min-edge-attr"} ? 1 : 0;

    return "--minval argument is required" if not $conf->{minval};
}


sub setupDefaults {
    my $self = shift;
    my $conf = shift;

    my $generateDir = $self->getOutputDir();
    my $jobId = $self->getJobId();

    ($conf->{file_name} = $conf->{title}) =~ s/[^A-Za-z0-9_\-]/_/g;
    $conf->{file_name} .= "_";
    $conf->{file_name} = $jobId . "_" . $conf->{file_name} if $jobId; 

    $conf->{has_parent} = ($conf->{parent_id} and -d $conf->{parent_dir});

    $conf->{output_dir} = "$generateDir/$conf->{filter}-$conf->{minval}-$conf->{minlen}-$conf->{maxlen}";
    $conf->{output_dir} .= "-$conf->{minn}" if $conf->{use_anno_spec};
    $conf->{output_dir} .= "-$conf->{mine}" if $conf->{use_min_edge_attr};

    $conf->{blast_file} = "$conf->{output_dir}/2.out";
    $conf->{anno_file} = "$conf->{output_dir}/struct.filtered.out";
    $conf->{meta_file} = "$generateDir/" . EFI::Config::FASTA_META_FILENAME;
    $conf->{anno_spec_file} = "$generateDir/" . EFI::Config::ANNOTATION_SPEC_FILENAME;

    $conf->{has_domain} = checkForDomain("$generateDir/1.out");

    if (-f "$generateDir/database_version") {
        $conf->{dbver} = `head -1 $generateDir/database_version`;
        chomp $conf->{dbver};
    }

    if (not $conf->{dbver}) {
        my @p = split(m/\//, $self->{db}->{name});
        ($conf->{dbver} = $p[$#p]) =~ s/\D//g;
    }
}


sub createJobs {
    my $self = shift;

    my $S = $self->getScheduler();
    die "Need scheduler" if not $S;

    my @jobs;
    my $B;
    my $job;

    my $job1 = $self->createGetAnnotationsJob($S);
    push @jobs, {job => $job1, deps => [], name => "get_annotations"};

    my $job2 = $self->createFilterBlastJob($S);
    push @jobs, {job => $job2, deps => [$job1], name => "filter_blast"};

    my $job3 = $self->createFullXgmmlJob($S);
    push @jobs, {job => $job3, deps => [$job2], name => "full_xgmml"};

    my $job4 = $self->createRepNodeXgmmlJob($S);
    push @jobs, {job => $job4, deps => [$job3], name => "repnode_xgmml"};

    my $job5 = $self->createStatsJob($S);
    push @jobs, {job => $job5, deps => [{obj => $job4, is_job_array => 1}], name => "stats"};

    return @jobs;
}


####################################################################################################
# RETRIEVE ANNOTATIONS (STRUCT.OUT) FOR SSN
# And for UniRef inputs, filter out UniRef cluster members that are outside the input length
# thresholds.
sub createGetAnnotationsJob {
    my $self = shift;
    my $S = shift;
    my $conf = $self->{conf}->{analyze};

    my $configFile = $self->getConfigFile();
    my $toolPath = $self->getToolPath();
    my $generateDir = $self->getOutputDir();

    my $B = $S->getBuilder();
    $B->resource(1, 1, "5gb");

    #TODO: right now if you useAnnoSpec, we actually just include the bare minimum.  In the future allow the user to determine which annotations to include.
    if ($conf->{use_anno_spec}) {
        open SPEC, ">", $conf->{anno_spec_file};
        print SPEC <<ANNO;
Sequence_Length
Organism
Superkingdom
Description
ANNO
        close SPEC;
    }

    my $userHeaderFileOption = "--meta-file $conf->{meta_file}";
    my $annoSpecOption = $conf->{use_anno_spec} ? "--anno-spec-file $conf->{anno_spec_file}" : "";
    my $unirefOption = $conf->{uniref_version} ? "--uniref-version $conf->{uniref_version}" : "";
    my $lenArgs = "--min-len $conf->{minlen} --max-len $conf->{maxlen}";
    # Don't filter out UniRef cluster members if this is a domain job.
    $lenArgs = "" if $conf->{has_domain};
    my $annoDep = 0;

    $self->addStandardEnv($B);
    $self->addDatabaseEnvVars($B) if not $configFile;
    $B->addAction("$toolPath/get_annotations.pl --out $conf->{anno_file} $unirefOption $lenArgs $userHeaderFileOption $annoSpecOption --config $configFile");

    return $B;
}


sub createFilterBlastJob {
    my $self = shift;
    my $S = shift;
    my $conf = $self->{conf}->{analyze};

    my $configFile = $self->getConfigFile();
    my $toolPath = $self->getToolPath();
    my $generateDir = $self->getOutputDir();

    my $B = $S->getBuilder();
    $B->resource(1, 1, "5gb");

    $self->addStandardEnv($B);

    if ($conf->{custom_cluster_dir} and $conf->{custom_cluster_file}) {
        $B->addAction("$toolPath/filter_ssn_seq_custom.pl --blastin $generateDir/1.out --blastout $conf->{blast_file} --custom-cluster-file $conf->{output_dir}/$conf->{custom_cluster_file}");
        $B->addAction("cp $generateDir/allsequences.fa $conf->{output_dir}/sequences.fa");
    } else {
        my $domMetaArg = ($conf->{uniref_version} and $conf->{has_domain}) ? "--domain-meta $conf->{anno_file}" : "";
        $B->addAction("$toolPath/filter_ssn_seq_blast_results.pl --blastin $generateDir/1.out --blastout $conf->{blast_file} --fastain $generateDir/allsequences.fa --fastaout $conf->{output_dir}/sequences.fa --filter $conf->{filter} --minval $conf->{minval} --maxlen $conf->{maxlen} --minlen $conf->{minlen} $domMetaArg");
    }
    if ($conf->{has_parent}) {
        $B->addAction("cp $conf->{parent_dir}/*.png $generateDir/");
    }

    return $B;
}


sub createFullXgmmlJob {
    my $self = shift;
    my $S = shift;
    my $conf = $self->{conf}->{analyze};

    my $configFile = $self->getConfigFile();
    my $toolPath = $self->getToolPath();

    my $outFile = "$conf->{output_dir}/$conf->{file_name}full_ssn.xgmml";
    my $seqsArg = $conf->{include_sequences} ? "--include-sequences" : "";
    my $useMinArg = $conf->{use_min_edge_attr} ? "--use-min-edge-attr" : "";

    my $B = $S->getBuilder();
    $B->resource(1, 1, "10gb");

    $self->addStandardEnv($B);

    $B->addAction("$toolPath/make_full_ssn.pl --blast $conf->{blast_file} --fasta $conf->{output_dir}/sequences.fa --struct $conf->{anno_file} --out $outFile --title=\"$conf->{title}\" --maxfull $conf->{maxfull} --dbver $conf->{dbver} $seqsArg $useMinArg");
    $B->addAction("zip -j $outFile.zip $outFile");

    return $B;
}


sub createRepNodeXgmmlJob {
    my $self = shift;
    my $S = shift;
    my $conf = $self->{conf}->{analyze};

    my $configFile = $self->getConfigFile();
    my $toolPath = $self->getToolPath();

    my $outFile = "$conf->{output_dir}/$conf->{file_name}repnode-\${CDHIT}_ssn.xgmml";
    my $seqsArg = $conf->{include_sequences} ? "--include-sequences" : "";
    my $useMinArg = $conf->{use_min_edge_attr} ? "--use-min-edge-attr" : "";

    my $B = $S->getBuilder();
    $B->resource(1, 1, "10gb");
    $B->jobArray("40-100:5");
    #$B->jobArray("40,45,50,55,60,65,70,75,80,85,90,95,100");
    $self->addStandardEnv($B);

    $B->addAction("CDHIT=\$(echo \"scale=2; \${PBS_ARRAY_INDEX}/100\" |bc -l)");
    
    $B->addAction("cd-hit -n 2 -s 1 -i $conf->{output_dir}/sequences.fa -o $conf->{output_dir}/cdhit\$CDHIT -c \$CDHIT -d 0");
    $B->addAction("$toolPath/make_repnode_ssn.pl --blast $conf->{blast_file} --cdhit $conf->{output_dir}/cdhit\$CDHIT.clstr --fasta $conf->{output_dir}/sequences.fa --struct $conf->{anno_file} --out $outFile --title=\"$conf->{title}\" --dbver $conf->{dbver} --maxfull $conf->{maxfull} $seqsArg $useMinArg");
    $B->addAction("zip -j $outFile.zip $outFile");

    return $B;
}


sub createFixJob {
    my $self = shift;
    my $S = shift;
    my $conf = $self->{conf}->{analyze};

    my $configFile = $self->getConfigFile();
    my $toolPath = $self->getToolPath();

    my $B = $S->getBuilder();
    $B->resource(1, 1, "1gb");

    $B->addAction("sleep 5");

    return $B;
}


sub createStatsJob {
    my $self = shift;
    my $S = shift;
    my $conf = $self->{conf}->{analyze};

    my $configFile = $self->getConfigFile();
    my $toolPath = $self->getToolPath();

    my $B = $S->getBuilder();
    $B->resource(1, 1, "5gb");
    
    $self->addStandardEnv($B);

    $B->addAction("sleep 5");
    $B->addAction("$toolPath/calc_ssn_stats.pl -run-dir $conf->{output_dir} -out $conf->{output_dir}/stats.tab");

    return $B;
}


sub createJobStructure {
    my $self = shift;
    my $dir = $self->{conf}->{analyze}->{output_dir};
    mkdir $dir;
    return ($dir, $dir, $dir);
}


sub addAnalyzeEnv {
    my $self = shift;
    my $B = shift;

    my @mods = $self->getEnvironment("est-std");
    map { $B->addAction($_); } @mods;
}


sub checkForDomain {
    my $file = shift;

    open FILE, $file or return 0;
    my $line = <FILE>;
    close FILE;

    return $line =~ m/^\S+:\d+:\d+/;
}


1;

