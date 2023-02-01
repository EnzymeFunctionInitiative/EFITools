
package EFI::JobManager;

use strict;
use warnings;

use JSON;
use Capture::Tiny qw(capture);
use File::Copy;
use Data::Dumper;
use File::Basename;
use File::Path qw(make_path);


my $STATUS_TABLE = "job_info";
my $STATUS_COL = "job_info_status";
my $JOB_ID_COL = "job_info_id";
my $TYPE_COL = "job_info_type";
my $SLURM_ID_COL = "job_info_job_id";
my $MSG_COL = "job_info_msg";
my $UPDATE_TIME_COL = "job_info_time_updated";

my $S_RUNNING = "RUNNING";
my $S_NEW = "NEW";
my $S_FINISH = "FINISH";
my $S_ERROR = "FAILED";


use EFI::JobManager::Types;
use EFI::JobManager::Info;

use constant D_FINISH => 1;
use constant D_SHOW_NEW => 2;
use constant D_CREATE_NEW => 3;

use Exporter qw(import);
our @EXPORT = qw(D_FINISH D_SHOW_NEW D_CREATE_NEW);



sub new {
    my $class = shift;
    my %args = @_;

    my @types = EFI::JobManager::Types::get_all_types();
    my $info = new EFI::JobManager::Info(config => $args{config}, dbh => $args{dbh});
    #foreach my $type (@types) {
    #    $info->addType($type);
    #}

    my $self = {
        debug => $args{debug},
        dbh => $args{dbh},
        config => $args{config}, 
        info => $info,
        types => \@types,
    };
    bless $self, $class;

    return $self;
}


sub checkForFinish {
    my $self = shift;
    foreach my $type (@{ $self->{types} }) {
        $self->checkForJobFinish($self->{info}->getTypeData($type));
    }
}


sub checkForJobFinish {
    my $self = shift;
    my $jobTypeInfo = shift;
    my $dbh = $self->{dbh};

    my $tableName = $jobTypeInfo->getTableName();
    my $jobType = $jobTypeInfo->getType();

    $self->log("Checking for job completion for $jobType");

    my $sql = "SELECT * FROM $STATUS_TABLE WHERE $STATUS_COL = '$S_RUNNING' AND $TYPE_COL = ?";

    my $sth = $dbh->prepare($sql);
    $sth->execute($jobType);

    while (my $row = $sth->fetchrow_hashref) {
        my $slurmId = $row->{$SLURM_ID_COL};
        my $jobId = $row->{$JOB_ID_COL};
        my $finishFile = $jobTypeInfo->getFinishFile($jobId, 1);

        $self->log("\t$slurmId, $jobId, $finishFile");
        next if $self->isJobRunning($slurmId);

        $self->log("\tJob has stopped running $finishFile");

        my $jobStatus = -f $finishFile ? $S_FINISH : $S_ERROR;

        $self->log("\tJob state: $jobStatus");

        $self->setDbStatusVal($jobId, $tableName, undef, $jobStatus, undef);
    }
}


sub isJobRunning {
    my $self = shift;
    my $slurmId = shift;

    my @args = ("/usr/bin/squeue", "-h", "-o", "%A,%j,%t,%N,%M,%P", "-p", $self->{config}->{queue}.",".$self->{config}->{mem_queue});
    #$self->log("\t" . join(" ", @args));
    my ($output, $error) = capture {
        system(@args);
    };
    die "Can't run " . join(" ", @args) . " : $error" if $error;
    my @res = split(m/\n/s, $output);
    if (grep(m/^$slurmId,/, @res)) {
        return 1;
    } else {
        return 0;
    }
}
 

