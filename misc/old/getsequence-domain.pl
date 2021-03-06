#!/usr/bin/env perl

BEGIN {
    die "Please load efishared before runing this script" if not $ENV{EFISHARED};
    use lib $ENV{EFISHARED};
}

#version 0.9.0 moved from getting accesions by grepping files to using sqlite database
#version 0.9.0 options of specifing ssf and gene3d numbers added
#version 0.9.2 modified to accept 6-10 characters as accession ids
#version 0.9.3 modified to use cfg file to load location of variables for database
#version 0.9.4 change way cfg file used to load database location
#version 1.0.0 added fasta parsing and manual accessions

use warnings;
use strict;

use Getopt::Long;
use List::MoreUtils qw{apply uniq any} ;
use FindBin;
use Data::Dumper;
use Capture::Tiny ':all';
use EFI::IdMapping;
use EFI::IdMapping::Util;
use EFI::Fasta::Headers;
use EFI::Database;
use EFI::Annotations;

use lib "$FindBin::Bin/lib";
use FileUtil;



my ($ipro, $pfam, $gene3d, $ssf, $access, $maxsequence, $manualAccession, $accessionFile, $useOptionASettings);
my ($fastaFileOut, $fastaFileIn, $metaFileOut, $useFastaHeaders, $useDomain, $domainFamily, $fraction, $noMatchFile);
my ($seqCountFile, $unirefVersion, $unirefExpand, $configFile, $errorFile, $randomFraction, $maxFullFam);
my ($minSeqLen, $maxSeqLen, $mapUniref50to90);

my $result = GetOptions(
    "ipro=s"                => \$ipro,
    "pfam=s"                => \$pfam,
    "gene3d=s"              => \$gene3d,
    "ssf=s"                 => \$ssf,
    "accession-output=s"    => \$access,
    "error-file=s"          => \$errorFile,
    "maxsequence=s"         => \$maxsequence,
    "max-full-fam-ur90=i"   => \$maxFullFam,
    "accession-id=s"        => \$manualAccession,
    "accession-file=s"      => \$accessionFile,
    "use-option-a-settings" => \$useOptionASettings, # This option appends the retrieved IDs to the accession file (used in the Option A/BLAST pipeline)
    "out=s"                 => \$fastaFileOut,
    "fasta-file=s"          => \$fastaFileIn,
    "meta-file=s"           => \$metaFileOut,
    "use-fasta-headers"     => \$useFastaHeaders,
    "domain=s"              => \$useDomain,
    "domain-family=s"       => \$domainFamily, # domainFamily is for option D
    "fraction=i"            => \$fraction,
    "random-fraction"       => \$randomFraction,
    "no-match-file=s"       => \$noMatchFile,
    "seq-count-file=s"      => \$seqCountFile,
    "min-seq-len=i"         => \$minSeqLen,
    "max-seq-len=i"         => \$maxSeqLen,
    "uniref-version=s"      => \$unirefVersion,
    "uniref-expand"         => \$unirefExpand,  # expand to include all homologues of UniRef seed sequences that are provided.
    "map-uniref-50-to-90"   => \$mapUniref50to90, # expand the uniref50 seed sequence clusters to uniref90 and then continue
    "config=s"              => \$configFile,
);

#die "Command-line arguments are not valid: missing -config=config_file_path argument" if not defined $configFile or not -f $configFile;
die "Environment variables not set properly: missing EFIDB variable" if not exists $ENV{EFIDB};

my $perpass = (exists $ENV{EFIPASS} and $ENV{EFIPASS}) ? $ENV{EFIPASS} : 1000;
my $data_files = $ENV{EFIDBPATH};
my %ids;
my %accessionhash;
my @ipros;
my @pfams;
my @gene3ds;
my @ssfs;
my @manualAccessions;
my %blastHitsIds; # A list of IDs that we exclude from database retrieval.
my $headerData = {}; # Header data for fasta and accession file inputs.
my @accessions; # accessions from the input family


verifyArgs();

parseFamilyArgs();

my $db = new EFI::Database(config_file_path => $configFile);
my $dbh = $db->getHandle();


#######################################################################################################################
# DATA FOR MAPPING UNIREF50 AND UNIREF90 CLUSTER IDS TO ACCESSION IDS
#
my $unirefData = {};
# If $unirefVersion is set, %accessionhash will contain the UniRef cluster IDs that are in the family.


######################################################################################################################
# COUNTS FOR KEEPING TRACK OF THE VARIOUS TYPES OF IDS
my $familyIdCount = 0; # This is the number of IDs that came from the family, accounting for UniRef.
my $fullFamilyIdCount = 0; # This is the full family size
my $fileFastaUnmatchedIdCount = 0;
my $fileFastaReplSeqCount = 0;     # The number of sequences that were duplicated due to multiple IDs in the FASTA file.

my $fileAccOrigIdCount = 0;        # The number of raw IDs in the accession input file.
my $fileAccMatchedIdCount = 0;      # The number of UniProt IDs in the accession input file.
my $fileAccUnmatchedIdCount = 0;    # The number of unmatched IDs in the accession input file.
my $fileAccDupCount = 0;            # The number of accession IDs in the input file that are duplicates of each other.
my $fileAccOverlapCount = 0;        # The number of sequences in the file that overlap the input family (accession).
my $fileAccAdded = 0;               # The number of sequences in the file that were actually added.
my $fileAccUnirefOverlapCount = 0;  # The number of IDs that are members of UniRef clusters (not included since we're already including the cluster ID).

my $fileFastaOrigSeqCount = 0;      # The number of actual sequences in the FASTA file, not the number of IDs or headers.
my $fileFastaMatchedIdCount = 0;
my $fileFastaTotalIdCount = 0;
my $fileFastaOverlapCount = 0;      # The number of sequences in the file that overlap the input family (FASTA).
my $fileFastaNumHeaders = 0;        # The number of headers in the FASTA file.


######################################################################################################################
# PARSE ANY MANUAL ACCESSION FILE FOR IDS
#
if (defined $accessionFile and -f $accessionFile) {
    parseManualAccessionFile();
}

