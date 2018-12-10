
BEGIN {
    die "The EFISHARED environment variable must be set before including this module" if not exists $ENV{EFISHARED} and not length $ENV{EFISHARED};
    use lib $ENV{EFISHARED};
}


package EFI::GNN;

use constant PFAM_THRESHOLD => 0;
use constant PFAM_ANY => 1;
use constant PFAM_SPLIT => 2;
use constant PFAM_ANY_SPLIT => 4;
use constant MAX_NB_SIZE => 20;

use List::MoreUtils qw{apply uniq any};
use List::Util qw(sum max);
use Array::Utils qw(:all);

use base qw(EFI::GNN::Base);
use EFI::GNN::Base;
use EFI::GNN::NeighborUtil;
use EFI::GNN::AnnotationUtil;


sub new {
    my ($class, %args) = @_;

    my $self = EFI::GNN::Base->new(%args);

    my $annoUtil = new EFI::GNN::AnnotationUtil(dbh => $args{dbh});

    $self->{anno_util} = $annoUtil;
    $self->{no_pfam_fh} = {};
    $self->{use_new_neighbor_method} = exists $args{use_nnm} ? $args{use_nnm} : 1;
    $self->{pfam_dir} = $args{pfam_dir} if exists $args{pfam_dir} and -d $args{pfam_dir}; # only Pfams within cooccurrence threshold
    $self->{all_pfam_dir} = $args{all_pfam_dir} if exists $args{all_pfam_dir} and -d $args{all_pfam_dir}; # all Pfams, regardless of cooccurrence
    $self->{split_pfam_dir} = $args{split_pfam_dir} if exists $args{split_pfam_dir} and -d $args{split_pfam_dir}; # all Pfams, regardless of cooccurrence
    $self->{all_split_pfam_dir} = $args{all_split_pfam_dir} if exists $args{all_split_pfam_dir} and -d $args{all_split_pfam_dir}; # all Pfams, regardless of cooccurrence
    
    $self->{pfam_dir} = "" if not exists $self->{pfam_dir};
    $self->{all_pfam_dir} = "" if not exists $self->{all_pfam_dir};
    $self->{split_pfam_dir} = "" if not exists $self->{split_pfam_dir};
    $self->{all_split_pfam_dir} = "" if not exists $self->{all_split_pfam_dir};

    return bless($self, $class);
}


sub getPfamNames{
    my $self = shift @_;
    my $pfamNumbers=shift @_;

    my $pfam_info;
    my @pfam_short=();
    my @pfam_long=();

    foreach my $tmp (split('-',$pfamNumbers)){
        my $sth=$self->{dbh}->prepare("select * from family_info where family='$tmp';");
        $sth->execute;
        $pfam_info=$sth->fetchrow_hashref;
        my $shorttemp=$pfam_info->{short_name};
        my $longtemp=$pfam_info->{long_name};
        if($shorttemp eq ''){
            $shorttemp=$tmp;
        }
        if($longtemp eq ''){
            $longtemp=$shorttemp;
        }
        push @pfam_short,$shorttemp;
        push @pfam_long, $longtemp;
    }
    return (join('-', @pfam_short),join('-',@pfam_long));
}



sub getPdbInfo{
    my $self = shift @_;
    my @accessions=@{shift @_};

    my $shape = 'broken';
    my %pdbInfo = ();
    my $pdbValueCount = 0;
    my $reviewedCount = 0;

    foreach my $accession (@accessions){
        my $sth=$self->{dbh}->prepare("select STATUS,EC,pdb from annotations where accession='$accession'");
        $sth->execute;
        my $attribResults=$sth->fetchrow_hashref;
        my $status = $attribResults->{STATUS} eq "Reviewed" ? "SwissProt" : "TrEMBL";
        my $pdbNumber = $attribResults->{pdb};
        
        if ($status eq "SwissProt") {
            $reviewedCount++;
        }
        if ($pdbNumber ne "None") {
            $pdbValueCount++;
        }

        $sth=$self->{dbh}->prepare("select PDB,e from pdbhits where ACC='$accession'");
        $sth->execute;

        my $pdbEvalue = "None";
        my $closestPdbNumber = "None";
        if ($sth->rows > 0) {
            my $pdbresults = $sth->fetchrow_hashref;
            $pdbEvalue = $pdbresults->{e};
            $closestPdbNumber = $pdbresults->{PDB};
        }
        $pdbInfo{$accession} = join(":", $attribResults->{EC}, $pdbNumber, $closestPdbNumber, $pdbEvalue, $status);
    }
    if ($pdbValueCount > 0 and $reviewedCount > 0) {
        $shape='diamond';
    } elsif ($pdbValueCount > 0) {
        $shape='square';
    } elsif ($reviewedCount > 0) {
        $shape='triangle'
    } else {
        $shape='circle';
    }
    return $shape, \%pdbInfo;
}