sub processNewJobs {
    my $self = shift;
    my $dbh = $self->{dbh};

    # Debug level == finish means we only check if the jobs have finished
    return if ($self->{debug} and $self->{debug} < D_SHOW_NEW);

    #my @tables = (TYPE_GENERATE, TYPE_ANALYSIS, TYPE_GNN, TYPE_GND);

    #foreach my $table (@tables) {
    {
        my $sql = "SELECT * FROM job_info WHERE job_info_status = '$S_NEW'";
        my $sth = $dbh->prepare($sql);
        $sth->execute;
        while (my $row = $sth->fetchrow_hashref) {
            my $jobId = $row->{job_info_id};
            my $jobType = $row->{job_info_type};
            my $typeCol = "${jobType}_type";
            my $jobTable = $jobType;
            my $idCol = "${jobType}_id";

            $self->log("Processing $jobId / $jobType");

            ## Now we need to check if it's already running, failed, or been run.  It will exist in the
            ## job_info table in some form or another if that's the case.
            #my $c_sql = "SELECT * FROM job_info WHERE job_info_type = '$jobTable' AND job_info_id = ?";
            #my $c_sth = $dbh->prepare($c_sql);
            #$c_sth->execute($jobId);
            #my $c_row = $c_sth->fetchrow_hashref;
            #next if $c_row;

            my $tSql = $self->getJobTableQuerySql($jobType, $jobTable, $idCol);
            my $sth = $self->{dbh}->prepare($tSql);
            $sth->execute($jobId);
            my $row = $sth->fetchrow_hashref;
            die "Invalid ID for $jobTable / $jobId" if not $row;

            my $info = $self->getJobParameters($jobId, $jobTable, $row);
            warn "Unable to process job $jobId in $jobTable" and next if not $info;

            $self->log(showNewDebug($info)) if $self->{debug} >= D_SHOW_NEW;
            next if $self->{debug} == D_SHOW_NEW;

            #print Dumper($info);
            #die;

            if (not -d $info->{job_dir_path}) {
                make_path($info->{job_dir_path}) or warn "Unable to make dir $info->{job_dir_path}: $!; continuing";
            }

            #if ($info->{source_file} and $info->{target_file}) {
            #    copy($info->{source_file}, $info->{target_file});
            #}

            my $mainScript = $info->{script};

            my $startScript = $info->{job_dir_path} . "/startup_$jobId.sh";
            open my $fh, ">", $startScript;
            if (not $fh) {
                $self->setDbError($jobId, $jobTable, 0, $S_ERROR, $!);
                warn "Unable to write to startup script $startScript: $!";
                next;
            }

            $fh->print($info->{env}, "\n");
            $fh->print("cd $info->{job_dir_path}\n");
            $fh->print(join(" ", $mainScript, @{ $info->{args} }), "\n");
            close $fh;

            print "\t/bin/bash $startScript\n" if $self->{debug} >= D_CREATE_NEW;
            next if $self->{debug} == D_CREATE_NEW;

            my ($output, $error) = capture {
                system("/bin/bash", $startScript);
            };

            print("|$error|\n");
            $self->updateDatabases($jobId, $jobTable, $output, $error);
        }
    }
}


sub updateDatabases {
    my $self = shift;
    my $jobId = shift;
    my $table = shift;
    my $output = shift;
    my $error = shift;

    my $slurmId = 0;
    my $msg = "";
    my $status = $S_ERROR;
    if ($output and not $error) {
        $slurmId = $self->{info}->parseForSlurmId($output);
        $msg = $error ? "JOB STARTUP ERROR: $error" : "";
        $status = $slurmId ? $S_RUNNING : $S_ERROR;
    }

    $self->setDbStatusVal($jobId, $table, $slurmId, $status, $error);
}


sub setDbStatusVal {
    my $self = shift;
    my $jobId = shift;
    my $table = shift;
    my $slurmId = shift;
    my $status = shift;
    my $msg = shift;
    my $dbh = $self->{dbh};

    my ($sec, $min, $hour, $mday, $mon, $year) = localtime(time);
    $mon += 1;
    $year += 1900;
    my $updateTime = sprintf("%04d-%02d-%02d %02d:%02d:%02d", $year, $mon, $mday, $hour, $min, $sec);

    my %updates;
    $updates{$SLURM_ID_COL} = $slurmId if defined $slurmId;
    $updates{$STATUS_COL} = $status if $status;
    $updates{$MSG_COL} = $msg // "";

    my @updateKeys = keys %updates;
    my $sets = join(", ", map { "$_ = ?" } @updateKeys);
    $sets .= ($sets ? ", " : "") . "$UPDATE_TIME_COL = ?";

    my @vals = map { $updates{$_} } @updateKeys;
    push @vals, $updateTime;
    my $sql = "UPDATE $STATUS_TABLE SET $sets WHERE $JOB_ID_COL = ? AND $TYPE_COL = ?";
    $self->log("    Update $jobId/$table with " . join(", ", map { "$_=$updates{$_}" } @updateKeys));
    $dbh->do($sql, undef, @vals, $jobId, $table);
}