if ($useOptionASettings and defined $access and -f $access) {
    getExcludeIds();
}

# Do reverse-id database lookup if we've been given manual accessions.
my $idMapper;
if ($#manualAccessions >= 0) {
    $idMapper = new EFI::IdMapping(config_file_path => $configFile);
}


#######################################################################################################################
# PARSE FASTA FILE FOR HEADER IDS (IF ANY)
#
my @fastaUniprotIds;
if ($fastaFileIn and $fastaFileIn =~ /\w+/ and -s $fastaFileIn) {
    parseFastaFile();
} else {
    $fastaFileIn = "";
}

#######################################################################################################################
# GETTING ACCESSIONS FROM INTERPRO, PFAM, GENE3D, AND SSF FAMILY(S), AND/OR PFAM CLANS
#

# Map any UniRef cluster members to the UniRef seed sequence.  Used to avoid duplicates from Option C and Option D inputs.
my %unirefMapping;
my %inFamilyIds;
my $FracCount = 0;
my $FracFlag = 0;
retrieveFamilyAccessions();


#######################################################################################################################
# ADDING MANUAL ACCESSION IDS FROM FILE OR ARGUMENT
#
# Reverse map any IDs that aren't UniProt.
my $accUniprotIdRevMap = {};
my @accUniprotIds;
my $noMatches;
if ($#manualAccessions >= 0) {
    if ($mapUniref50to90) {
        expandUnirefSequences();
    }
    if ($unirefVersion and not $unirefExpand) {
        addUnirefData();
    } elsif ($unirefExpand and not $mapUniref50to90) {
        expandUnirefSequences();
    }
    reverseLookupManualAccessions();
}

$idMapper->finish() if defined $idMapper;
print "Done with rev lookup\n";


