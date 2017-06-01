#!/usr/bin/env perl

#print "USING LOCAL COPY\n";

sub findneighbors {
  my $ac=shift @_;
  my $n=shift @_;
  my $dbh=shift @_;
  my $fh=shift @_;
  my $neighfile=shift @_;
  my %pfam=();
  my $numqable=0;
  my $numneighbors=0;

  my $selSql = "select * from ena where AC='$ac' limit 1;";
  $sth=$dbh->prepare($selSql);
  #print "SQL: $selSql\n"; 
  $sth->execute;
  if($sth->rows>0){
    while(my $row=$sth->fetchrow_hashref){
    #  $row=$sth->fetchrow_hashref;
      if($row->{DIRECTION}==1){
        $origdirection='complement';
      }elsif($row->{DIRECTION}==0){
        $origdirection='normal';
      }else{
        die "Direction of ".$row->{AC}." does not appear to be normal (0) or complement(1)\n";
      }
      $origtmp=join('-', sort {$a <=> $b} uniq split(",",$row->{pfam}));
      $low=$row->{NUM}-$n;
      $high=$row->{NUM}+$n;
      $query="select * from ena where ID='".$row->{ID}."' and num>=$low and num<=$high";
      my $neighbors=$dbh->prepare($query);
      $neighbors->execute;
      if($neighbors->rows >1){
	push @{$pfam{'withneighbors'}{$origtmp}}, $ac;
      }else{
	print $neighfile "$ac\n";
      }
      while(my $neighbor=$neighbors->fetchrow_hashref){
	my $tmp=join('-', sort {$a <=> $b} uniq split(",",$neighbor->{pfam}));
        if($tmp eq ''){
	  $tmp='none';
        }
        push @{$pfam{'orig'}{$tmp}}, $ac;
	$distance=$neighbor->{NUM}-$row->{NUM};
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
	    
#	    push @{$pfam{'orig'}{$tmp}}, $ac;
#	    print "add $ac to $tmp\n";
	  }	
      }
    }
  }else{
    print $fh "$ac\n";
  }
  #print "print out results from pfam data structure\n";
  #foreach $key (keys %pfam){
  #  foreach $keyb (keys %{$pfam{$key}}){
  #    print "$key $keyb ".join(",",@{$pfam{$key}{$keyb}})."\n";
  #  }
  #}

  foreach my $key (keys %{$pfam{'orig'}}){
    @{$pfam{'orig'}{$key}}=uniq @{$pfam{'orig'}{$key}};
  }
  return \%pfam;
}

sub getcolors {
  my $dbh=shift @_;
  my %colors=();
  my $sth=$dbh->prepare("select * from colors;");
  $sth->execute;
  while(my $row=$sth->fetchrow_hashref){
    $colors{$row->{cluster}}=$row->{color};
  }
  return \%colors;
}

sub median{
    my @vals = sort {$a <=> $b} @_;
    my $len = @vals;
    if($len%2) #odd?
    {
        return $vals[int($len/2)];
    }
    else #even
    {
        return ($vals[int($len/2)-1] + $vals[int($len/2)])/2;
    }
}

sub writeGnnField {
  my $writer=shift @_;
  my $name=shift @_;
  my $type=shift @_;
  my $value=shift @_;
  unless($type eq 'string' or $type eq 'integer' or $type eq 'real'){
    die "Invalid GNN type $type\n";
  }
  $writer->emptyTag('att', 'name' => $name, 'type' => $type, 'value' => $value);
}

sub writeGnnListField {
  my $writer=shift @_;
  my $name=shift @_;
  my $type=shift @_;
  my @values=@{ shift @_ };
  unless($type eq 'string' or $type eq 'integer' or $type eq 'real'){
    die "Invalid GNN type $type\n";
  }
  $writer->startTag('att', 'type' => 'list', 'name' => $name);
  foreach my $element (sort @values){
    $writer->emptyTag('att', 'type' => $type, 'name' => $name, 'value' => $element);
  }
  $writer->endTag;
}

