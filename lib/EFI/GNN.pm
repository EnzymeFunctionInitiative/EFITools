
BEGIN {
    die "The EFISHARED environment variable must be set before including this module" if not exists $ENV{EFISHARED} and not length $ENV{EFISHARED};
    use lib $ENV{EFISHARED};
}


package EFI::GNN;

use List::MoreUtils qw{apply uniq any};
use List::Util qw(sum);
use Array::Utils qw(:all);

use base qw(EFI::GNNShared);
use EFI::GNNShared;


sub new {
    my ($class, %args) = @_;

    my $self = EFI::GNNShared->new(%args);

    $self->{no_pfam_fh} = {};
    $self->{use_new_neighbor_method} = $args{use_nnm};
    $self->{pfam_dir} = $args{pfam_dir} if exists $args{pfam_dir} and -d $args{pfam_dir};
    
    return bless($self, $class);
}


sub findNeighbors {
    my $self = shift @_;
    my $ac=shift @_;
    my $n=shift @_;
    my $warning_fh = shift @_;
    my $testForCirc = shift @_;
    my $noneFamily = shift @_;

    my $debug = 0;

    my $genomeId = "";
    my $noNeighbors = 0;
    my %pfam=();
    my $numqable=0;
    my $numneighbors=0;

    my $isCircSql = "select * from ena where AC='$ac' order by TYPE limit 1";
    $sth = $self->{dbh}->prepare($isCircSql);
    $sth->execute;

    if (not $sth->rows) {
        print $warning_fh "$ac:nomatch\n";
        return \%pfam, 1, -1, $genomeId;
    }

    my $row = $sth->fetchrow_hashref;
    $genomeId = $row->{ID};

    if ($self->{use_new_neighbor_method}) {
        # If the sequence is a part of any circular genome(s), then we check which genome, if their are multiple
        # genomes, has the most genes and use that one.
        if ($row->{TYPE} == 0) {
            my $sql = "select *, max(NUM) as MAX_NUM from ena where ID in (select ID from ena where AC='$ac' and TYPE=0 order by ID) group by ID order by TYPE, MAX_NUM desc limit 1";
            print "CIRCULAR $sql\n"                                                         if $debug;
            my $sth = $self->{dbh}->prepare($sql);
            $sth->execute;
            $genomeId = $sth->fetchrow_hashref->{ID};
        } else {
            my $sql = <<SQL;
select
        ena.ID,
        ena.AC,
        ena.NUM,
        ABS(ena.NUM / max_table.MAX_NUM - 0.5) as PCT,
        (ena.NUM < max_table.MAX_NUM - 10) as RRR,
        (ena.NUM > 10) as LLL
    from ena
    inner join
        (
            select *, max(NUM) as MAX_NUM from ena where ID in
            (
                select ID from ena where AC='$ac' and TYPE=1 order by ID
            )
        ) as max_table
    where
        ena.AC = '$ac'
    order by
        LLL desc,
        RRR desc,
        PCT
    limit 1
SQL
            ;
            print "LINEAR $sql\n"                                                           if $debug;
            my $sth = $self->{dbh}->prepare($sql);
            $sth->execute;
            my $row = $sth->fetchrow_hashref;
            $genomeId = $row->{ID};
            if ($debug) {
                do {
                    print join("\t", $row->{ID}, $row->{AC}, $row->{NUM}, $row->{LLL}, $row->{RRR}, $row->{PCT}), "\n";
                } while ($row = $sth->fetchrow_hashref);
            }
        }
    }

    print "Using $genomeId as genome ID\n"                                              if $debug;

    my $selSql = "select * from ena where ID = '$genomeId' and AC = '$ac' limit 1;";
    print "$selSql\n"                                                                   if $debug;
    $sth=$self->{dbh}->prepare($selSql);
    $sth->execute;

    my $row = $sth->fetchrow_hashref;
    if($row->{DIRECTION}==1){
        $origdirection='complement';
    }elsif($row->{DIRECTION}==0){
        $origdirection='normal';
    }else{
        die "Direction of ".$row->{AC}." does not appear to be normal (0) or complement(1)\n";
    }
    $origtmp=join('-', sort {$a <=> $b} uniq split(",",$row->{pfam}));

    my $num = $row->{NUM};
    my $id = $row->{ID};
    
    $low=$num-$n;
    $high=$num+$n;
    $type = $row->{TYPE};

    $query="select * from ena where ID='$id' ";
    my $clause = "and num>=$low and num<=$high";

    # Handle circular case
    my ($max, $circHigh, $circLow);
    if (defined $testForCirc and $testForCirc and $type == 0) {
        my $maxQuery = "select NUM from ena where ID = '$id' order by NUM desc limit 1";
        my $maxSth = $self->{dbh}->prepare($maxQuery);
        $maxSth->execute;

        $max = $maxSth->fetchrow_hashref()->{NUM};

        if ($n < $max) {
            my @maxClause;
            if ($low < 1) {
                $circHigh = $max + $low;
                push(@maxClause, "num >= $circHigh");
            }
            if ($high > $max) {
                $circLow = $high - $max;
                push(@maxClause, "num <= $circLow");
            }
            my $subClause = join(" or ", @maxClause);
            $subClause = "or " . $subClause if $subClause;
            $clause = "and ((num >= $low and num <= $high) $subClause)";
        }
    }

    $query .= $clause;

    my $neighbors=$self->{dbh}->prepare($query);
    $neighbors->execute;

    if($neighbors->rows >1){
        $noNeighbors = 0;
        push @{$pfam{'withneighbors'}{$origtmp}}, $ac;
    }else{
        $noNeighbors = 1;
        print $warning_fh "$ac\tnoneighbor\n";
    }

    $pfam{'genome'}{$ac} = $id;

    while(my $neighbor=$neighbors->fetchrow_hashref){
        my $tmp=join('-', sort {$a <=> $b} uniq split(",",$neighbor->{pfam}));
        if($tmp eq ''){
            $tmp='none';
            $noneFamily->{$neighbor->{AC}} = 1;
        }
        push @{$pfam{'orig'}{$tmp}}, $ac;
        
        my $neighNum = $neighbor->{NUM};
        if ($neighNum > $high and defined $circHigh and defined $max) {
            $distance = $neighNum - $num - $max;
        } elsif ($neighNum < $low and defined $circLow and defined $max) {
            $distance = $neighNum - $num + $max;
        } else {
            $distance = $neighNum - $num;
        }

        print join("\t", $neighbor->{AC}, $neighbor->{NUM}, $neighbor->{pfam}, $neighNum, $num, $distance), "\n"               if $debug;

        unless($distance==0){
            push @{$pfam{'neigh'}{$tmp}}, "$ac:".$neighbor->{AC};
            push @{$pfam{'neighlist'}{$tmp}}, $neighbor->{AC};
            if($neighbor->{TYPE}==1){
                $type='linear';
            }elsif($neighbor->{TYPE}==0){
                $type='circular';
            }else{
                die "Type of ".$neighbor->{AC}." does not appear to be circular (0) or linear(1)\n";
            }
            if($neighbor->{DIRECTION}==1){
                $direction='complement';
            }elsif($neighbr->{DIRECTION}==0){
                $direction='normal';
            }else{
                die "Direction of ".$neighbor->{AC}." does not appear to be normal (0) or complement(1)\n";
            }
            push @{$pfam{'dist'}{$tmp}}, "$ac:$origdirection:".$neighbor->{AC}.":$direction:$distance";
            push @{$pfam{'stats'}{$tmp}}, abs $distance;
            push @{$pfam{'data'}{$tmp}}, { query_id => $ac,
                                           neighbor_id => $neighbor->{AC},
                                           distance => (abs $distance),
                                           direction => "$origdirection-$direction"
                                         };
        }	
    }

    foreach my $key (keys %{$pfam{'orig'}}){
        @{$pfam{'orig'}{$key}}=uniq @{$pfam{'orig'}{$key}};
    }

    return \%pfam, 0, $noNeighbors, $genomeId;
}

