
package EFI::GNN::Base;

use File::Basename;
use Cwd 'abs_path';
use lib abs_path(dirname(__FILE__) . "/../../");

use List::MoreUtils qw{apply uniq any};
use List::Util qw(sum);
use Array::Utils qw(:all);
use EFI::Annotations;


use Exporter 'import';
@EXPORT = qw(median writeGnnField writeGnnListField);

our $ClusterUniProtIDFilePattern = "cluster_UniProt_IDs_";


sub new {
    my ($class, %args) = @_;

    my $self = {};
    bless($self, $class);

    $self->{dbh} = $args{dbh};
    $self->{incfrac} = $args{incfrac};
    $self->{color_util} = $args{color_util};
#    $self->{colors} = $self->getColors();
#    $self->{num_colors} = scalar keys %{$self->{colors}};
#    $self->{pfam_color_counter} = 1;
#    $self->{pfam_colors} = {};
#    $self->{uniprot_id_dir} = ($args{uniprot_id_dir} and -d $args{uniprot_id_dir}) ? $args{uniprot_id_dir} : "";
#    $self->{uniref50_id_dir} = ($args{uniref50_id_dir} and -d $args{uniref50_id_dir}) ? $args{uniref50_id_dir} : "";
#    $self->{uniref90_id_dir} = ($args{uniref90_id_dir} and -d $args{uniref90_id_dir}) ? $args{uniref90_id_dir} : "";
#    $self->{cluster_fh} = {};
    $self->{color_only} = exists $args{color_only} ? $args{color_only} : 0;
    $self->{anno} = EFI::Annotations::get_annotation_data();

    return $self;
}


sub getNodesAndEdges{
    my $self = shift;
    my $reader = shift;

    my @nodes=();
    my @edges=();
    $parser = XML::LibXML->new();
    $reader->read();
    if($reader->nodeType==8){ #node type 8 is a comment
        print "XGMML made with ".$reader->value."\n";
        $reader->read; #we do not want to start reading a comment
    }
    my $graphname=$reader->getAttribute('label');
    $self->{title} = $graphname;
    my $firstnode=$reader->nextElement();
    my $tmpstring=$reader->readOuterXml;
    my $tmpnode=$parser->parse_string($tmpstring);
    my $node=$tmpnode->firstChild;
    
    if ($reader->name() eq "node"){
        push @nodes, $node;
    }

    my %degrees;
    while($reader->nextSiblingElement()){
        $tmpstring=$reader->readOuterXml;
        $tmpnode=$parser->parse_string($tmpstring);
        $node=$tmpnode->firstChild;
        if($reader->name() eq "node"){
            push @nodes, $node;
        }elsif($reader->name() eq "edge"){
            push @edges, $node;
            my $label = $node->getAttribute("label");
            my ($source, $target) = split /,/, $label;
            $degrees{$source} = 0 if not exists $degrees{$source};
            $degrees{$target} = 0 if not exists $degrees{$target};
            $degrees{$source}++;
            $degrees{$target}++;
        }else{
            warn "not a node or an edge\n $tmpstring\n";
        }
    }
    return ($graphname, \@nodes, \@edges, \%degrees);
}

