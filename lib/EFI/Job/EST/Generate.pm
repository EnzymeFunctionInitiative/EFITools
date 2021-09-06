
package EFI::Job::EST::Generate;

use strict;
use warnings;

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use lib dirname(abs_path(__FILE__)) . "/../../../";

use parent qw(EFI::Job::EST);

use constant DEFAULT_BLAST_EVALUE => 5;


sub new {
    my $class = shift;
    my %args = @_;

    my $self = $class->SUPER::new(%args);

    my %options = (
        "evalue" => "i",
        "max-sequence|maxsequence" => "i",
        "max-blast-hits|blasthits" => "i",
        "inc-frac|incfrac" => "f",
        "seq-count-file" => "s",
        "length-diff|lengthdif" => "s",
        "seq-id-threshold|sim" => "i",
        "multiplex" => "s",
        "blast-type|blast" => "s",
        "oldgraphs" => "",
        "graph-version" => "i",
        "exclude-fragments" => "",
        "no-demux" => "",
        "use-hdf5" => "",
    );
    my $parms = $args{option_parser}->getOptions(\%options);

    my $conf = validateOptions($parms);

    $self->setupDefaults($conf);

    $self->{conf}->{generate} = $conf;

    return $self;
}


sub addStandardEnv {
    my $self = shift;
    my $B = shift;
    
    my $func = $B;
    if (ref($B) ne "CODE") {
        $func = sub { $B->addAction(shift); };
    }

    my @mods = $self->getEnvironment("est-std");
    map { $func->($_); } @mods;
}


sub addRemoveTempFiles {
    my $self = shift;
    my $B = shift;

    if ($self->{config}->{remove_temp}) {
        my $outputDir = $self->getOutputDir();
        my $conf = $self->{conf}->{generate};
        $B->addAction("rm $outputDir/alphabetized.blastfinal.tab $conf->{blast_final_file} $outputDir/sorted.alphabetized.blastfinal.tab $outputDir/unsorted.1.out $outputDir/mux.out");
        $B->addAction("rm $conf->{blast_output_dir}/blastout-*.tab");
        $B->addAction("rm $conf->{frac_dir}/fracfile-*.fa");
    }
}


sub validateOptions {
    my $parms = shift;
    my $self = shift;

    my $conf = {};
    $conf->{evalue} = "1e-" . (($parms->{evalue} // 5) or 5);
    $conf->{max_sequence} = $parms->{"max-sequence"} // 0;
    $conf->{max_full_family} = $parms->{"max-full-family"} // 0;
    $conf->{max_blast_hits} = $parms->{"max-blast-hits"} // 1000000;
    $conf->{inc_frac} = $parms->{"inc-frac"} // 1;
    $conf->{seq_count_file} = $parms->{"seq-count-file"} // "";
    $conf->{cdhit_length_diff} = $parms->{"length-diff"} // 1;
    $conf->{cdhit_seq_id_threshold} = $parms->{"seq-id-threshold"} // 1;
    $conf->{multiplex} = ($parms->{multiplex} and $parms->{multiplex} eq "off") ? 0 : 1;
    $conf->{blast_type} = $parms->{"blast-type"} // "blast";
    $conf->{graph_version} = ($parms->{"oldgraphs"} or not $parms->{"graph-version"}) ? 1 : $parms->{"graph-version"};
    $conf->{exclude_fragments} = $parms->{"exclude-fragments"} ? 1 : 0;
    $conf->{no_demux} = $parms->{"no-demux"} ? 1 : 0;
    $conf->{use_hdf5} = $parms->{"use-hdf5"} ? 1 : 0;

    return $conf;
}


sub setupDefaults {
    my $self = shift;
    my $conf = shift;

    my $outputDir = $self->getOutputDir();

    $conf->{seq_count_file} = "$outputDir/acc_counts.txt";
    $conf->{acc_list_file} = "$outputDir/accession.txt";
    $conf->{filt_seq_filename} = "sequences.fa";
    $conf->{filt_seq_file} = "$outputDir/$conf->{filt_seq_filename}";
    $conf->{all_seq_file} = "$outputDir/allsequences.fa";
    $conf->{frac_dir} = "$outputDir/fractions";
    $conf->{blast_final_file} = "$outputDir/blastfinal.tab";
    $conf->{blast_output_dir} = "$outputDir/blastout";
    $conf->{struct_file} = "$outputDir/struct.out";
    $conf->{error_file} = "$conf->{acc_list_file}.failed";
    $conf->{len_uniprot_file} = "$outputDir/length_uniprot.tab"; # full lengths of all UniProt sequences (expanded from UniRef if necessary)
    $conf->{len_uniprot_dom_file} = "$outputDir/length_uniprot_domain.tab"; # domain lengths of all UniProt sequences (expanded from UniRef if necessary)
    $conf->{len_uniref_file} = "$outputDir/length_uniref.tab"; # full lengths of UR cluster ID sequences
    $conf->{len_uniref_dom_file} = "$outputDir/length_uniref_domain.tab"; # domain lengths of UR cluster ID sequences
    $conf->{uniref_flag_file} = "$outputDir/use_uniref"; # domain lengths of UR cluster ID sequences
}


sub getJobInfo {
    my $self = shift;
    my $info = $self->SUPER::getJobInfo();
    my $conf = $self->{conf}->{generate};

    (my $evalue = $conf->{evalue}) =~ s/^1e-//;
    push @$info, [evalue => $evalue] if $evalue != DEFAULT_BLAST_EVALUE;
    push @$info, [exclude_fragments => $conf->{exclude_fragments}] if $conf->{exclude_fragments};

    return $info;
}


sub outputSharedUsage {
    my $self = shift;
    my ($mandatory, $optional, $descs) = @_;

    my $usage = join(" ", @$mandatory) . "\n    ";
    $usage .= "[" . fancyJoin(" ", @$optional, "--exclude-fragments") . "]\n\n";;

    foreach my $desc (@$descs, ["--exclude-fragments", "exclude sequences that are defined as fragments by UniProt"]) {
        $usage .= sprintf "    %-19s %s\n", $desc->[0], fancyJoin(" ", split(m/ /, $desc->[1]), 23);
    }
    
    return $usage;
}


sub fancyJoin {
    my $sep = shift;
    my @parts = @_;

    my $indent = pop @parts if $parts[$#parts] =~ m/^\d+$/;
    $indent = 4 if not $indent;

    my $str = "";
    my $len = 0;
    foreach my $p (@parts) {
        $str .= $sep if $str;
        $str .= $p;
        $len += length $p;
        if ($len > 90 - $indent) {
            $str .= "\n" . $sep x $indent;
            $len = 0;
        }
    }

    $str =~ s/\s+$//gs;

    return $str;
}


sub makeJobs {
    my $self = shift;
    return ();
}


1;

