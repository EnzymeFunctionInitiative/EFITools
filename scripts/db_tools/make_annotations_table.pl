#!/usr/bin/env perl

use strict;

use Getopt::Long;
use List::MoreUtils qw{apply uniq any} ;
use FindBin;
use Data::Dumper;

use lib "$FindBin::Bin/../../lib";
use lib "$FindBin::Bin/lib";

use EFI::IdMapping::Util;
use EFI::Annotations;


my ($inputFile, $outputFile, $fragmentIdFile, $giFile, $efiTidFile, $gdnaFile, $hmpFile);
my ($debug, $idMappingFile, $familyTable, $metadataFormat, $packJson, $alphafoldFile);
my $result = GetOptions(
    "dat=s"             => \$inputFile,
    "annotations=s"     => \$outputFile,
    "fragment-ids=s"    => \$fragmentIdFile,
    "uniprotgi=s"       => \$giFile,
    "efitid=s"          => \$efiTidFile,
    "gdna=s"            => \$gdnaFile,
    "hmp=s"             => \$hmpFile,
    "idmapping=s"       => \$idMappingFile,
    "debug=i"           => \$debug,
    "family-table=s"    => \$familyTable, # Optional
    "metadata-format=s" => \$metadataFormat,
    "pack-json"         => \$packJson,
    "alphafold=s"       => \$alphafoldFile
);

my $usage = <<USAGE;
Usage: $0 --dat combined_dat_input_file --annotations output_annotations_tab_file
            [-uniprotgi gi_file_path --efitid efi_tid_file_path --gdna gdna_file_path --hmp hmp_file_path
             --debug num_iterations_to_run --idmapping idmapping_tab_file_path
             --uniref50 uniref50_tab_file --uniref90 uniref90_tab_file --pfam pfam_tab_file
             --interpro interpro_tab_file --family-table tab_file --metadata-format json|tab
             --alphafold alphafold_csv_file]

    Anything in [] is optional.

        --uniprotgi  will include GI numbers, otherwise they are left out
        --idmapping  use the idmapping.tab file output by the import_id_mapping.pl script to obtain the
                    refseq, embl-cds, and gi numbers 
        --metadata-format controls the metadata columns; if it's json then they are stored in a single column
                    in JSON format.  If it's tab they values are stored in separate columns.

USAGE


die "Input file --dat argument is required: $usage" if (not defined $inputFile or not -f $inputFile);
die "Output file --struct argument is required; $usage" if not $outputFile;



my (%EfiTidData, %HmpData, %GdnaData, %GI, %alphafoldData);
if ($giFile) {
    getGiNums();
}
if ($gdnaFile) {
    getGdnaData();
}
if ($hmpFile) {
    #the key for %HmpData is the taxid
    getHmpData();
}
if ($efiTidFile) {
    getEfiTids();
}
if ($alphafoldFile) {
print "Loading AF\n";
    %alphafoldData = getAlphafoldData($alphafoldFile);
print "AF Loaded\n";
}




my $metadataFormat = $metadataFormat // "json";
my $debugNumRows = $debug // 2**50;



my $Data = {};
my $Fields = getFields(); # In appropriate order
my $Handlers = getHandlers(); # A handler is a parsing function

print "Parsing DAT Annotation Information\n";

open my $datFh, "<", $inputFile or die "could not open dat file $inputFile\n";
open my $structFh, ">", $outputFile or die "could not write struct data to $outputFile\n";
open my $fragIdsFh, ">", $fragmentIdFile or die "could not write struct data to $fragmentIdFile\n" if $fragmentIdFile;
open my $familyTableFh, ">", $familyTable if $familyTable;

my $currentId = ""; # Not the UniProt accession ID
my $lastLine;
my $commentBlockState = {};

my $lc = 0;
$| = 1;

