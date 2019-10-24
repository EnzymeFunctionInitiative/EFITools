
package EFI::HMM::Job;

use strict;
use warnings;


sub makeJob {
    my $SS = shift;
    my $info = shift;
    my $depJobId = shift;

    return if not $info->{hmm_option};

    my $isUniProtNetwork = $info->{ssn_type} ? $info->{ssn_type} eq "UniProt" : 0;
    my $logoListFile = $info->{hmm_logo_list};
    my $weblogoListFile = $info->{hmm_weblogo_list};
    my $histListFile = $info->{hmm_histogram_list};
    my $alignListFile = $info->{hmm_alignment_list};
    my $crListFile = $info->{hmm_consensus_residue_info_list};
    my @types = getHmmTypes();
    @types = ("wpb");
    my $consensusThreshold = $info->{hmm_consensus_threshold} ? $info->{hmm_consensus_threshold} : 80;
    my @cons = map { $_ < 1 ? $_*100 : $_ } split(m/,/, $consensusThreshold);
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

    my $fullClusterListFile = "$fullOutDir/cluster_list_min_seq.txt";
    my $domClusterListFile = "$domOutDir/cluster_list_min_seq.txt";
    my $fullCountFile = "$fullOutDir/cluster_node_counts.txt";
    my $domCountFile = "$domOutDir/cluster_node_counts.txt";

    my $np = $info->{num_tasks} ? $info->{num_tasks} : 1;
    my $B = $SS->getBuilder();
    $B->resource(1, $np, "20gb");
    $B->dependency(0, $depJobId);
    $B->setScriptAbortOnError(0); # don't abort on error

    #find DIR -type f -print0 | sed 's%/private_stores/gerlt/efi_test/results/14137/output/cluster-data/hmm/domain/align/%%g' | sed 's/\.afa//g' | xargs -n 1 -P 12  -0 -I % echo weblogo -D fasta -F png --resolution 300 --stacks-per-line 80 -f /private_stores/gerlt/efi_test/results/14137/output/cluster-data/hmm/domain/align/%.afa -o ~/junk/t/weblogo/%.png
    $B->addAction(<<SCRIPT
module load MUSCLE
module load numpy
module load GhostScript
module load HMMER
module load skylign
module load R
module load CD-HIT

export PYTHONPATH=\$PYTHONPATH:/home/n-z/noberg/lib/python
export PATH=\$PATH:/home/n-z/noberg/bin
if [[ -d $fastaDir ]]; then
SCRIPT
    );

    ########## FULL - MSA
    if ($info->{hmm_option} =~ m/HMM|CR|WEBLOGO/) {
        $B->addAction(<<SCRIPT
    mkdir -p $fullAlignDir
    $appDir/get_cluster_count.pl --fasta-dir $fastaDir --count-file $fullCountFile
SCRIPT
        );

        my $clusterSizeFile = "$info->{output_path}/$info->{cluster_size_file}";
        if ($isUniProtNetwork) {
            my $localFastaDir = "$fullOutDir/fasta-unique";
            $B->addAction(<<SCRIPT
    mkdir -p $localFastaDir
    find $fastaDir -name 'cluster_*.fasta' -type f -print0 | sed 's%$fastaDir/\\([a-z_0-9]\\+\\)\\.fasta%\\1%g' | xargs -P $np -0 -I % cd-hit -c 1 -s 1 -i $fastaDir/%.fasta -o $localFastaDir/%.fasta -M 14900
    $appDir/get_cluster_count.pl --fasta-dir $localFastaDir --count-file $fullClusterListFile --min-count $info->{hmm_min_seq_msa}
SCRIPT
            );
            $fastaDir = $localFastaDir;
        } else {
            $B->addAction(<<SCRIPT
    $appDir/get_cluster_count.pl --size-file $clusterSizeFile --count-file $fullClusterListFile --min-count $info->{hmm_min_seq_msa}
SCRIPT
            );
        }

        $B->addAction(<<SCRIPT

    #MAKE MULTIPLE SEQUENCE ALIGNMENTs FOR FULL SEQUENCES
    cat $fullClusterListFile | xargs -P $np -I % muscle -quiet -in $fastaDir/cluster_%.fasta -out $fullAlignDir/cluster_%.afa
    find $fullAlignDir -name 'cluster_*.afa' -type f | sed 's%$fullAlignDir/\\(cluster_\\([0-9]\\+\\)\\)\\.afa%\\2\\tfull\\tnormal\\t$info->{hmm_rel_path}/full/normal/align/\\1.afa%g' > $alignListFile

SCRIPT
        );
    }

    ########## FULL - HMM
    if ($info->{hmm_option} =~ m/HMM/i) {
        my $hmmZipFilename = "$info->{hmm_zip_prefix}_HMMs_Full.zip";
        my $hmmZip = "$info->{output_path}/$hmmZipFilename";
        $B->addAction(<<SCRIPT
    mkdir -p $fullOutDir/hmm
    cat $fullClusterListFile | xargs -P $np -I % hmmbuild $fullOutDir/hmm/cluster_%.hmm $fullAlignDir/cluster_%.afa
    cat $fullClusterListFile | xargs -P $np -I % $appDir/make_skylign_logo.pl --hmm $fullOutDir/hmm/cluster_%.hmm --json $fullOutDir/hmm/cluster_%.json --png $fullOutDir/hmm/cluster_%.png
    find $fullOutDir/hmm -name 'cluster_*.hmm' -type f | sed 's%$fullOutDir/hmm/\\(cluster_\\([0-9]\\+\\)\\)\\.hmm%\\2\\tfull\\tnormal\\t$info->{hmm_rel_path}/full/normal/hmm/\\1%g' > $logoListFile
    DIR=`pwd`
    cd $fullOutDir/hmm && zip -r $hmmZip . -i '*'
    cd \$DIR

SCRIPT
        );
        #print $logoListFh join("\t", $clusterNum, $seqTypeLabel, $opt->[0], "$relHmmDir/$opt->[0]/$filename"), "\n";
    }

    ########## FULL - CONSENSUS RESIDUE OR WEBLOGO
    if ($info->{hmm_option} =~ m/CR|WEBLOGO/i) {
        $B->addAction(<<SCRIPT
    mkdir -p $fullOutDir/weblogo
    cat $fullClusterListFile | xargs -P $np -I % weblogo -D fasta -F png --resolution 300 --stacks-per-line 80 -f $fullAlignDir/cluster_%.afa -o $fullOutDir/weblogo/cluster_%.png $colorList
    cat $fullClusterListFile | xargs -P $np -I % weblogo -D fasta -F logodata -f $fullAlignDir/cluster_%.afa -o $fullOutDir/weblogo/cluster_%.txt
    find $fullOutDir/weblogo -name 'cluster_*.png' -type f | sed 's%$fullOutDir/weblogo/\\(cluster_\\([0-9]\\+\\)\\)\\.png%\\2\\tfull\\tnormal\\t$info->{hmm_rel_path}/full/normal/weblogo/\\1%g' > $weblogoListFile

SCRIPT
        );
    }

    ########## FULL - CONSENSUS RESIDUE
    if ($info->{hmm_option} =~ m/CR/i) {
        foreach my $aa (@aas) {
            my $consDir = "$fullOutDir/consensus_residue_results_$aa";
            my $consZipName = "$info->{hmm_zip_prefix}_ConsensusResidue_${aa}_Full.zip";
            my $consZip = "$info->{output_path}/$consZipName";
            $B->addAction("    mkdir -p $consDir");
            my $mergeCounts = "";
            my $mergePercent = "";
            foreach my $ct (@cons) {
                my $baseFile = "consensus_residue_$ct";
                my $listDir = "$consDir/id_lists_$ct";
                $B->addAction(<<SCRIPT
    #CONSENSUS RESIDUE CALCULATION
    $appDir/count_msa_aa.pl --msa-dir $fullAlignDir --logo-dir $fullOutDir/weblogo --aa $aa --count-file $consDir/${baseFile}_position.txt --pct-file $consDir/${baseFile}_percentage.txt --threshold $ct --node-count-file $fullCountFile
    mkdir -p $listDir
    $appDir/collect_aa_ids.pl --aa-count-file $consDir/${baseFile}_position.txt --output-dir $listDir --id-mapping $info->{output_path}/$info->{domain_map_file}
SCRIPT
                );
                $mergeCounts .= " --position-file $ct=$consDir/${baseFile}_position.txt";
                $mergePercent .= " --percentage-file $ct=$consDir/${baseFile}_percentage.txt";
            }
            my $outBaseName = "$info->{hmm_zip_prefix}_ConsensusResidue_${aa}";
            my $posSumFileName = "${outBaseName}_Position_Summary_Full.txt";
            my $pctSumFileName = "${outBaseName}_Percentage_Summary_Full.txt";
            $B->addAction(<<SCRIPT
    $appDir/make_summary_tables.pl --position-summary-file $info->{output_path}/$posSumFileName --percentage-summary-file $info->{output_path}/$pctSumFileName $mergeCounts $mergePercent
    DIR=`pwd`
    cd $consDir && zip -r $consZip . -i '*'
    cd \$DIR
    echo "$aa\tfull\tposition\t$posSumFileName" >> $crListFile
    echo "$aa\tfull\tpercentage\t$pctSumFileName" >> $crListFile
    echo "$aa\tfull\tzip\t$consZipName" >> $crListFile
SCRIPT
            );
        }
    }
    $B->addAction(""); #empty line

    ########## FULL - LENGTH HISTOGRAM
    if ($info->{hmm_option} =~ m/HIST/i) {
        my $outDir = "$fullOutDir/hist-uniprot";
        $B->addAction(<<SCRIPT
    mkdir -p $outDir
    find $fastaDir -name 'cluster_*.fasta' -type f -print0 | sed 's%$fastaDir/\\([a-z_0-9]\\+\\)\\.fasta%\\1%g' | xargs -P $np -0 -I % $appDir/make_length_histo.pl -seq-file $info->{fasta_data_dir}/%.fasta -histo-file $outDir/%.txt
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
#cd $info->{hmm_data_dir} && zip -r $info->{hmm_zip} . -i '*'
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
    $appDir/get_cluster_count.pl --fasta-dir $fastaDomainDir --count-file $domCountFile
SCRIPT
        );

        my $clusterSizeFile = "$info->{output_path}/$info->{cluster_size_file}";
        if ($isUniProtNetwork) {
            my $localFastaDir = "$domOutDir/fasta-unique";
            $B->addAction(<<SCRIPT
    mkdir -p $localFastaDir
    find $fastaDomainDir -name 'cluster_*.fasta' -type f -print0 | sed 's%$fastaDomainDir/\\([a-z_0-9]\\+\\)\\.fasta%\\1%g' | xargs -P $np -0 -I % cd-hit -c 1 -s 1 -i $fastaDomainDir/%.fasta -o $localFastaDir/%.fasta -M 14900
    $appDir/get_cluster_count.pl --fasta-dir $localFastaDir --count-file $domClusterListFile --min-count $info->{hmm_min_seq_msa}
SCRIPT
            );
            $fastaDomainDir = $localFastaDir;
        } else {
            $B->addAction(<<SCRIPT
    $appDir/get_cluster_count.pl --size-file $clusterSizeFile --count-file $domClusterListFile --min-count $info->{hmm_min_seq_msa}
SCRIPT
            );
        }

        $B->addAction(<<SCRIPT

    #MAKE MULTIPLE SEQUENCE ALIGNMENTs FOR DOMAIN SEQUENCES
    cat $domClusterListFile | xargs -P $np -I % muscle -quiet -in $fastaDomainDir/cluster_domain_%.fasta -out $domAlignDir/cluster_domain_%.afa
    find $domAlignDir -name 'cluster_*.afa' -type f | sed 's%$domAlignDir/\\(cluster_domain_\\([0-9]\\+\\)\\)\\.afa%\\2\\tdomain\\tnormal\\t$info->{hmm_rel_path}/domain/align/\\1.afa%g' >> $alignListFile

SCRIPT
        );
    }

    ########## DOMAIN - CONSENSUS RESIDUE OR WEBLOGO
    if ($info->{hmm_option} =~ m/CR|WEBLOGO/i) {
        $B->addAction(<<SCRIPT
    #MAKE WEBLOGOs
    mkdir -p $domOutDir/weblogo
    cat $domClusterListFile | xargs -P $np -I % weblogo -D fasta -F png --resolution 300 --stacks-per-line 80 -f $domAlignDir/cluster_domain_%.afa -o $domOutDir/weblogo/cluster_domain_%.png $colorList
    cat $domClusterListFile | xargs -P $np -I % weblogo -D fasta -F logodata -f $domAlignDir/cluster_domain_%.afa -o $domOutDir/weblogo/cluster_domain_%.txt
    find $domOutDir/weblogo -name 'cluster_*.png' -type f | sed 's%$domOutDir/weblogo/\\(cluster_\\(domain\\)\\?_\\?\\([0-9]\\+\\)\\)\\.png%\\3\\t\\2\\tnormal\\t$info->{hmm_rel_path}/domain/weblogo/\\1%g' >> $weblogoListFile

SCRIPT
        );
    }

    ########## DOMAIN - HMM
    if ($info->{hmm_option} =~ m/HMM/i) {
        my $hmmZipFilename = "$info->{hmm_zip_prefix}_HMMs_Domain.zip";
        my $hmmZip = "$info->{output_path}/$hmmZipFilename";
        foreach my $type (@types) {
            my $typeDir = "$domOutDir/hmm";
            $B->addAction(<<SCRIPT
    #MAKE HMMs AND SKYLIGN LOGOs
    mkdir -p $typeDir
    cat $domClusterListFile | xargs -P $np -I % hmmbuild --$type $typeDir/cluster_domain_%.hmm $domAlignDir/cluster_domain_%.afa
    cat $domClusterListFile | xargs -P $np -I % $appDir/make_skylign_logo.pl --hmm $typeDir/cluster_domain_%.hmm --json $typeDir/cluster_domain_%.json --png $typeDir/cluster_domain_%.png
    find $typeDir -name 'cluster_*.hmm' -type f | sed 's%$typeDir/\\(cluster_\\(domain\\)\\?_\\?\\([0-9]\\+\\)\\)\\.hmm%\\3\\t\\2\\t$type\\t$info->{hmm_rel_path}/domain/hmm/\\1%g' >> $logoListFile
    DIR=`pwd`
    cd $domOutDir/hmm && zip -r $hmmZip . -i '*'
    cd \$DIR

SCRIPT
            );
        }
    }

    ########## DOMAIN - CONSENSUS RESIDUE
    if ($info->{hmm_option} =~ m/CR/i) {
        foreach my $aa (@aas) {
            my $consDir = "$domOutDir/consensus_residue_results_$aa";
            my $consZipName = "$info->{hmm_zip_prefix}_ConsensusResidue_${aa}_Domain.zip";
            my $consZip = "$info->{output_path}/$consZipName";
            $B->addAction("    mkdir -p $consDir");
            my $mergeCounts = "";
            my $mergePercent = "";
            foreach my $ct (@cons) {
                my $baseFile = "consensus_residue_$ct";
                my $listDir = "$consDir/id_lists_$ct";
                $B->addAction(<<SCRIPT
    #CONSENSUS RESIDUE CALCULATION
    $appDir/count_msa_aa.pl --msa-dir $domAlignDir --logo-dir $domOutDir/weblogo --aa $aa --count-file $consDir/${baseFile}_position.txt --pct-file $consDir/${baseFile}_percentage.txt --threshold $ct --node-count-file $domCountFile
    mkdir -p $listDir
    $appDir/collect_aa_ids.pl --aa-count-file $consDir/${baseFile}_position.txt --output-dir $listDir --id-mapping $info->{output_path}/$info->{domain_map_file}
SCRIPT
                );
                $mergeCounts .= " --position-file $ct=$consDir/${baseFile}_position.txt";
                $mergePercent .= " --percentage-file $ct=$consDir/${baseFile}_percentage.txt";
            }
            my $outBaseName = "$info->{hmm_zip_prefix}_ConsensusResidue_${aa}";
            my $posSumFileName = "${outBaseName}_Position_Summary_Domain.txt";
            my $pctSumFileName = "${outBaseName}_Percentage_Summary_Domain.txt";
            $B->addAction(<<SCRIPT
    $appDir/make_summary_tables.pl --position-summary-file $info->{output_path}/$posSumFileName --percentage-summary-file $info->{output_path}/$pctSumFileName $mergeCounts $mergePercent
    DIR=`pwd`
    cd $consDir && zip -r $consZip . -i '*'
    cd \$DIR
    echo "$aa\tdomain\tposition\t$posSumFileName" >> $crListFile
    echo "$aa\tdomain\tpercentage\t$pctSumFileName" >> $crListFile
    echo "$aa\tdomain\tzip\t$consZipName" >> $crListFile
SCRIPT
            );
        }
    }
    $B->addAction(""); #empty line

    ########## DOMAIN - LENGTH HISTOGRAM
    if ($info->{hmm_option} =~ m/HIST/i) {
        if ($info->{fasta_domain_data_dir}) {
            my $outDir = "$domOutDir/hist-uniprot";
            $B->addAction(<<SCRIPT
    mkdir -p $outDir
    find $info->{fasta_domain_data_dir} -name 'cluster_*.fasta' -type f -print0 | sed 's%$info->{fasta_domain_data_dir}/\\([a-z_0-9]\\+\\)\\.fasta%\\1%g' | xargs -P $np -0 -I % $appDir/make_length_histo.pl -seq-file $info->{fasta_domain_data_dir}/%.fasta -histo-file $outDir/%.txt
    find $outDir -name '*.txt' -type f -not -empty -print0 | sed 's%\\($outDir/[a-z_0-9]\\+\\)\\.txt%\\1%g' | xargs -P $np -0 -I % Rscript $appDir/hist-length.r legacy %.txt %.png 0 'Domain-UniProt' 700 315
    find $outDir -name '*.png' | sed 's%$outDir/\\(cluster_\\(domain\\)\\?_\\?\\([0-9]\\+\\)\\)\\.png%\\3\\tdomain\\tuniprot\\t$info->{hmm_rel_path}/domain/hist-uniprot/\\1%g' >> $histListFile
SCRIPT
            );
        } elsif ($info->{fasta_uniref90_domain_data_dir}) {
            my $urType = "90";
            my $outDir = "$domOutDir/hist-uniref$urType";
            $B->addAction(<<SCRIPT
    mkdir -p $outDir
    find $info->{fasta_uniref90_domain_data_dir} -name 'cluster_*.fasta' -type f -print0 | sed 's%$info->{fasta_uniref90_domain_data_dir}/\\([a-z_0-9]\\+\\)\\.fasta%\\1%g' | xargs -P $np -0 -I % $appDir/make_length_histo.pl -seq-file $info->{fasta_uniref90_domain_data_dir}/%.fasta -histo-file $outDir/%.txt
    find $outDir -name '*.txt' -type f -not -empty -print0 | sed 's%\\($outDir/[a-z_0-9]\\+\\)\\.txt%\\1%g' | xargs -P $np -0 -I % Rscript $appDir/hist-length.r legacy %.txt %.png 0 'Domain-UniRef90' 700 315
    find $outDir -name '*.png' | sed 's%$outDir/\\(cluster_\\(domain\\)\\?_\\?\\([0-9]\\+\\)\\)\\.png%\\3\\tdomain\\tuniref90\\t$info->{hmm_rel_path}/domain/hist-uniref90/\\1%g' >> $histListFile
SCRIPT
            );
        } elsif ($info->{fasta_uniref50_domain_data_dir}) {
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

#cd $info->{hmm_data_dir} && zip -r $info->{hmm_zip} . -i '*'

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

