
package EFI::HMM::Job;

use strict;
use warnings;


sub makeJob {
    my $SS = shift;
    my $info = shift;
    my $depJobId = shift;

    return if not $info->{hmm_option};

    my $logoListFile = $info->{hmm_logo_list};
    my $weblogoListFile = $info->{hmm_weblogo_list};
    my $histListFile = $info->{hmm_histogram_list};
    my @types = getHmmTypes();
    @types = ("wpb");
    my $consensusThreshold = $info->{hmm_consensus_threshold} ? $info->{hmm_consensus_threshold} : 0.8;
    my @cons = split(m/,/, $consensusThreshold);
    my $appDir = $info->{hmm_tool_dir};
    my @aas = @{$info->{hmm_amino_acids}};

    my $colorList = "";
    if ($info->{hmm_option} =~ m/CR/i) {
        my @colors = @{$info->{hmm_weblogo_colors}};
        for (my $i = 0; $i < scalar @aas; $i++) {
            my $cidx = $i % scalar @colors;
            $colorList .= " --color $colors[$cidx] $aas[$i] '$aas[$i]'";
        }
    }

    #if ($info->{fasta_data_dir} and $info->{fasta_zip} and $info->{hmm_data_dir} and $info->{hmm_zip}) {
    #&$writeGetFastaIf($info->{uniprot_node_data_dir}, $info->{uniprot_node_zip}, "cluster_All_UniProt_IDs.txt", $info->{uniprot_domain_node_data_dir}, $info->{fasta_data_dir}, $info->{fasta_domain_data_dir});
    #&$writeGetFastaIf($info->{uniref90_node_data_dir}, $info->{uniref90_node_zip}, "cluster_All_UniRef90_IDs.txt", $info->{uniref90_domain_node_data_dir}, $info->{fasta_uniref90_data_dir}, $info->{fasta_uniref90_domain_data_dir});
    #&$writeGetFastaIf($info->{uniref50_node_data_dir}, $info->{uniref50_node_zip}, "cluster_All_UniRef50_IDs.txt", $info->{uniref50_domain_node_data_dir}, $info->{fasta_uniref50_data_dir}, $info->{fasta_uniref50_domain_data_dir});
    #&$writeBashZipIf($info->{uniprot_domain_node_data_dir}, $info->{uniprot_domain_node_zip}, "cluster_All_UniProt_Domain_IDs.txt");
    #&$writeBashZipIf($info->{uniref50_domain_node_data_dir}, $info->{uniref50_domain_node_zip}, "cluster_All_UniRef50_Domain_IDs.txt");
    #&$writeBashZipIf($info->{uniref90_domain_node_data_dir}, $info->{uniref90_domain_node_zip}, "cluster_All_UniRef90_Domain_IDs.txt");
    #&$writeBashZipIf($info->{fasta_data_dir}, $info->{fasta_zip}, "all.fasta", sub { $B->addAction("    HMM_FASTA_DIR=$info->{fasta_data_dir}"); });
    #&$writeBashZipIf($info->{fasta_domain_data_dir}, $info->{fasta_domain_zip}, "all.fasta", sub { $B->addAction("    HMM_FASTA_DOMAIN_DIR=$info->{fasta_domain_data_dir}"); });
    #&$writeBashZipIf($info->{fasta_uniref90_data_dir}, $info->{fasta_uniref90_zip}, "all.fasta", sub { $B->addAction("    HMM_FASTA_DIR=$info->{fasta_uniref90_data_dir}"); });
    #&$writeBashZipIf($info->{fasta_uniref90_domain_data_dir}, $info->{fasta_uniref90_domain_zip}, "all.fasta", sub { $B->addAction("    HMM_FASTA_DOMAIN_DIR=$info->{fasta_uniref90_domain_data_dir}"); });
    #&$writeBashZipIf($info->{fasta_uniref50_data_dir}, $info->{fasta_uniref50_zip}, "all.fasta", sub { $B->addAction("    HMM_FASTA_DIR=$info->{fasta_uniref50_data_dir}"); });

    my $fastaDir = $info->{fasta_data_dir};
    $fastaDir = $info->{fasta_uniref90_data_dir} if $info->{fasta_uniref90_data_dir};
    $fastaDir = $info->{fasta_uniref50_data_dir} if $info->{fasta_uniref50_data_dir};
    my $fastaDomainDir = $info->{fasta_domain_data_dir};
    $fastaDomainDir = $info->{fasta_uniref90_domain_data_dir} if $info->{fasta_uniref90_domain_data_dir};
    $fastaDomainDir = $info->{fasta_uniref50_domain_data_dir} if $info->{fasta_uniref50_domain_data_dir};

    my $domOutDir = "$info->{hmm_data_dir}/domain";
    my $fullOutDir = "$info->{hmm_data_dir}/full/normal";
    my $domAlignDir = "$domOutDir/align";
    my $fullAlignDir = "$fullOutDir/align";

    my $fullCountFile = "$fullOutDir/cluster_list_min_seq.txt";
    my $domCountFile = "$domOutDir/cluster_list_min_seq.txt";

    my $np = $info->{num_tasks} ? $info->{num_tasks} : 1;
    my $B = $SS->getBuilder();
    $B->resource(1, $np, "20gb");
    $B->dependency(0, $depJobId);
    $B->setScriptAbortOnError(0); # don't abort on error

    #TODO: $info->{hmm_min_seq_msa}
    #TODO: "Cluster Node Count"
    #TODO: histogram tabs

    #find DIR -type f -print0 | sed 's%/private_stores/gerlt/efi_test/results/14137/output/cluster-data/hmm/domain/align/%%g' | sed 's/\.afa//g' | xargs -n 1 -P 12  -0 -I % echo weblogo -D fasta -F png --resolution 300 --stacks-per-line 80 -f /private_stores/gerlt/efi_test/results/14137/output/cluster-data/hmm/domain/align/%.afa -o ~/junk/t/weblogo/%.png
    $B->addAction(<<SCRIPT
module load MUSCLE
module load numpy
module load GhostScript
module load HMMER
module load skylign
module load R

export PYTHONPATH=\$PYTHONPATH:/home/n-z/noberg/lib/python
export PATH=\$PATH:/home/n-z/noberg/bin
if [[ -d $fastaDir ]]; then

SCRIPT
    );

    ########## FULL - MSA
    if ($info->{hmm_option} =~ m/HMM|CR|WEBLOGO/) {
        $B->addAction(<<SCRIPT
    mkdir -p $fullAlignDir
    $appDir/get_cluster_count.pl --size-file $info->{output_path}/$info->{cluster_size_file} --count-file $fullCountFile --min-count $info->{hmm_min_seq_msa}

    #MAKE MULTIPLE SEQUENCE ALIGNMENTs FOR FULL SEQUENCES
    #find $fullAlignDir -name 'cluster_*.afa' -type f -print0 | sed 's%$fullAlignDir/\\([a-z_0-9]\\+\\)\\.afa%\\1%g' | xargs -P $np -0 -I % muscle -quiet -in $fullAlignDir/%.afa -out $fullAlignDir/%.afa
    cat $fullCountFile | xargs -P $np -I % muscle -quiet -in $fastaDir/cluster_%.fasta -out $fullAlignDir/cluster_%.afa

SCRIPT
        );
    }

    ########## FULL - HMM
    if ($info->{hmm_option} =~ m/HMM/i) {
        $B->addAction(<<SCRIPT
    mkdir -p $fullOutDir/hmm
    #find $fullAlignDir -name 'cluster_*.afa' -type f -print0 | sed 's%$fullAlignDir/\\([a-z_0-9]\\+\\)\\.afa%\\1%g' | xargs -P $np -0 -I % hmmbuild $fullOutDir/hmm/%.hmm $fullAlignDir/%.afa
    #find $fullAlignDir -name 'cluster_*.afa' -type f -print0 | sed 's%$fullAlignDir/\\([a-z_0-9]\\+\\)\\.afa%\\1%g' | xargs -P $np -0 -I % $appDir/make_skylign_logo.pl --hmm $fullOutDir/hmm/%.hmm --json $fullOutDir/hmm/%.json --png $fullOutDir/hmm/%.png
    cat $fullCountFile | xargs -P $np -I % hmmbuild $fullOutDir/hmm/cluster_%.hmm $fullAlignDir/cluster_%.afa
    cat $fullCountFile | xargs -P $np -I cluster_% $appDir/make_skylign_logo.pl --hmm $fullOutDir/hmm/cluster_%.hmm --json $fullOutDir/hmm/cluster_%.json --png $fullOutDir/hmm/cluster_%.png
    find $fullOutDir/hmm -name 'cluster_*.hmm' -type f | sed 's%$fullOutDir/hmm/\\(cluster_\\([0-9]\\+\\)\\)\\.hmm%\\2\\tfull\\tnormal\\t$info->{hmm_rel_path}/full/normal/hmm/\\1%g' > $logoListFile

SCRIPT
        );
        #print $logoListFh join("\t", $clusterNum, $seqTypeLabel, $opt->[0], "$relHmmDir/$opt->[0]/$filename"), "\n";
    }

    ########## FULL - CONSENSUS RESIDUE OR WEBLOGO
    if ($info->{hmm_option} =~ m/CR|WEBLOGO/i) {
        $B->addAction(<<SCRIPT
    mkdir -p $fullOutDir/weblogo
    #find $fullAlignDir -name 'cluster_*.afa' -type f -print0 | sed 's%$fullAlignDir/\\([a-z_0-9]\\+\\)\\.afa%\\1%g' | xargs -P $np -0 -I % weblogo -D fasta -F png --resolution 300 --stacks-per-line 80 -f $fullAlignDir/%.afa -o $fullOutDir/weblogo/%.png $colorList
    #find $fullAlignDir -name 'cluster_*.afa' -type f -print0 | sed 's%$fullAlignDir/\\([a-z_0-9]\\+\\)\\.afa%\\1%g' | xargs -P $np -0 -I % weblogo -D fasta -F logodata -f $fullAlignDir/%.afa -o $fullOutDir/weblogo/%.txt
    cat $fullCountFile | xargs -P $np -I % weblogo -D fasta -F png --resolution 300 --stacks-per-line 80 -f $fullAlignDir/cluster_%.afa -o $fullOutDir/weblogo/cluster_%.png $colorList
    cat $fullCountFile | xargs -P $np -I % weblogo -D fasta -F logodata -f $fullAlignDir/cluster_%.afa -o $fullOutDir/weblogo/cluster_%.txt
    find $fullOutDir/weblogo -name 'cluster_*.png' -type f | sed 's%$fullOutDir/weblogo/\\(cluster_\\([0-9]\\+\\)\\)\\.png%\\2\\tfull\\tnormal\\t$info->{hmm_rel_path}/full/normal/weblogo/\\1%g' > $weblogoListFile

SCRIPT
        );
    }

    ########## FULL - CONSENSUS RESIDUE
    if ($info->{hmm_option} =~ m/CR/i) {
        foreach my $aa (@aas) {
            foreach my $ct (@cons) {
                my $baseFile = "consensus_residue_${aa}_$ct";
                my $listDir = "$fullOutDir/id_lists_${aa}_$ct";
                $B->addAction(<<SCRIPT
    #CONSENSUS RESIDUE CALCULATION
    $appDir/count_msa_aa.pl --msa-dir $fullAlignDir --logo-dir $fullOutDir/weblogo --aa $aa --count-file $fullOutDir/${baseFile}_counts.txt --pct-file $fullOutDir/${baseFile}_pct.txt --threshold $ct
    mkdir -p $listDir
    $appDir/collect_aa_ids.pl --aa-count-file $fullOutDir/${baseFile}_counts.txt --output-dir $listDir --id-mapping $info->{output_path}/$info->{domain_map_file}
SCRIPT
                );
            }
        }
    }
    $B->addAction(""); #empty line

    ########## FULL - LENGTH HISTOGRAM
    if ($info->{hmm_option} =~ m/HIST/i) {
        my $outDir = "$fullOutDir/hist-uniprot";
        $B->addAction(<<SCRIPT
    mkdir -p $outDir
    find $info->{fasta_data_dir} -name 'cluster_*.fasta' -type f -print0 | sed 's%$info->{fasta_data_dir}/\\([a-z_0-9]\\+\\)\\.fasta%\\1%g' | xargs -P $np -0 -I % $appDir/make_length_histo.pl -seq-file $info->{fasta_data_dir}/%.fasta -histo-file $outDir/%.txt
    find $outDir -name '*.txt' -type f -not -empty -print0 | sed 's%\\($outDir/[a-z_0-9]\\+\\)\\.txt%\\1%g' | xargs -P $np -0 -I % Rscript $appDir/hist-length.r legacy %.txt %.png 0 'Full-UniProt' 700 315
    find $outDir -name '*.png' | sed 's%$outDir/\\(cluster_\\(domain\\)\\?_\\?\\([0-9]\\+\\)\\)\\.png%\\3\\tfull\\tuniprot\\t$info->{hmm_rel_path}/full/normal/hist-uniprot/\\1%g' >> $histListFile
SCRIPT
        );
        if ($info->{fasta_uniref90_data_dir}) {
            my $urType = "90";
            my $outDir = "$fullOutDir/hist-uniref$urType";
            $B->addAction(<<SCRIPT
    mkdir -p $outDir
    find $info->{fasta_uniref90_data_dir} -name 'cluster_*.fasta' -type f -print0 | sed 's%$info->{fasta_uniref90_data_dir}/\\([a-z_0-9]\\+\\)\\.fasta%\\1%g' | xargs -P $np -0 -I % $appDir/make_length_histo.pl -seq-file $info->{fasta_uniref90_data_dir}/%.fasta -histo-file $outDir/%.txt
    find $outDir -name '*.txt' -type f -not -empty -print0 | sed 's%\\($outDir/[a-z_0-9]\\+\\)\\.txt%\\1%g' | xargs -P $np -0 -I % Rscript $appDir/hist-length.r legacy %.txt %.png 0 'Full-UniRef90' 700 315
    find $outDir -name '*.png' | sed 's%$outDir/\\(cluster_\\(domain\\)\\?_\\?\\([0-9]\\+\\)\\)\\.png%\\3\\tfull\\tuniref90\\t$info->{hmm_rel_path}/full/normal/hist-uniref90/\\1%g' >> $histListFile
SCRIPT
            );
        }
        if ($info->{fasta_uniref50_data_dir}) {
            my $urType = "50";
            my $outDir = "$fullOutDir/hist-uniref$urType";
            $B->addAction(<<SCRIPT
    mkdir -p $outDir
    find $info->{fasta_uniref50_data_dir} -name 'cluster_*.fasta' -type f -print0 | sed 's%$info->{fasta_uniref50_data_dir}/\\([a-z_0-9]\\+\\)\\.fasta%\\1%g' | xargs -P $np -0 -I % $appDir/make_length_histo.pl -seq-file $info->{fasta_uniref50_data_dir}/%.fasta -histo-file $outDir/%.txt
    find $outDir -name '*.txt' -type f -not -empty -print0 | sed 's%\\($outDir/[a-z_0-9]\\+\\)\\.txt%\\1%g' | xargs -P $np -0 -I % Rscript $appDir/hist-length.r legacy %.txt %.png 0 'Full-UniRef50' 700 315
    find $outDir -name '*.png' | sed 's%$outDir/\\(cluster_\\(domain\\)\\?_\\?\\([0-9]\\+\\)\\)\\.png%\\3\\tfull\\tuniref50\\t$info->{hmm_rel_path}/full/normal/hist-uniref50/\\1%g' >> $histListFile
SCRIPT
            );
        }
    }

    $B->addAction(<<SCRIPT
fi

SCRIPT
    );

    # If there are no domain then we zip the file and wrap up.
    if (not $fastaDomainDir) {
        $B->addAction(<<SCRIPT
cd $info->{hmm_data_dir} && zip -r $info->{hmm_zip} . -i '*'
SCRIPT
        );
        return $B;
    }



    ########## DOMAIN CASES
    $B->addAction(<<SCRIPT
if [[ -d $fastaDomainDir ]]; then

SCRIPT
    );

    ########## DOMAIN - MSA
    if ($info->{hmm_option} =~ m/HMM|CR|WEBLOGO/) {
        $B->addAction(<<SCRIPT
    mkdir -p $domAlignDir
    $appDir/get_cluster_count.pl --size-file $info->{output_path}/$info->{cluster_size_file} --count-file $domCountFile --min-count $info->{hmm_min_seq_msa}

    #MAKE MULTIPLE SEQUENCE ALIGNMENTs FOR DOMAIN SEQUENCES
    #find $fastaDomainDir -name 'cluster_*.fasta' -type f -print0 | sed 's%$fastaDomainDir/\\([a-z_0-9]\\+\\)\\.fasta%\\1%g' | xargs -P $np -0 -I % muscle -quiet -in $fastaDomainDir/%.fasta -out $domAlignDir/%.afa
    cat $domCountFile | xargs -P $np -I % muscle -quiet -in $fastaDomainDir/cluster_domain_%.fasta -out $domAlignDir/cluster_domain_%.afa

SCRIPT
        );
    }

    ########## DOMAIN - CONSENSUS RESIDUE OR WEBLOGO
    if ($info->{hmm_option} =~ m/CR|WEBLOGO/i) {
        $B->addAction(<<SCRIPT
    #MAKE WEBLOGOs
    mkdir -p $domOutDir/weblogo
    #find $domAlignDir -name 'cluster_*.afa' -type f -print0 | sed 's%$domAlignDir/\\([a-z_0-9]\\+\\)\\.afa%\\1%g' | xargs -P $np -0 -I % weblogo -D fasta -F png --resolution 300 --stacks-per-line 80 -f $domAlignDir/%.afa -o $domOutDir/weblogo/%.png $colorList
    #find $domAlignDir -name 'cluster_*.afa' -type f -print0 | sed 's%$domAlignDir/\\([a-z_0-9]\\+\\)\\.afa%\\1%g' | xargs -P $np -0 -I % weblogo -D fasta -F logodata -f $domAlignDir/%.afa -o $domOutDir/weblogo/%.txt
    cat $domCountFile | xargs -P $np -I % weblogo -D fasta -F png --resolution 300 --stacks-per-line 80 -f $domAlignDir/cluster_domain_%.afa -o $domOutDir/weblogo/cluster_domain_%.png $colorList
    cat $domCountFile | xargs -P $np -I % weblogo -D fasta -F logodata -f $domAlignDir/cluster_domain_%.afa -o $domOutDir/weblogo/cluster_domain_%.txt
    find $domOutDir/weblogo -name 'cluster_*.png' -type f | sed 's%$domOutDir/weblogo/\\(cluster_\\(domain\\)\\?_\\?\\([0-9]\\+\\)\\)\\.png%\\3\\t\\2\\tnormal\\t$info->{hmm_rel_path}/domain/weblogo/\\1%g' >> $weblogoListFile

SCRIPT
        );
    }

    ########## DOMAIN - HMM
    if ($info->{hmm_option} =~ m/HMM/i) {
        foreach my $type (@types) {
            my $typeDir = "$domOutDir/hmm";
            $B->addAction(<<SCRIPT
    #MAKE HMMs AND SKYLIGN LOGOs
    mkdir -p $typeDir
    #find $domAlignDir -name 'cluster_*.afa' -type f -print0 | sed 's%$domAlignDir/\\([a-z_0-9]\\+\\)\\.afa%\\1%g' | xargs -P $np -0 -I % hmmbuild --$type $typeDir/%.hmm $domAlignDir/%.afa
    #find $domAlignDir -name 'cluster_*.afa' -type f -print0 | sed 's%$domAlignDir/\\([a-z_0-9]\\+\\)\\.afa%\\1%g' | xargs -P $np -0 -I % $appDir/make_skylign_logo.pl --hmm $typeDir/%.hmm --json $typeDir/%.json --png $typeDir/%.png
    cat $domCountFile | xargs -P $np -I % hmmbuild --$type $typeDir/cluster_domain_%.hmm $domAlignDir/cluster_domain_%.afa
    cat $domCountFile | xargs -P $np -I % $appDir/make_skylign_logo.pl --hmm $typeDir/cluster_domain_%.hmm --json $typeDir/cluster_domain_%.json --png $typeDir/cluster_domain_%.png
    find $typeDir -name 'cluster_*.hmm' -type f | sed 's%$typeDir/\\(cluster_\\(domain\\)\\?_\\?\\([0-9]\\+\\)\\)\\.hmm%\\3\\t\\2\\t$type\\t$info->{hmm_rel_path}/domain/hmm/\\1%g' >> $logoListFile

SCRIPT
            );
        }
    }

    ########## DOMAIN - CONSENSUS RESIDUE
    if ($info->{hmm_option} =~ m/CR/i) {
        foreach my $aa (@aas) {
            foreach my $ct (@cons) {
                my $baseFile = "consensus_residue_${aa}_$ct";
                my $listDir = "$domOutDir/id_lists_${aa}_$ct";
                $B->addAction(<<SCRIPT
    #CONSENSUS RESIDUE CALCULATION
    $appDir/count_msa_aa.pl --msa-dir $domAlignDir --logo-dir $domOutDir/weblogo --aa $aa --count-file $domOutDir/${baseFile}_counts.txt --pct-file $domOutDir/${baseFile}_pct.txt --threshold $ct
    mkdir -p $listDir
    $appDir/collect_aa_ids.pl --aa-count-file $domOutDir/${baseFile}_counts.txt --output-dir $listDir --id-mapping $info->{output_path}/$info->{domain_map_file}
SCRIPT
                );
            }
        }
    }
    $B->addAction(""); #empty line

    ########## DOMAIN - LENGTH HISTOGRAM
    if ($info->{hmm_option} =~ m/HIST/i) {
        my $outDir = "$domOutDir/hist-uniprot";
        $B->addAction(<<SCRIPT
    mkdir -p $outDir
    find $info->{fasta_domain_data_dir} -name 'cluster_*.fasta' -type f -print0 | sed 's%$info->{fasta_domain_data_dir}/\\([a-z_0-9]\\+\\)\\.fasta%\\1%g' | xargs -P $np -0 -I % $appDir/make_length_histo.pl -seq-file $info->{fasta_domain_data_dir}/%.fasta -histo-file $outDir/%.txt
    find $outDir -name '*.txt' -type f -not -empty -print0 | sed 's%\\($outDir/[a-z_0-9]\\+\\)\\.txt%\\1%g' | xargs -P $np -0 -I % Rscript $appDir/hist-length.r legacy %.txt %.png 0 'Domain-UniProt' 700 315
    find $outDir -name '*.png' | sed 's%$outDir/\\(cluster_\\(domain\\)\\?_\\?\\([0-9]\\+\\)\\)\\.png%\\3\\tdomain\\tuniprot\\t$info->{hmm_rel_path}/domain/hist-uniprot/\\1%g' >> $histListFile
SCRIPT
        );
        if ($info->{fasta_uniref90_domain_data_dir}) {
            my $urType = "90";
            my $outDir = "$domOutDir/hist-uniref$urType";
            $B->addAction(<<SCRIPT
    mkdir -p $outDir
    find $info->{fasta_uniref90_domain_data_dir} -name 'cluster_*.fasta' -type f -print0 | sed 's%$info->{fasta_uniref90_domain_data_dir}/\\([a-z_0-9]\\+\\)\\.fasta%\\1%g' | xargs -P $np -0 -I % $appDir/make_length_histo.pl -seq-file $info->{fasta_uniref90_domain_data_dir}/%.fasta -histo-file $outDir/%.txt
    find $outDir -name '*.txt' -type f -not -empty -print0 | sed 's%\\($outDir/[a-z_0-9]\\+\\)\\.txt%\\1%g' | xargs -P $np -0 -I % Rscript $appDir/hist-length.r legacy %.txt %.png 0 'Domain-UniRef90' 700 315
    find $outDir -name '*.png' | sed 's%$outDir/\\(cluster_\\(domain\\)\\?_\\?\\([0-9]\\+\\)\\)\\.png%\\3\\tdomain\\tuniref90\\t$info->{hmm_rel_path}/domain/hist-uniref90/\\1%g' >> $histListFile
SCRIPT
            );
        }
        if ($info->{fasta_uniref50_domain_data_dir}) {
            my $urType = "50";
            my $outDir = "$domOutDir/hist-uniref$urType";
            $B->addAction(<<SCRIPT
    mkdir -p $outDir
    find $info->{fasta_uniref50_domain_data_dir} -name 'cluster_*.fasta' -type f -print0 | sed 's%$info->{fasta_uniref50_domain_data_dir}/\\([a-z_0-9]\\+\\)\\.fasta%\\1%g' | xargs -P $np -0 -I % $appDir/make_length_histo.pl -seq-file $info->{fasta_uniref50_domain_data_dir}/%.fasta -histo-file $outDir/%.txt
    find $outDir -name '*.txt' -type f -not -empty -print0 | sed 's%\\($outDir/[a-z_0-9]\\+\\)\\.txt%\\1%g' | xargs -P $np -0 -I % Rscript $appDir/hist-length.r legacy %.txt %.png 0 'Domain-UniRef50' 700 315
    find $outDir -name '*.png' | sed 's%$outDir/\\(cluster_\\(domain\\)\\?_\\?\\([0-9]\\+\\)\\)\\.png%\\3\\tdomain\\tuniref50\\t$info->{hmm_rel_path}/domain/hist-uniref50/\\1%g' >> $histListFile
SCRIPT
            );
        }
    }

    $B->addAction(<<SCRIPT
fi

cd $info->{hmm_data_dir} && zip -r $info->{hmm_zip} . -i '*'

SCRIPT
    );

    return $B;
}


sub getHmmTypes {
    return (
            "wpb",
#            "wgsc",
#            "wblosum",
#            "wnone",
#            "enone",
#            "pnone",
#            "wpb-enone",
#            "wpb-pnone",
#            "wblosum-enone",
#            "wgsc-enone",
#            "wblosum-pnone",
#            "wnone-pnone",
#            "wnone-enone",
#            "enone-pnone",
#            "wnone-enone-pnone",
#            "wpb-enone-pnone",
#            "wblosum-enone-pnone",
#            "wblosum-enone-pnone",
    );
}


1;