sub writePfamSpoke{
    my $self = shift @_;
    my $gnnwriter=shift @_;
    my $pfam=shift @_;
    my $clusternumber=shift @_;
    my $totalSsnNodes = shift @_;
    my @cluster=@{shift @_};
    my %info=%{shift @_};

    my @tmparray;
    my $shape = '';
    my $nodeSize = max(1, int(sprintf("%.2f",int(scalar(uniq @{$info{'orig'}})/scalar(@cluster)*100)/100)*100));

    (my $pfam_short, my $pfam_long)= $self->getPfamNames($pfam);
    ($shape, my $pdbinfo)= $self->getPdbInfo(\@{$info{'neighlist'}});
    $gnnwriter->startTag('node', 'id' => "$clusternumber:$pfam", 'label' => "$pfam_short");
    writeGnnField($gnnwriter, 'SSN Cluster Number', 'integer', $clusternumber);
    writeGnnField($gnnwriter, 'Pfam', 'string', $pfam);
    writeGnnField($gnnwriter, 'Pfam Description', 'string', $pfam_long);
    writeGnnField($gnnwriter, '# of Queries with Pfam Neighbors', 'integer', scalar(uniq @{$info{'orig'}}));
    writeGnnField($gnnwriter, '# of Pfam Neighbors', 'integer', scalar(@{$info{'neigh'}}));
    writeGnnField($gnnwriter, '# of Sequences in SSN Cluster', 'integer', $totalSsnNodes);
    writeGnnField($gnnwriter, '# of Sequences in SSN Cluster with Neighbors','integer',scalar(@cluster));
    writeGnnListField($gnnwriter, 'Query Accessions', 'string', \@{$info{'orig'}});
    @tmparray=map "$pfam:$_:".${$pdbinfo}{(split(":",$_))[1]}, @{$info{'neigh'}};
    writeGnnListField($gnnwriter, 'Query-Neighbor Accessions', 'string', \@tmparray);
    @tmparray=map "$pfam:$_", @{$info{'dist'}};
    writeGnnListField($gnnwriter, 'Query-Neighbor Arrangement', 'string', \@tmparray);
    writeGnnField($gnnwriter, 'Average Distance', 'real', sprintf("%.2f", int(sum(@{$info{'stats'}})/scalar(@{$info{'stats'}})*100)/100));
    writeGnnField($gnnwriter, 'Median Distance', 'real', sprintf("%.2f",int(median(@{$info{'stats'}})*100)/100));
    writeGnnField($gnnwriter, 'Co-occurrence', 'real', sprintf("%.2f",int(scalar(uniq @{$info{'orig'}})/scalar(@cluster)*100)/100));
    writeGnnField($gnnwriter, 'Co-occurrence Ratio','string',scalar(uniq @{$info{'orig'}})."/".scalar(@cluster));
    writeGnnListField($gnnwriter, 'Hub Queries with Pfam Neighbors', 'string', []);
    writeGnnListField($gnnwriter, 'Hub Pfam Neighbors', 'string', []);
    writeGnnListField($gnnwriter, 'Hub Average and Median Distance', 'string', []);
    writeGnnListField($gnnwriter, 'Hub Co-occurrence and Ratio', 'string', []);
    writeGnnField($gnnwriter, 'node.fillColor','string', '#EEEEEE');
    writeGnnField($gnnwriter, 'node.shape', 'string', $shape);
    writeGnnField($gnnwriter, 'node.size', 'string', $nodeSize);
    $gnnwriter->endTag;

    return \@tmparray;
}

sub writeClusterHub{
    my $self = shift @_;
    my $gnnwriter=shift @_;
    my $clusterNumber=shift @_;
    my $info=shift @_;
    my @pdbarray=@{shift @_};
    my $numQueryable=shift @_;
    my $totalSsnNodes=shift @_;
    my $color=shift @_;

    my @tmparray=();

    $gnnwriter->startTag('node', 'id' => $clusterNumber, 'label' => $clusterNumber);
    writeGnnField($gnnwriter,'SSN Cluster Number', 'integer', $clusterNumber);
    writeGnnField($gnnwriter,'# of Sequences in SSN Cluster', 'integer', $totalSsnNodes);
    writeGnnField($gnnwriter,'# of Sequences in SSN Cluster with Neighbors', 'integer',$numQueryable);
    @tmparray=uniq grep { $_ ne '' } map { if(int(scalar(uniq @{$info->{$_}{'orig'}})/$numQueryable*100)/100>$self->{incfrac}) {"$clusterNumber:$_:".scalar(uniq @{$info->{$_}{'orig'}}) }} sort keys %$info;
    writeGnnListField($gnnwriter, 'Hub Queries with Pfam Neighbors', 'string', \@tmparray);
    @tmparray= grep { $_ ne '' } map { if(int(scalar(uniq @{$info->{$_}{'orig'}})/$numQueryable*100)/100>$self->{incfrac}) { "$clusterNumber:$_:".scalar @{$info->{$_}{'neigh'}}}} sort keys %$info;
    writeGnnListField($gnnwriter, 'Hub Pfam Neighbors', 'string', \@tmparray);
    @tmparray= grep { $_ ne '' } map { if(int(scalar(uniq @{$info->{$_}{'orig'}})/$numQueryable*100)/100>$self->{incfrac}) { "$clusterNumber:$_:".sprintf("%.2f", int(sum(@{$info->{$_}{'stats'}})/scalar(@{$info->{$_}{'stats'}})*100)/100).":".sprintf("%.2f",int(median(@{$info->{$_}{'stats'}})*100)/100)}} sort keys %$info;
    writeGnnListField($gnnwriter, 'Hub Average and Median Distance', 'string', \@tmparray);
    @tmparray=grep { $_ ne '' } map { if(int(scalar(uniq @{$info->{$_}{'orig'}})/$numQueryable*100)/100>$self->{incfrac}){"$clusterNumber:$_:".sprintf("%.2f",int(scalar(uniq @{$info->{$_}{'orig'}})/$numQueryable*100)/100).":".scalar(uniq @{$info->{$_}{'orig'}})."/".$numQueryable}} sort keys %$info;
    writeGnnListField($gnnwriter, 'Hub Co-occurrence and Ratio', 'string', \@tmparray);
    writeGnnField($gnnwriter,'node.fillColor','string', $color);
    writeGnnField($gnnwriter,'node.shape', 'string', 'hexagon');
    writeGnnField($gnnwriter,'node.size', 'string', '70.0');
    $gnnwriter->endTag;
}

sub writePfamEdge{
    my $self = shift @_;
    my $gnnwriter=shift @_;
    my $pfam=shift @_;
    my $clusternumber=shift @_;
    $gnnwriter->startTag('edge', 'label' => "$clusternumber to $clusternumber:$pfam", 'source' => $clusternumber, 'target' => "$clusternumber:$pfam");
    $gnnwriter->endTag();
}