sub showNewDebug {
    my $info = shift;
    my $args = join(" ", @{ $info->{args} });
    my $env = join(" && ", split(m/\n/s, $info->{env}));
    my $subType = $info->{sub_type} ? $info->{sub_type} : ""; 
    my $debug = "\ttype => $info->{type}/$subType, job_id => $info->{job_id}, results_dir => $info->{results_dir}, job_dir_path = $info->{job_dir_path}, env => $env\n";
    $debug .= "\t$info->{script} $args\n";
    return $debug;
}


sub makeArgs {
    my $self = shift;
    my $jobId = shift;
    my $type = shift;
    my $row = shift;
    my $info = shift;

    my $numProcessors = 64;
    my $evalue = 5; # TODO
    my $maxSeq = 100000000;
    my $defaultMaxBlastSeq = 1000; # TODO

    my @args;

    if ($type eq TYPE_GENERATE) {
        my $params = decode_json($row->{generate_params});

        my $subType = $row->{generate_type};
        $info->{sub_type} = $subType;

        if ($subType eq TYPE_COLORSSN or $subType eq TYPE_CLUSTER or $subType eq TYPE_CONVRATIO or $subType eq TYPE_NBCONN) {
            my $sourceFile = $self->getUploadFile($type, $jobId, $params, $subType);
            $info->{source_file} = $sourceFile->{file_path};
            my $targetName = getBaseSsnName($params->{generate_fasta_file});

            warn "Unable to generate $subType job because upload file doesn't exist" and next if not $sourceFile;
            push @args, "--ssn-in", $info->{source_file};
            if ($subType eq TYPE_CONVRATIO) {
                push @args, "--file-name", "conv_ratio.txt";
            } else {
                push @args, "--ssn-out", "${jobId}_$targetName.xgmml";
                push @args, "--ssn-out-zip", "ssn.zip";
            }
            push @args, "--large-mem", "--extra-ram", $params->{extra_ram} if $params->{extra_ram};

            if ($subType eq TYPE_COLORSSN) {
                push @args, "--skip-fasta" if $params->{skip_fasta};
            } elsif ($subType eq TYPE_CONVRATIO) {
                push @args, "--ascore", $params->{ascore} if $params->{ascore};
            } elsif ($subType eq TYPE_CLUSTER and $params->{make_hmm}) {
                push @args, "--opt-msa-option", $params->{make_hmm};
                if ($params->{make_hmm} =~ m/CR/) {
                    push @args, "--opt-aa-list", $params->{hmm_aa} if $params->{hmm_aa};
                    push @args, "--opt-aa-threshold", $params->{aa_threshold} if $params->{aa_threshold};
                }
                if ($params->{make_hmm} =~ m/(CR|HMM|WEBLOGO)/) {
                    push @args, "--opt-min-seq-msa", $params->{min_seq_msa} if $params->{min_seq_msa};
                    push @args, "--opt-max-seq-msa", $params->{max_seq_msa} if $params->{max_seq_msa};
                }
            } elsif ($subType eq TYPE_NBCONN) {
            }

            # Shared
            push @args, "--map-dir-name", "'cluster-data'";
            push @args, "--map-file-name", "mapping_table.txt";
            push @args, "--domain-map-file-name", "mapping_table_domain.txt";
            push @args, "--stats", "stats.txt";
            push @args, "--cluster-sizes", "cluster_sizes.txt";
            push @args, "--conv-ratio", "conv_ratio.txt";
            push @args, "--sp-clusters-desc", "swissprot_clusters_desc.txt";
            push @args, "--sp-singletons-desc", "swissprot_singletons_desc.txt";

        } else {
            push @args, ("--old-graphs", "--max-full-family", 1000000);

            print "$subType $jobId\n";
            push @args, "--np", $numProcessors;

            push @args, "--sim", $params->{generate_sequence_identity} if $params->{generate_sequence_identity};
            push @args, "--lengthdif", $params->{generate_length_overlap} if $params->{generate_length_overlap};
            push @args, "--uniref-version", $params->{generate_uniref} if $params->{generate_uniref};
            push @args, "--no-demux", $params->{generate_no_demux} if $params->{generate_no_demux};
            push @args, "--fraction", $params->{generate_fraction} if $params->{generate_fraction};
            push @args, "--evalue", $params->{generate_evalue} if $params->{generate_evalue};
            push @args, "--min-seq-len", $params->{generate_min_seq_len} if $params->{generate_min_seq_len};
            push @args, "--max-seq-len", $params->{generate_max_seq_len} if $params->{generate_max_seq_len};
            push @args, "--exclude-fragments" if $params->{exclude_fragments};
            push @args, "--tax-search", "'$params->{tax_search}'" if $params->{tax_search};
            push @args, "--family-filter", $params->{family_filter} if $params->{family_filter};
            push @args, getDomainArgs($params);
            push @args, getFamilyArgs($params);
            push @args, "--maxsequence", $maxSeq;
            push @args, "--seq-count-file", "acc_counts.txt";

            #if ($subType eq TYPE_TAXONOMY) {
            if ($row->{generate_is_tax_job}) {
                push @args, "--tax-search-only", "--use-fasta-headers";
            }
            if ($subType eq TYPE_ACCESSION) {
                push @args, "--no-match-file", "no_accession_matches.txt";
                my $targetName = "";
                #TODO add domain
                if ($params->{tax_job_id}) {
                    my $taxJobId = $params->{tax_job_id};
                    my $taxTreeId = $params->{tax_tree_id};
                    my $taxIdType = $params->{tax_id_type};
                    my $sourceFile = $self->taxFileExists($type, TYPE_TAXONOMY, $taxJobId, $row);
                    if ($sourceFile) {
                        push @args, "--source-tax", join(",", $taxJobId, $taxTreeId, $taxIdType);
                        $targetName = $sourceFile; # the file that is input into create_generate_job.pl
                    }
                }
                if (not $params->{tax_job_id}) {
                    my $sourceFile = $self->getUploadFile($type, $jobId, $params, $subType, $row);
                    warn "Unable to generate $subType job because upload file doesn't exist" and next if not $sourceFile;
                    $targetName = $sourceFile->{file_path};
                }
                push @args, "--useraccession", $targetName;
            } elsif ($subType eq TYPE_FASTA or $subType eq TYPE_FASTA_ID) {
                if ($subType eq TYPE_FASTA_ID) {
                    push @args, "--use-fasta-headers";
                }
                my $sourceFile = $self->getUploadFile($type, $jobId, $params, $subType, $row);
                warn "Unable to generate $subType job because upload file doesn't exist" and next if not $sourceFile;
                push @args, "--userfasta", $sourceFile->{file_path};
            } elsif ($subType eq TYPE_FAMILIES) {
            } elsif ($subType eq TYPE_BLAST) {
                push @args, "--seq", $params->{generate_blast};
                push @args, "--blast-evalue", $params->{generate_blast_evalue};
                push @args, "--db-type", $params->{blast_db_type} if $params->{blast_db_type};
                push @args, "--nresults", ($params->{generate_blast_max_sequence} ? $params->{generate_blast_max_sequence} : $defaultMaxBlastSeq);
            }
        }
    } elsif ($type eq TYPE_ANALYSIS) {
        my $aDirPath = $self->{info}->getAnalysisDirPath($jobId); # analysis job id
        push @args, "--minlen", $row->{analysis_min_length};
        push @args, "--maxlen", $row->{analysis_max_length};
        push @args, "--minval", $row->{analysis_evalue};
        push @args, "--filter", $row->{analysis_filter};
        push @args, "--title", "'" . $row->{analysis_name} . "'";
        push @args, "--maxfull", $maxSeq;
        push @args, "--generate-job-id", $info->{generate_job_id};
        push @args, "--output-path", $aDirPath; # full path

        # Comes from generate job
        my $genParms = decode_json($row->{generate_params});
        my $unirefVersion = getUniRefVersion($genParms);
        push @args, "--uniref-version", $unirefVersion if $unirefVersion;

        # Comes from generate job
        # If job type is FASTA or FASTA_ID
        if ($row->{generate_type} eq TYPE_FASTA or $row->{generate_type} eq TYPE_FASTA_ID) {
            push @args, "--include-sequences";
            if ($genParms->{include_all_seq}) { # Comes from generate job
                push @args, "--include-all-sequences";
            }
        }

        my $params = decode_json($row->{analysis_params});
        $params = {} if (not $params or ref $params ne "HASH"); # this can happen if there are no values

        push @args, "--use-anno_spec" if $params->{use_min_node_attr};
        push @args, "--use-min-edge-attr" if $params->{use_min_edge_attr};
        push @args, "--compute-nc" if $params->{compute_nc};
        push @args, "--no-repnode" if (exists $params->{build_repnode} and (not $params->{build_repnode} or $params->{build_repnode} eq "false"));
        push @args, "--remove-fragments" if $params->{remove_fragments};

        if ($params->{tax_search}) {
            push @args, "--tax-search", "\"" . $params->{tax_search} . "\"";
            push @args, "--tax-search-hash", $params->{tax_search_hash};
        }

        push @args, "--name", $params->{analysis_name} if $params->{analysis_name};
    } elsif ($type eq TYPE_GND) {
        my $params = decode_json($row->{diagram_params});

        my $subType = $row->{diagram_type};
        my $title = $row->{diagram_title} // "";

        if ($subType eq "DIRECT" or $subType eq "DIRECT_ZIP") {
            my $sourceFile = $self->getUploadFile($type, $jobId, $params, $subType, $row);
            $info->{source_file} = $sourceFile->{file_path};
            push @args, "--zip-file", $info->{source_file};
        } elsif ($subType eq "BLAST") {
            my $seq = $params->{blast_seq} // "";
            $seq =~ s/[\n\r]//gs;
            push @args, "--blast", "\"$seq\"";
            push @args, "--evalue", $params->{evalue} if $params->{evalue};
            push @args, "--seq-db-type", $params->{seq_db_type} if $params->{seq_db_type};
        } elsif ($subType eq "ID_LOOKUP") {
            if ($params->{tax_job_id} and $params->{tax_id_type} and exists $params->{tax_tree_id}) {
                my $sourceFile = $self->taxFileExists(TYPE_GENERATE, TYPE_TAXONOMY, $params->{tax_job_id}, $row);
                if ($sourceFile) {
                    push @args, "--tax-file", $sourceFile, "--tax-id-type", $params->{tax_id_type}, "--tax-tree-id", $params->{tax_tree_id};
                }
            } else {
                my $uploadsDir = $self->{config}->getUploadsDir($type);
                my $sourceFile = "$uploadsDir/$jobId.txt";
                push @args, "--id-file", $sourceFile;
            }
            push @args, "--seq-db-type", $params->{seq_db_type} if $params->{seq_db_type};
        } elsif ($subType eq "FASTA") {
            my $uploadsDir = $self->{config}->getUploadsDir($type);
            my $sourceFile = "$uploadsDir/$jobId.txt";
            push @args, "--fasta-file", $sourceFile;
        }

        push @args, "--output", "$jobId.sqlite";
        push @args, "--title", "\"" . $title . "\"" if $title;
        push @args, "--job-type", $subType;
        push @args, "--nb-size", $params->{neighborhood_size} if ($params and ref $params eq "HASH" and $params->{neighborhood_size});
    } elsif ($type eq TYPE_GNN) {
        my $params = decode_json($row->{gnn_params});
        my $sourceFile = $self->getUploadFile($type, $jobId, $params, "", $row);
        warn "Unable to process $type job because upload file doesn't exist" and return if not $sourceFile;
        $info->{source_file} = $sourceFile->{file_path};
        push @args, "--ssn-in", $info->{source_file};

        my ($fn, $fp, $fx) = fileparse($params->{filename}, ".xgmml", ".xgmml.zip", ".zip");
        my $filename = "${jobId}_$fn";

        my $nameSuffix = "_co$params->{cooccurrence}_ns$params->{neighborhood_size}";

        push @args, "--nb-size", $params->{neighborhood_size};
        push @args, "--cooc", $params->{cooccurrence};
        push @args, "--name", "\"" . $filename . "\"";
        push @args, "--gnn", "${filename}_ssn_cluster_gnn$nameSuffix.xgmml";
        push @args, "--gnn-zip", "ssn_cluster_gnn.zip";
        push @args, "--ssn-out", "${filename}_coloredssn$nameSuffix.xgmml";
        push @args, "--ssn-out-zip", "coloredssn.zip";
        push @args, "--pfam-hub", "${filename}_pfam_family_gnn$nameSuffix.xgmml";
        push @args, "--pfam-hub-zip", "pfam_family_gnn.zip";
        push @args, "--stats", "stats.txt";
        push @args, "--cluster-sizes", "cluster_sizes.txt";
        push @args, "--sp-clusters-desc", "swissprot_clusters_desc.txt";
        push @args, "--sp-singletons-desc", "swissprot_singletons_desc.txt";
        push @args, "--warning-file", "nomatches_noneighbors.txt";
        push @args, "--id-out", "mapping_table.txt";
        push @args, "--id-out-domain", "domain_mapping_table.txt";
        push @args, "--extra-ram" if $params->{extra_ram};
 
        push @args, "--pfam-zip", "pfam_mapping.zip";
        push @args, "--all-pfam-zip", "all_pfam_mapping.zip";
        push @args, "--split-pfam-zip", "split_pfam_mapping.zip";
        push @args, "--all-split-pfam-zip", "all_split_pfam_mapping.zip";
        push @args, "--uniprot-id-zip", "UniProt_IDs.zip";
        push @args, "--uniprot-domain-id-zip", "UniProt_Domain_IDs.zip";
        push @args, "--uniref50-id-zip", "UniRef50_IDs.zip";
        push @args, "--uniref50-domain-id-zip", "UniRef50_Domain_IDs.zip";
        push @args, "--uniref90-id-zip", "UniRef90_IDs.zip";
        push @args, "--uniref90-domain-id-zip", "UniRef90_Domain_IDs.zip";
        push @args, "--none-zip", "no_pfam_neighbors.zip";
        push @args, "--fasta-zip", "FASTA.zip";
        push @args, "--fasta-domain-zip", "FASTA_Domain.zip";
        push @args, "--fasta-uniref90-zip", "FASTA_UniRef90.zip";
        push @args, "--fasta-uniref90-domain-zip", "FASTA_Domain_UniRef90.zip";
        push @args, "--fasta-uniref50-zip", "FASTA_UniRef50.zip";
        push @args, "--fasta-uniref50-domain-zip", "FASTA_Domain_UniRef50.zip";
        push @args, "--arrow-file", "$jobId.sqlite";
        push @args, "--cooc-table", "cooc_table.txt";
        push @args, "--hub-count-file", "hub_count.txt";
    } elsif ($type eq TYPE_CGFP_IDENTIFY) {
        my $params = decode_json($row->{identify_params});

        my $jobDir = $info->{job_dir_path};
        my $resDir = $info->{results_dir};

        my $searchType = $params->{identify_search_type};
        my ($fn, $fp, $fx) = fileparse($params->{identify_filename}, ".xgmml", ".xgmml.zip", ".zip");
        my $outputSsnName = "${jobId}_${fn}_identify_ssn";

        my $sourceFile = $self->getUploadFile($type, $jobId, $params, "", $row);
        warn "Unable to process $type job because upload file doesn't exist" and next if not $sourceFile;
        $info->{source_file} = $sourceFile->{file_path};
        push @args, "--ssn-in", $info->{source_file};
        push @args, "--ssn-out-name", $outputSsnName;
        push @args, "--cdhit-out-name", "cdhit.txt";
        push @args, "--tmpdir", $resDir;
        push @args, "--np", $numProcessors;
        push @args, "--search-type", $params->{identify_search_type} if $searchType;
        push @args, "--min-seq-len", $params->{identify_min_seq_len} if $params->{identify_min_seq_len};
        push @args, "--max-seq-len", $params->{identify_max_seq_len} if $params->{identify_max_seq_len};
        push @args, "--ref-db", $params->{identify_ref_db} if $params->{identify_ref_db};
        push @args, "--cdhit-sid", $params->{identify_cdhit_sid} if $params->{identify_cdhit_sid};
        push @args, "--cons-thresh", $params->{identify_cons_thresh} if $params->{identify_cons_thresh};
        push @args, "--diamond-sens", $params->{identify_diamond_sens} if $params->{identify_diamond_sens};

        if ($searchType eq "diamond" or $searchType eq "v2-blast") {
            $info->{env} .= "\n" . $self->{config}->{"identify.diamond_module"} . "\n";
        } else {
            $info->{env} .= "\n" . $self->{config}->{"identify.blast_module"} . "\n";
        }

        #TODO: handle parent stuff

    } elsif ($type eq TYPE_CGFP_QUANTIFY) {
        my $params = decode_json($row->{quantify_params});
        my $iparams = decode_json($row->{identify_params});

        my $jobDir = $info->{job_dir_path};
        my $resDir = $info->{results_dir};

        my $metaDb = "/home/groups/efi/databases/HMP/hmp.db"; #TODO
        my $metaIds = $params->{quantify_metagenome_ids};
        my $qDir = "quantify-$info->{job_id}";
        my $idId = $row->{quantify_identify_id};
        my $searchType = $params->{quantify_search_type};

        my $idPath = "$jobDir/$resDir";
        my ($fn, $fp, $fx) = fileparse($iparams->{identify_filename}, ".xgmml", ".xgmml.zip", ".zip");
        my $baseSsnName = "${idId}_$fn";
        my $outputSsnName = "${baseSsnName}_quantify_ssn";
        my $inputSsn = -f "$idPath/${baseSsnName}_identify_ssn.xgmml" ? "$idPath/${baseSsnName}_identify_ssn.xgmml" : "$idPath/${baseSsnName}_markers.xgmml";

        push @args, "--metagenome-db", $metaDb; 
        push @args, "--quantify-dir", $qDir; # dir name, relative to the --id-dir
        #push @args, "--id-dir", $resDir; # output dir name, relative to the job-dir
        push @args, "--metagenome-ids", $metaIds;
        push @args, "--ssn-in", $inputSsn;
        push @args, "--ssn-out", $outputSsnName;
        push @args, "--protein-file", "protein_abundance";
        push @args, "--cluster-file", "cluster_abundance";
        push @args, "--search-type", $searchType if $searchType;

        if ($searchType eq "diamond" or $searchType eq "v2-blast") {
            $info->{env} .= "\n" . $self->{config}->{"quantify.diamond_module"} . "\n";
        } else {
            $info->{env} .= "\n" . $self->{config}->{"quantify.blast_module"} . "\n";
        }

        #TODO: handle parent stuff
        #if ($params->{parent_quantify_id} and $params->{parent_identify_id}) {
        #}
    }

    return @args;
}


