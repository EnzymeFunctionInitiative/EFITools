
package EFI::GNN::NeighborUtil;

use List::MoreUtils qw{uniq};
use Array::Utils qw(:all);



sub new {
    my ($class, %args) = @_;

    $self->{dbh} = $args{dbh};
    $self->{use_new_neighbor_method} = exists $args{use_nnm} ? $args{use_nnm} : 1;
    
    return bless($self, $class);
}


sub findNeighbors {
    my $self = shift;
    my $ac = shift;
    my $neighborhoodSize = shift;
    my $warning_fh = shift;
    my $testForCirc = shift;
    my $noneFamily = shift;
    my $accessionData = shift;

    my $debug = 0;

    my $genomeId = "";
    my $noNeighbors = 0;
    my %pfam;
    my $numqable = 0;
    my $numneighbors = 0;

    if (not $self->{dbh}->ping()) {
        warn "Database disconnected at " . scalar localtime;
        $self->{dbh} = $self->{dbh}->clone() or die "Cannot reconnect to database.";
    }

    my $isCircSql = "select * from ena where AC='$ac' order by TYPE limit 1";
    $sth = $self->{dbh}->prepare($isCircSql);
    $sth->execute;

    my $row = $sth->fetchrow_hashref;
    if (not defined $row or not $row) {
        print $warning_fh "$ac\tnomatch\n";
        return \%pfam, 1, -1, $genomeId;
    }

    $genomeId = $row->{ID};

    if ($self->{use_new_neighbor_method}) {
        # If the sequence is a part of any circular genome(s), then we check which genome, if their are multiple
        # genomes, has the most genes and use that one.
        if ($row->{TYPE} == 0) {
            my $sql = "select *, max(NUM) as MAX_NUM from ena where ID in (select ID from ena where AC='$ac' and TYPE=0 order by ID) group by ID order by TYPE, MAX_NUM desc limit 1";
            my $sth = $self->{dbh}->prepare($sql);
            $sth->execute;
            my $frow = $sth->fetchrow_hashref;
            if (not defined $frow or not $frow) {
                die "Unable to execute query $sql";
            }
            $genomeId = $frow->{ID};
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
    if($row->{DIRECTION}==0){
        $origdirection='complement';
    }elsif($row->{DIRECTION}==1){
        $origdirection='normal';
    }else{
        die "Direction of ".$row->{AC}." does not appear to be normal (0) or complement(1)\n";
    }
    $origtmp=join('-', sort {$a <=> $b} uniq split(",",$row->{pfam}));

    my $num = $row->{NUM};
    my $id = $row->{ID};
    my $acc_start = int($row->{start});
    my $acc_stop = int($row->{stop});
    my $acc_seq_len = int(abs($acc_stop - $acc_start) / 3 - 1);
    my $acc_strain = $row->{strain};
    my $acc_family = $row->{pfam};
    
    $low=$num-$neighborhoodSize;
    $high=$num+$neighborhoodSize;
    my $acc_type = $row->{TYPE} == 1 ? "linear" : "circular";

    $query="select * from ena where ID='$id' ";
    my $clause = "and num>=$low and num<=$high";

    # Handle circular case
    my ($max, $circHigh, $circLow, $maxCoord);
    my $maxQuery = "select NUM,stop from ena where ID = '$id' order by NUM desc limit 1";
    my $maxSth = $self->{dbh}->prepare($maxQuery);
    $maxSth->execute;
    my $maxRow = $maxSth->fetchrow_hashref;
    $max = $maxRow->{NUM};
    $maxCoord = $maxRow->{stop};

    if (defined $testForCirc and $testForCirc and $acc_type eq "circular") {
        if ($neighborhoodSize < $max) {
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

    $query .= $clause . " order by NUM";

    my $neighbors=$self->{dbh}->prepare($query);
    $neighbors->execute;

    if($neighbors->rows >1){
        $noNeighbors = 0;
        push @{$pfam{'withneighbors'}{$origtmp}}, $ac;
    }else{
        $noNeighbors = 1;
        print $warning_fh "$ac\tnoneighbor\n";
    }

    my $isBound = ($low < 1 ? 1 : 0);
    $isBound = $isBound | ($high > $max ? 2 : 0);

    $pfam{'genome'}{$ac} = $id;
    $accessionData->{$ac}->{attributes} = {accession => $ac, num => $num, family => $origtmp, id => $id,
       start => $acc_start, stop => $acc_stop, rel_start => 0, rel_stop => $acc_stop - $acc_start, 
       strain => $acc_strain, direction => $origdirection, is_bound => $isBound,
       type => $acc_type, seq_len => $acc_seq_len};

    while(my $neighbor=$neighbors->fetchrow_hashref){
        my $tmp=join('-', sort {$a <=> $b} uniq split(",",$neighbor->{pfam}));
        if($tmp eq ''){
            $tmp='none';
            $noneFamily->{$neighbor->{AC}} = 1;
        }
        push @{$pfam{'orig'}{$tmp}}, $ac;
        
        my $nbStart = int($neighbor->{start});
        my $nbStop = int($neighbor->{stop});
        my $nbSeqLen = abs($neighbor->{stop} - $neighbor->{start});
        my $nbSeqLenBp = int($nbSeqLen / 3 - 1);

        my $relNbStart;
        my $relNbStop;
        my $neighNum = $neighbor->{NUM};
        if ($neighNum > $high and defined $circHigh and defined $max) {
            $distance = $neighNum - $num - $max;
            $relNbStart = $nbStart - $maxCoord;
        } elsif ($neighNum < $low and defined $circLow and defined $max) {
            $distance = $neighNum - $num + $max;
            $relNbStart = $maxCoord + $nbStart;
        } else {
            $distance = $neighNum - $num;
            $relNbStart = $nbStart;
        }
        $relNbStart = int($relNbStart - $acc_start);
        $relNbStop = int($relNbStart + $nbSeqLen);

        print join("\t", $ac, $neighbor->{AC}, $neighbor->{NUM}, $neighbor->{pfam}, $neighNum, $num, $distance), "\n"               if $debug;

        unless($distance==0){
            my $type;
            if($neighbor->{TYPE}==1){
                $type='linear';
            }elsif($neighbor->{TYPE}==0){
                $type='circular';
            }else{
                die "Type of ".$neighbor->{AC}." does not appear to be circular (0) or linear(1)\n";
            }
            if($neighbor->{DIRECTION}==0){
                $direction='complement';
            }elsif($neighbor->{DIRECTION}==1){
                $direction='normal';
            }else{
                die "Direction of ".$neighbor->{AC}." does not appear to be normal (1) or complement(0)\n";
            }

            push @{$accessionData->{$ac}->{neighbors}}, {accession => $neighbor->{AC}, num => int($neighbor->{NUM}),
                family => $tmp, id => $neighbor->{ID},
                rel_start => $relNbStart, rel_stop => $relNbStop, start => $nbStart, stop => $nbStop,
                #strain => $neighbor->{strain},
                direction => $direction, type => $type, seq_len => $nbSeqLenBp};
            push @{$pfam{'neigh'}{$tmp}}, "$ac:".$neighbor->{AC};
            push @{$pfam{'neighlist'}{$tmp}}, $neighbor->{AC};
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

1;