my $debugNumRows = 0;
while (my $line = <$datFh>) {
    chomp $line;
    $line =~ s/\&/and/g;
    $line =~ s/\\//g;

    if (not ($lc++ % 1000000)) {
        print "$lc\n";
    }

    if ($line =~ /^ID\s+(\w+)\s+(\w+);\s+(\d+)/) {
        # Stop after a certain number of UniProt records
        last if ($debug and $debugNumRows++ > $debug);

        if ($currentId) {
            writeUniprotRecord($Data, $Fields, $commentBlockState);
        }

        $currentId = $1;
        my $swissprotStatus = $2;
        my $aaSize = $3;
        $swissprotStatus = $swissprotStatus eq "Reviewed" ? 1 : 0;
        my $meta = initMeta($Fields);
        $meta->{uniprot_id} = $currentId;
        $Data = {acc_id => "", swissprot_status => $swissprotStatus, length => $aaSize, tax_id => 0, is_fragment => 0, metadata => $meta};
        $commentBlockState = {};
    } elsif ($line =~ /^AC\s+(\w+);?/) {
        if ($lastLine !~ /^AC/) {
            my $acc = $1;
            print "Found UniProt ID $acc\n" if $debug;
            $Data->{acc_id} = $acc;
            &{$Handlers->{efi_tid}}($Data->{metadata}, $acc);
            &{$Handlers->{alphafold}}($Data->{metadata}, $acc);
        }
    } elsif ($line =~ /^OX\s+NCBI_TaxID\s*=\s*(\d+)/) {
        my $taxId = $1;
        $Data->{tax_id} = $taxId;
        &{$Handlers->{gdna}}($Data->{metadata}, $taxId);
        &{$Handlers->{hmp}}($Data->{metadata}, $taxId);
    } elsif ($line =~ /^CC\s+(.*)$/) {
        processCommentBlock($1, $commentBlockState);
    } elsif ($line =~ /^(\S\S)\s+(.*)$/) {
        my $recType = $1;
        my $value = $2;
        processLine($Data, $recType, $value);
    }
    $lastLine = $line;
}


writeUniprotRecord($Data, $Fields, $commentBlockState);

close $familyTableFh if $familyTableFh;
close $fragIdsFh if $fragIdsFh;
close $structFh;
close $datFh;


print "Wrote the following columns to the annotations table:\n    ";

my @metadataFields = map { $_->{name} } grep { $_->{field_type} eq "db" and not $_->{db_hidden} } @$Fields;
print join("\n    ", "accession", @metadataFields);
print "\n";





sub processLine {
    my $data = shift;
    my $recType = shift;
    my $record = shift;

    $recType = lc $recType;
    if ($Handlers->{$recType}) {
        &{$Handlers->{$recType}}($data->{metadata}, $record);
    #} else {
    #    print "Couldn't process $recType // $record\n";
    }
}


sub writeUniprotRecord {
    my $data = shift;
    my $fields = shift;
    my $commentBlockState = shift;

    postProcessUniprotRecord($data, $commentBlockState);

    my $meta = $data->{metadata};

    my $jsonRow = {};
    my @tabRow;
    foreach my $field (@$fields) {
        my $val = "";
        next if ($field->{field_type} ne "db" or $field->{db_hidden});
        if ($field->{json_type_spec} eq "array") {
            $val = join(",", @{ $meta->{$field->{name}} });
            #$val = "None" if not $val;
        } elsif ($field->{json_type_spec} eq "hash") {
        } else {
            $val = $meta->{$field->{name}};
        }
        my $jsonName = $packJson ? $field->{json_name} // $field->{name} : $field->{name};
        $jsonRow->{$jsonName} = $val if ($val or not $packJson);
        push @tabRow, $val;
    }

    my @line = ($data->{acc_id}, $data->{swissprot_status}, $data->{is_fragment}, $data->{length}, $data->{tax_id});

    if ($metadataFormat eq "json") {
        push @line, EFI::Annotations::save_meta_struct($jsonRow);
    } else {
        push @line, @tabRow;
    }

    print $structFh join("\t", @line), "\n";
    print $fragIdsFh join("\t", $data->{acc_id}), "\n" if $fragIdsFh and $data->{is_fragment};
    map { print $familyTableFh join("\t", $_, $data->{acc_id}), "\n"; } (@{ $meta->{uniprot_interpro} }, @{ $meta->{uniprot_pfam} }) if $familyTableFh;
}