sub getBaseSsnName {
    my $file = shift;
    my ($fn, $fp, $fx) = fileparse($file, ".xgmml", ".xgmml.zip", ".zip");
    return $fn;
}


sub getUniRefVersion {
    my $params = shift;

    my $uniref = 0;
    if ($params->{generate_uniref}) {
        $uniref = $params->{generate_uniref};
    } elsif ($params->{blast_db_type} and $params->{blast_db_type} =~ m/^uniref(.+)$/) {
        $uniref = $1;
    }

    return $uniref;
}


sub getDomainArgs {
    my $params = shift;

    my @args;
    if ($params->{generate_domain}) {
        push @args, "--domain";
        push @args, "--domain-region", $params->{generate_domain_region} if $params->{generate_domain_region};
    }

    return @args;
}


sub getFamilyArgs {
    my $params = shift;

    return if not $params->{generate_families};

    my @fams = split(m/,/, $params->{generate_families});

    my $pfams = join(",", grep {m/^(PF|CL)/i} @fams);
    my $ipros = join(",", grep {m/^(IP)/i} @fams);

    my @args;
    push @args, "--pfam", $pfams if $pfams;
    push @args, "--ipro", $ipros if $ipros;

    return @args;
}


sub getUploadFile {
    my $self = shift;
    my $type = shift;
    my $jobId = shift;
    my $params = shift;
    my $subType = shift || "";
    my $dbRow = shift || undef;

    if (not $params) {
        my $tableName = $self->{info}->getTableName($type);
        my $sql = "SELECT ${tableName}_params AS params FROM $tableName WHERE ${tableName}_id = ?";
        my $sth = $self->{dbh}->prepare($sql);
        $sth->execute($jobId);
        my $row = $sth->fetchrow_hashref;
        #TODO
        return undef if not $row;
        $params = $row->{params};
    }

    # Handle the case where transferring from EST -> GNT
    if ($type eq TYPE_GNN and $dbRow and $dbRow->{gnn_est_source_id}) {
        my $info = $self->{info}->getSsnInfoFromSsnJob($dbRow->{gnn_est_source_id}, $params->{ssn_idx}, $dbRow);
        return $info;
    }

    my $fileInfo = $self->{info}->getUploadedFilename($type, $jobId, $params, $subType, $dbRow);
    return undef if not $fileInfo;

    # If file_path is present then this is a transfer.
    if ($fileInfo->{file_path}) {
        return {file_path => $fileInfo->{file_path}, ext => $fileInfo->{ext}};
    } else {
        my $uploadsDir = $self->{config}->getUploadsDir($type);
        return {file_path => "$uploadsDir/$fileInfo->{file}", ext => $fileInfo->{ext}};
    }
}


