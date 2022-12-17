
package EFI::Job::EST::Color::HMM;

use strict;
use warnings;


sub makeJob {
    my $B = shift;
    my $info = shift;

    return if not $info->{hmm_option};
    
    my $hmmRelPath = $info->{hmm_rel_path};
    my $outputPath = $info->{output_path};
    my $resultsPath = $info->{results_path};
    my $minSeqMsa = $info->{hmm_min_seq_msa};
    my $hmmOption = $info->{hmm_option};
    my $hmmDataDir = $info->{hmm_data_dir};

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
    if ($hmmOption =~ m/CR/i) {
        my @colors = @{$info->{hmm_weblogo_colors}};
        for (my $i = 0; $i < scalar @aas; $i++) {
            my $cidx = $i % scalar @colors;
            $colorList .= " --color $colors[$cidx] $aas[$i] '$aas[$i]'";
        }
    }

    my $maxMsaSeq = int($info->{hmm_max_seq_msa} // 0);
    my $doPim = $info->{compute_pim} // 0;

    my $checkFn = sub { return $info->{$_[0]}->{fasta_dir} ? $_[0] : ""; };
    my $dataType = &$checkFn("uniref50") ? "uniref50" : (&$checkFn("uniref90") ? "uniref90" : "uniprot");
    $dataType = "uniprot" if not $dataType;
    my $mainFastaDir = $info->{uniprot}->{fasta_dir};
    my $dirs = $info->{$dataType};
    my $fastaDir = $dirs->{fasta_dir};
    $dataType = &$checkFn("uniref50_domain") ? "uniref50_domain" : (&$checkFn("uniref90_domain") ? "uniref90_domain" : "uniprot_domain");
    my $domDirs = $info->{$dataType};
    my $fastaDomainDir = $domDirs->{fasta_dir};

    my $domOutDir = "$hmmDataDir/domain";
    my $fullOutDir = "$hmmDataDir/full/normal";
    my $domAlignDir = "$domOutDir/align";
    my $fullAlignDir = "$fullOutDir/align";
    my $fullPimDir = "$fullOutDir/pim";

    my $fullClusterListFile = "$fullOutDir/cluster_list_min_seq.txt";
    my $domClusterListFile = "$domOutDir/cluster_list_min_seq.txt";
    my $fullCountFile = "$fullOutDir/cluster_node_counts.txt";
    my $domCountFile = "$domOutDir/cluster_node_counts.txt";
    my $domainMapFile = "$resultsPath/$info->{domain_map_file}";
    my $mapFile = "$resultsPath/$info->{map_file}";
    
    my $zipPrefix = $info->{hmm_zip_prefix};

    my $zipFiles = {};

    my $weblogoBin = $info->{weblogo_bin};
    my $np = $info->{num_tasks} ? $info->{num_tasks} : 1;

    $B->addAction(<<SCRIPT
if [[ -d $fastaDir ]]; then
SCRIPT
    );

    ########## FULL - MSA
    if ($hmmOption =~ m/HMM|CR|WEBLOGO/) {
        $B->addAction(<<SCRIPT
    mkdir -p $fullAlignDir
    $appDir/get_cluster_count.pl --fasta-dir $fastaDir --count-file $fullCountFile
SCRIPT
        );

        my $clusterSizeFile = "$outputPath/$info->{cluster_size_file}";
        if ($isUniProtNetwork) {
            my $localFastaDir = "$fullOutDir/fasta-unique";
            $B->addAction(<<SCRIPT
    mkdir -p $localFastaDir
    find $fastaDir -name 'cluster_*.fasta' -type f -print0 | sed 's%$fastaDir/\\([a-z_0-9]\\+\\)\\.fasta%\\1%g' | xargs -P $np -0 -I % cd-hit -c 1 -s 1 -i $fastaDir/%.fasta -o $localFastaDir/%.fasta -M 14900
    $appDir/get_cluster_count.pl --fasta-dir $localFastaDir --count-file $fullClusterListFile --min-count $minSeqMsa
SCRIPT
            );
            $fastaDir = $localFastaDir;
        } else {
            $B->addAction(<<SCRIPT
    $appDir/get_cluster_count.pl --size-file $clusterSizeFile --count-file $fullClusterListFile --min-count $minSeqMsa
SCRIPT
            );
        }

        my $zipFilename= "${zipPrefix}MSAs_Full.zip";
        my $zipFile = "$resultsPath/$zipFilename";
        $B->addAction(<<SCRIPT

    #MAKE MULTIPLE SEQUENCE ALIGNMENTs FOR FULL SEQUENCES
SCRIPT
        );
        if ($maxMsaSeq) {
            my $localFastaDir = "$fullOutDir/fasta-fraction";
            $B->addAction(<<SCRIPT
    mkdir -p $localFastaDir
    cat $fullClusterListFile | xargs -P $np -I % $appDir/subset_fasta.pl --fasta-in $fastaDir/cluster_%.fasta --fasta-out $localFastaDir/cluster_%_subset${maxMsaSeq}.fasta --max-seq $maxMsaSeq
    cat $fullClusterListFile | xargs -P $np -I % bash -c "muscle -quiet -in $localFastaDir/cluster_%_subset${maxMsaSeq}.fasta -fastaout $fullAlignDir/cluster_%.afa -clwstrictout $fullAlignDir/cluster_%.clw || true"
SCRIPT
            );
        } else {
            $B->addAction(<<SCRIPT
    cat $fullClusterListFile | xargs -P $np -I % bash -c "muscle -quiet -in $fastaDir/cluster_%.fasta -fastaout $fullAlignDir/cluster_%.afa -clwstrictout $fullAlignDir/cluster_%.clw || true"
SCRIPT
            );
        }
        if ($doPim) {
            my $pimZipFilename= "${zipPrefix}PIMs_Full.zip";
            my $pimZipFile = "$resultsPath/$pimZipFilename";
            $B->addAction(<<SCRIPT
    mkdir -p $fullPimDir
    cat $fullClusterListFile | xargs -P $np -I % bash -c "clustalo -i $fullAlignDir/cluster_%.clw --percent-id --distmat-out=$fullPimDir/cluster_%.txt --full --force || true"
    rm $fullAlignDir/cluster_*.clw
    DIR=`pwd`
    cd $fullPimDir && zip -r $pimZipFile . -i '*'
    cd \$DIR
SCRIPT
            );
        }
        $B->addAction(<<SCRIPT
    find $fullAlignDir -name 'cluster_*.afa' -type f | sed 's%$fullAlignDir/\\(cluster_\\([0-9]\\+\\)\\)\\.afa%\\2\\tfull\\tnormal\\t$hmmRelPath/full/normal/align/\\1.afa%g' > $alignListFile
    DIR=`pwd`
    cd $fullAlignDir && zip -r $zipFile . -i '*'
    cd \$DIR

SCRIPT
        );
    }

    ########## FULL - HMM
    if ($hmmOption =~ m/HMM/i) {
        my $zipFilename = "${zipPrefix}HMMs_Full.zip";
        my $zipFile = "$resultsPath/$zipFilename";
        $B->addAction(<<SCRIPT
    mkdir -p $fullOutDir/hmm
    cat $fullClusterListFile | xargs -P $np -I % hmmbuild $fullOutDir/hmm/cluster_%.hmm $fullAlignDir/cluster_%.afa
    cat $fullClusterListFile | xargs -P $np -I % $appDir/make_skylign_logo.pl --hmm $fullOutDir/hmm/cluster_%.hmm --json $fullOutDir/hmm/cluster_%.json --png $fullOutDir/hmm/cluster_%.png
    find $fullOutDir/hmm -name 'cluster_*.hmm' -type f | sed 's%$fullOutDir/hmm/\\(cluster_\\([0-9]\\+\\)\\)\\.hmm%\\2\\tfull\\tnormal\\t$hmmRelPath/full/normal/hmm/\\1%g' > $logoListFile
    DIR=`pwd`
    cd $fullOutDir/hmm && zip -r $zipFile . -i '*'
    cd \$DIR

SCRIPT
        );
        $zipFiles->{"hmm"}->{"full"} = $zipFile;
    }

    ########## FULL - CONSENSUS RESIDUE OR WEBLOGO
    if ($hmmOption =~ m/CR|WEBLOGO/i) {
        my $zipFilename= "${zipPrefix}WebLogos_Full.zip";
        my $zipFile = "$resultsPath/$zipFilename";
        $B->addAction(<<SCRIPT
    mkdir -p $fullOutDir/weblogo
    cat $fullClusterListFile | xargs -P $np -I % $weblogoBin -D fasta -F png --resolution 300 --stacks-per-line 80 -f $fullAlignDir/cluster_%.afa -o $fullOutDir/weblogo/cluster_%.png $colorList
    cat $fullClusterListFile | xargs -P $np -I % $weblogoBin -D fasta -F logodata -f $fullAlignDir/cluster_%.afa -o $fullOutDir/weblogo/cluster_%.txt
    find $fullOutDir/weblogo -name 'cluster_*.png' -type f | sed 's%$fullOutDir/weblogo/\\(cluster_\\([0-9]\\+\\)\\)\\.png%\\2\\tfull\\tnormal\\t$hmmRelPath/full/normal/weblogo/\\1%g' > $weblogoListFile
    DIR=`pwd`
    cd $fullOutDir/weblogo && zip -r $zipFile . -i '*.png'
    cd \$DIR

SCRIPT
        );
    }

    ########## FULL - CONSENSUS RESIDUE
    if ($hmmOption =~ m/CR/i) {
        foreach my $aa (@aas) {
            my $consDir = "$fullOutDir/consensus_residue_results_$aa";
            my $consZipName = "${zipPrefix}ConsensusResidue_${aa}_Full.zip";
            my $consZip = "$resultsPath/$consZipName";
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
    $appDir/collect_aa_ids.pl --aa-count-file $consDir/${baseFile}_position.txt --output-dir $listDir --id-mapping $mapFile
SCRIPT
                );
                $mergeCounts .= " --position-file $ct=$consDir/${baseFile}_position.txt";
                $mergePercent .= " --percentage-file $ct=$consDir/${baseFile}_percentage.txt";
            }
            my $outBaseName = "${zipPrefix}ConsensusResidue_${aa}";
            my $posSumFileName = "${outBaseName}_Position_Summary_Full.txt";
            my $pctSumFileName = "${outBaseName}_Percentage_Summary_Full.txt";
            $B->addAction(<<SCRIPT
    $appDir/make_summary_tables.pl --position-summary-file $resultsPath/$posSumFileName --percentage-summary-file $resultsPath/$pctSumFileName $mergeCounts $mergePercent
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
    if ($hmmOption =~ m/HIST/i) {
        my $zipFilename= "${zipPrefix}LenHist_UniProt_Full.zip";
        my $zipFile = "$resultsPath/$zipFilename";
        my $outDir = "$fullOutDir/hist-uniprot";
        $B->addAction(<<SCRIPT
    mkdir -p $outDir
    find $fastaDir -name 'cluster_*.fasta' -type f -print0 | sed 's%$fastaDir/\\([a-z_0-9]\\+\\)\\.fasta%\\1%g' | xargs -P $np -0 -I % $appDir/make_length_histo.pl -seq-file $mainFastaDir/%.fasta -histo-file $outDir/%.txt
    find $outDir -name '*.txt' -type f -not -empty -print0 | sed 's%\\($outDir/[a-z_0-9]\\+\\)\\.txt%\\1%g' | xargs -P $np -0 -I % Rscript $appDir/hist-length.r legacy %.txt %.png 0 'Full-UniProt' 700 315
    find $outDir -name '*.png' | sed 's%$outDir/\\(cluster_\\(domain\\)\\?_\\?\\([0-9]\\+\\)\\)\\.png%\\3\\tfull\\tuniprot\\t$hmmRelPath/full/normal/hist-uniprot/\\1%g' >> $histListFile
    DIR=`pwd`
    cd $outDir && zip -r $zipFile . -i '*.png'
    cd \$DIR
SCRIPT
        );
        my $outputFn = sub {
            my $dirs = shift;
            my $urType = shift;
            my $fileType = lc($urType);
            my $zipFilename= "${zipPrefix}LenHist_${urType}_Full.zip";
            my $zipFile = "$resultsPath/$zipFilename";
            my $outDir = "$fullOutDir/hist-$fileType";
            $B->addAction(<<SCRIPT
    mkdir -p $outDir
    find $dirs->{fasta_dir} -name 'cluster_*.fasta' -type f -print0 | sed 's%$dirs->{fasta_dir}/\\([a-z_0-9]\\+\\)\\.fasta%\\1%g' | xargs -P $np -0 -I % $appDir/make_length_histo.pl -seq-file $dirs->{fasta_dir}/%.fasta -histo-file $outDir/%.txt
    find $outDir -name '*.txt' -type f -not -empty -print0 | sed 's%\\($outDir/[a-z_0-9]\\+\\)\\.txt%\\1%g' | xargs -P $np -0 -I % Rscript $appDir/hist-length.r legacy %.txt %.png 0 'Full-$urType' 700 315
    find $outDir -name '*.png' | sed 's%$outDir/\\(cluster_\\(domain\\)\\?_\\?\\([0-9]\\+\\)\\)\\.png%\\3\\tfull\\t$fileType\\t$hmmRelPath/full/normal/hist-$fileType/\\1%g' >> $histListFile
    DIR=`pwd`
    cd $outDir && zip -r $zipFile . -i '*.png'
    cd \$DIR
SCRIPT
            );
        };
        &$outputFn($info->{uniref90}, "uniref90") if $info->{uniref90} and $info->{uniref90}->{fasta_dir};
        &$outputFn($info->{uniref50}, "uniref50") if $info->{uniref50} and $info->{uniref50}->{fasta_dir};
    }

    $B->addAction(<<SCRIPT
fi

SCRIPT
    );

    # If there are no domain then we zip the file and wrap up.
    if (not $fastaDomainDir) {
        $B->addAction(<<SCRIPT
#cd $hmmDataDir && zip -r $info->{hmm_zip} . -i '*'
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
    if ($hmmOption =~ m/HMM|CR|WEBLOGO/) {
        my $msaZipFilename = "${zipPrefix}WebLogos_Full.zip";
        my $msaZip = "$resultsPath/$msaZipFilename";
        $B->addAction(<<SCRIPT
    mkdir -p $domAlignDir
    $appDir/get_cluster_count.pl --fasta-dir $fastaDomainDir --count-file $domCountFile
SCRIPT
        );

        my $clusterSizeFile = "$outputPath/$info->{cluster_size_file}";
        if ($isUniProtNetwork) {
            my $localFastaDir = "$domOutDir/fasta-unique";
            $B->addAction(<<SCRIPT
    mkdir -p $localFastaDir
    find $fastaDomainDir -name 'cluster_*.fasta' -type f -print0 | sed 's%$fastaDomainDir/\\([a-z_0-9]\\+\\)\\.fasta%\\1%g' | xargs -P $np -0 -I % cd-hit -c 1 -s 1 -i $fastaDomainDir/%.fasta -o $localFastaDir/%.fasta -M 14900
    $appDir/get_cluster_count.pl --fasta-dir $localFastaDir --count-file $domClusterListFile --min-count $minSeqMsa
SCRIPT
            );
            $fastaDomainDir = $localFastaDir;
        } else {
            $B->addAction(<<SCRIPT
    $appDir/get_cluster_count.pl --size-file $clusterSizeFile --count-file $domClusterListFile --min-count $minSeqMsa
SCRIPT
            );
        }

        my $zipFilename= "${zipPrefix}MSAs_Domain.zip";
        my $zipFile = "$resultsPath/$zipFilename";
        $B->addAction(<<SCRIPT

    #MAKE MULTIPLE SEQUENCE ALIGNMENTs FOR DOMAIN SEQUENCES
SCRIPT
        );
        if ($maxMsaSeq) {
            my $localFastaDir = "$domOutDir/fasta-fraction";
            $B->addAction(<<SCRIPT
    mkdir -p $localFastaDir
    cat $fullClusterListFile | xargs -P $np -I % $appDir/subset_fasta.pl --fasta-in $fastaDomainDir/cluster_domain_%.fasta --fasta-out $localFastaDir/cluster_domain_%_subset${maxMsaSeq}.fasta --max-seq $maxMsaSeq
    cat $domClusterListFile | xargs -P $np -I % bash -c "muscle -quiet -in $localFastaDir/cluster_domain_%_subset${maxMsaSeq}.fasta -out $domAlignDir/cluster_domain_%.afa || true"
SCRIPT
            );
        } else {
            $B->addAction(<<SCRIPT
    cat $domClusterListFile | xargs -P $np -I % bash -c "muscle -quiet -in $fastaDomainDir/cluster_domain_%.fasta -out $domAlignDir/cluster_domain_%.afa || true"
SCRIPT
            );
        }
        $B->addAction(<<SCRIPT
    find $domAlignDir -name 'cluster_*.afa' -type f | sed 's%$domAlignDir/\\(cluster_domain_\\([0-9]\\+\\)\\)\\.afa%\\2\\tdomain\\tnormal\\t$hmmRelPath/domain/align/\\1.afa%g' >> $alignListFile
    DIR=`pwd`
    cd $domAlignDir && zip -r $zipFile . -i '*'
    cd \$DIR

SCRIPT
        );
    }

    ########## DOMAIN - CONSENSUS RESIDUE OR WEBLOGO
    if ($hmmOption =~ m/CR|WEBLOGO/i) {
        my $zipFilename= "${zipPrefix}WebLogos_Domain.zip";
        my $zipFile = "$resultsPath/$zipFilename";
        $B->addAction(<<SCRIPT
    #MAKE WEBLOGOs
    mkdir -p $domOutDir/weblogo
    cat $domClusterListFile | xargs -P $np -I % $weblogoBin -D fasta -F png --resolution 300 --stacks-per-line 80 -f $domAlignDir/cluster_domain_%.afa -o $domOutDir/weblogo/cluster_domain_%.png $colorList
    cat $domClusterListFile | xargs -P $np -I % $weblogoBin -D fasta -F logodata -f $domAlignDir/cluster_domain_%.afa -o $domOutDir/weblogo/cluster_domain_%.txt
    find $domOutDir/weblogo -name 'cluster_*.png' -type f | sed 's%$domOutDir/weblogo/\\(cluster_\\(domain\\)\\?_\\?\\([0-9]\\+\\)\\)\\.png%\\3\\t\\2\\tnormal\\t$hmmRelPath/domain/weblogo/\\1%g' >> $weblogoListFile
    DIR=`pwd`
    cd $domOutDir/weblogo && zip -r $zipFile . -i '*.png'
    cd \$DIR

SCRIPT
        );
    }

    ########## DOMAIN - HMM
    if ($hmmOption =~ m/HMM/i) {
        my $zipFilename = "${zipPrefix}HMMs_Domain.zip";
        my $zipFile = "$resultsPath/$zipFilename";
        foreach my $type (@types) {
            my $typeDir = "$domOutDir/hmm";
            $B->addAction(<<SCRIPT
    #MAKE HMMs AND SKYLIGN LOGOs
    mkdir -p $typeDir
    cat $domClusterListFile | xargs -P $np -I % hmmbuild --$type $typeDir/cluster_domain_%.hmm $domAlignDir/cluster_domain_%.afa
    cat $domClusterListFile | xargs -P $np -I % $appDir/make_skylign_logo.pl --hmm $typeDir/cluster_domain_%.hmm --json $typeDir/cluster_domain_%.json --png $typeDir/cluster_domain_%.png
    find $typeDir -name 'cluster_*.hmm' -type f | sed 's%$typeDir/\\(cluster_\\(domain\\)\\?_\\?\\([0-9]\\+\\)\\)\\.hmm%\\3\\t\\2\\t$type\\t$hmmRelPath/domain/hmm/\\1%g' >> $logoListFile
    DIR=`pwd`
    cd $domOutDir/hmm && zip -r $zipFile . -i '*'
    cd \$DIR

SCRIPT
            );
        }
    }

    ########## DOMAIN - CONSENSUS RESIDUE
    if ($hmmOption =~ m/CR/i) {
        foreach my $aa (@aas) {
            my $consDir = "$domOutDir/consensus_residue_results_$aa";
            my $consZipName = "${zipPrefix}ConsensusResidue_${aa}_Domain.zip";
            my $consZip = "$resultsPath/$consZipName";
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
    $appDir/collect_aa_ids.pl --aa-count-file $consDir/${baseFile}_position.txt --output-dir $listDir --id-mapping $domainMapFile
SCRIPT
                );
                $mergeCounts .= " --position-file $ct=$consDir/${baseFile}_position.txt";
                $mergePercent .= " --percentage-file $ct=$consDir/${baseFile}_percentage.txt";
            }
            my $outBaseName = "${zipPrefix}ConsensusResidue_${aa}";
            my $posSumFileName = "${outBaseName}_Position_Summary_Domain.txt";
            my $pctSumFileName = "${outBaseName}_Percentage_Summary_Domain.txt";
            $B->addAction(<<SCRIPT
    $appDir/make_summary_tables.pl --position-summary-file $resultsPath/$posSumFileName --percentage-summary-file $resultsPath/$pctSumFileName $mergeCounts $mergePercent
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
    if ($hmmOption =~ m/HIST/i) {
        my $outputFn = sub {
            my $dirs = shift;
            my $urType = shift;
            my $fileType = lc($urType);
            my $zipFilename= "${zipPrefix}LenHist_${fileType}_Domain.zip";
            my $zipFile = "$resultsPath/$zipFilename";
            my $outDir = "$domOutDir/hist-$fileType";
            $B->addAction(<<SCRIPT
    mkdir -p $outDir
    find $dirs->{fasta_dir} -name 'cluster_*.fasta' -type f -print0 | sed 's%$dirs->{fasta_dir}/\\([a-z_0-9]\\+\\)\\.fasta%\\1%g' | xargs -P $np -0 -I % $appDir/make_length_histo.pl -seq-file $dirs->{fasta_dir}/%.fasta -histo-file $outDir/%.txt
    find $outDir -name '*.txt' -type f -not -empty -print0 | sed 's%\\($outDir/[a-z_0-9]\\+\\)\\.txt%\\1%g' | xargs -P $np -0 -I % Rscript $appDir/hist-length.r legacy %.txt %.png 0 'Domain-UniProt' 700 315
    find $outDir -name '*.png' | sed 's%$outDir/\\(cluster_\\(domain\\)\\?_\\?\\([0-9]\\+\\)\\)\\.png%\\3\\tdomain\\t$fileType\\t$hmmRelPath/domain/hist-$fileType/\\1%g' >> $histListFile
    DIR=`pwd`
    cd $outDir && zip -r $zipFile . -i '*.png'
    cd \$DIR
SCRIPT
            );
        };
        if ($info->{uniprot_domain}) {
            &$outputFn($info->{uniprot_domain});
        } elsif ($info->{uniref90_domain}) {
            &$outputFn($info->{uniref90_domain});
        } elsif ($info->{uniref50_domain}) {
            &$outputFn($info->{uniref50_domain});
        }
    }

    $B->addAction(<<SCRIPT
fi

#cd $hmmDataDir && zip -r $info->{hmm_zip} . -i '*'

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