sub getClusterHubData {
    my $self = shift;
    my $supernodes = shift;
    my $neighborhoodSize = shift @_;
    my $warning_fh = shift @_;
    my $useCircTest = shift @_;
    my $supernodeOrder = shift;
    my $numberMatch = shift;

    my %withNeighbors;
    my %clusterNodes;
    my %noNeighbors;
    my %noMatches;
    my %genomeIds;
    my %noneFamily;
    my %accessionData;
    my ($allNbAccessionData, $allPfamData) = ({}, {}, {});

    # This is used to retain the order of the nodes in the xgmml file when we write the arrow sqlite database.
    my $sortKey = 0;

    my $nbFind = new EFI::GNN::NeighborUtil(dbh => $self->{dbh}, use_nnm => $self->{use_new_neighbor_method});

    foreach my $clusterNode (@{ $supernodeOrder }) {
        $noneFamily{$clusterNode} = {};
        foreach my $accession (uniq @{$supernodes->{$clusterNode}}){
            $accessionData{$accession}->{neighbors} = [];
            my ($pfamsearch, $iprosearch, $localNoMatch, $localNoNeighbors, $genomeId) =
                $nbFind->findNeighbors($accession, $neighborhoodSize, $warning_fh, $useCircTest, $noneFamily{$clusterNode}, \%accessionData);
            $noNeighbors{$accession} = $localNoNeighbors;
            $genomeIds{$accession} = $genomeId;
            $noMatches{$accession} = $localNoMatch;
            
            # Find the maximum window so we can filter later.
            $allNbAccessionData->{$accession}->{neighbors} = [];
            my ($allNeighborData, $allIproNbData) = ($pfamsearch, $iprosearch);
            if ($neighborhoodSize != MAX_NB_SIZE) {
                ($allNeighborData, $allIproNbData) = $nbFind->findNeighbors($accession, MAX_NB_SIZE, undef, $useCircTest, {}, $allNbAccessionData);
            }
            $allPfamData->{$accession} = $allNeighborData;
            
            my @accDataStructs = \%accessionData;
            if ($neighborhoodSize != MAX_NB_SIZE) {
                push @accDataStructs, $allNbAccessionData;
            }
            
            my ($organism, $taxId, $annoStatus, $desc, $familyDesc, $iproFamilyDesc) = $self->getAnnotations($accession, $accessionData{$accession}->{attributes}->{family}, $accessionData{$accession}->{attributes}->{ipro_family});
            for (my $idx = 0; $idx < scalar @accDataStructs; $idx++) {
                my $accStruct = $accDataStructs[$idx];

                $accStruct->{$accession}->{attributes}->{sort_order} = $sortKey++;
                $accStruct->{$accession}->{attributes}->{organism} = $organism;
                $accStruct->{$accession}->{attributes}->{taxon_id} = $taxId;
                $accStruct->{$accession}->{attributes}->{anno_status} = $annoStatus;
                $accStruct->{$accession}->{attributes}->{desc} = $desc;
                $accStruct->{$accession}->{attributes}->{family_desc} = $familyDesc;
                $accStruct->{$accession}->{attributes}->{ipro_family_desc} = $iproFamilyDesc;
                $accStruct->{$accession}->{attributes}->{cluster_num} = exists $numberMatch->{$clusterNode} ? $numberMatch->{$clusterNode} : "";
                foreach my $nbObj (@{ $accStruct->{$accession}->{neighbors} }) {
                    my ($nbOrganism, $nbTaxId, $nbAnnoStatus, $nbDesc, $nbFamilyDesc, $nbIproFamilyDesc) =
                        $self->getAnnotations($nbObj->{accession}, $nbObj->{family}, $nbObj->{ipro_family});
                    $nbObj->{taxon_id} = $nbTaxId;
                    $nbObj->{anno_status} = $nbAnnoStatus;
                    $nbObj->{desc} = $nbDesc;
                    $nbObj->{family_desc} = $nbFamilyDesc;
                    $nbObj->{ipro_family_desc} = $nbIproFamilyDesc;
                }
            }

            foreach my $pfamNumber (sort {$a <=> $b} keys %{$pfamsearch->{neigh}}){
                push @{$clusterNodes{$clusterNode}{$pfamNumber}{orig}}, @{$pfamsearch->{orig}{$pfamNumber}};
                push @{$clusterNodes{$clusterNode}{$pfamNumber}{dist}}, @{$pfamsearch->{dist}{$pfamNumber}};
                push @{$clusterNodes{$clusterNode}{$pfamNumber}{stats}}, @{$pfamsearch->{stats}{$pfamNumber}};
                push @{$clusterNodes{$clusterNode}{$pfamNumber}{neigh}}, @{$pfamsearch->{neigh}{$pfamNumber}};
                push @{$clusterNodes{$clusterNode}{$pfamNumber}{neighlist}}, @{$pfamsearch->{neighlist}{$pfamNumber}};
                push @{$clusterNodes{$clusterNode}{$pfamNumber}{data}}, @{$pfamsearch->{data}{$pfamNumber}};
            }
            foreach my $pfamNumber (sort {$a <=> $b} keys %{$pfamsearch->{withneighbors}}){
                push @{$withNeighbors{$clusterNode}}, @{$pfamsearch->{withneighbors}{$pfamNumber}};
            }
        }
    }

    if ($neighborhoodSize == MAX_NB_SIZE) {
        $allNbAccessionData = \%accessionData;
    }

    return \%clusterNodes, \%withNeighbors, \%noMatches, \%noNeighbors, \%genomeIds, \%noneFamily, \%accessionData,
        $allNbAccessionData, $allPfamData;
}