sub taxFileExists {
    my $self = shift;
    my $type = shift;
    my $subType = shift;
    my $jobId = shift;
    my $row = shift;

    my $outputPath = $self->{info}->getJobDir($type, $jobId, $row);
    $outputPath .= "/tax.json";
    return -f $outputPath ? $outputPath : "";
}


sub getJobParameters {
    my $self = shift;
    my $jobId = shift;
    my $type = shift;
    my $row = shift;

    my $info = {type => $type};
    $info->{env} = $self->{config}->getEnv($type);

    # Generate/top-level job dir
    my $outputPath = "";
    $outputPath = $self->{info}->getJobDir($type, $jobId, $row);

    $info->{generate_job_id} = $row->{analysis_generate_id} if $type eq TYPE_ANALYSIS;
    $info->{job_id} = $jobId;
    $info->{job_dir_path} = $outputPath;
    $info->{script} = $self->getScript($type, $row);
    $info->{results_dir} = $self->{info}->getResultsDirName($type, $jobId); # usually 'output', a sub-dir of --job-dir; in the future will be a abs path

    my @globalArgs = ("--job-id", $jobId, "--remove-temp", "--job-dir", $outputPath, "--results-dir-name", $info->{results_dir});

    my @schedArgs = ("--scheduler", $self->{config}->getGlobal("scheduler"), "--queue", $self->{config}->getGlobal("queue"), "--mem-queue", $self->{config}->getGlobal("mem_queue"));

    my @args = $self->makeArgs($jobId, $type, $row, $info);

    $info->{args} = [@globalArgs, @args, @schedArgs];


    print Dumper($info);
    #die;


    return $info;
}