my $showNoMatches = (($#manualAccessions >= 0 ? 1 : 0) and defined $noMatchFile);
# Write out the no matches to a file.
if ($showNoMatches) {
    openNoMatchesFile();
}


#######################################################################################################################
# VERIFY THAT THE ACCESSIONS ARE IN THE DATABASE AND RETRIEVE THE DOMAIN
#


#######################################################################################################################
# VERIFY THAT THE ACCESSIONS ARE IN THE DATABASE AND RETRIEVE THE DOMAIN
#
my %inUserIds;

my $sth;
if (scalar @accUniprotIds) {
    verifyAccessions();
}

$sth->finish if $sth;
$dbh->disconnect();


my $numIdsToRetrieve = scalar @accessions;
print "There are a total of $numIdsToRetrieve IDs whose sequences will be retrieved.\n";

checkMaxSequencesExceeded();

writeAccessions();

my @err;
my @origAccessions;
retrieveSequences();

writeMetadata();

writeErrors();

closeNoMatchesFile();

writeSequenceCountFile();

print "Completed getsequences\n";




















sub parseFastaHeaders {
    my ($fastaFileIn, $fastaFileOut, $useFastaHeaders, $idMapper, $seqMeta, $configFile, $fraction) = @_;

    my $parser = new EFI::Fasta::Headers(config_file_path => $configFile);

    open INFASTA, $fastaFileIn;
    open FASTAOUT, ">$fastaFileOut";

    my %seq;        # actual sequence data

    my $lastLineIsHeader = 0;
    my $lastId = "";
    my $id;
    my $seqLength = 0;
    my $seqCount = 0;
    my $headerCount = 0;
    while (my $line = <INFASTA>) {
        $line =~ s/[\r\n]+$//;

        my $headerLine = 0;
        my $writeSeq = 0;

        # Option C + read FASTA headers
        if ($useFastaHeaders) {
            my $result = $parser->parse_line_for_headers($line);

            if ($result->{state} eq EFI::Fasta::Headers::HEADER) {
                $headerCount++;
            }
            # When we get here we are at the end of the headers and have started reading a sequence.
            elsif ($result->{state} eq EFI::Fasta::Headers::FLUSH) {
                
                if (not scalar @{ $result->{uniprot_ids} }) {
                    $id = makeSequenceId($seqCount);
                    push(@{$seqMeta->{$id}->{description}}, $result->{raw_headers}); # substr($result->{raw_headers}, 0, 200);
                    $seqMeta->{$id}->{other_ids} = $result->{other_ids};
                    push(@{ $seq{$seqCount}->{ids} }, $id);
                } else {
                    foreach my $res (@{ $result->{uniprot_ids} }) {
                        $id = $res->{uniprot_id};
                        my $ss = $seqMeta->{$id};
                        push(@{ $ss->{query_ids} }, $res->{other_id});
                        foreach my $dupId (@{ $result->{duplicates}->{$id} }) {
                            push(@{ $ss->{query_ids} }, $dupId);
                        }
                        push(@{ $seq{$seqCount}->{ids} }, $id);
                        push(@{ $ss->{other_ids} }, @{ $result->{other_ids} });
                        $ss->{copy_seq_from} = $id;
                        $seqMeta->{$id} = $ss;
                    }
                }

                # Ensure that the first line of the sequence is written to the file.
                $writeSeq = 1;
                $seqCount++;
                $headerLine = 1;

            # Here we have encountered a sequence line.
            } elsif ($result->{state} eq EFI::Fasta::Headers::SEQUENCE) {
                $writeSeq = 1;
            }
        # Option C
        } else {
            # Custom header for Option C
            if ($line =~ /^>/ and not $lastLineIsHeader) {
                $line =~ s/^>//;

                # $id is written to the file at the bottom of the while loop.
                $id = makeSequenceId($seqCount);
                my $ss = exists $seqMeta->{$id} ? $seqMeta->{$id} : {};
                push(@{ $seq{$seqCount}->{ids} }, $id);
                
                push(@{$ss->{description}}, $line);

                $seqCount++;
                $headerLine = 1;
                $headerCount++;

                $seqMeta->{$id} = $ss;
                $lastLineIsHeader = 1;
            } elsif ($line =~ /^>/ and $lastLineIsHeader) {
                $line =~ s/^>//;
                push(@{$seqMeta->{$id}->{description}}, $line);
                $headerCount++;
            } elsif ($line =~ /\S/ and $line !~ /^>/) {
                $writeSeq = 1;
                $lastLineIsHeader = 0;
            }
        }

        if ($headerLine and $seqCount > 1) {
            $seq{$seqCount - 2}->{seq_len} = $seqLength;
            $seqLength = 0;
        }

        if ($writeSeq) {
            my $ss = $seq{$seqCount - 1};
            if (not exists $ss->{seq}) {
                $ss->{seq} = $line . "\n";
            } else {
                $ss->{seq} .= $line . "\n";
            }
            $seqLength += length($line);
        }
    }

    $seq{$seqCount - 1}->{seq_len} = $seqLength;

    my $numMultUniprotIdSeq = 0;
    my @seqToWrite;
    foreach my $seqIdx (sort sortFn keys %seq) {
        # Since multiple Uniprot IDs may map to the same sequence in the FASTA file, we need to write those
        # as sepearate sequences which is what "Expanding" means.
        next if not exists $seq{$seqIdx}->{ids};
        my @seqIds = @{ $seq{$seqIdx}->{ids} };

#        # If the FASTA sequence is present in a UniRef cluster, then we write out the UniRef
#        # cluster ID sequence instead of the FASTA sequence.
#        if (grep { exists($unirefMapping{$_}) } @seqIds) {
#            print "found a sequence in the fasta file that maps to a uniref cluster: ", join(",", @seqIds), "\n";
#            push(@fastaUniref, @seqIds);
#            next;
#        }

        push(@seqToWrite, @seqIds);
        $numMultUniprotIdSeq += scalar @seqIds - 1 if scalar @seqIds > 1; # minus one because we only want to count the number of sequences that were *added*
        print "MULT ", join(",", @seqIds), "\n" if scalar @seqIds > 1;

        # Since the same sequence may be pointed to by multiple uniprot IDs, we need to copy that sequence
        # because it won't by default be saved for all sequences above.
        my $sequence = "";
        if ($seq{$seqIdx}->{seq}) {
            $sequence = $seq{$seqIdx}->{seq};
        }

        foreach my $id (@seqIds) {
            if ($sequence) { #$seqIdx =~ /^z/) {
                print FASTAOUT ">$id\n";
                print FASTAOUT $sequence;
                print FASTAOUT "\n";
            } else {
                print "ERROR: Couldn't find the sequence for $seqIdx\n";
            }
            $seqMeta->{$id}->{seq_len} = $seq{$seqIdx}->{seq_len} if $id =~ /^z/;
        }
    }

    my @fastaUniprotMatch = grep !/^z/, @seqToWrite;

    close FASTAOUT;
    close INFASTA;

    $parser->finish();

    return ($seqCount, $headerCount, $numMultUniprotIdSeq, \@fastaUniprotMatch);
}


sub sortFn {
    if ($a =~ /^z/ and $b =~ /^z/) {
        (my $aa = $a) =~ s/\D//g;
        (my $bb = $b) =~ s/\D//g;
        return $aa <=> $bb;
    } else {
        return $a cmp $b;
    }
}


sub writeSeqData {
    my ($id, $seqMeta, $mfh) = @_;

    my $desc = "";
    if (exists $seqMeta->{description}) {
        # Get rid of commas, since they are used to transform the multiple headers into lists
        $desc = join("; ", @{$seqMeta->{description}});
        $desc =~ s/,//g;
        $desc =~ s/>/,/g;
    }
    print $mfh "\tDescription\t" . $desc . "\n"                                                 if $desc;
    print $mfh "\tSequence_Length\t" . $seqMeta->{seq_len} . "\n"                               if exists $seqMeta->{seq_len};
    print $mfh "\tOther_IDs\t" . join(",", @{ $seqMeta->{other_ids} }) . "\n"                   if exists $seqMeta->{other_ids};
    print $mfh "\tQuery_IDs\t" . join(",", @{ $seqMeta->{query_ids} }) . "\n"                   if exists $seqMeta->{query_ids};
}


sub makeSequenceId {
    my ($seqCount) = @_;
    my $id = sprintf("%7d", $seqCount);
    $id =~ tr/ /z/;
    return $id;
}


sub getDomainFromDb {
    my ($dbh, $table, $accessionHash, $fractionFunc, $unirefData, $unirefVersion, @elements) = @_;
    my $c = 1;
    my %unirefFamSizeHelper;
    print "Accessions found in $table:\n";
    my %idsProcessed;

    my $unirefField = "";
    my $unirefCol = "";
    my $unirefJoin = "";
    if ($unirefVersion) {
        $unirefField = $unirefVersion eq "90" ? "uniref90_seed" : "uniref50_seed";
        $unirefCol = ", $unirefField";
        $unirefJoin = "LEFT JOIN uniref ON $table.accession = uniref.accession";
    }

    foreach my $element (@elements) {
        my $sql = "SELECT $table.accession AS accession, start, end $unirefCol FROM $table $unirefJoin WHERE $table.id = '$element'";
        #my $sql = "select * from $table $joinClause where $table.id = '$element'";
        my $sth = $dbh->prepare($sql);
        $sth->execute;
        my $ac = 1;
        while (my $row = $sth->fetchrow_hashref) {
            (my $uniprotId = $row->{accession}) =~ s/\-\d+$//; #remove homologues
            next if (not $useDomain and exists $idsProcessed{$uniprotId});
            $idsProcessed{$uniprotId} = 1;

            if ($unirefVersion) {
                my $unirefId = $row->{$unirefField};
                if (&$fractionFunc($c)) {
                    $ac++;
                    push @{$unirefData->{$unirefId}}, $uniprotId;
                    # The accessionHash element will be overwritten multiple times, once for each accession ID 
                    # in the UniRef cluster that corresponds to the UniRef cluster ID.
                    if ($unirefId eq $uniprotId) {
                        push @{$accessionHash->{$uniprotId}}, {'start' => $row->{start}, 'end' => $row->{end}};
                    }
                }
                # Only increment the family size if the uniref cluster ID hasn't yet been encountered.  This
                # is because the select query above retrieves all accessions in the family based on UniProt
                # not based on UniRef.
                if (not exists $unirefFamSizeHelper{$unirefId}) {
                    $unirefFamSizeHelper{$unirefId} = 1;
                    $c++;
                }
                $unirefMapping{$uniprotId} = $unirefId;
            } else {
                if (&$fractionFunc($c)) {
                    $ac++;
                    push @{$accessionHash->{$uniprotId}}, {'start' => $row->{start}, 'end' => $row->{end}};
                }
                $c++;
            }
        }
        print "Family $element had $ac elements that were added\n";
        $sth->finish;
    }
    @accessions = keys %$accessionHash;
    print "Initial " . scalar @accessions . " sequences after $table\n";

    # Get actual family count
    my $fullFamCount = 0;
    if ($unirefVersion) {
        my $sql = "select count(distinct accession) from $table where $table.id in ('" . join("', '", @elements) . "')";
        my $sth = $dbh->prepare($sql);
        $sth->execute;
        $fullFamCount = $sth->fetchrow;
    }

    return [$c, $fullFamCount];
}


sub getRawFamilyCount {
    my ($dbh, $table, $ids, $fractionFunc, @fams) = @_;

    my $c = 0;
    foreach my $fam (@fams) {
        my $sth = $dbh->prepare("select * from $table where $table.id = '$fam'");
        $sth->execute;
        my $ac = 1;
        while (my $row = $sth->fetchrow_hashref) {
            (my $uniprotId = $row->{accession}) =~ s/\-\d+$//;

            if (&$fractionFunc($c)) {
                $ac++;
                $ids->{$uniprotId} = 1;
            }
            $c++;
        }
        $sth->finish;
    }
}


sub retrieveFamiliesForClans {
    my (@clans) = @_;

    my @fams;
    foreach my $clan (@clans) {
        my $sql = "select pfam_id from PFAM_clans where clan_id = '$clan'";
        my $sth = $dbh->prepare($sql);
        $sth->execute;
    
        while (my $row = $sth->fetchrow_arrayref) {
            push @fams, $row->[0];
        }
    }

    return @fams;
}


sub parseFastaFile {

    print "Parsing the FASTA file.\n";

    ## Any ids from families are assigned a query_id value but only do it if we have specified
    ## an FASTA input file.
    #map { $headerData->{$_}->{query_ids} = [$_]; } keys %accessionhash;

    $useFastaHeaders = defined $useFastaHeaders ? 1 : 0;
    # Returns the Uniprot IDs that were found in the file.  All sequences found in the file are written directly
    # to the output FASTA file.
    # The '1' parameter tells the function not to apply any fraction computation.
    my ($fastaNumUnmatched, $numMultUniprotIdSeq, $fastaUniprotIds) = (0, 0, 0);
    ($fileFastaOrigSeqCount, $fileFastaNumHeaders, $numMultUniprotIdSeq, $fastaUniprotIds) = 
        parseFastaHeaders($fastaFileIn, $fastaFileOut, $useFastaHeaders, $idMapper, $headerData, $configFile, 1);

    @fastaUniprotIds = @$fastaUniprotIds;
    my $fastaNumUniprotIdsInDb = scalar @$fastaUniprotIds;
    $fastaNumUnmatched = $fileFastaOrigSeqCount + $numMultUniprotIdSeq - $fastaNumUniprotIdsInDb;
    
    print "There were $fileFastaNumHeaders headers, $fastaNumUniprotIdsInDb IDs with matching UniProt IDs, ";
    print "$fastaNumUnmatched IDs that weren't found in idmapping, and $fileFastaOrigSeqCount sequences in the FASTA file.\n";
    print "There were $numMultUniprotIdSeq sequences that were replicated because they had multiple Uniprot IDs in the headers.\n";
#    print "The uniprot ids that were found in the FASTA file:", "\t", join(",", @fastaUniprotIds), "\n";

    $fileFastaMatchedIdCount = $fastaNumUniprotIdsInDb - $numMultUniprotIdSeq;
    $fileFastaTotalIdCount = $fileFastaOrigSeqCount + $numMultUniprotIdSeq;
    $fileFastaReplSeqCount = $numMultUniprotIdSeq;
    $fileFastaUnmatchedIdCount = $fastaNumUnmatched;
}


sub parseManualAccessionFile {
    print ":accessionFile $accessionFile:\n";
    open ACCFILE, $accessionFile or die "Unable to open user accession file $accessionFile: $!";
    
    # Read the case where we have a mac file (CR \r only); we read in the entire file and then split.
    my $delim = $/;
    $/ = undef;
    my $line = <ACCFILE>;
    $/ = $delim;

    my @lines = split /[\r\n\s]+/, $line;
    foreach my $accId (grep m/.+/, map { split(",", $_) } @lines) {
        push(@manualAccessions, $accId);
    }

    $fileAccOrigIdCount = scalar @manualAccessions;
    print "There were $fileAccOrigIdCount manual accession IDs taken from ", scalar @lines, " lines in the accession file\n";
}


sub getExcludeIds {
    open ACCLIST, $access or die "Unable to read input accession exclude list $access: $!";
    while (<ACCLIST>) {
        chomp;
        $blastHitsIds{$_} = 1;
    }
    close ACCLIST;
}


sub reverseLookupManualAccessions {

    print "Parsing the accession ID file.\n";

    my $upIds = [];
    ($upIds, $noMatches, $accUniprotIdRevMap) = $idMapper->reverseLookup(EFI::IdMapping::Util::AUTO, @manualAccessions);
    @accUniprotIds = @$upIds;
    
    # Any ids from families are assigned a query_id value but only do it if we have specified
    # an accession ID input file.
    map { $headerData->{$_}->{query_ids} = [$_]; } keys %accessionhash;

    my $numUniprotIds = scalar @accUniprotIds;
    my $numNoMatches = scalar @$noMatches;

    print "There were $numUniprotIds Uniprot ID matches and $numNoMatches no-matches in the input accession ID file.\n";
#    print "The uniprot ids that were found in the accession file:", "\t", join(",", @accUniprotIds), "\n";

    $fileAccMatchedIdCount = $numUniprotIds;
    $fileAccUnmatchedIdCount = $numNoMatches;
}


sub expandUnirefSequences {
    print "Expanding UniRef seed sequences\n";

    my $selClause = "";
    if ($mapUniref50to90) {
        $selClause = "select distinct(uniref90_seed) from uniref where uniref50_seed = '<SEED>'";
    } else {
        $selClause = "select accession from uniref where uniref${unirefVersion}_seed = '<SEED>'";
    }

    my @seeds;
    foreach my $seedId (@manualAccessions) {
        (my $sql = $selClause) =~ s/<SEED>/$seedId/;
        my $sth = $dbh->prepare($sql);
        $sth->execute;
        my $row = $sth->fetchrow_arrayref;

        if (not $row) {
            push @seeds, $seedId;
        } else {
            while ($row) {
                push @seeds, $row->[0];
                $row = $sth->fetchrow_arrayref;
            }
        }

        $sth->finish if $sth;
    }

    @manualAccessions = uniq @seeds;
}


sub addUnirefData {
    print "Adding UniRef accession data\n";

    my $col = "uniref${unirefVersion}_seed";

    foreach my $seed (@manualAccessions) {
        my $sql = "SELECT accession FROM uniref WHERE $col = '$seed'";
        my $sth = $dbh->prepare($sql);
        $sth->execute;
        
        while (my $row = $sth->fetchrow_arrayref) {
            push @{$unirefData->{$seed}}, $row->[0];
        }

        $sth->finish if $sth;
    }
}


sub verifyAccessions {

    my @uniqAccUniprotIds = uniq @accUniprotIds;
    
    my $noMatchCount = 0;
    $fileAccDupCount = $fileAccMatchedIdCount - (scalar @uniqAccUniprotIds);

    my $domJoin = "";
    my $domSel = "";
    my $domWhere = "";
    my $domProcessed = {};
    if ($useDomain and $domainFamily) {
        my $famTable = $domainFamily =~ m/^PF/ ? "PFAM" : "INTERPRO";
        $domJoin = "LEFT JOIN $famTable ON $famTable.accession = annotations.accession";
        $domSel = ", $famTable.start AS start, $famTable.end AS end";
        $domWhere = "AND $famTable.id = '$domainFamily'";
    }
    
    # Lookup each manual accession ID to get the domain as well as verify that it exists.
    foreach my $element (@uniqAccUniprotIds) {
        my $sql = "SELECT annotations.accession $domSel FROM annotations $domJoin WHERE annotations.accession = '$element' $domWhere";
        $sth = $dbh->prepare($sql);
        $sth->execute;
        if (my $row = $sth->fetchrow_hashref) {
            $inUserIds{$element} = 1;

            # If we are putting accession IDs in manually and specifying a domain family, then we
            # need to get the domain extents.
            my $extHash = {};
            my $domExists = 0;
            if ($useDomain and $domainFamily) {
                $extHash->{start} = $row->{start};
                $extHash->{end} = $row->{end};
                $domExists = exists $domProcessed->{$element}; # This allows us to handle the case where multiple instances of the family occur.
                $domProcessed->{$element} = 1;
            }
            
            if (exists $accessionhash{$element}) {
                $fileAccOverlapCount++;
                if ($domExists) {
                    push @{$accessionhash{$element}}, $extHash;
                } else {
                    $accessionhash{$element} = [$extHash];
                }
                $headerData->{$element}->{query_ids} = $accUniprotIdRevMap->{$element};
            } else {
                # Only add to the list if it's not a UniRef seed sequence or part of a UniRef cluster.
                if (not exists $unirefMapping{$element}) {
                    $fileAccAdded++;
                    push(@accessions, $element);
                    if ($domExists) {
                        push @{$accessionhash{$element}}, $extHash;
                    } else {
                        $accessionhash{$element} = [$extHash];
                    }
                    $headerData->{$element}->{query_ids} = $accUniprotIdRevMap->{$element};
                } else {
                    $fileAccUnirefOverlapCount++;
                }
            }
        } else {
            $noMatchCount++;
            print NOMATCH "$element\tNOT_FOUND_DATABASE\n";
        }
    }

    $fileAccUnmatchedIdCount += $noMatchCount;
    # Subtract the no matches here from the match count; the id may be in the
    # id mapping table but not in the uniprot table (e.g. redundant or
    # archived, since the idmapping is occasionally out of sync with uniprot)
    $fileAccMatchedIdCount -= $noMatchCount;    
    $fileAccMatchedIdCount -= $fileAccDupCount;
    
    print "There were $fileAccDupCount duplicate IDs in the Uniprot IDs that were idenfied from the accession file.\n";
    print "The number of Uniprot IDs in the accession file that were already in the specified family is $fileAccOverlapCount.\n";
    print "The number of Uniprot IDs in the accession file that were added to the retrieval list is $fileAccAdded.\n";
    print "The number of Uniprot IDs in the accession file that didn't have a match in the annotations database is $noMatchCount\n";
    print "The number of Uniprot IDs in the accession file that are excluded because they are part of a UniRef cluster in the specified family is $fileAccUnirefOverlapCount.\n";
}


sub openNoMatchesFile {
    if ($noMatchFile) {
        open NOMATCH, ">$noMatchFile" or die "Unable to create nomatch file '$noMatchFile': $!";
    } else {
        open NOMATCH, ">/dev/null";
    }
    foreach my $noMatch (@$noMatches) {
        print NOMATCH "$noMatch\tNOT_FOUND_IDMAPPING\n";
    }
}


sub writeAccessions {
    print "Final retrieved accession count $numIdsToRetrieve\n";
    print "Print out accessions\n";

    return if not $access;
    if ($useOptionASettings) {
        open GREP, ">>$access" or die "Could not write to output accession ID file '$access': $!";
    } else {
        open GREP, ">$access" or die "Could not write to output accession ID file '$access': $!";
    }

    foreach my $accession (sort keys %accessionhash) {
        my @domains = @{$accessionhash{$accession}};
        foreach my $piece (@domains) {
            if (not $useDomain) {
                print GREP "$accession\n";
            } else {
                print GREP "$accession:${$piece}{'start'}:${$piece}{'end'}\n"
            }
        }
    }
    close GREP;
}


sub retrieveSequences {
    print "Retrieving Sequences\n";

    if ($useOptionASettings or ($fastaFileIn =~ /\w+/ and -s $fastaFileIn)) {
        open OUT, ">>$fastaFileOut" or die "Cannot write to output fasta $fastaFileOut\n";
    } elsif ($fastaFileOut) {
        open OUT, ">$fastaFileOut" or die "Cannot write to output fasta $fastaFileOut\n";
    } else {
        open OUT, ">/dev/null";
    }

    @origAccessions = @accessions;
    @accessions = sort @accessions;
    while(scalar @accessions) {
        my @batch=splice(@accessions, 0, $perpass);
        my $batchline=join ',', @batch;
        my ($fastacmdOutput, $fastaErr) = capture {
            system("fastacmd", "-d", "${data_files}/combined.fasta", "-s", "$batchline");
        };
        push(@err, $fastaErr);
        #print "fastacmd -d $data_files/combined.fasta -s $batchline\n";
        my @sequences=split /\n>/, $fastacmdOutput;
        $sequences[0] = substr($sequences[0], 1) if $#sequences >= 0 and substr($sequences[0], 0, 1) eq ">";
        my $accession = "";
        foreach my $sequence (@sequences) { 
            #print "raw $sequence\n";
            if ($sequence =~ s/^\w\w\|(\w{6,10})\|.*//) {
                $accession=$1;
            } else {
                $accession="";
            }
            # This length filter is only valid for Option E jobs (CD-HIT only). It will run for other jobs
            # but will give bogus results because it will exclude sequences from the fasta file but not
            # from the other metadata files.
            if (length($sequence) >= $minSeqLen and length($sequence) <= $maxSeqLen) {
                if (not $useDomain and $accession ne "") {
                    print OUT ">$accession$sequence\n\n";
                } elsif ($useDomain and $accession ne "") {
                    $sequence =~ s/\s+//g;
                    my @domains = @{$accessionhash{$accession}};
                    if (scalar @domains) {
                        foreach my $piece (@domains) {
                            my $thissequence=join("\n", unpack("(A80)*", substr $sequence,${$piece}{'start'}-1,${$piece}{'end'}-${$piece}{'start'}+1));
                            print OUT ">$accession:${$piece}{'start'}:${$piece}{'end'}\n$thissequence\n\n";
                        }
                    } else {
                        print OUT ">$accession$sequence\n\n";
                    }
                }
            }
        }
    }
    close OUT;
    
}


sub writeMetadata {
    print "Starting to write to metadata file $metaFileOut\n";

    return if not $metaFileOut;

    my $optaData = {};
    if ($useOptionASettings) {
        $optaData = FileUtil::read_struct_file($metaFileOut);
        rename($metaFileOut, "$metaFileOut.orig");
    }
    open META, ">$metaFileOut" or die "Unable to open user fasta ID file '$metaFileOut' for writing: $!";

    print Dumper(\%inFamilyIds);

    if ($useOptionASettings) {
        foreach my $acc (sort keys %$optaData) {
            my $src = $optaData->{$acc}->{EFI::Annotations::FIELD_SEQ_SRC_KEY};
            print META "$acc\n";
            print META "\t", EFI::Annotations::FIELD_SEQ_SRC_KEY, "\t";
            if (exists $inFamilyIds{$acc}) {
                print META EFI::Annotations::FIELD_SEQ_SRC_VALUE_BLASTHIT_FAMILY;
            } else {
                print META $src;
            }
            print META "\n";
            print META "\tDescription\t" . $optaData->{$acc}->{Description}. "\n" if exists $optaData->{$acc}->{Description};
            print META "\tSequence_Length\t" . $optaData->{$acc}->{Sequence_Length} . "\n" if exists $optaData->{$acc}->{Sequence_Length};
        }
    }
    
    my @metaAcc = @origAccessions;
    # Add in the sequences that were in the fasta file (which we didn't retrieve from the BLAST database).
    push(@metaAcc, @fastaUniprotIds);
    foreach my $acc (sort sortFn @metaAcc) {
        print META "$acc\n";

        # If the sequence exists in the BLAST results (only for Option A), then don't write
        # out the sequence source, since it's already been done.
        if (not exists $optaData->{$acc}) { 
            print META "\t", EFI::Annotations::FIELD_SEQ_SRC_KEY, "\t";
            if (exists $inUserIds{$acc} and exists $inFamilyIds{$acc}) {
                print META EFI::Annotations::FIELD_SEQ_SRC_VALUE_BOTH;
            } elsif (exists $inUserIds{$acc}) {
                print META EFI::Annotations::FIELD_SEQ_SRC_VALUE_FASTA;
            } else {
                print META EFI::Annotations::FIELD_SEQ_SRC_VALUE_FAMILY;
                # Don't write the query ID for ones that are family-only
                delete $headerData->{$acc}->{query_ids};
            }
            print META "\n";
        }
        if (exists $unirefData->{$acc} and $unirefVersion) {
            my @urIds = uniq @{ $unirefData->{$acc} };
            print META "\tUniRef${unirefVersion}_IDs\t", join(",", @urIds), "\n";
            print META "\tUniRef${unirefVersion}_Cluster_Size\t", scalar(@urIds), "\n";
        }
    
        # For user-supplied FASTA sequences that have headers with metadata and that appear in an input
        # PFAM family, write out the metadata.
        if (exists $headerData->{$acc}) {
            writeSeqData($acc, $headerData->{$acc}, \*META);
            delete $headerData->{$acc}; # delete this key so we don't write the same entry again below.
        }
    }
    
#    # Add up all of the IDs that were identified (or retrieved in previous steps) with the number of sequences
#    # in the FASTA file that did not have matching entries in our database.
#    # Don't include the fasta UniRef IDs since they are included in $numIdsToRetrieve.
#    $totalIdCount = scalar @fastaUniprotIds + $numIdsToRetrieve;

    # Write out the remaining zzz headers
    foreach my $acc (sort sortFn keys %$headerData) {
#        $totalIdCount++;
        print META "$acc\n";
        writeSeqData($acc, $headerData->{$acc}, \*META);
        print META "\t", EFI::Annotations::FIELD_SEQ_SRC_KEY, "\t";
        print META EFI::Annotations::FIELD_SEQ_SRC_VALUE_FASTA;
        print META "\n";
    }
    
    close META;
    
}


sub writeErrors {
    print "Starting to write errors\n";
    
    foreach my $err (@err) {
        my @lines = split(m/[\r\n]+/, $err);
        foreach my $line (@lines) {
            if ($line =~ s/^\[fastacmd\]\s+ERROR:\s+Entry\s+"([^"]+)"\s+not\s+found\s*$/$1/) {
                print NOMATCH "$line\tNOT_FOUND_DATABASE\n" if $showNoMatches;
            } else {
                print STDERR $line, "\n";
            }
        }
    }
}