sub getNodes{
    my $self = shift;
    my $nodes = shift;

    my %metanodeMap;
    my %nodenames; 
    my %nodeMap; # Maps metanodes to nodes
    my %swissprotDesc;
    my %clusterNumMap;

    my $efi = new EFI::Annotations;

    print "parse nodes for accessions\n";
    foreach $node (@{$nodes}){
        $nodehead=$node->getAttribute('label');
        #cytoscape exports replace the id with an integer instead of the accessions
        #%nodenames correlates this integer back to an accession
        #for efiest generated networks the key is the accession and it equals an accession, no harm, no foul
        $nodenames{$node->getAttribute('id')}=$nodehead;
        my @annotations=$node->findnodes('./*');
        push @{$metanodeMap{$nodehead}}, $nodehead;
        $nodeMap{$nodehead} = $node;
        foreach $annotation (@annotations){
            my $attrName = $annotation->getAttribute('name');
            if($efi->is_expandable_attr($attrName)){
                my @accessionlists=$annotation->findnodes('./*');
                foreach $accessionlist (@accessionlists){
                    #make sure all accessions within the node are included in the gnn network
                    my $attrAcc = $accessionlist->getAttribute('value');
                    print "Expanded $nodehead into $attrAcc\n" if $self->{debug};
                    push @{$metanodeMap{$nodehead}}, $attrAcc if $nodehead ne $attrAcc;
                }
            } elsif ($attrName =~ m/UniRef(\d+)/) {
                $self->{has_uniref} = "UniRef$1";
            } elsif ($attrName eq EFI::Annotations::FIELD_SWISSPROT_DESC) {
                my @childList = $annotation->findnodes('./*');
                foreach my $child (@childList) {
                    my $val = $child->getAttribute('value');
                    push(@{$swissprotDesc{$nodehead}}, $val);
                }
            } elsif ($attrName eq "Cluster Number" or $attrName eq "Singleton Number") {
                my $clusterNum = $annotation->getAttribute("value");
                $clusterNumMap{$nodehead} = $clusterNum;
            }
        }
    }

    return \%metanodeMap, \%nodenames, \%nodeMap, \%swissprotDesc, \%clusterNumMap;
}

sub getClusters{
    my $self = shift;
    my $metanodeMap = shift;
    my $nodenames = shift;
    my $edges = shift;
    my $nodemap = shift; # Deprecated, don't use
    my $includeSingletons = shift;

    my %constellations=();
    my %supernodes=();
    my %singletons;
    my $newnode=1;

    foreach $edge (@{$edges}){
        my $edgeSource = $edge->getAttribute('source');
        my $edgeTarget = $edge->getAttribute('target');
        my $nodeSource = $nodenames->{$edgeSource};
        my $nodeTarget = $nodenames->{$edgeTarget};
#        print "$nodeSource -> $nodeTarget\n";

        #if source exists, add target to source sc
        if(exists $constellations{$nodeSource}){
#            print "E1";
            #if target also already existed, add target data to source 
            if(exists $constellations{$nodeTarget}){
#                print "E2";
                #check if source and target are in the same constellation, if they are, do nothing, if not,
                # add change target sc to source and add target accessions to source accessions.
                # this is to handle the case that we've built two sub-constellations that are actually part
                # of a bigger constellation.
#            print "\t$constellations{$nodeSource}=$constellations{$nodeTarget}";
                unless($constellations{$nodeTarget} eq $constellations{$nodeSource}){
                    #add accessions from target supernode to source supernode
                    push @{$supernodes{$constellations{$nodeSource}}}, @{$supernodes{$constellations{$nodeTarget}}};
                    #delete target supernode
                    delete $supernodes{$constellations{$nodeTarget}};
                    #change the constellation number for all 
                    $oldtarget=$constellations{$nodeTarget};
                    foreach my $tmpkey (keys %constellations){
                        if($oldtarget==$constellations{$tmpkey}){
                            $constellations{$tmpkey}=$constellations{$nodeSource};
                        }
                    }
                }
            }else{
#                print "N2";
                #target does not exist, add it to source
                #change cluster number
                $constellations{$nodeTarget}=$constellations{$nodeSource};
#            print "\t$constellations{$nodeSource}=$constellations{$nodeTarget}";
                #add accessions
                push @{$supernodes{$constellations{$nodeSource}}}, @{$metanodeMap->{$nodeTarget}};
            }
        }elsif(exists $constellations{$nodeTarget}){
#            print "N1E2";
            #target exists, add source to target sc
            #change cluster number
            $constellations{$nodeSource}=$constellations{$nodeTarget};
#            print "\t$constellations{$nodeSource}=$constellations{$nodeTarget}";
#            print "\t" . join(",", @{$metanodeMap->{$nodeSource}});
            #add accessions
            push @{$supernodes{$constellations{$nodeTarget}}}, @{$metanodeMap->{$nodeSource}};
        }else{
#            print "N1N2";
            #neither exists, add both to same sc, and add accessions to supernode
            $constellations{$nodeSource}=$newnode;
            $constellations{$nodeTarget}=$newnode;
#            print "\t$constellations{$nodeSource}=$constellations{$nodeTarget}";
            push @{$supernodes{$newnode}}, @{$metanodeMap->{$nodeSource}};
            push @{$supernodes{$newnode}}, @{$metanodeMap->{$nodeTarget}};
            #increment for next sc node
            $newnode++;
        }
#        print "\n";
    }

    if ($includeSingletons) {
        # Look at each node in the network.  If we haven't processed it above (i.e. it doesn't have any edges attached)
        # then we add a new supernode and add any represented nodes (if it is a repnode).
        foreach my $nodeId (sort keys %$nodenames) {
            my $nodeLabel = $nodenames->{$nodeId};
            if (not exists $constellations{$nodeLabel}) {
                print "Adding singleton $nodeLabel from $nodeId\n" if $self->{debug};
                $supernodes{$newnode} = $metanodeMap->{$nodeLabel}; # metanodeMap contains an array of nodes, since it may be a repnode
                $singletons{$newnode} = $nodeLabel;
                $constellations{$nodeLabel} = $newnode;
                $newnode++;
            }
        }
    }
#    use Data::Dumper;
#    foreach my $id (sort {$a<=>$b} keys %supernodes) {
#        print Dumper({$id => $supernodes{$id}});
#    }
#    foreach my $id (sort keys %constellations) {
#        print "$id=$constellations{$id}\n";
#    }
##    print Dumper(\%supernodes);
#    die;

    return \%supernodes, \%constellations, \%singletons;
}