sub getJobTableQuerySql {
    my $self = shift;
    my $jobType = shift;
    my $jobTable = shift;
    my $idCol = shift;

    my $sql = "SELECT * FROM $jobTable WHERE $idCol = ?";
    if ($jobType eq TYPE_ANALYSIS) {
        $sql = "SELECT * FROM analysis LEFT JOIN generate ON analysis.analysis_generate_id = generate.generate_id WHERE analysis_id = ?";
    } elsif ($jobType eq TYPE_CGFP_QUANTIFY) {
        $sql = "SELECT * FROM quantify LEFT JOIN identify ON quantify.quantify_identify_id = identify.identify_id WHERE quantify_id = ?";
    }

    return $sql;
}


sub getScript {
    my $self = shift;
    my $type = shift;
    my $row = shift;

    #TODO: fix hard coded

    my $genJob = "create_generate_job.pl";
    my $ssnJob = "make_colorssn_job.pl";

    my %mapping = (
        &TYPE_ACCESSION => $genJob,
        &TYPE_BLAST => "create_blast_job.pl",
        &TYPE_CLUSTER => $ssnJob,
        &TYPE_COLORSSN => $ssnJob,
        &TYPE_FAMILIES => $genJob,
        &TYPE_FASTA => $genJob,
        &TYPE_FASTA_ID => $genJob,
        &TYPE_CONVRATIO => "create_cluster_conv_ratio_job.pl",
        &TYPE_NBCONN => "create_nb_conn_job.pl",
        &TYPE_TAXONOMY => $genJob,
        &TYPE_GNN => "submit_gnn.pl",
        &TYPE_GND => "submit_diagram.pl",
        &TYPE_ANALYSIS => "create_analysis_job.pl",
        &TYPE_CGFP_IDENTIFY => "submit_identify.pl",
        &TYPE_CGFP_QUANTIFY => "submit_quantify.pl",
    );

    my $script = "";

    if ($type eq TYPE_GENERATE) {
        my $subType = $row->{"generate_type"} // TYPE_FAMILIES;
        $script = $mapping{$subType};
    } elsif ($mapping{$type}) {
        return $mapping{$type};
    }

    return $script;
}


sub log {
    my $self = shift;
    my @msg = @_;
    map { print $_, "\n"; } @msg if $self->{debug};
}


1;