sub postProcessUniprotRecord {
    my $data = shift;
    my $ccState = shift; # comment block state

    my $meta = $data->{metadata};

    my $deDesc = $meta->{description} // "";
    $deDesc =~ s/[<>]//g;
    $deDesc =~ s/\s+/ /g;
    $deDesc =~ s/\&/and/g;
    $deDesc =~ s/^\s+//g;

    $data->{is_fragment} = ($deDesc =~ /Flags:.*Fragment/) ? 1 : 0;

    if ($deDesc =~ /^\s*RecName:\s+Full\s*=\s*(.*)$/) {
        $deDesc = $1;
        $deDesc =~ s/\{.*\}//g;
        $deDesc =~ s/Short[:=].*$//;
        $deDesc =~ s/Flags[:=].*$//;
        $deDesc =~ s/AltName[:=].*$//;
        $deDesc =~ s/RecName[:=].*$//;
        $deDesc =~ s/\s*=\*//g;
    } elsif ($deDesc =~ /^\s*SubName:\s*Full\s*=\s*(.*)$/) {
        $deDesc = $1;
        $deDesc =~ s/\{.*\}//g;
        $deDesc =~ s/Short[:=].*$//;
        $deDesc =~ s/Flags[:=].*$//;
        $deDesc =~ s/AltName[:=].*$//;
        $deDesc =~ s/RecName[:=].*$//;
        $deDesc =~ s/\s*=\*//g;
        #print "second $deDesc\n";
    } else {
        print "Unmatched DE record: $deDesc\n";
    }

    $deDesc =~ s/{.*?}//g;
    $deDesc =~ s/^\s*(.*?)\s*$/$1/;
    $deDesc =~ s/\s+;$//;

    $meta->{description} = $deDesc;
    #$meta->{reviewed_description} = lc $data->{swissprot_status} eq "reviewed" ? $deDesc : ""; # Previously NA

    if ($meta->{organism} =~ m/(.*?)\s*\(/) {
        my $osName = $1;
        if ($meta->{organism} =~ m/(\(strain.*?\))/) {
            $meta->{organism} = "$osName $1";
        } else {
            $meta->{organism} = $osName;
        }
    }

    my $parseFn = sub {
        my $text = shift;
        my @primaryParts = split(m/;\s+/, $text);
        foreach my $ppart (@primaryParts) {
            if ($ppart =~ m/Xref=(.*?)\s*$/) {
                my @xrefs = split(m/,\s+/, $1);
                foreach my $xref (@xrefs) {
                    my ($type, $ref) = split(m/:/, $xref, 2);
                    $type = lc $type;
                    $ref =~ s/\s//g;
                    push @{ $meta->{$type} }, $ref if exists $meta->{$type};
                }
            }
        }
    };
    if ($ccState->{topic}) {
        if ($ccState->{reaction}) {
            &$parseFn($ccState->{reaction});
        }
        if ($ccState->{phys_dir}) {
            &$parseFn($ccState->{phys_dir});
        }
    }
}
















sub getHandlers {

    my %handlers;

    my $de_ec_handler = sub { $_[0]->{ec_code} = $_[1]; };
    my $de_desc_handler = sub { $_[0]->{description} .= $_[1]; };
    $handlers{de} = sub {
        my $data = shift;
        my $val = shift;
        $val =~ /(.*)\s*=\s*(.*);/;
        if ($1 eq "EC") {
            &$de_ec_handler($data, $2);
        } else {
            &$de_desc_handler($data, $val);
        }
    };

    $handlers{os} = sub { $_[0]->{organism} .= $_[1]; };

    $handlers{dr_pfam} = sub { push @{ $_[0]->{uniprot_pfam} }, $_[1]; };
    $handlers{dr_pdb} = sub { push @{ $_[0]->{pdb} }, $_[1]; };
    $handlers{dr_cazy} = sub { push @{ $_[0]->{cazy} }, $_[1]; };
    $handlers{dr_interpro} = sub { push @{ $_[0]->{uniprot_interpro} }, $_[1]; };
    $handlers{dr_kegg} = sub { push @{ $_[0]->{kegg} }, $_[1]; };
    $handlers{dr_string} = sub { push @{ $_[0]->{string} }, $_[1]; };
    $handlers{dr_brenda} = sub { push @{ $_[0]->{brenda} }, ($_[2] ? "$_[1] $_[2]" : $_[1]); };
    $handlers{dr_patric} = sub { push @{ $_[0]->{patric} }, $_[1]; };
    $handlers{dr_go} = sub {
        my $data = shift;
        my $val = shift;
        my $extra = shift || "";
        $val =~ s/\D//g;
        if ($extra =~ m/F:(.*);/) {
            $extra = "$val $1";
            $extra =~ s/,/ /g;
            push @{ $data->{go} }, $extra;
        }
    };
    $handlers{dr} = sub {
        my $data = shift;
        my $val = shift;
        (my $type = $val) =~ s/^(\w+);\s+(\S+)\s+(.*?)$/$1/;
        my $extra = $3;
        (my $keyvalue = $2) =~ s/[\.;]*\s*$//;
        $extra =~ s/[\.;]*\s*$//;
        $type = lc $type;
        &{$handlers{"dr_$type"}}($data, $keyvalue, $extra) if $handlers{"dr_$type"};
    };

    $handlers{kw_rp} = sub {
        my $data = shift;
        my $val = shift;
        if ($val =~ m/^(\s+\{([^\}]+)\})/) {
            $data->{kw_rp} = $2;
        } else {
            $data->{kw_rp} = 1;
        }
    };
    $handlers{kw} = sub {
        my $data = shift;
        my $val = shift;
        if ($val =~ m/Reference proteome(.*)/) {
            &{$handlers{kw_rp}}($data, $1);
        }
    };

    $handlers{oc} = sub {
        my $data = shift;
        my $val = shift;
        my @parts = split /;/, $val;
        $data->{oc_domain} .= $parts[0];
    };
    $handlers{gn} = sub {
        my $data = shift;
        my $val = shift;
        if ($val =~ m/\w+=(\w+)/) {
            $data->{gn_gene} = $1;
        } else {
            $data->{gn_gene} = "";
        }
    };

    ## Todo: make this more robust, handle all Xrefs
    #$handlers{cc_xref_rhea} = sub {
    #    my $data = shift;
    #    my $val = shift;
    #    $data->{rhea} = $val;
    #};
    #$handlers{cc_xref} = sub {
    #    my $data = shift;
    #    my $val = shift;
    #    my @xrefs = split(m/; /, $1);
    #    foreach my $xref (@xrefs) {
    #        my ($xrefType, $xrefIdentifier) = split(m/:/, $xref, 2);
    #        $xrefType = lc $xrefType;
    #        my $k = "cc_xref_$xrefType";
    #        if ($handlers{$k}) {
    #            &{$handlers{$k}}($data, $xrefIdentifier);
    #        }
    #    }
    #};
    #$handlers{cc} = sub {
    #    my $data = shift;
    #    my $val = shift;
    #    if ($val =~ m/Xref=(.*)$/) {
    #        if ($handlers{cc_xref}) {
    #            &{$handlers{cc_xref}}($data, $1);
    #        }
    #    }
    #};

    $handlers{gdna} = sub {
        my $data = shift;
        my $taxId = shift;
        $data->{gdna} = $GdnaData{$taxId} ? "1" : "0"; # Previously True/False
    };
    $handlers{hmp} = sub {
        my $data = shift;
        my $taxId = shift;
        $data->{hmp} = $HmpData{$taxId} ? "1" : "0"; # Previously Yes/NA\
        $data->{hmp_site} = $HmpData{$taxId}{"sites"} // ""; # Previously None
        $data->{hmp_oxygen} = $HmpData{$taxId}{"oxygen"} // ""; # Previously None
    };
    $handlers{efi_tid} = sub {
        my $data = shift;
        my $uniprotId = shift;
        $data->{efi_tid} = $EfiTidData{$uniprotId} ? $EfiTidData{$uniprotId} : ""; # Previously NA
    };
    $handlers{gi} = sub {
        my $data = shift;
        my $uniprotId = shift;
        my $giLine = ""; # Previously None
        if (exists $GI{$uniprotId}) {
            $giLine = $GI{$uniprotId}{"number"} . ":" . $GI{$uniprotId}{"count"};
        }
        $data->{gi} = $giLine;
    };
    $handlers{alphafold} = sub {
        my $data = shift;
        my $uniprotId = shift;
        if ($alphafoldData{$uniprotId}) {
            $data->{alphafold} = $alphafoldData{$uniprotId}->{af_id};
        }
    };

    return \%handlers;
}