sub numberClusters {
    my $self = shift;
    my $supernodes = shift;
    my $useExistingNumber = shift;
    my $clusterNumbers = shift;

    my %numbermatch;
    my $simpleNumber = 1;
    my @numberOrder;

    foreach my $clusterNode (sort { my $bs = scalar uniq @{$supernodes->{$b}};
                                    my $as = scalar uniq @{$supernodes->{$a}};
                                    my $c = $bs <=> $as;
                                    $c = $a <=> $b if not $c; # handle equals case
                                    $c } keys %$supernodes){
        my $clusterSize = scalar @{$supernodes->{$clusterNode}};
        my $existingPhrase = "";
        my $clusterNum = $simpleNumber;
        if ($useExistingNumber) {
            my @ids = @{$supernodes->{$clusterNode}};
            if (scalar @ids) {
                $clusterNum = $clusterNumbers->{$ids[0]};
                $existingPhrase = "(keeping existing cluster number)";
            }
        }

        print "Supernode $clusterNode, $clusterSize original accessions, simplenumber $simpleNumber $existingPhrase\n";

        $numbermatch{$clusterNode} = $simpleNumber;
        push @numberOrder, $clusterNode;
        $simpleNumber++;
    }

    return \%numbermatch, \@numberOrder;
}

sub hasExistingNumber {
    my $self = shift;
    my $clusterNum = shift;

    return scalar keys %$clusterNum;
}

sub writeColorSsn {
    my $self = shift;
    my $nodes = shift;
    my $edges = shift;
    my $writer = shift;
    my $numbermatch = shift;
    my $constellations = shift;
    my $nodenames = shift;
    my $supernodes = shift;
    my $gnnData = shift;
    my $metanodeMap = shift;
    my $accessionData = shift;

    $writer->startTag('graph', 'label' => $self->{title} . " colorized", 'xmlns' => 'http://www.cs.rpi.edu/XGMML');
    $self->writeColorSsnNodes($nodes, $writer, $numbermatch, $constellations, $supernodes, $gnnData, $metanodeMap, $accessionData);
    $self->writeColorSsnEdges($edges, $writer, $nodenames);
    $writer->endTag(); 
}

sub saveGnnAttributes {
    my $self = shift;
    my $writer = shift;
    my $gnnData = shift;
    my $node = shift;
}