sub filterClusterHubData {
    my $self = shift;
    my $data = shift;
    my $supernodes = shift;
    my $nbSize = shift @_; # neighborhood size
    my $supernodeOrder = shift;

    my $withNeighbors = {};
    my $clusterNodes = {};
    my $accessionData = {};
    my $noNeighbors = {};
    my $noMatches = {};
    my $genomeIds = {};
    my $noneFamily = {};

    foreach my $clusterNode (@{ $supernodeOrder }) {
        foreach my $accession (uniq @{$supernodes->{$clusterNode}}){
            $accessionData->{$accession}->{attributes} = $data->{accessionData}->{$accession}->{attributes};
            $noNeighbors->{$accession} = $data->{noNeighborMap}->{$accession};
            $noMatches->{$accession} = $data->{noMatchMap}->{$accession};
            $genomeIds->{$accession} = $data->{genomeIds}->{$accession};

            foreach my $nb (@{$data->{accessionData}->{$accession}->{neighbors}}) {
                if ($nbSize >= abs($nb->{distance})) {
                    push @{$accessionData->{$accession}->{neighbors}}, $nb;
                    if (exists $data->{noneFamily}->{$clusterNode}->{$nb->{accession}}) {
                        $noneFamily->{$clusterNode}->{$nb->{accession}} = $data->{noneFamily}->{$clusterNode}->{$nb->{accession}};
                    }
                }
            }

            my $pfamsearch = $data->{allPfamData}->{$accession};
            foreach my $pfamNumber (sort {$a <=> $b} keys %{$pfamsearch->{neigh}}) {
                my (@orig, @dist, @stats, @neigh, @neighlist, @data);
                for (my $i = 0; $i < scalar @{$pfamsearch->{data}->{$pfamNumber}}; $i++) {
                    if ($nbSize >= abs($pfamsearch->{data}->{$pfamNumber}->[$i]->{distance})) {
                        push @orig, @{$pfamsearch->{orig}->{$pfamNumber}};
                        push @dist, $pfamsearch->{dist}->{$pfamNumber}->[$i];
                        push @stats, $pfamsearch->{stats}->{$pfamNumber}->[$i];
                        push @neigh, $pfamsearch->{neigh}->{$pfamNumber}->[$i];
                        push @neighlist, $pfamsearch->{neighlist}->{$pfamNumber}->[$i];
                        push @data, $pfamsearch->{data}->{$pfamNumber}->[$i];
                    }
                }

                if (scalar @data) {
                    push @{$clusterNodes->{$clusterNode}->{$pfamNumber}->{orig}}, uniq @orig;
                    push @{$clusterNodes->{$clusterNode}->{$pfamNumber}->{dist}}, @dist;
                    push @{$clusterNodes->{$clusterNode}->{$pfamNumber}->{stats}}, @stats;
                    push @{$clusterNodes->{$clusterNode}->{$pfamNumber}->{neigh}}, @neigh;
                    push @{$clusterNodes->{$clusterNode}->{$pfamNumber}->{neighlist}}, @neighlist;
                    push @{$clusterNodes->{$clusterNode}->{$pfamNumber}->{data}}, @data;
                }
            }
    
            foreach my $pfamNumber (sort {$a <=> $b} keys %{$pfamsearch->{withneighbors}}){
                push @{$withNeighbors->{$clusterNode}}, @{$pfamsearch->{withneighbors}->{$pfamNumber}};
            }

        }
    }

    return $clusterNodes, $withNeighbors, $noMatches, $noNeighbors, $genomeIds, $noneFamily, $accessionData;
}


sub getAnnotations {
    my $self = shift;
    my $accession = shift;
    my $pfams = shift;
    my $ipros = shift;

    return $self->{anno_util}->getAnnotations($accession, $pfams, $ipros);
    
#    my $sql = "select Organism,Taxonomy_ID,STATUS,Description from annotations where accession='$accession'";
#
#    my $sth = $self->{dbh}->prepare($sql);
#    $sth->execute;
#
#    my ($organism, $taxId, $annoStatus, $desc) = ("", "", "", "");
#    if (my $row = $sth->fetchrow_hashref) {
#        $organism = $row->{Organism};
#        $taxId = $row->{Taxonomy_ID};
#        $annoStatus = $row->{STATUS};
#        $desc = $row->{Description};
#    }
#
#    my @pfams = split '-', $pfams;
#
#    $sql = "select short_name from pfam_info where pfam in ('" . join("','", @pfams) . "')";
#
#    $sth = $self->{dbh}->prepare($sql);
#    $sth->execute;
#
#    my $rows = $sth->fetchall_arrayref;
#
#    my $pfamDesc = join("-", map { $_->[0] } @$rows);
#
#    $annoStatus = $annoStatus eq "Reviewed" ? "SwissProt" : "TrEMBL";
#
#    return ($organism, $taxId, $annoStatus, $desc, $pfamDesc);
}


sub writeClusterHubGnn{
    my $self = shift @_;
    my $gnnwriter=shift @_;
    my $clusterNodes=shift @_;
    my $withneighbors=shift @_;
    my $numbermatch=shift @_;
    my $supernodes=shift @_;
    my $singletons=shift @_;

    $gnnwriter->startTag('graph', 'label' => $self->{title} . " GNN", 'xmlns' => 'http://www.cs.rpi.edu/XGMML');

    foreach my $cluster (sort {$a <=> $b} keys %$clusterNodes){
        my $numQueryableSsns = scalar @{ $withneighbors->{$cluster} };
        my $totalSsns = scalar @{ $supernodes->{$cluster} };
        if (exists $singletons->{$cluster}) {
            print "excluding hub node $cluster, simplenumber " . $numbermatch->{$cluster} . " because it's a singleton hub\n" if $self->{debug};
            next;
        }
        if ($numQueryableSsns < 2) {
            print "excluding hub node $cluster, simplenumber " . $numbermatch->{$cluster} . " because it only has 1 queryable ssn.\n" if $self->{debug};
            next;
        }

        print "building hub node $cluster, simplenumber ".$numbermatch->{$cluster}."\n" if $self->{debug};
        my @pdbinfo=();
        foreach my $pfam (sort keys %{$clusterNodes->{$cluster}}){
            my $numNeighbors = scalar(@{$withneighbors->{$cluster}});
            my $numNodes = scalar(uniq @{$clusterNodes->{$cluster}{$pfam}{'orig'}});
            #if ($numNeighbors == 1) {
            #    print "Excluding $pfam spoke node because it has only one neighbor\n";
            #    next;
            #}

            my $cooccurrence = sprintf("%.2f", int($numNodes / $numNeighbors * 100) / 100);
            if($self->{incfrac} <= $cooccurrence){
                my $tmparray= $self->writePfamSpoke($gnnwriter, $pfam, $numbermatch->{$cluster}, $totalSsns, $withneighbors->{$cluster}, $clusterNodes->{$cluster}{$pfam});
                push @pdbinfo, @{$tmparray};
                $self->writePfamEdge($gnnwriter, $pfam, $numbermatch->{$cluster});
            }
        }

        #my $color = $self->{colors}->{$numbermatch->{$cluster}});
        my $color = $self->getColor($numbermatch->{$cluster});
        $self->writeClusterHub($gnnwriter, $numbermatch->{$cluster}, $clusterNodes->{$cluster}, \@pdbinfo, $numQueryableSsns, $totalSsns, $color);
    }

    $gnnwriter->endTag();
}