sub closeNoMatchesFile {
    close NOMATCH if $showNoMatches;
}


sub checkMaxSequencesExceeded {
    if ($numIdsToRetrieve > $maxsequence and $maxsequence != 0) {
        open ERROR, ">$errorFile" or die "cannot write error output file $errorFile\n";
        print ERROR "Number of sequences $numIdsToRetrieve exceeds maximum specified $maxsequence\n";
        close ERROR;
        die "Number of sequences $numIdsToRetrieve exceeds maximum specified $maxsequence";
    }
}


sub writeSequenceCountFile {
    print "Starting to write $seqCountFile\n";
    
    if ($seqCountFile) {
        my $blastTotal = 0;
        if ($useOptionASettings) {
            open SEQCOUNT, "$seqCountFile" or die "Unable to read sequence count file $seqCountFile: $!";
            while (<SEQCOUNT>) {
                chomp;
                if (m/Blast.*\t(\d+)/) {
                    $blastTotal = $1; # minus one because we need to subtract one for the query sequence
                    last;
                }
            }
            close SEQCOUNT;
        }

        my $accTotal = $fileAccMatchedIdCount;  # the actual number of valid IDs in the file (no matches and duplicates removed)
        my $fastaTotal = $fileFastaOrigSeqCount + $fileFastaReplSeqCount; # the actual number of sequences in the file, replicated as necessary
        my $fileTotal = $fileAccOrigIdCount + $fileFastaOrigSeqCount;  # raw count

        my $matchedCount = $fileAccMatchedIdCount + $fileFastaMatchedIdCount;
        my $unmatchedCount = $fileAccUnmatchedIdCount + $fileFastaUnmatchedIdCount;
        
        # For accessions (Opt D) the accessions in the file are included in numIdsToRetrieve.
        
        my $totalIdCount = $numIdsToRetrieve + $blastTotal + $fastaTotal;
        my $familyOverlap = 0;

        open SEQCOUNT, "> $seqCountFile" or die "Unable to write to sequence count file $seqCountFile: $!";
   
        if ($blastTotal) {
            $familyOverlap = $familyIdCount - $numIdsToRetrieve;
            $totalIdCount++; # to account for input seq
            print SEQCOUNT "Blast\t$blastTotal\n";
        }
        print SEQCOUNT "FileTotal\t$fileTotal\n";           # raw number of sequences, only what's in the file
        print SEQCOUNT "FileMatched\t$matchedCount\n";      # number of uniprot sequences in the input file, including any that were replicated
        print SEQCOUNT "FileUnmatched\t$unmatchedCount\n";  # number of sequences that had no match (for FASTA written as zzz)
        
        # We used to include both the fasta sequence and the family sequence, but to
        # make things consistent with the other parts of the app only write out family
        # sequences that aren't in the input filea.

        if ($fastaFileIn) {
            $familyOverlap = $fileFastaOverlapCount;
            #my $fastaUnique = $fastaTotal - $fileFastaOverlapCount;
            #print SEQCOUNT "FamilyOverlap\t$fileFastaOverlapCount\n";
            # number of sequences that were added to the input sequence due to multiple UniProt IDs in the header
            print SEQCOUNT "FastaFileReplSeq\t$fileFastaReplSeqCount\n";
        }
        if ($accessionFile) {
            $familyOverlap = $fileAccOverlapCount;
            #my $accUnique = $fileAccMatchedIdCount - $fileAccOverlapCount;
            #print SEQCOUNT "Unique\t$accUnique\n";
            print SEQCOUNT "AccUniRefOverlap\t$fileAccUnirefOverlapCount\n";
            # number of sequences that were in the input file that were not in the included family
            print SEQCOUNT "AccFileDuplicate\t$fileAccDupCount\n";
        }

        # number of sequences that were in the input file that were not in the included family
        print SEQCOUNT "FamilyOverlap\t$familyOverlap\n";
        print SEQCOUNT "Family\t$familyIdCount\n";  # the number of IDs in the family (raw, not including any excluded due to file matches)
        print SEQCOUNT "FullFamily\t$fullFamilyIdCount\n";
        print SEQCOUNT "Total\t$totalIdCount\n";
    
        close SEQCOUNT;
    }
}