sub writeColorSsnNodes {
    my $self = shift;
    my $nodes = shift;
    my $writer = shift;
    my $numbermatch = shift;
    my $constellations = shift;
    my $supernodes = shift;
    my $gnnData = shift;
    my $metanodeMap = shift;
    my $accessionData = shift;

    my %nodeCount;

    my $numField = "Cluster Number";
    my $singletonField = "Singleton Number";
    my $colorField = "node.fillColor";
    my $countField = "Cluster Sequence Count";
    my $nbFamField = "Neighbor Families";
    my $badNum = 999999;
    my $singleNum = 0;

    my %skipFields = ($numField => 1, $colorField => 1, $countField => 1, $singletonField => 1, $nbFamField => 1);
    $skipFields{"Present in ENA Database?"} = 1;
    $skipFields{"Genome Neighbors in ENA Database?"} = 1;
    $skipFields{"ENA Database Genome ID"} = 1;

    foreach my $node (@{$nodes}){
        my $nodeId = $node->getAttribute('label');
        my $clusterId = $constellations->{$nodeId};
        my $clusterNum = $numbermatch->{$clusterId};

        # In a previous step, we included singletons (historically they were excluded).
        unless($clusterNum eq ""){
            $nodeCount{$clusterNum} = scalar uniq @{ $supernodes->{$clusterId} } if not exists $nodeCount{$clusterNum};

            # This should be done in cluster_gnn.pl
            #$self->saveNodeToClusterMap($clusterId, $numbermatch, $supernodes, $metanodeMap) if $nodeCount{$clusterNum} > 1;

            $writer->startTag('node', 'id' => $nodeId, 'label' => $nodeId);

            # find color and add attribute
            my $color = "";
            $color = $self->getColor($clusterNum) if $nodeCount{$clusterNum} > 1;
            #$color = $self->{colors}->{$clusterNum} if $nodeCount{$clusterNum} > 1;
            my $isSingleton = $nodeCount{$clusterNum} < 2;
            my $clusterNumAttr = $clusterNum;
            my $fieldName = $numField;
            if ($isSingleton) {
                $singleNum++;
                $clusterNumAttr = $singleNum;
                $fieldName = $singletonField;
            }

            my $savedAttrs = 0;

            foreach $attribute ($node->getChildnodes){
                if($attribute=~/^\s+$/){
                    #print "\t badattribute: $attribute:\n";
                    #the parser is returning newline xml fields, this removes it
                    #code will break if we do not remove it.
                }else{
                    my $attrType = $attribute->getAttribute('type');
                    my $attrName = $attribute->getAttribute('name');
                    if ($attrName eq "Organism") { #TODO: need to make this a shared constant
                        writeGnnField($writer, $fieldName, 'integer', $clusterNumAttr);
                        writeGnnField($writer, $countField, 'integer', $nodeCount{$clusterNum});
                        writeGnnField($writer, $colorField, 'string', $color);
                        if (not $self->{color_only}) {
                            $self->saveGnnAttributes($writer, $gnnData, $node);
                        }
                        $savedAttrs = 1;
                    }

                    if (not exists $skipFields{$attrName}) {
                        if ($attrType eq 'list') {
                            $writer->startTag('att', 'type' => $attrType, 'name' => $attrName);
                            foreach $listelement ($attribute->getElementsByTagName('att')){
                                $writer->emptyTag('att', 'type' => $listelement->getAttribute('type'),
                                                  'name' => $listelement->getAttribute('name'),
                                                  'value' => $listelement->getAttribute('value'));
                            }
                            $writer->endTag;
                        } elsif ($attrName eq 'interaction') {
                            #do nothing
                            #this tag causes problems and it is not needed, so we do not include it
                        } else {
                            if (defined $attribute->getAttribute('value')) {
                                $writer->emptyTag('att', 'type' => $attrType, 'name' => $attrName,
                                                  'value' => $attribute->getAttribute('value'));
                            } else {
                                $writer->emptyTag('att', 'type' => $attrType, 'name' => $attrName);
                            }
                        }
                        #} else {
                        #} elprint "Skipping $attrName for $nodeId because we're rewriting it\n";
                    }
                }
            }

            if (not $savedAttrs) {
                writeGnnField($writer, $fieldName, 'integer', $clusterNumAttr);
                writeGnnField($writer, $countField, 'integer', $nodeCount{$clusterNum});
                writeGnnField($writer, $colorField, 'string', $color);
                if (not $self->{color_only}) {
                    $self->saveGnnAttributes($writer, $gnnData, $node);
                }
            }

            $writer->endTag(  );
        } else {
            print "Node $nodeId was not found in any of the clusters we built today\n";
        }
    }
}