sub getPfamCooccurrenceTable {
    my $self = shift @_;
    my $clusterNodes=shift @_;
    my $withneighbors=shift @_;
    my $numbermatch=shift @_;
    my $supernodes=shift @_;
    my $singletons=shift @_;

    my %pfamStats;

    foreach my $cluster (sort {$a <=> $b} keys %$clusterNodes){
        my $numQueryableSsns = scalar @{ $withneighbors->{$cluster} };
        next if (exists $singletons->{$cluster} || $numQueryableSsns < 2);
        my $clusterNum = $numbermatch->{$cluster};

        foreach my $pfam (keys %{$clusterNodes->{$cluster}}){
            my $numNeighbors = scalar(@{$withneighbors->{$cluster}});
            my $numNodes = scalar(uniq @{$clusterNodes->{$cluster}{$pfam}{'orig'}});
            my $cooccurrence = sprintf("%.2f", int($numNodes / $numNeighbors * 100) / 100);
            foreach my $subPfam (split('-', $pfam)) {
                $pfamStats{$subPfam}->{$clusterNum} = 0 if (not exists $pfamStats{$subPfam}->{$clusterNum});
                $pfamStats{$subPfam}->{$clusterNum} += $cooccurrence;
                #            y$$pfamStats{$pfam}->{$clusterNum} = $cooccurrence;
            }
        }
    }

    return \%pfamStats;
}

sub saveGnnAttributes {
    my $self = shift;
    my $writer = shift;
    my $gnnData = shift;
    my $node = shift;

    my $attrName = $self->{anno}->{ACC}->{display};

    # If this is a repnode network, there will be a child node named "ACC". If so, we need to wrap
    # all of the no matches, etc into a list rather than a simple attribute.
    my @accIdNode = grep { $_ =~ /\S/ and $_->getAttribute('name') eq $attrName } $node->getChildNodes;
    if (scalar @accIdNode) {
        my $accNode = $accIdNode[0];
        my @accIdAttrs = $accNode->findnodes("./*");

        my @hasNeighbors;
        my @hasMatch;
        my @genomeId;
        my @nbFams;
        my @nbIproFams;

        foreach my $accIdAttr (@accIdAttrs) {
            my $accId = $accIdAttr->getAttribute('value');
            push @hasNeighbors, $gnnData->{noNeighborMap}->{$accId} == 1 ? "false" : $gnnData->{noNeighborMap}->{$accId} == -1 ? "n/a" : "true";
            push @hasMatch, $gnnData->{noMatchMap}->{$accId} ? "false" : "true";
            push @genomeId, $gnnData->{genomeIds}->{$accId};
            my $nbFams = join(",", uniq sort grep {$_ ne "none"} map { split m/-/, $_->{family} } @{$gnnData->{accessionData}->{$accIdAttr}->{neighbors}});
            push @nbFams, $nbFams;
            $nbFams = join(",", uniq sort grep {$_ ne "none"} map { split m/-/, $_->{ipro_family} } @{$gnnData->{accessionData}->{$accIdAttr}->{neighbors}});
            push @nbIproFams, $nbFams;
        }

        writeGnnListField($writer, 'Present in ENA Database?', 'string', \@hasMatch, 0);
        writeGnnListField($writer, 'Genome Neighbors in ENA Database?', 'string', \@hasNeighbors, 0);
        writeGnnListField($writer, 'ENA Database Genome ID', 'string', \@genomeId, 0);
        writeGnnListField($writer, 'Neighbor Pfam Families', 'string', \@nbFams, "");
        writeGnnListField($writer, 'Neighbor InterPro Families', 'string', \@nbIproFams, "");
    } else {
        my $nodeId = $node->getAttribute('label');
        my $hasNeighbors = $gnnData->{noNeighborMap}->{$nodeId} == 1 ? "false" : $gnnData->{noNeighborMap}->{$nodeId} == -1 ? "n/a" : "true";
        my $genomeId = $gnnData->{genomeIds}->{$nodeId};
        my $hasMatch = $gnnData->{noMatchMap}->{$nodeId} ? "false" : "true";
        my @nbFams = uniq sort grep {$_ ne "none"} map { split m/-/, $_->{family} } @{$gnnData->{accessionData}->{$nodeId}->{neighbors}};
        my @nbIproFams = uniq sort grep {$_ ne "none"} map { split m/-/, $_->{ipro_family} } @{$gnnData->{accessionData}->{$nodeId}->{neighbors}};
        writeGnnField($writer, 'Present in ENA Database?', 'string', $hasMatch);
        writeGnnField($writer, 'Genome Neighbors in ENA Database?', 'string', $hasNeighbors);
        writeGnnField($writer, 'ENA Database Genome ID', 'string', $genomeId);
        writeGnnListField($writer, 'Neighbor Pfam Families', 'string', \@nbFams, "");
        writeGnnListField($writer, 'Neighbor InterPro Families', 'string', \@nbIproFams, "");
    }
}