sub getPfamNames{
  my $dbh=shift @_;
  my $pfamNumbers=shift @_;
  my $pfam_info;
  my @pfam_short=();
  my @pfam_long=();
  foreach my $tmp (split('-',$pfamNumbers)){
      my $sth=$dbh->prepare("select * from pfam_info where pfam='$tmp';");
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
  my $dbh=shift @_;
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
    my $sth=$dbh->prepare("select STATUS,EC from annotations where accession='$accession'");
    $sth->execute;
    $ecresults=$sth->fetchrow_hashref;
    if($ecresults->{EC} ne 'None'){
      $ec++;
    }
    $sth=$dbh->prepare("select PDB,e from pdbhits where ACC='$accession'");
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
  my $gnnwriter=shift @_;
  my $pfam=shift @_;
  my $dbh=shift @_;
  my $clusternumber=shift @_;
  my @cluster=@{shift @_};
  my %info=%{shift @_};
  my @tmparray=();
  my $shape='';
  (my $pfam_short, my $pfam_long)=getPfamNames($dbh, $pfam);
  (my $shape, my $pdbinfo)=getPdbInfo($dbh, \@{$info{'neighlist'}});
  $gnnwriter->startTag('node', 'id' => "$clusternumber:$pfam", 'label' => "$pfam_short");
  #writeGnnField($gnnwriter, 'node.fillColor', 'string', '#FFFFFF');
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
  my $gnnwriter=shift @_;
  my $clusterNumber=shift @_;
  my %info=%{shift @_};
  my @pdbarray=@{shift @_};
  my @cluster=@{shift @_};
  my $incfrac=shift @_;
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
  #@tmparray=combineArraysAddPfam(\%info,'orig',$incfrac,\@cluster,$clusterNumber);
  @tmparray=uniq grep { $_ ne '' } map { if(int(scalar(uniq @{$info{$_}{'orig'}})/scalar(@cluster)*100)/100>$incfrac) {"$clusterNumber:$_:".scalar(uniq @{$info{$_}{'orig'}}) }} sort keys %info;
  writeGnnListField($gnnwriter, 'Hub Queries with Pfam Neighbors', 'string', \@tmparray);
  #writeGnnListField($gnnwriter, 'Query-Neighbor Accessions', 'string', \@pdbarray);
  #@tmparray=combineArraysAddPfam(\%info, 'dist', $incfrac,\@cluster, $clusterNumber);
  #writeGnnListField($gnnwriter, 'Query-Neighbor Arrangement', 'string', \@tmparray);
  @tmparray= grep { $_ ne '' } map { if(int(scalar(uniq @{$info{$_}{'orig'}})/scalar(@cluster)*100)/100>$incfrac) { "$clusterNumber:$_:".scalar @{$info{$_}{'neigh'}}}} sort keys %info;
  writeGnnListField($gnnwriter, 'Hub Pfam Neighbors', 'string', \@tmparray);
  @tmparray= grep { $_ ne '' } map { if(int(scalar(uniq @{$info{$_}{'orig'}})/scalar(@cluster)*100)/100>$incfrac) { "$clusterNumber:$_:".sprintf("%.2f", int(sum(@{$info{$_}{'stats'}})/scalar(@{$info{$_}{'stats'}})*100)/100).":".sprintf("%.2f",int(median(@{$info{$_}{'stats'}})*100)/100)}} sort keys %info;
  writeGnnListField($gnnwriter, 'Hub Average and Median Distance', 'string', \@tmparray);
  #@tmparray= map "$_:".sprintf("%.2f",int(median(@{$info{$_}{'stats'}})*100)/100),keys %info;
  #writeGnnListField($gnnwriter, 'Hub Median Distance', 'string', \@tmparray);
  @tmparray=grep { $_ ne '' } map { if(int(scalar(uniq @{$info{$_}{'orig'}})/scalar(@cluster)*100)/100>$incfrac){"$clusterNumber:$_:".sprintf("%.2f",int(scalar(uniq @{$info{$_}{'orig'}})/scalar(@cluster)*100)/100).":".scalar(uniq @{$info{$_}{'orig'}})."/".scalar(@cluster)}} sort keys %info;
  writeGnnListField($gnnwriter, 'Hub Co-occurrence and Ratio', 'string', \@tmparray);
  $gnnwriter->endTag;
}

sub writePfamEdge{
  my $gnnwriter=shift @_;
  my $pfam=shift @_;
  my $clusternumber=shift @_;
  $gnnwriter->startTag('edge', 'label' => "$clusternumber to $clusternumber:$pfam", 'source' => $clusternumber, 'target' => "$clusternumber:$pfam");
  $gnnwriter->endTag();
}

sub combineArraysAddPfam{
  my %info=%{shift @_};
  my $subkey=shift @_;
  my $incfrac=shift @_;
  my @cluster=@{shift @_};
  my $clusterNumber=shift @_;
  my @tmparray=();
  foreach my $key (keys %info){
    if( int(scalar(uniq @{$info{$key}{'orig'}})/scalar(@cluster)*100)/100>=$incfrac){
      push @tmparray, map "$clusterNumber:$key:$_", @{$info{$key}{$subkey}};
    }
  } 
  return @tmparray;
}

sub getNodesAndEdges{
  my $reader=shift @_;
  my @nodes=();
  my @edges=();
  $parser = XML::LibXML->new();
  $reader->read();
  if($reader->nodeType==8){ #node type 8 is a comment
    print "XGMML made with ".$reader->value."\n";
   $reader->read; #we do not want to start reading a comment
  }
  my $graphname=$reader->getAttribute('label');
  my $firstnode=$reader->nextElement();
  my $tmpstring=$reader->readOuterXml;
  my $tmpnode=$parser->parse_string($tmpstring);
  my $node=$tmpnode->firstChild;
  push @nodes, $node;
  while($reader->nextSiblingElement()){
    $tmpstring=$reader->readOuterXml;
    $tmpnode=$parser->parse_string($tmpstring);
    $node=$tmpnode->firstChild;
    if($reader->name() eq "node"){
      push @nodes, $node;
    }elsif($reader->name() eq "edge"){
      push @edges, $node;
    }else{
      warn "not a node or an edge\n $tmpstring\n";
    }
  }
  return ($graphname, \@nodes, \@edges);
}

sub getNodes{
  my $nodes=shift @_;
  my %nodehash=();
  my %nodenames=();
  print "parse nodes for accessions\n";
  foreach $node (@{$nodes}){
    $nodehead=$node->getAttribute('label');
    #cytoscape exports replace the id with an integer instead of the accessions
    #%nodenames correlates this integer back to an accession
    #for efiest generated networks the key is the accession and it equals an accession, no harm, no foul
    $nodenames{$node->getAttribute('id')}=$nodehead;
    my @annotations=$node->findnodes('./*');
    push @{$nodehash{$nodehead}}, $nodehead;
    foreach $annotation (@annotations){
      if($annotation->getAttribute('name') eq "ACC"){
        my @accessionlists=$annotation->findnodes('./*');
        foreach $accessionlist (@accessionlists){
	  #make sure all accessions within the node are included in the gnn network
	  push @{$nodehash{$nodehead}}, $accessionlist->getAttribute('value');
        }
      }
    }
  }
  return \%nodehash, \%nodenames;
}

sub getClusters{
#($constallations, $supernodes)=getClusters(\%nodehash, \%nodenames, \@edges);
  my $nodehash=shift @_;
  my $nodenames=shift @_;
  my $edges=shift @_;
  my %constellations=();
  my %supernodes=();
  my $newnode=1;

  foreach $edge (@{$edges}){
    #if source exists, add target to source sc
    if(exists $constellations{${$nodenames}{$edge->getAttribute('source')}}){
      #if target also already existed, add target data to source 
      if(exists $constellations{${$nodenames}{$edge->getAttribute('target')}}){
        #check if source and target are in the same constellation, if they are, do nothing, if not, add change target sc to source and add target accessions to source accessions
        unless($constellations{${$nodenames}{$edge->getAttribute('target')}} eq $constellations{${$nodenames}{$edge->getAttribute('source')}}){
	  #add accessions from target supernode to source supernode
	  push @{$supernodes{$constellations{${$nodenames}{$edge->getAttribute('source')}}}}, @{$supernodes{$constellations{${$nodenames}{$edge->getAttribute('target')}}}};
	  #delete target supernode
	  delete $supernodes{$constellations{${$nodenames}{$edge->getAttribute('target')}}};
	  #change the constellation number for all 
	  $oldtarget=$constellations{${$nodenames}{$edge->getAttribute('target')}};
	  foreach my $tmpkey (keys %constellations){
	    if($oldtarget==$constellations{$tmpkey}){
	      $constellations{$tmpkey}=$constellations{${$nodenames}{$edge->getAttribute('source')}};
	    }
	  }
        }
      }else{
        #target does not exist, add it to source
        #change cluster number
        $constellations{${$nodenames}{$edge->getAttribute('target')}}=$constellations{${$nodenames}{$edge->getAttribute('source')}};
        #add accessions
        push @{$supernodes{$constellations{${$nodenames}{$edge->getAttribute('source')}}}}, @{${$nodehash}{${$nodenames}{$edge->getAttribute('target')}}}      
      }
    }elsif(exists $constellations{${$nodenames}{$edge->getAttribute('target')}}){
      #target exists, add source to target sc
      #change cluster number
      $constellations{${$nodenames}{$edge->getAttribute('source')}}=$constellations{${$nodenames}{$edge->getAttribute('target')}};
      #add accessions
      push @{$supernodes{$constellations{${$nodenames}{$edge->getAttribute('target')}}}}, @{${$nodehash}{${$nodenames}{$edge->getAttribute('source')}}}
    }else{
      #neither exists, add both to same sc, and add accessions to supernode
      $constellations{${$nodenames}{$edge->getAttribute('source')}}=$newnode;
      $constellations{${$nodenames}{$edge->getAttribute('target')}}=$newnode;
      push @{$supernodes{$newnode}}, @{${$nodehash}{${$nodenames}{$edge->getAttribute('source')}}};
      push @{$supernodes{$newnode}}, @{${$nodehash}{${$nodenames}{$edge->getAttribute('target')}}};
      #increment for next sc node
      $newnode++;
    }
  }
  return \%supernodes, \%constellations;
}

sub getClusterHubData {
#$clusterNodes=getClusterHubData(\%supernodes, $dbh, $n, $nomatch_fh, $noneighfile_fh);
  my %supernodes=%{shift @_};
  my $dbh=shift @_;
  my $n=shift @_;
  my $nomatch_fh=shift @_;
  my $noneighfile_fh=shift @_;
  my %withneighbors=();
  my %clusternodes=();
  my %numbermatch=();
  my $simplenumber=1;
#$clusterfraction=int(scalar(uniq @{$pfams{$key}{$sc}{'orig'}})/scalar(@{$withneighbors{$sc}})*1000)/1000
#$gnnwriter->emptyTag('att', 'name' => 'Co-occurrence', 'type' => 'real', 'value' =>  sprintf("%.2f",$clusterfraction));
  foreach my $clusterNode (sort {$a <=> $b} keys %supernodes){
    print "Supernode $clusterNode, ".scalar @{$supernodes{$clusterNode}}." original accessions, simplenumber $simplenumber\n";
    $numbermatch{$clusterNode}=$simplenumber;
    foreach my $accession (uniq @{$supernodes{$clusterNode}}){       
      my $pfamsearch=findneighbors $accession, $n, $dbh, $nomatch_fh, $noneighfile_fh;
      foreach my $pfamNumber (sort {$a <=> $b} keys %{${$pfamsearch}{'neigh'}}){;
        push @{$clusterNodes{$clusterNode}{$pfamNumber}{'orig'}}, @{${$pfamsearch}{'orig'}{$pfamNumber}};
        push @{$clusterNodes{$clusterNode}{$pfamNumber}{'dist'}}, @{${$pfamsearch}{'dist'}{$pfamNumber}};
        push @{$clusterNodes{$clusterNode}{$pfamNumber}{'stats'}}, @{${$pfamsearch}{'stats'}{$pfamNumber}};
        push @{$clusterNodes{$clusterNode}{$pfamNumber}{'neigh'}}, @{${$pfamsearch}{'neigh'}{$pfamNumber}};
        push @{$clusterNodes{$clusterNode}{$pfamNumber}{'neighlist'}}, @{${$pfamsearch}{'neighlist'}{$pfamNumber}};
        #push @{$withneighbors{$clusterNode}}, @{${$pfamsearch}{'withneighbors'}{$pfamNumber}}
      }
      foreach my $pfamNumber (sort {$a <=> $b} keys %{${$pfamsearch}{'withneighbors'}}){
        push @{$withneighbors{$clusterNode}}, @{${$pfamsearch}{'withneighbors'}{$pfamNumber}};
      }
    }
    $simplenumber++;
  }
  return \%numbermatch, \%clusterNodes, \%withneighbors;
}

sub writeClusterHubGnn{
  #writeClusterHubGnn($gnnwriter, \%clusterNodes, \%withneighbors, $incfrac, $cluster, \%numbermatch);
  my $gnnwriter=shift @_;
  my %clusterNodes=%{shift @_};
  my %withneighbors=%{shift @_};
  my $incfrac=shift @_;
  my %numbermatch=%{shift @_};
  my %supernodes=%{shift @_};
  $gnnwriter->startTag('graph', 'label' => "$title gnn", 'xmlns' => 'http://www.cs.rpi.edu/XGMML');
  foreach my $cluster (sort {$a <=> $b} keys %clusterNodes){
    print "building hub node $cluster, simplenumber ".$numbermatch{$cluster}."\n";
    my @pdbinfo=();
    foreach my $pfam (keys %{$clusterNodes{$cluster}}){
      $cooccurrence= sprintf("%.2f",int(scalar(uniq @{$clusterNodes{$cluster}{$pfam}{'orig'}})/scalar(@{$withneighbors{$cluster}})*100)/100);
      if($incfrac<=$cooccurrence){
        my $tmparray=writePfamSpoke($gnnwriter,$pfam, $dbh, $numbermatch{$cluster},\@{$withneighbors{$cluster}}, \%{$clusterNodes{$cluster}{$pfam}});
        push @pdbinfo, @{$tmparray};
        writePfamEdge($gnnwriter,$pfam,$numbermatch{$cluster});
      }
    }
 #   writeClusterHub($gnnwriter, $numbermatch{$cluster}, \%{$clusterNodes{$cluster}}, \@pdbinfo,\@{$withneighbors{$cluster}}, $incfrac, \@{$supernodes{$cluster}}, $colors{$numbermatch{$cluster}});
    writeClusterHub($gnnwriter, $numbermatch{$cluster}, \%{$clusterNodes{$cluster}}, \@pdbinfo,\@{$withneighbors{$cluster}}, $incfrac, \@{$supernodes{$cluster}}, $colors{$numbermatch{$cluster}});

  }
  $gnnwriter->endTag();
}

sub writeColorSsn {
  my $nodes=shift @_;
  my $edges=shift @_;
  my $title=shift @_;
  my $writer=shift @_;
  my $colors=shift @_;
  my $numbermatch=shift @_;
  my $constellations=shift @_;
  my $nodenames=shift @_;
  $writer->startTag('graph', 'label' => "$title colorized", 'xmlns' => 'http://www.cs.rpi.edu/XGMML');
  writeColorSsnNodes($nodes,$writer,$colors,$numbermatch,$constellations);
  writeColorSsnEdges($edges,$writer,$nodenames);
  $writer->endTag(); 
}

sub writeColorSsnNodes {
  my $nodes=shift @_;
  my $writer=shift @_;
  my $colors=shift @_;
  my $numbermatch=shift @_;
  my $constellations=shift @_;
  foreach my $node (@{$nodes}){
    unless(${$numbermatch}{${$constellations}{$node->getAttribute('label')}} eq ""){
      $writer->startTag('node', 'id' => $node->getAttribute('label'), 'label' => $node->getAttribute('label'));
      #find color and add attribute
      writeGnnField($writer,'node.fillColor', 'string', ${$colors}{${$numbermatch}{${$constellations}{$node->getAttribute('label')}}});
      writeGnnField($writer, 'Cluster Number', 'integer', ${$numbermatch}{${$constellations}{$node->getAttribute('label')}});
      foreach $attribute ($node->getChildnodes){
        if($attribute=~/^\s+$/){
          #print "\t badattribute: $attribute:\n";
          #the parser is returning newline xml fields, this removes it
          #code will break if we do not remove it.
        }else{
          if($attribute->getAttribute('type') eq 'list'){
	    $writer->startTag('att', 'type' => $attribute->getAttribute('type'), 'name' => $attribute->getAttribute('name'));
	    foreach $listelement ($attribute->getElementsByTagName('att')){
	      $writer->emptyTag('att', 'type' => $listelement->getAttribute('type'), 'name' => $listelement->getAttribute('name'), 'value' => $listelement->getAttribute('value'));
	    }
	    $writer->endTag;
          }elsif($attribute->getAttribute('name') eq 'interaction'){
	    #do nothing
	    #this tag causes problems and it is not needed, so we do not include it
          }else{
            if(defined $attribute->getAttribute('value')){
  	      $writer->emptyTag('att', 'type' => $attribute->getAttribute('type'), 'name' => $attribute->getAttribute('name'), 'value' => $attribute->getAttribute('value'));
	    }else{
	      $writer->emptyTag('att', 'type' => $attribute->getAttribute('type'), 'name' => $attribute->getAttribute('name'));
	    }
          }
        }
      }
      $writer->endTag(  );
    }
  }
}

sub writeColorSsnEdges {
  my $edges=shift @_;
  my $writer=shift @_;
  my $nodenames=shift @_;
  foreach $edge (@{$edges}){
    $writer->startTag('edge', 'id' => $edge->getAttribute('id'), 'label' => $edge->getAttribute('label'), 'source' => ${$nodenames}{$edge->getAttribute('source')}, 'target' => ${$nodenames}{$edge->getAttribute('target')});
    foreach $attribute ($edge->getElementsByTagName('att')){
      if($attribute->getAttribute('name') eq 'interaction' or $attribute->getAttribute('name')=~/rep-net/){
        #print "do nothing\n";
        #this tag causes problems and it is not needed, so we do not include it
      }else{
        $writer->emptyTag('att', 'name' => $attribute->getAttribute('name'), 'type' => $attribute->getAttribute('type'), 'value' =>$attribute->getAttribute('value'));
      }
    }
    $writer->endTag;
  }
}

sub writePfamHubGnn {
  my $writer=shift @_;
  my $clusterNodes=shift @_;
  my $withneighbors = shift @_;
  my $incfrac = shift @_;
  my $numbermatch = shift @_;
  my $supernodes = shift @_;
  my $dbh= shift @_;
  my $colors = shift @_;
  my @pfamHubs=uniq sort map {keys %{${$clusterNodes}{$_}}} keys %{$clusterNodes};
  $writer->startTag('graph', 'label' => "$title Pfam Gnn", 'xmlns' => 'http://www.cs.rpi.edu/XGMML');
  foreach my $pfam (@pfamHubs){
    (my $pfam_short, my $pfam_long)=getPfamNames($dbh, $pfam);
    my $spokecount=0;
    my @hubPdb=();
    my @clusters=();
    foreach my $cluster (keys %{$clusterNodes}){
      if(exists ${$clusterNodes}{$cluster}{$pfam}){
        if((int(scalar( uniq (@{${$clusterNodes}{$cluster}{$pfam}{'orig'}}))/scalar(@{${$withneighbors}{$cluster}})*100)/100)>=$incfrac){
          #print "co-occurrence $pfam $cluster is ".(int(scalar( uniq (@{${$clusterNodes}{$cluster}{$pfam}{'orig'}}))/scalar(@{${$withneighbors}{$cluster}})*100)/100)."\n";
	  push @clusters, $cluster;
          my $spokePdb=writeClusterSpoke($writer, $pfam, $cluster, $clusterNodes, $numbermatch, $dbh, $pfam_short, $pfam_long, ${$colors}{${$numbermatch}{$cluster}},$supernodes);
	  push @hubPdb, @{$spokePdb};
          writeClusterEdge($writer, $pfam, $cluster, $numbermatch);
          $spokecount++;
        }
      }
    }
    if($spokecount>0){
      print "Building hub $pfam\n";
      writePfamHub($writer,$pfam, $pfam_short, $pfam_long, \@hubPdb, \@clusters, $clusterNodes,$supernodes,$withneighbors, $numbermatch);
    }
  }
  $writer->endTag();
}

sub writeClusterSpoke{
  my $writer=shift @_;
  my $pfam=shift @_;
  my $cluster=shift @_;
  my $clusterNodes=shift @_;
  my $numbermatch=shift @_;
  my $dbh=shift @_;
  my $pfam_short=shift @_;
  my $pfam_long=shift @_;
  my $color=shift @_;
  my $supernodes=shift @_;
  (my $shape, my $pdbinfo)=getPdbInfo($dbh, \@{${$clusterNodes}{$cluster}{$pfam}{'neighlist'}});
  my $avgDist=sprintf("%.2f", int(sum(@{${$clusterNodes}{$cluster}{$pfam}{'stats'}})/scalar(@{${$clusterNodes}{$cluster}{$pfam}{'stats'}})*100)/100);
  my $medDist=sprintf("%.2f",int(median(@{${$clusterNodes}{$cluster}{$pfam}{'stats'}})*100)/100);
  my $coOcc=(int(scalar( uniq (@{${$clusterNodes}{$cluster}{$pfam}{'orig'}}))/scalar(@{${$withneighbors}{$cluster}})*100)/100);
  my $coOccRat=scalar( uniq (@{${$clusterNodes}{$cluster}{$pfam}{'orig'}}))."/".scalar(@{${$withneighbors}{$cluster}});
  $writer->startTag('node', 'id' => "$pfam:${$numbermatch}{$cluster}", 'label' => "${$numbermatch}{$cluster}");
  writeGnnField($writer, 'node.fillColor','string', $color);
  writeGnnField($writer, 'Co-occurrence','real',$coOcc);
  writeGnnField($writer, 'Co-occurrence Ratio','string',$coOccRat);
  writeGnnField($writer, 'Cluster Number', 'integer', ${$numbermatch}{$cluster});
  writeGnnField($writer, 'Total SSN Sequences', 'integer', scalar(@{${$supernodes}{$cluster}}));
  writeGnnField($writer, 'Queries with Pfam Neighbors', 'integer', scalar( uniq (@{${$clusterNodes}{$cluster}{$pfam}{'orig'}})));
  writeGnnField($writer, 'Queriable SSN Sequences', 'integer', scalar(@{${$withneighbors}{$cluster}}));
  writeGnnField($writer, 'node.size', 'string',$coOcc*100);
  writeGnnField($writer, 'node.shape', 'string', $shape);
  writeGnnField($writer, 'Average Distance', 'real', $avgDist);
  writeGnnField($writer, 'Median Distance', 'real', $medDist);
  writeGnnField($writer, 'Pfam Neighbors', 'integer', scalar(@{${$clusterNodes}{$cluster}{$pfam}{'neigh'}}));
  writeGnnListField($writer, 'Query Accessions', 'string', \@{${$clusterNodes}{$cluster}{$pfam}{'orig'}});
  #@tmparray=map "${$numbermatch}{$cluster}:$_", @{${$clusterNodes}{$cluster}{$pfam}{'dist'}};
  writeGnnListField($writer, 'Query-Neighbor Arrangement', 'string', \@{${$clusterNodes}{$cluster}{$pfam}{'dist'}});
  @tmparray=map "$_:".${$pdbinfo}{(split(":",$_))[1]}, @{${$clusterNodes}{$cluster}{$pfam}{'neigh'}};
  writeGnnListField($writer, 'Query-Neighbor Accessions', 'string', \@tmparray);
  $writer->endTag();
  @tmparray=map "${$numbermatch}{$cluster}:$_", @tmparray;
  @{${$clusterNodes}{$cluster}{$pfam}{'orig'}}=map "${$numbermatch}{$cluster}:$_",@{${$clusterNodes}{$cluster}{$pfam}{'orig'}};
  @{${$clusterNodes}{$cluster}{$pfam}{'neigh'}}=map "${$numbermatch}{$cluster}:$_",@{${$clusterNodes}{$cluster}{$pfam}{'neigh'}};
  @{${$clusterNodes}{$cluster}{$pfam}{'dist'}}=map "${$numbermatch}{$cluster}:$_",@{${$clusterNodes}{$cluster}{$pfam}{'dist'}};
  return \@tmparray;
}

sub writeClusterEdge{
  my $writer=shift @_;
  my $pfam=shift @_;
  my $cluster=shift @_;
  my $numbermatch=shift @_;
  $writer->startTag('edge', 'label' => "$pfam to $pfam:${$numbermatch}{$cluster}", 'source' => $pfam, 'target' => "$pfam:${$numbermatch}{$cluster}");
  $writer->endTag();
}

sub writePfamHub {
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
  writeGnnField($writer, 'Total SSN Sequences', 'integer', sum(map scalar(@{${$supernodes}{$_}}), @{$clusters}));
  writeGnnField($writer, 'Queriable SSN Sequences','integer', sum(map scalar(@{${$withneighbors}{$_}}), @{$clusters}));
  writeGnnField($writer, 'Queries with Pfam Neighbors', 'integer',sum(map scalar( uniq (@{${$clusterNodes}{$_}{$pfam}{'orig'}})), @{$clusters}));
  writeGnnField($writer, 'Pfam Neighbors', 'integer',sum(map scalar( uniq (@{${$clusterNodes}{$_}{$pfam}{'neigh'}})), @{$clusters}));
  writeGnnListField($writer, 'Query-Neighbor Accessions', 'string', $hubPdb);
  @tmparray=map @{${$clusterNodes}{$_}{$pfam}{'dist'}},  sort {$a <=> $b} @{$clusters};
  writeGnnListField($writer, 'Query-Neighbor Arrangement', 'string', \@tmparray);
  #@tmparray=map (int(sum(@{${$clusterNodes}{$_}{$pfam}{'stats'}})/scalar(@{${$clusterNodes}{$_}{$pfam}{'stats'}})*100)/100).":".(int(median(@{${$clusterNodes}{$_}{$pfam}{'stats'}})*100)/100), @{$clusters};
  @tmparray=map "${$numbermatch}{$_}:".sprintf("%.2f",int(sum(@{${$clusterNodes}{$_}{$pfam}{'stats'}})/scalar(@{${$clusterNodes}{$_}{$pfam}{'stats'}})*100)/100).":".sprintf("%.2f",int(median(@{${$clusterNodes}{$_}{$pfam}{'stats'}})*100)/100), sort {$a <=> $b} @{$clusters};
  writeGnnListField($writer, 'Hub Average and Median Distances', 'string', \@tmparray);
  @tmparray=map "${$numbermatch}{$_}:".sprintf("%.2f",int(scalar( uniq (@{${$clusterNodes}{$_}{$pfam}{'orig'}}))/scalar(@{${$withneighbors}{$_}})*100)/100).":".scalar( uniq (@{${$clusterNodes}{$_}{$pfam}{'orig'}}))."/".scalar(@{${$withneighbors}{$_}}), sort {$a <=> $b} @{$clusters};
  writeGnnListField($writer, 'Hub Co-occurrence and Ratio', 'string', \@tmparray);
  writeGnnField($writer, 'node.fillColor','string', '#EEEEEE');
  $writer->endTag;
}