sub retrieveFamilyAccessions {
    my @clans = grep {m/^cl/i} @pfams;
    @pfams = grep {m/^pf/i} @pfams;
    push @pfams, retrieveFamiliesForClans(@clans);
    
    my $fractionFunc;
    if (not defined $fraction or $fraction == 1) {
        $fractionFunc = sub {
            return 1;
        };
    } elsif (not defined $randomFraction) {
        $fractionFunc = sub {
            my $count = shift;
            return $count % $fraction == 0;
        };
    } else {
        my $halfFrac = int($fraction / 2);
        $halfFrac = $halfFrac < 2 ? 1 : $halfFrac;
        $fractionFunc = sub {
            #my $count = shift;
            if (++$FracCount >= $fraction) {
                if (not $FracFlag) {
                    $FracCount = 0;
                    $FracFlag = 0;
                    return 1;
                } else {
                    $FracCount = 0;
                    $FracFlag = 0;
                    return 0;
                }
            } elsif (int(rand($fraction)) == $halfFrac and not $FracFlag) {
                $FracFlag = 1;
                return 1;
            } else {
                return 0;
            }
        };
    }

    # Check if the combined size of the families is greater than the given threshold, then we force uniref usage.
    # This is a bit brute force but the SQL table structure doesn't lend itself easily to do this in SQL.
    if ($maxFullFam > 0 and not $unirefVersion) {
        my %ids;
        getRawFamilyCount($dbh, "INTERPRO", \%ids, $fractionFunc, @ipros);
        getRawFamilyCount($dbh, "PFAM", \%ids, $fractionFunc, @pfams);
        getRawFamilyCount($dbh, "GENE3D", \%ids, $fractionFunc, @gene3ds);
        getRawFamilyCount($dbh, "SSF", \%ids, $fractionFunc, @ssfs);

        my $numFullFamilyIds = scalar keys %ids;
        if ($numFullFamilyIds > $maxFullFam) {
            print "Automatically switching to using UniRef90 since there the number of full family IDs ($numFullFamilyIds) is greater than the maximum value of $maxFullFam.\n";
            $unirefVersion = "90";
        }
    }

    print "Getting Acession Numbers in specified Families\n";
    my $famAcc = getDomainFromDb($dbh, "INTERPRO", \%accessionhash, $fractionFunc, $unirefData, $unirefVersion, @ipros);
    $fullFamilyIdCount += $famAcc->[1];
    $famAcc = getDomainFromDb($dbh, "PFAM", \%accessionhash, $fractionFunc, $unirefData, $unirefVersion, @pfams);
    $fullFamilyIdCount += $famAcc->[1];
    $famAcc = getDomainFromDb($dbh, "GENE3D", \%accessionhash, $fractionFunc, $unirefData, $unirefVersion, @gene3ds);
    $fullFamilyIdCount += $famAcc->[1];
    $famAcc = getDomainFromDb($dbh, "SSF", \%accessionhash, $fractionFunc, $unirefData, $unirefVersion, @ssfs);
    $fullFamilyIdCount += $famAcc->[1];

    # For Option A. Do proper family count, before we remove the IDs we don't retrieve (due to them being
    # already retreived).
    @accessions = keys %accessionhash;
    $familyIdCount = scalar @accessions;
    
    # Save the accessions that are specified through a family.
    %inFamilyIds = map { ($_, 1) } @accessions;

    # Exclude any IDs that are to be excluded.  These are the ones we have sequences for already (Option C or A).
    map { delete $accessionhash{$_} if exists $accessionhash{$_}; } keys %blastHitsIds;
    foreach my $xid (@fastaUniprotIds) {
        if (exists $accessionhash{$xid}) {
            delete $accessionhash{$xid};
            $fileFastaOverlapCount++; 
        } else {
            $inUserIds{$xid} = 1;
        }
    }
    
    # Get the uniqued list of family accessions THAT WILL BE RETREIVED FROM THE BLAST DATABASE.
    @accessions = sort keys %accessionhash;
    my $retrCount = scalar @accessions;
    
    print "Done with family lookup. There are $familyIdCount IDs in the family(s) selected (retrieving $retrCount).\n";
}