sub processCommentBlock {
    my $data = shift;
    my $state = shift;
    if ($data =~ m/^\s*-!- (.*?):?\s*$/) {
        my $topic = $1;
        if ($state->{cur_topic}) {
            #TODO; process the topic;
        }
        return if $topic ne "CATALYTIC ACTIVITY";
        $state->{topic} = $topic;
        $state->{section} = "";
        $state->{reaction} = "";
        $state->{phys_dir} = "";
    } elsif ($data =~ m/^\s*Reaction=(.*)$/) {
        $state->{section} = "reaction";
        $state->{reaction} = $1;
    } elsif ($data =~ m/^\s*PhysiologicalDirection=(.*)$/) {
        $state->{section} = "phys_dir";
        $state->{phys_dir} = $1;
    } elsif ($state->{topic} and $state->{section}) {
        $state->{$state->{section}} .= " " . $data;
    }
}


sub initMeta {
    my $fields = shift;
    my $data = {};
    foreach my $field (@$fields) {
        if ($field->{json_type_spec} eq "array") {
            $data->{$field->{name}} = [];
        } elsif ($field->{json_type_spec} eq "hash") {
            $data->{$field->{name}} = {};
        } else {
            $data->{$field->{name}} = "";
        }
    }
    return $data;
}


sub getFields {
    my @fields = EFI::Annotations::get_annotation_fields();
    return \@fields;
    #my @fields;
    #push @fields, {name => "ec_code", json_type_spec => "str"};
    #push @fields, {name => "description", json_type_spec => "str"};
    #push @fields, {name => "organism", json_type_spec => "str"};
    #push @fields, {name => "uniprot_pfam", json_type_spec => "array", hidden => 1};
    #push @fields, {name => "pdb", json_type_spec => "array"};
    #push @fields, {name => "cazy", json_type_spec => "array"};
    #push @fields, {name => "uniprot_interpro", json_type_spec => "array", hidden => 1};
    #push @fields, {name => "kegg", json_type_spec => "array"};
    #push @fields, {name => "string", json_type_spec => "array"};
    #push @fields, {name => "brenda", json_type_spec => "array"};
    #push @fields, {name => "patric", json_type_spec => "array"};
    #push @fields, {name => "go", json_type_spec => "array"};
    #push @fields, {name => "organism", json_type_spec => "str"};
    #push @fields, {name => "kw_rp", json_type_spec => "str"};
    #push @fields, {name => "oc_domain", json_type_spec => "str", hidden => 1};
    #push @fields, {name => "gn_gene", json_type_spec => "str"};
    #push @fields, {name => "rhea" => json_type_spec => "array"};
    #push @fields, {name => "efi_tid", json_type_spec => "str"};
    #push @fields, {name => "hmp", json_type_spec => "str"};
    #push @fields, {name => "hmp_site", json_type_spec => "str"};
    #push @fields, {name => "hmp_oxy", json_type_spec => "str"};
    #push @fields, {name => "gdna", json_type_spec => "str"};
    #push @fields, {name => "reviewed_description", json_type_spec => "str"};
    #return \@fields;
}