sub writePfamHubGnn {
    my $self = shift @_;
    my $writer=shift @_;
    my $clusterNodes=shift @_;
    my $withneighbors = shift @_;
    my $numbermatch = shift @_;
    my $supernodes = shift @_;

    my @pfamHubs=uniq sort map {keys %{${$clusterNodes}{$_}}} keys %{$clusterNodes};

    $writer->startTag('graph', 'label' => $self->{title} . " Pfam GNN", 'xmlns' => 'http://www.cs.rpi.edu/XGMML');

    foreach my $pfam (@pfamHubs){
        my ($pfam_short, $pfam_long) = $self->getPfamNames($pfam);
        my $spokecount = 0;
        my @hubPdb;
        my @clusters;
        my @allClusters;
        foreach my $cluster (sort keys %{$clusterNodes}){
            if(exists ${$clusterNodes}{$cluster}{$pfam}){
                my $numQueryable = scalar(@{$withneighbors->{$cluster}});
                my $numWithNeighbors = scalar(uniq(@{${$clusterNodes}{$cluster}{$pfam}{'orig'}}));
                if ($numQueryable > 1 and int($numWithNeighbors / $numQueryable * 100) / 100 >= $self->{incfrac}) {
                    push @clusters, $cluster;
                    my $spokePdb = $self->writeClusterSpoke($writer, $pfam, $cluster, $clusterNodes, $numbermatch, $pfam_short, $pfam_long, $supernodes, $withneighbors);
                    push @hubPdb, @{$spokePdb};
                    $self->writeClusterEdge($writer, $pfam, $cluster, $numbermatch);
                    $spokecount++;
                }
                push @allClusters, $cluster;
            }
        }
        if($spokecount>0){
            print "Building hub $pfam\n" if $self->{debug};
            $self->writePfamHub($writer,$pfam, $pfam_short, $pfam_long, \@hubPdb, \@clusters, $clusterNodes,$supernodes,$withneighbors, $numbermatch);
            $self->writePfamQueryData($pfam, \@clusters, $clusterNodes, $supernodes, $numbermatch, PFAM_THRESHOLD);
            $self->writePfamQueryData($pfam, \@clusters, $clusterNodes, $supernodes, $numbermatch, PFAM_SPLIT);
        }
        print "WRITING $pfam\n";
        $self->writePfamQueryData($pfam, \@allClusters, $clusterNodes, $supernodes, $numbermatch, PFAM_ANY);
        $self->writePfamQueryData($pfam, \@allClusters, $clusterNodes, $supernodes, $numbermatch, PFAM_ANY_SPLIT);
    }

    $writer->endTag();
}

sub writeClusterSpoke{
    my $self = shift@_;
    my $writer=shift @_;
    my $pfam=shift @_;
    my $cluster=shift @_;
    my $clusterNodes=shift @_;
    my $numbermatch=shift @_;
    my $pfam_short=shift @_;
    my $pfam_long=shift @_;
    my $supernodes=shift @_;
    my $withneighbors = shift @_;

    (my $shape, my $pdbinfo)= $self->getPdbInfo(\@{${$clusterNodes}{$cluster}{$pfam}{'neighlist'}});
    #my $color = $self->{colors}->{$numbermatch->{$cluster}};
    my $color = $self->getColor($numbermatch->{$cluster});
    my $clusterNum = $numbermatch->{$cluster};

    my $avgDist = sprintf("%.2f", int(sum(@{${$clusterNodes}{$cluster}{$pfam}{'stats'}})/scalar(@{${$clusterNodes}{$cluster}{$pfam}{'stats'}})*100)/100);
    my $medDist = sprintf("%.2f",int(median(@{${$clusterNodes}{$cluster}{$pfam}{'stats'}})*100)/100);
    my $coOcc = (int(scalar( uniq (@{${$clusterNodes}{$cluster}{$pfam}{'orig'}}))/scalar(@{$withneighbors->{$cluster}})*100)/100);
    my $coOccRat = scalar( uniq (@{${$clusterNodes}{$cluster}{$pfam}{'orig'}}))."/".scalar(@{$withneighbors->{$cluster}});
    my $nodeSize = max(1, $coOcc*100);

    my @tmparray=map "$_:".${$pdbinfo}{(split(":",$_))[1]}, @{${$clusterNodes}{$cluster}{$pfam}{'neigh'}};

    $writer->startTag('node', 'id' => "$pfam:" . $numbermatch->{$cluster}, 'label' => $numbermatch->{$cluster});

    writeGnnField($writer, 'Pfam', 'string', "");
    writeGnnField($writer, 'Pfam Description', 'string', "");
    writeGnnField($writer, 'Cluster Number', 'integer', $clusterNum);
    writeGnnField($writer, '# of Sequences in SSN Cluster', 'integer', scalar(@{$supernodes->{$cluster}}));
    writeGnnField($writer, '# of Sequences in SSN Cluster with Neighbors', 'integer', scalar(@{$withneighbors->{$cluster}}));
    writeGnnField($writer, '# of Queries with Pfam Neighbors', 'integer', scalar( uniq (@{${$clusterNodes}{$cluster}{$pfam}{'orig'}})));
    writeGnnField($writer, '# of Pfam Neighbors', 'integer', scalar(@{${$clusterNodes}{$cluster}{$pfam}{'neigh'}}));
    writeGnnListField($writer, 'Query Accessions', 'string', \@{${$clusterNodes}{$cluster}{$pfam}{'orig'}});
    writeGnnListField($writer, 'Query-Neighbor Accessions', 'string', \@tmparray);
    writeGnnListField($writer, 'Query-Neighbor Arrangement', 'string', \@{${$clusterNodes}{$cluster}{$pfam}{'dist'}});
    writeGnnField($writer, 'Average Distance', 'real', $avgDist);
    writeGnnField($writer, 'Median Distance', 'real', $medDist);
    writeGnnField($writer, 'Co-occurrence','real',$coOcc);
    writeGnnField($writer, 'Co-occurrence Ratio','string',$coOccRat);
    writeGnnListField($writer, 'Hub Average and Median Distances', 'string', []);
    writeGnnListField($writer, 'Hub Co-occurrence and Ratio', 'string', []);
    writeGnnField($writer, 'node.fillColor','string', $color);
    writeGnnField($writer, 'node.shape', 'string', $shape);
    writeGnnField($writer, 'node.size', 'string', $nodeSize);
    
    $writer->endTag();
    
    @tmparray=map $numbermatch->{$cluster}.":$_", @tmparray;
    @{${$clusterNodes}{$cluster}{$pfam}{'orig'}}=map $numbermatch->{$cluster}.":$_",@{${$clusterNodes}{$cluster}{$pfam}{'orig'}};
    @{${$clusterNodes}{$cluster}{$pfam}{'neigh'}}=map $numbermatch->{$cluster}.":$_",@{${$clusterNodes}{$cluster}{$pfam}{'neigh'}};
    @{${$clusterNodes}{$cluster}{$pfam}{'dist'}}=map $numbermatch->{$cluster}.":$_",@{${$clusterNodes}{$cluster}{$pfam}{'dist'}};
    
    return \@tmparray;
}