sub verifyArgs {
    $useDomain = (defined $useDomain and $useDomain eq "on");
    $domainFamily = ($useDomain and $domainFamily) ? uc($domainFamily) : "";
    $fraction = (defined $fraction and $fraction !~ m/\D/ and $fraction > 0) ? $fraction : 1;
    
    $unirefVersion = ""             if not defined $unirefVersion;
    $unirefExpand = 0               if not defined $unirefExpand or not $unirefVersion;
    $mapUniref50to90 = 0            if not defined $mapUniref50to90;
    $maxsequence = 0                if not defined $maxsequence;
    $maxFullFam = 0                 if not defined $maxFullFam;
    $useOptionASettings = 0         if not defined $useOptionASettings;
    $minSeqLen = 0                  if not defined $minSeqLen;
    $maxSeqLen = 1000000            if not defined $maxSeqLen;
    $errorFile = "$access.failed"   if not $errorFile;
    $domainFamily = ""              if not $domainFamily =~ m/^(PF|IPR)/; # domainFamily is for option D

    if ((not $configFile or not -f $configFile) and exists $ENV{EFICONFIG}) {
        $configFile = $ENV{EFICONFIG};
    }

    die "Config file (--config=...) option is required" unless (defined $configFile and -f $configFile);

    my $pwd = `pwd`; chomp $pwd;
    $access = "$pwd/getseq.default.access"                  if not $access;
    $fastaFileOut = "$pwd/getseq.default.fasta"             if not $fastaFileOut;
    $metaFileOut = "$pwd/getseq.default.meta"               if not $metaFileOut;
    $noMatchFile = "$pwd/getseq.default.nomatch"            if not $noMatchFile;
    $seqCountFile = "$pwd/getseq.default.seqcount"          if not $seqCountFile;

    if (not $ipro and not $pfam and not $gene3d and not $ssf and not $manualAccession and not $fastaFileIn and not $accessionFile) {
        $access = $fastaFileOut = $metaFileOut = $noMatchFile = $seqCountFile = "";
    }
}


sub parseFamilyArgs {
    if (defined $ipro and $ipro) {
        print ":$ipro:\n";
        @ipros = split /,/, $ipro;
    }
    
    if (defined $pfam and $pfam) {
        print ":$pfam:\n";
        @pfams = split /,/, $pfam;
    }
    
    if (defined $gene3d and $gene3d) {
        print ":$gene3d:\n";
        @gene3ds = split /,/, $gene3d;
    }
    
    if (defined $ssf and $ssf) {
        print ":$ssf:\n";
        @ssfs = split /,/, $ssf;
    }
    
    if (defined $manualAccession and $manualAccession ne 0) {
        print ":manual $manualAccession:\n";
        @manualAccessions = split m/,/, $manualAccession;
    }
}