sub getAlphafoldData {
    my $file = shift;

    my %data;

    open my $fh, "<", $file or die "Unable to open alphafold file $file: $!\n";
    while (my $line = <$fh>) {
        chomp $line;
        next if $line =~ m/^\s*$/;
        my ($uniprotId, $firstRes, $lastRes, $afId, $ver) = split(m/,/, $line);
        $data{$uniprotId} = {af_id => $afId, first_res => $firstRes, last_res => $lastRes, last_ver => $ver};
    }
    close $fh;

    return %data;
}


sub getEfiTids {
    open my $efitidFh, "<", $efiTidFile or die "could not open efi target id file $efiTidFile\n";
    while (my $line = <$efitidFh>) {
        chomp $line;
        my @parts = split /\t/, $line;
        $EfiTidData{@parts[2]} = $parts[0];
    }
    close $efitidFh;
}


sub getHmpData {
    open my $hmpFh, $hmpFile or die "could not open gda file $hmpFile\n";
    while (my $line = <$hmpFh>) {
        chomp $line;
        my @line = split /\t/, $line;
        if ($line[16] eq "") {
            $line[16] = 'Not Specified';
        }
        if ($line[47] eq "") {
            $line[47] = 'Not Specified';
        }
        if ($line[5] eq "") {
            die "key is an empty value\n";
        }
        $line[16] =~ s/,\s+/,/g;
        $line[47] =~ s/,\s+/,/g;
        push @{$HmpData{$line[5]}{'sites'}}, $line[16];
        push @{$HmpData{$line[5]}{'oxygen'}}, $line[47];
    }
    close $hmpFh;
    
    #remove hmp doubles and set up final hash
    foreach my $key (keys %HmpData) {
        $HmpData{$key}{'sites'} = join(",", uniq split(",",join(",", @{$HmpData{$key}{'sites'}})));
        $HmpData{$key}{'oxygen'} = join(",", uniq split(",",join(",", @{$HmpData{$key}{'oxygen'}})));
    }
}


sub getGdnaData {
    open my $gdnaFh, $gdnaFile or die "could not open gdna file $gdnaFile\n";
    while (my $line = <$gdnaFh>) {
        chomp $line;
        $GdnaData{$line} = 1;
    }
    close $gdnaFh;
}


sub getGiNums {
    open my $giFh, $giFile or die "could not open $giFile for GI\n";
    while (my $line = <$giFh>) {
        chomp $line;
        my @line = split /\s/, $line;
        $GI{@line[0]}{'number'} = @line[2];
        if (exists $GI{@line[0]}{'count'}) {
            $GI{@line[0]}{'count'}++;
        } else {
            $GI{@line[0]}{'count'} = 0;
        }
    }
    close $giFh;
}