sub writeClusterEdge{
    my $self = shift @_;
    my $writer=shift @_;
    my $pfam=shift @_;
    my $cluster=shift @_;
    my $numbermatch=shift @_;

    $writer->startTag('edge', 'label' => "$pfam to $pfam:".$numbermatch->{$cluster}, 'source' => $pfam, 'target' => "$pfam:" . $numbermatch->{$cluster});
    $writer->endTag();
}

sub writePfamHub {
    my $self = shift @_;
    my $writer=shift @_;
    my $pfam=shift @_;
    my $pfam_short = shift @_;
    my $pfam_long = shift @_;
    my $hubPdb=shift @_;
    my $clusters=shift @_;
    my $clusterNodes=shift @_;
    my $supernodes=shift @_;
    my $withneighbors=shift @_;
    my $numbermatch=shift @_;

    my @tmparray=();

    $writer->startTag('node', 'id' => $pfam, 'label' => $pfam_short);

    writeGnnField($writer, 'Pfam', 'string', $pfam);
    writeGnnField($writer, 'Pfam Description', 'string', $pfam_long);
    writeGnnField($writer, '# of Sequences in SSN Cluster', 'integer', sum(map scalar(@{$supernodes->{$_}}), @{$clusters}));
    writeGnnField($writer, '# of Sequences in SSN Cluster with Neighbors','integer', sum(map scalar(@{$withneighbors->{$_}}), @{$clusters}));
    writeGnnField($writer, '# of Queries with Pfam Neighbors', 'integer',sum(map scalar( uniq (@{${$clusterNodes}{$_}{$pfam}{'orig'}})), @{$clusters}));
    writeGnnField($writer, '# of Pfam Neighbors', 'integer',sum(map scalar( uniq (@{${$clusterNodes}{$_}{$pfam}{'neigh'}})), @{$clusters}));
    writeGnnListField($writer, 'Query-Neighbor Accessions', 'string', $hubPdb);
    @tmparray=map @{${$clusterNodes}{$_}{$pfam}{'dist'}},  sort {$a <=> $b} @{$clusters};
    writeGnnListField($writer, 'Query-Neighbor Arrangement', 'string', \@tmparray);
    @tmparray=map $numbermatch->{$_}.":".sprintf("%.2f",int(sum(@{${$clusterNodes}{$_}{$pfam}{'stats'}})/scalar(@{${$clusterNodes}{$_}{$pfam}{'stats'}})*100)/100).":".sprintf("%.2f",int(median(@{${$clusterNodes}{$_}{$pfam}{'stats'}})*100)/100), sort {$a <=> $b} @{$clusters};
    writeGnnListField($writer, 'Hub Average and Median Distances', 'string', \@tmparray);
    @tmparray=map $numbermatch->{$_}.":".sprintf("%.2f",int(scalar( uniq (@{${$clusterNodes}{$_}{$pfam}{'orig'}}))/scalar(@{$withneighbors->{$_}})*100)/100).":".scalar( uniq (@{${$clusterNodes}{$_}{$pfam}{'orig'}}))."/".scalar(@{$withneighbors->{$_}}), sort {$a <=> $b} @{$clusters};
    writeGnnListField($writer, 'Hub Co-occurrence and Ratio', 'string', \@tmparray);
    writeGnnField($writer, 'node.fillColor','string', '#EEEEEE');
    writeGnnField($writer,'node.shape', 'string', 'hexagon');
    writeGnnField($writer,'node.size', 'string', '70.0');

    $writer->endTag;
}

sub writePfamQueryData {
    my $self = shift;
    my $pfam = shift;
    my $clustersInPfam = shift;
    my $clusterNodes = shift;
    my $supernodes = shift;
    my $numbermatch = shift;
    my $fileTypeFlag = shift;

    $fileTypeFlag = 0 if not defined $fileTypeFlag;

    my $pfamDir = $self->{pfam_dir};
    $pfamDir = $self->{all_pfam_dir} if $fileTypeFlag == PFAM_ANY;
    $pfamDir = $self->{split_pfam_dir} if $fileTypeFlag == PFAM_SPLIT;
    $pfamDir = $self->{all_split_pfam_dir} if $fileTypeFlag == PFAM_ANY_SPLIT;

    return if not $pfamDir or not -d $pfamDir;

    my $allFh;
    if ($fileTypeFlag == PFAM_ANY) {
        if (not exists $self->{all_pfam_fh_any}) {
            open($self->{all_pfam_fh_any}, ">" . $pfamDir . "/ALL_PFAM.txt");
            $self->{all_pfam_fh_any}->print(join("\t", "Query ID", "Neighbor ID", "Neighbor Pfam", "SSN Query Cluster #",
                                                   "SSN Query Cluster Color", "Query-Neighbor Distance", "Query-Neighbor Directions"), "\n");
        }
        $allFh = $self->{all_pfam_fh_any};
    } elsif ($fileTypeFlag == PFAM_SPLIT) {
        if (not exists $self->{all_pfam_fh_split}) {
            open($self->{all_pfam_fh_split}, ">" . $pfamDir . "/ALL_PFAM.txt");
            $self->{all_pfam_fh_split}->print(join("\t", "Query ID", "Neighbor ID", "Neighbor Pfam", "SSN Query Cluster #",
                                               "SSN Query Cluster Color", "Query-Neighbor Distance", "Query-Neighbor Directions"), "\n");
        }
        $allFh = $self->{all_pfam_fh_split};
    } elsif ($fileTypeFlag == PFAM_ANY_SPLIT) {
        if (not exists $self->{all_pfam_fh_any_split}) {
            open($self->{all_pfam_fh_any_split}, ">" . $pfamDir . "/ALL_PFAM.txt");
            $self->{all_pfam_fh_any_split}->print(join("\t", "Query ID", "Neighbor ID", "Neighbor Pfam", "SSN Query Cluster #",
                                               "SSN Query Cluster Color", "Query-Neighbor Distance", "Query-Neighbor Directions"), "\n");
        }
        $allFh = $self->{all_pfam_fh_any_split};
    } else {
        if (not exists $self->{all_pfam_fh}) {
            open($self->{all_pfam_fh}, ">" . $pfamDir . "/ALL_PFAM.txt");
            $self->{all_pfam_fh}->print(join("\t", "Query ID", "Neighbor ID", "Neighbor Pfam", "SSN Query Cluster #",
                                               "SSN Query Cluster Color", "Query-Neighbor Distance", "Query-Neighbor Directions"), "\n");
        }
        $allFh = $self->{all_pfam_fh};
    }


    my @pfams = ($pfam);
    my $origPfam = $pfam;
    if ($fileTypeFlag == PFAM_SPLIT or $fileTypeFlag == PFAM_ANY_SPLIT) {
        @pfams = split(m/\-/, $pfam);
    }

    foreach my $pfam (@pfams) {
        my $outFile = $pfamDir . "/pfam_neighbors_$pfam.txt";
        my $fileExists = -f $outFile;

        my $mode = ($fileTypeFlag == PFAM_SPLIT or $fileTypeFlag == PFAM_ANY_SPLIT) ? ">>" : ">";
        open(PFAMFH, $mode, $outFile) or die "Unable to write to PFAM $outFile: $!";
    
        if (not $fileExists) {
            print PFAMFH join("\t", "Query ID", "Neighbor ID", "Neighbor Pfam", "SSN Query Cluster #", "SSN Query Cluster Color",
                                    "Query-Neighbor Distance", "Query-Neighbor Directions"), "\n";
        }
    
        foreach my $clusterId (@$clustersInPfam) {
            #my $color = $self->{colors}->{$numbermatch->{$clusterId}};
            my $color = $self->getColor($numbermatch->{$clusterId});
            my $clusterNum = $numbermatch->{$clusterId};
            $clusterNum = "none" if not $clusterNum;
    
            foreach my $data (@{ $clusterNodes->{$clusterId}->{$origPfam}->{data} }) {
                my $line = join("\t", $data->{query_id},
                                      $data->{neighbor_id},
                                      $origPfam,
                                      $clusterNum,
                                      $color,
                                      sprintf("%02d", $data->{distance}),
                                      $data->{direction},
                               ) . "\n";
                print PFAMFH $line;
                $allFh->print($line);
            }
        }
    
        close(PFAMFH);
    }
}