sub writeColorSsnEdges {
    my $self = shift;
    my $edges = shift;
    my $writer = shift;
    my $nodenames = shift;

    foreach $edge (@{$edges}){
        $writer->startTag('edge', 'id' => $edge->getAttribute('id'), 'label' => $edge->getAttribute('label'), 'source' => $nodenames->{$edge->getAttribute('source')}, 'target' => $nodenames->{$edge->getAttribute('target')});
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


#sub saveNodeToClusterMap {
#    my $self = shift;
#    my $clusterId = shift;
#    my $numbermatch = shift;
#    my $supernodes = shift;
#    my $metanodeMap = shift;
#
#    return if not $self->{id_dir} or not -d $self->{id_dir} or exists $self->{cluster_map_processed}->{$clusterId};
#
#    $self->{cluster_map_processed}->{$clusterId} = 1;
#
#    my $clusterNum = $numbermatch->{$clusterId};
#    $clusterNum = "none" if not $clusterNum;
#
#    my $openMode = exists $self->{cluster_fh}->{$clusterNum} ? ">>" : ">";
#
#    open($self->{cluster_fh}->{$clusterNum}, $openMode, $self->{id_dir} . "/cluster_UniProt_IDs_$clusterNum.txt");
#    foreach my $nodeId (uniq @{ $supernodes->{$clusterId} }) {
#        $self->{cluster_fh}->{$clusterNum}->print("$nodeId\n");
#    }
#    $self->{cluster_fh}->{$clusterNum}->close();
#    
#    if (exists $self->{has_uniref} and $self->{has_uniref}) {
#        open($self->{cluster_fh_ur}->{$clusterNum}, $openMode, $self->{id_dir} . "/cluster_" . $self->{has_uniref} . "_IDs_$clusterNum.txt");
#        foreach my $nodeId (uniq @{ $supernodes->{$clusterId} }) {
#            if (exists $metanodeMap->{$nodeId}) { # Only print metanodes
#                $self->{cluster_fh_ur}->{$clusterNum}->print("$nodeId\n");
#            }
#        }
#        $self->{cluster_fh_ur}->{$clusterNum}->close();
#    }
#}


sub writeIdMapping {
    my $self = shift;
    my $idMapPath = shift;
    my $numbermatch = shift;
    my $constellations = shift;
    my $supernodes = shift;

    open IDMAP, ">$idMapPath";

    print IDMAP "UniProt ID\tCluster Number\tCluster Color\n";
    my @data;
    foreach my $clusterId (sort keys %$supernodes) {
        my $clusterNum = $numbermatch->{$clusterId};
        next if scalar @{ $supernodes->{$clusterId} } < 2;

        foreach my $nodeId (uniq @{ $supernodes->{$clusterId} }) {
            my $color = $self->getColor($clusterNum);
            #push @data, [$nodeId, $clusterNum, $self->{colors}->{$clusterNum}];
            push @data, [$nodeId, $clusterNum, $color];
        }
    }

    foreach my $row (sort idmapsort @data) {
        print IDMAP join("\t", @$row), "\n";
    }

    close IDMAP;
}


#sub writeSingletons {
#    my $self = shift;
#    my $filePath = shift;
#    my $supernodes = shift;
#
#    open SINGLE, ">$filePath";
#
#    print SINGLE "UniProt ID\n";
#    foreach my $clusterId (sort keys %$supernodes) {
#        if (scalar @{ $supernodes->{$clusterId} } == 1) {
#            print SINGLE $supernodes->{$clusterId}->[0], "\n";
#        }
#    }
#
#    close SINGLE;
#}


sub idmapsort {
    my $comp = $a->[1] <=> $b->[1];
    if ($comp == 0) {
        return $a->[0] cmp $b->[0];
    } else {
        return $comp;
    }
}


#sub closeClusterMapFiles {
#    my $self = shift;
#
#    return if not $self->{id_dir} or not -d $self->{id_dir};
#
#    foreach my $key (keys %{ $self->{cluster_fh} }) {
#        close($self->{cluster_fh}->{$key});
#    }
#
#    foreach my $key (keys %{ $self->{no_pfam_fh} }) {
#        close($self->{no_pfam_fh}->{$key});
#    }
#}


#sub getColors {
#    my $self = shift;
#
#    my %colors=();
#    my $sth=$self->{dbh}->prepare("select * from colors;");
#    $sth->execute;
#    while(my $row=$sth->fetchrow_hashref){
#        $colors{$row->{cluster}}=$row->{color};
#    }
#    return \%colors;
#}
#
#
#sub getColorForPfam {
#    my $self = shift;
#    my $pfam = shift;
#
#    if (not exists $self->{pfam_colors}->{$pfam}) {
#        if ($self->{pfam_color_counter} > $self->{num_colors}) {
#            $self->{pfam_color_counter} = 1;
#        }
#        $self->{pfam_colors}->{$pfam} = $self->{colors}->{$self->{pfam_color_counter}};
#        $self->{pfam_color_counter}++;
#    }
#
#    return $self->{pfam_colors}->{$pfam};
#}


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
    my $writer = shift;
    my $name = shift;
    my $type = shift;
    my $value = shift;

    unless($type eq 'string' or $type eq 'integer' or $type eq 'real'){
        die "Invalid GNN type $type\n";
    }

    $writer->emptyTag('att', 'name' => $name, 'type' => $type, 'value' => $value);
}

sub writeGnnListField {
    my $writer = shift;
    my $name = shift;
    my $type = shift;
    my $valuesIn = shift;
    my $toSortOrNot = shift;

    unless($type eq 'string' or $type eq 'integer' or $type eq 'real'){
        die "Invalid GNN type $type\n";
    }
    $writer->startTag('att', 'type' => 'list', 'name' => $name);
    
    my @values;
    if (defined $toSortOrNot and $toSortOrNot) {
        @values = sort @$valuesIn;
    } else {
        @values = @$valuesIn;
    }

    foreach my $element (@values){
        $writer->emptyTag('att', 'type' => $type, 'name' => $name, 'value' => $element);
    }
    $writer->endTag;
}

sub addFileActions {
    my $B = shift; # This is an EFI::SchedulerApi::Builder object
    my $info = shift;

    my $fastaTool = "$info->{fasta_tool_path} -node-dir $info->{uniprot_node_data_path} -out-dir $info->{fasta_data_path} -config $info->{config_file}";
    $fastaTool .= " -all $info->{all_fasta_file}" if $info->{all_fasta_file};
    $fastaTool .= " -singletons $info->{singletons_file}" if $info->{singletons_file};
    $fastaTool .= " -input-sequences $info->{input_seqs_file}" if $info->{input_seqs_file};
    $B->addAction($fastaTool);
    if (exists $info->{cat_tool_path}) {
        $B->addAction("$info->{cat_tool_path} -input-file-pattern \"$info->{uniprot_node_data_path}/cluster_UniProt_IDs*\" -output-file $info->{uniprot_node_data_path}/cluster_All_UniProt_IDs.txt.unsorted");
        $B->addAction("$info->{cat_tool_path} -input-file-pattern \"$info->{uniref50_node_data_path}/cluster_UniRef50_IDs*\" -output-file $info->{uniref50_node_data_path}/cluster_All_UniRef50_IDs.txt.unsorted");
        $B->addAction("$info->{cat_tool_path} -input-file-pattern \"$info->{uniref90_node_data_path}/cluster_UniRef90_IDs*\" -output-file $info->{uniref90_node_data_path}/cluster_All_UniRef90_IDs.txt.unsorted");
    } else {
        $B->addAction("cat $info->{uniprot_node_data_path}/cluster_UniProt_IDs* > $info->{uniprot_node_data_path}/cluster_All_UniProt_IDs.txt.unsorted");
    }
    $B->addAction("sort $info->{uniprot_node_data_path}/cluster_All_UniProt_IDs.txt.unsorted > $info->{uniprot_node_data_path}/cluster_All_UniProt_IDs.txt");
    $B->addAction("rm $info->{uniprot_node_data_path}/cluster_All_UniProt_IDs.txt.unsorted");
    $B->addAction("if [[ -f $info->{uniref50_node_data_path}/cluster_All_UniRef50_IDs.txt.unsorted ]]; then");
    $B->addAction("    sort $info->{uniref50_node_data_path}/cluster_All_UniRef50_IDs.txt.unsorted > $info->{uniref50_node_data_path}/cluster_All_UniRef50_IDs.txt");
    $B->addAction("    rm $info->{uniref50_node_data_path}/cluster_All_UniRef50_IDs.txt.unsorted");
    $B->addAction("fi");
    $B->addAction("if [[ -f $info->{uniref90_node_data_path}/cluster_All_UniRef90_IDs.txt.unsorted ]]; then");
    $B->addAction("    sort $info->{uniref90_node_data_path}/cluster_All_UniRef90_IDs.txt.unsorted > $info->{uniref90_node_data_path}/cluster_All_UniRef90_IDs.txt");
    $B->addAction("    rm $info->{uniref90_node_data_path}/cluster_All_UniRef90_IDs.txt.unsorted");
    $B->addAction("fi");

    $B->addAction("zip -jq $info->{ssn_out_zip} $info->{ssn_out}") if $info->{ssn_out} and $info->{ssn_out_zip};
    $B->addAction("zip -jq -r $info->{uniprot_node_zip} $info->{uniprot_node_data_path}") if $info->{uniprot_node_zip} and $info->{uniprot_node_data_path};
    $B->addAction("zip -jq -r $info->{uniref50_node_zip} $info->{uniref50_node_data_path}") if $info->{uniref50_node_zip} and $info->{uniref50_node_data_path};
    $B->addAction("zip -jq -r $info->{uniref90_node_zip} $info->{uniref90_node_data_path}") if $info->{uniref90_node_zip} and $info->{uniref90_node_data_path};
    $B->addAction("zip -jq -r $info->{fasta_zip} $info->{fasta_data_path}") if $info->{fasta_data_path} and $info->{fasta_zip};
    $B->addAction("zip -jq $info->{gnn_zip} $info->{gnn}") if $info->{gnn} and $info->{gnn_zip};
    $B->addAction("zip -jq $info->{pfamhubfile_zip} $info->{pfamhubfile}") if $info->{pfamhubfile_zip} and $info->{pfamhubfile};
    $B->addAction("zip -jq -r $info->{pfam_zip} $info->{pfam_dir}") if $info->{pfam_zip} and $info->{pfam_dir};
    $B->addAction("zip -jq -r $info->{all_pfam_zip} $info->{all_pfam_dir}") if $info->{all_pfam_zip} and $info->{all_pfam_dir};
    $B->addAction("zip -jq -r $info->{split_pfam_zip} $info->{split_pfam_dir}") if $info->{split_pfam_zip} and $info->{split_pfam_dir};
    $B->addAction("zip -jq -r $info->{all_split_pfam_zip} $info->{all_split_pfam_dir}") if $info->{all_split_pfam_zip} and $info->{all_split_pfam_dir};
    $B->addAction("zip -jq -r $info->{none_zip} $info->{none_dir}") if $info->{none_zip} and $info->{none_dir};
    $B->addAction("zip -jq $info->{arrow_zip} $info->{arrow_file}") if $info->{arrow_zip} and $info->{arrow_file};
}

sub getColor {
    my $self = shift;
    my $clusterNum = shift;

    return $self->{color_util}->getColorForCluster($clusterNum);
}

sub getSequenceSource {
    my $self = shift;

    if (exists $self->{has_uniref}) {
        return $self->{has_uniref};
    } else {
        return "UniProt";
    }
}


1;