sub getPfamNames{
    my $self = shift @_;
    my $pfamNumbers=shift @_;

    my $pfam_info;
    my @pfam_short=();
    my @pfam_long=();

    foreach my $tmp (split('-',$pfamNumbers)){
        my $sth=$self->{dbh}->prepare("select * from pfam_info where pfam='$tmp';");
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

    my $shape='broken';
    my %pdbInfo=();
    my $pdb=0;
    my $ec=0;
    my $pdbNumber='';
    my $pdbEvalue='';
    my $pdbresults;
    my $ecresults;

    foreach my $accession (@accessions){
        my $sth=$self->{dbh}->prepare("select STATUS,EC from annotations where accession='$accession'");
        $sth->execute;
        $ecresults=$sth->fetchrow_hashref;
        if($ecresults->{EC} ne 'None'){
            $ec++;
        }
        $sth=$self->{dbh}->prepare("select PDB,e from pdbhits where ACC='$accession'");
        $sth->execute;
        if($sth->rows > 0){
            $pdb++;
            $pdbresults=$sth->fetchrow_hashref;
            $pdbNumber=$pdbresults->{PDB};
            $pdbEvalue=$pdbresults->{e};
        }else{
            $pdbNumber='None';
            $pdbEvalue='None';
        }
        $pdbInfo{$accession}=$ecresults->{EC}.":$pdbNumber:$pdbEvalue:".$ecresults->{STATUS};
    }
    if($pdb>0 and $ec>0){
        $shape='diamond';
    }elsif($pdb>0){
        $shape='square';
    }elsif($ec>0){
        $shape='triangle'
    }else{
        $shape='circle';
    }
    return $shape, \%pdbInfo;
}

sub writePfamSpoke{
    my $self = shift @_;
    my $gnnwriter=shift @_;
    my $pfam=shift @_;
    my $clusternumber=shift @_;
    my @cluster=@{shift @_};
    my %info=%{shift @_};

    my @tmparray=();
    my $shape='';

    (my $pfam_short, my $pfam_long)= $self->getPfamNames($pfam);
    (my $shape, my $pdbinfo)= $self->getPdbInfo(\@{$info{'neighlist'}});
    $gnnwriter->startTag('node', 'id' => "$clusternumber:$pfam", 'label' => "$pfam_short");
    writeGnnField($gnnwriter, 'node.size', 'string', int(sprintf("%.2f",int(scalar(uniq @{$info{'orig'}})/scalar(@cluster)*100)/100)*100));
    writeGnnField($gnnwriter, 'node.shape', 'string', $shape);
    writeGnnField($gnnwriter, 'node.fillColor','string', '#EEEEEE');
    writeGnnField($gnnwriter, 'Co-occurrence', 'real', sprintf("%.2f",int(scalar(uniq @{$info{'orig'}})/scalar(@cluster)*100)/100));
    writeGnnField($gnnwriter, 'Co-occurrence Ratio','string',scalar(uniq @{$info{'orig'}})."/".scalar(@cluster));
    writeGnnField($gnnwriter, 'Average Distance', 'real', sprintf("%.2f", int(sum(@{$info{'stats'}})/scalar(@{$info{'stats'}})*100)/100));
    writeGnnField($gnnwriter, 'Median Distance', 'real', sprintf("%.2f",int(median(@{$info{'stats'}})*100)/100));
    writeGnnField($gnnwriter, 'Pfam Neighbors', 'integer', scalar(@{$info{'neigh'}}));
    writeGnnField($gnnwriter, 'Queries with Pfam Neighbors', 'integer', scalar(uniq @{$info{'orig'}}));
    writeGnnField($gnnwriter, 'Queriable Sequences','integer',scalar(@cluster));
    writeGnnField($gnnwriter, 'Cluster Number', 'integer', $clusternumber);
    writeGnnField($gnnwriter, 'Pfam Description', 'string', $pfam_long);
    writeGnnField($gnnwriter, 'Pfam', 'string', $pfam);
    writeGnnListField($gnnwriter, 'Query Accessions', 'string', \@{$info{'orig'}});
    @tmparray=map "$pfam:$_", @{$info{'dist'}};
    writeGnnListField($gnnwriter, 'Query-Neighbor Arrangement', 'string', \@tmparray);
    @tmparray=map "$pfam:$_:".${$pdbinfo}{(split(":",$_))[1]}, @{$info{'neigh'}};
    writeGnnListField($gnnwriter, 'Query-Neighbor Accessions', 'string', \@tmparray);
    $gnnwriter->endTag;

    return \@tmparray;
}

sub writeClusterHub{
    my $self = shift @_;
    my $gnnwriter=shift @_;
    my $clusterNumber=shift @_;
    my $info=%{shift @_};
    my @pdbarray=@{shift @_};
    my @cluster=@{shift @_};
    my $ssnNodes=scalar @{shift @_};
    my $color=shift @_;

    my @tmparray=();

    $gnnwriter->startTag('node', 'id' => $clusterNumber, 'label' => $clusterNumber);
    writeGnnField($gnnwriter,'node.shape', 'string', 'hexagon');
    writeGnnField($gnnwriter,'node.size', 'string', '70.0');
    writeGnnField($gnnwriter,'node.fillColor','string', $color);
    writeGnnField($gnnwriter,'Cluster Number', 'integer', $clusterNumber);
    writeGnnField($gnnwriter,'Queriable SSN Sequences', 'integer',scalar @cluster);
    writeGnnField($gnnwriter,'Total SSN Sequences', 'integer', $ssnNodes);
    @tmparray=uniq grep { $_ ne '' } map { if(int(scalar(uniq @{$info->{$_}{'orig'}})/scalar(@cluster)*100)/100>$self->{incfrac}) {"$clusterNumber:$_:".scalar(uniq @{$info->{$_}{'orig'}}) }} sort keys %info;
    writeGnnListField($gnnwriter, 'Hub Queries with Pfam Neighbors', 'string', \@tmparray);
    @tmparray= grep { $_ ne '' } map { if(int(scalar(uniq @{$info->{$_}{'orig'}})/scalar(@cluster)*100)/100>$self->{incfrac}) { "$clusterNumber:$_:".scalar @{$info->{$_}{'neigh'}}}} sort keys %info;
    writeGnnListField($gnnwriter, 'Hub Pfam Neighbors', 'string', \@tmparray);
    @tmparray= grep { $_ ne '' } map { if(int(scalar(uniq @{$info->{$_}{'orig'}})/scalar(@cluster)*100)/100>$self->{incfrac}) { "$clusterNumber:$_:".sprintf("%.2f", int(sum(@{$info->{$_}{'stats'}})/scalar(@{$info->{$_}{'stats'}})*100)/100).":".sprintf("%.2f",int(median(@{$info->{$_}{'stats'}})*100)/100)}} sort keys %info;
    writeGnnListField($gnnwriter, 'Hub Average and Median Distance', 'string', \@tmparray);
    @tmparray=grep { $_ ne '' } map { if(int(scalar(uniq @{$info->{$_}{'orig'}})/scalar(@cluster)*100)/100>$self->{incfrac}){"$clusterNumber:$_:".sprintf("%.2f",int(scalar(uniq @{$info->{$_}{'orig'}})/scalar(@cluster)*100)/100).":".scalar(uniq @{$info->{$_}{'orig'}})."/".scalar(@cluster)}} sort keys %info;
    writeGnnListField($gnnwriter, 'Hub Co-occurrence and Ratio', 'string', \@tmparray);
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

sub combineArraysAddPfam{
    my %info=%{shift @_};
    my $subkey=shift @_;
    my @cluster=@{shift @_};
    my $clusterNumber=shift @_;

    my @tmparray=();

    foreach my $key (keys %info){
        if( int(scalar(uniq @{$info{$key}{'orig'}})/scalar(@cluster)*100)/100>=$self->{incfrac}){
            push @tmparray, map "$clusterNumber:$key:$_", @{$info{$key}{$subkey}};
        }
    } 

    return @tmparray;
}

sub getClusterHubData {
    my $self = shift;
    my $supernodes = shift;
    my $n = shift @_;
    my $warning_fh = shift @_;
    my $useCircTest = shift @_;
    my $supernodeOrder = shift;

    my %withneighbors=();
    my %clusternodes=();
    my %noNeighbors;
    my %noMatches;
    my %genomeIds;
    my %noneFamily;

    foreach my $clusterNode (@{ $supernodeOrder }) {
        $noneFamily{$clusterNode} = {};
        foreach my $accession (uniq @{$supernodes->{$clusterNode}}){
            my ($pfamsearch, $localNoMatch, $localNoNeighbors, $genomeId) =
                $self->findNeighbors($accession, $n, $warning_fh, $useCircTest, $noneFamily{$clusterNode});
            $noNeighbors{$accession} = $localNoNeighbors;
            $genomeIds{$accession} = $genomeId;
            $noMatches{$accession} = $localNoMatch;
            foreach my $pfamNumber (sort {$a <=> $b} keys %{${$pfamsearch}{'neigh'}}){
                push @{$clusterNodes{$clusterNode}{$pfamNumber}{'orig'}}, @{${$pfamsearch}{'orig'}{$pfamNumber}};
                push @{$clusterNodes{$clusterNode}{$pfamNumber}{'dist'}}, @{${$pfamsearch}{'dist'}{$pfamNumber}};
                push @{$clusterNodes{$clusterNode}{$pfamNumber}{'stats'}}, @{${$pfamsearch}{'stats'}{$pfamNumber}};
                push @{$clusterNodes{$clusterNode}{$pfamNumber}{'neigh'}}, @{${$pfamsearch}{'neigh'}{$pfamNumber}};
                push @{$clusterNodes{$clusterNode}{$pfamNumber}{'neighlist'}}, @{${$pfamsearch}{'neighlist'}{$pfamNumber}};
                push @{$clusterNodes{$clusterNode}{$pfamNumber}{'data'}}, @{${$pfamsearch}{'data'}{$pfamNumber}};
            }
            foreach my $pfamNumber (sort {$a <=> $b} keys %{${$pfamsearch}{'withneighbors'}}){
                push @{$withneighbors{$clusterNode}}, @{${$pfamsearch}{'withneighbors'}{$pfamNumber}};
            }
        }
    }

    return \%clusterNodes, \%withneighbors, \%noMatches, \%noNeighbors, \%genomeIds, \%noneFamily;
}


sub writeClusterHubGnn{
    my $self = shift @_;
    my $gnnwriter=shift @_;
    my $clusterNodes=shift @_;
    my $withneighbors=shift @_;
    my $numbermatch=shift @_;
    my $supernodes=shift @_;

    $gnnwriter->startTag('graph', 'label' => "$title gnn", 'xmlns' => 'http://www.cs.rpi.edu/XGMML');

    foreach my $cluster (sort {$a <=> $b} keys %$clusterNodes){
        print "building hub node $cluster, simplenumber ".$numbermatch->{$cluster}."\n";
        my @pdbinfo=();
        foreach my $pfam (keys %{$clusterNodes->{$cluster}}){
            $cooccurrence= sprintf("%.2f",int(scalar(uniq @{$clusterNodes->{$cluster}{$pfam}{'orig'}})/scalar(@{$withneighbors->{$cluster}})*100)/100);
            if($self->{incfrac}<=$cooccurrence){
                my $tmparray= $self->writePfamSpoke($gnnwriter,$pfam, $numbermatch->{$cluster}, $withneighbors->{$cluster}, $clusterNodes->{$cluster}{$pfam});
                push @pdbinfo, @{$tmparray};
                $self->writePfamEdge($gnnwriter,$pfam,$numbermatch->{$cluster});
            }
        }
        $self->writeClusterHub($gnnwriter, $numbermatch->{$cluster}, $clusterNodes->{$cluster}, \@pdbinfo, $withneighbors->{$cluster}, $supernodes->{$cluster}, $self->{colors}->{$numbermatch{$cluster}});

    }

    $gnnwriter->endTag();
}

sub saveGnnAttributes {
    my $self = shift;
    my $writer = shift;
    my $gnnData = shift;
    my $node = shift;

    # If this is a repnode network, there will be a child node named "ACC". If so, we need to wrap
    # all of the no matches, etc into a list rather than a simple attribute.
    my @accIdNode = grep { $_ =~ /\S/ and $_->getAttribute('name') eq "ACC" } $node->getChildNodes;
    if (scalar @accIdNode) {
        my $accNode = $accIdNode[0];
        my @accIdAttrs = $accNode->findnodes("./*");

        my @hasNeighbors;
        my @hasMatch;
        my @genomeId;

        foreach my $accIdAttr (@accIdAttrs) {
            my $accId = $accIdAttr->getAttribute('value');
            push @hasNeighbors, $gnnData->{noNeighborMap}->{$accId} == 1 ? "false" : $gnnData->{noNeighborMap}->{$accId} == -1 ? "n/a" : "true";
            push @hasMatch, $gnnData->{noMatchMap}->{$accId} ? "false" : "true";
            push @genomeId, $gnnData->{genomeIds}->{$accId};
        }

        writeGnnListField($writer, 'Has Neighbors', 'string', \@hasNeighbors, 0);
        writeGnnListField($writer, 'Has Match', 'string', \@hasMatch, 0);
        writeGnnListField($writer, 'Genome ID', 'string', \@genomeId, 0);
    } else {
        my $nodeId = $node->getAttribute('label');
        my $hasNeighbors = $gnnData->{noNeighborMap}->{$nodeId} == 1 ? "false" : $gnnData->{noNeighborMap}->{$nodeId} == -1 ? "n/a" : "true";
        my $genomeId = $gnnData->{genomeIds}->{$nodeId};
        my $hasMatch = $gnnData->{noMatchMap}->{$nodeId} ? "false" : "true";
        writeGnnField($writer, 'Has Neighbors', 'string', $hasNeighbors);
        writeGnnField($writer, 'Has Match', 'string', $hasMatch);
        writeGnnField($writer, 'Genome ID', 'string', $genomeId);
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

    $writer->startTag('graph', 'label' => "$title Pfam Gnn", 'xmlns' => 'http://www.cs.rpi.edu/XGMML');

    foreach my $pfam (@pfamHubs){
        (my $pfam_short, my $pfam_long)= $self->getPfamNames($pfam);
        my $spokecount=0;
        my @hubPdb=();
        my @clusters=();
        foreach my $cluster (keys %{$clusterNodes}){
            if(exists ${$clusterNodes}{$cluster}{$pfam}){
                if((int(scalar( uniq (@{${$clusterNodes}{$cluster}{$pfam}{'orig'}}))/scalar(@{$withneighbors->{$cluster}})*100)/100)>=$self->{incfrac}){
                    push @clusters, $cluster;
                    my $spokePdb= $self->writeClusterSpoke($writer, $pfam, $cluster, $clusterNodes, $numbermatch, $pfam_short, $pfam_long, $supernodes,$withneighbors);
                    push @hubPdb, @{$spokePdb};
                    $self->writeClusterEdge($writer, $pfam, $cluster, $numbermatch);
                    $spokecount++;
                }
            }
        }
        if($spokecount>0){
            print "Building hub $pfam\n";
            $self->writePfamHub($writer,$pfam, $pfam_short, $pfam_long, \@hubPdb, \@clusters, $clusterNodes,$supernodes,$withneighbors, $numbermatch);
            $self->writePfamQueryData($pfam, \@clusters, $clusterNodes, $supernodes, $numbermatch);
        }
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
    my $color = $self->{colors}->{$numbermatch->{$cluster}};
    my $clusterNum = $numbermatch->{$cluster};

    my $avgDist=sprintf("%.2f", int(sum(@{${$clusterNodes}{$cluster}{$pfam}{'stats'}})/scalar(@{${$clusterNodes}{$cluster}{$pfam}{'stats'}})*100)/100);
    my $medDist=sprintf("%.2f",int(median(@{${$clusterNodes}{$cluster}{$pfam}{'stats'}})*100)/100);
    my $coOcc=(int(scalar( uniq (@{${$clusterNodes}{$cluster}{$pfam}{'orig'}}))/scalar(@{$withneighbors->{$cluster}})*100)/100);
    my $coOccRat=scalar( uniq (@{${$clusterNodes}{$cluster}{$pfam}{'orig'}}))."/".scalar(@{$withneighbors->{$cluster}});

    $writer->startTag('node', 'id' => "$pfam:" . $numbermatch->{$cluster}, 'label' => $numbermatch->{$cluster});

    writeGnnField($writer, 'node.fillColor','string', $color);
    writeGnnField($writer, 'Co-occurrence','real',$coOcc);
    writeGnnField($writer, 'Co-occurrence Ratio','string',$coOccRat);
    writeGnnField($writer, 'Cluster Number', 'integer', $clusterNum);
    writeGnnField($writer, 'Total SSN Sequences', 'integer', scalar(@{$supernodes->{$cluster}}));
    writeGnnField($writer, 'Queries with Pfam Neighbors', 'integer', scalar( uniq (@{${$clusterNodes}{$cluster}{$pfam}{'orig'}})));
    writeGnnField($writer, 'Queriable SSN Sequences', 'integer', scalar(@{$withneighbors->{$cluster}}));
    writeGnnField($writer, 'node.size', 'string',$coOcc*100);
    writeGnnField($writer, 'node.shape', 'string', $shape);
    writeGnnField($writer, 'Average Distance', 'real', $avgDist);
    writeGnnField($writer, 'Median Distance', 'real', $medDist);
    writeGnnField($writer, 'Pfam Neighbors', 'integer', scalar(@{${$clusterNodes}{$cluster}{$pfam}{'neigh'}}));
    
    writeGnnListField($writer, 'Query Accessions', 'string', \@{${$clusterNodes}{$cluster}{$pfam}{'orig'}});
    writeGnnListField($writer, 'Query-Neighbor Arrangement', 'string', \@{${$clusterNodes}{$cluster}{$pfam}{'dist'}});
    @tmparray=map "$_:".${$pdbinfo}{(split(":",$_))[1]}, @{${$clusterNodes}{$cluster}{$pfam}{'neigh'}};
    writeGnnListField($writer, 'Query-Neighbor Accessions', 'string', \@tmparray);
    
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

    writeGnnField($writer,'node.shape', 'string', 'hexagon');
    writeGnnField($writer,'node.size', 'string', '70.0');
    writeGnnField($writer, 'Pfam', 'string', $pfam);
    writeGnnField($writer, 'Pfam Description', 'string', $pfam_long);
    writeGnnField($writer, 'Total SSN Sequences', 'integer', sum(map scalar(@{$supernodes->{$_}}), @{$clusters}));
    writeGnnField($writer, 'Queriable SSN Sequences','integer', sum(map scalar(@{$withneighbors->{$_}}), @{$clusters}));
    writeGnnField($writer, 'Queries with Pfam Neighbors', 'integer',sum(map scalar( uniq (@{${$clusterNodes}{$_}{$pfam}{'orig'}})), @{$clusters}));
    writeGnnField($writer, 'Pfam Neighbors', 'integer',sum(map scalar( uniq (@{${$clusterNodes}{$_}{$pfam}{'neigh'}})), @{$clusters}));
    writeGnnListField($writer, 'Query-Neighbor Accessions', 'string', $hubPdb);
    @tmparray=map @{${$clusterNodes}{$_}{$pfam}{'dist'}},  sort {$a <=> $b} @{$clusters};
    writeGnnListField($writer, 'Query-Neighbor Arrangement', 'string', \@tmparray);
    @tmparray=map $numbermatch->{$_}.":".sprintf("%.2f",int(sum(@{${$clusterNodes}{$_}{$pfam}{'stats'}})/scalar(@{${$clusterNodes}{$_}{$pfam}{'stats'}})*100)/100).":".sprintf("%.2f",int(median(@{${$clusterNodes}{$_}{$pfam}{'stats'}})*100)/100), sort {$a <=> $b} @{$clusters};
    writeGnnListField($writer, 'Hub Average and Median Distances', 'string', \@tmparray);
    @tmparray=map $numbermatch->{$_}.":".sprintf("%.2f",int(scalar( uniq (@{${$clusterNodes}{$_}{$pfam}{'orig'}}))/scalar(@{$withneighbors->{$_}})*100)/100).":".scalar( uniq (@{${$clusterNodes}{$_}{$pfam}{'orig'}}))."/".scalar(@{$withneighbors->{$_}}), sort {$a <=> $b} @{$clusters};
    writeGnnListField($writer, 'Hub Co-occurrence and Ratio', 'string', \@tmparray);
    writeGnnField($writer, 'node.fillColor','string', '#EEEEEE');

    $writer->endTag;
}

sub writePfamQueryData {
    my $self = shift;
    my $pfam = shift;
    my $clustersInPfam = shift;
    my $clusterNodes = shift;
    my $supernodes = shift;
    my $numbermatch = shift;

    return if not $self->{pfam_dir} or not -d $self->{pfam_dir};

    if (not exists $self->{all_pfam_fh}) {
        open($self->{all_pfam_fh}, ">" . $self->{pfam_dir} . "/ALL_PFAM.txt");
        $self->{all_pfam_fh}->print(join("\t", "Query ID", "Neighbor ID", "Neighbor Pfam", "SSN Query Cluster #",
                                               "SSN Query Cluster Color", "Query-Neighbor Distance", "Query-Neighbor Directions"), "\n");
    }

    open(PFAMFH, ">" . $self->{pfam_dir} . "/no_pfam_neighbors_$pfam.txt") or die "Help " . $self->{pfam_dir} . "/pfam_nodes_$pfam.txt: $!";

    print PFAMFH join("\t", "Query ID", "Neighbor ID", "Neighbor Pfam", "SSN Query Cluster #", "SSN Query Cluster Color",
                            "Query-Neighbor Distance", "Query-Neighbor Directions"), "\n";

    foreach my $clusterId (@$clustersInPfam) {
        my $color = $self->{colors}->{$numbermatch->{$clusterId}};
        my $clusterNum = $numbermatch->{$clusterId};
        $clusterNum = "none" if not $clusterNum;

        foreach my $data (@{ $clusterNodes->{$clusterId}->{$pfam}->{data} }) {
            my $line = join("\t", $data->{query_id},
                                  $data->{neighbor_id},
                                  $pfam,
                                  $clusterNum,
                                  $color,
                                  sprintf("%02d", $data->{distance}),
                                  $data->{direction},
                           ) . "\n";
            print PFAMFH $line;
            $self->{all_pfam_fh}->print($line);
        }
    }

    close(PFAMFH);
}

sub writePfamNoneClusters {
    my $self = shift;
    my $outDir = shift;
    my $noneFamily = shift;
    my $numbermatch = shift;

    foreach my $clusterId (keys %$noneFamily) {
        my $clusterNum = $numbermatch->{$clusterId};

        open NONEFH, ">$outDir/pfam_none_$clusterNum.txt";

        foreach my $nodeId (keys %{ $noneFamily->{$clusterId} }) {
            print NONEFH "$nodeId\n";
        }

        close NONEFH;
    }
}

sub finish {
    my $self = shift;

    close($self->{all_pfam_fh}) if exists $self->{all_pfam_fh};
}

1;