sub writePfamNoneClusters {
    my $self = shift;
    my $outDir = shift;
    my $noneFamily = shift;
    my $numbermatch = shift;

    foreach my $clusterId (keys %$noneFamily) {
        my $clusterNum = $numbermatch->{$clusterId};

        open NONEFH, ">$outDir/no_pfam_neighbors_$clusterNum.txt";

        foreach my $nodeId (keys %{ $noneFamily->{$clusterId} }) {
            print NONEFH "$nodeId\n";
        }

        close NONEFH;
    }
}

sub writeSsnStats {
    my $self = shift;
    my $supernodes = shift;
    my $constellations = shift;
    my $numbermatch = shift;
    my $spDesc = shift; # swissprot description
    my $statsFile = shift;
    my $sizeFile = shift;
    my $spClustersDescFile = shift;
    my $spSinglesDescFile = shift;

    my %clusterSizes;
    my $numMetanodes = scalar keys %$constellations;
    my $numAccessions = 0;
    my $numClusters = 0;
    my $numSingles = 0;
    foreach my $clusterId (keys %$supernodes) {
        my $count = scalar @{$supernodes->{$clusterId}};
        $numAccessions += $count;
        $numSingles++ if $count == 1;
        $numClusters++ if $count > 1;

        if ($count > 1) {
            my $clusterNum = $numbermatch->{$clusterId};
            $clusterSizes{$clusterNum} = $count;
        }
    }

    my $seqSrc = exists $self->{has_uniref} ? $self->{has_uniref} : "UniProt";

    open STATS, ">", $statsFile or die "Unable to open stats file $statsFile for writing: $!";

    print STATS "Number of SSN clusters\t$numClusters\n";
    print STATS "Number of SSN singletons\t$numSingles\n";
    print STATS "SSN sequence source\t$seqSrc\n";
    print STATS "Number of SSN (meta)nodes\t$numMetanodes\n";
    print STATS "Number of accession IDs in SSN\t$numAccessions\n";

    close STATS;


    open SIZE, ">", $sizeFile or die "Unable to open size file $sizeFile for writing: $!";

    foreach my $clusterNum (sort {$a <=> $b} keys %clusterSizes) {
        print SIZE "$clusterNum\t$clusterSizes{$clusterNum}\n";
    }

    close SIZE;


    open SPCLDESC, ">", $spClustersDescFile or die "Unable to open swissprot desc file $spClustersDescFile for writing: $!";
    open SPSGDESC, ">", $spSinglesDescFile or die "Unable to open swissprot desc file $spSinglesDescFile for writing: $!";

    print SPCLDESC join("\t", "Cluster Number", "Metanode UniProt ID", "SwissProt Annotations"), "\n";
    print SPSGDESC join("\t", "Singleton Number", "UniProt ID", "SwissProt Annotations"), "\n";

    my @metaIds = sort
        {
            my $res = $numbermatch->{$constellations->{$a}} <=> $numbermatch->{$constellations->{$b}};
            $res = $a cmp $b if not $res;
            return $res;
        } keys %$constellations;
    foreach my $id (@metaIds) {
        if (exists $spDesc->{$id}) {
            my $clId = $constellations->{$id};
            my $fh = scalar @{$supernodes->{$clId}} > 1 ? \*SPCLDESC : \*SPSGDESC;

            my @desc = grep !m/^NA$/, map { split(m/,/) } @{$spDesc->{$id}};
            if (scalar @desc) {
                my $clNum = $numbermatch->{$clId};
                $fh->print(join("\t", $clNum, $id, join(",", @desc)), "\n");
            }
        }
    }

    close SPCLDESC;
    close SPSGDESC;
}

sub finish {
    my $self = shift;

    close($self->{all_pfam_fh}) if exists $self->{all_pfam_fh};
    close($self->{all_pfam_fh_any}) if exists $self->{all_pfam_fh_any};
    close($self->{all_pfam_fh_split}) if exists $self->{all_pfam_fh_split};
}


1;

