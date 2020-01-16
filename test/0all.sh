#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
OPTS=""

if [[ -z "$1" || "$1" == "colorssn" ]]; then
    echo "RUNNING color_uniprot_domain"
    perl $DIR/color_uniprot_domain.pl $OPTS
fi

if [[ -z "$1" || "$1" == "accession" ]]; then
    echo "RUNNING ssn_accession_domain_family"
    perl $DIR/ssn_accession_domain_family.pl $OPTS
    echo "RUNNING ssn_accession_domain_region"
    perl $DIR/ssn_accession_domain_region.pl $OPTS
    echo "RUNNING ssn_accession_family"
    perl $DIR/ssn_accession_family.pl $OPTS
    echo "RUNNING ssn_accession"
    perl $DIR/ssn_accession.pl $OPTS
    echo "RUNNING ssn_accession_uniref90"
    perl $DIR/ssn_accession_uniref90.pl $OPTS
fi

if [[ "$1" == "analyze" ]]; then
    echo "RUNNING analyze"
    PARENT=ssn_family_uniprot_full perl $DIR/ssn_analyze_uniprot_full.pl $OPTS
    PARENT=ssn_family_uniprot_full perl $DIR/ssn_analyze_uniref50_full.pl $OPTS
fi

if [[ -z "$1" || "$1" == "blast" ]]; then
   echo "RUNNING ssn_blast_uniprot_pfam_uniprot"
   perl $DIR/ssn_blast_uniprot_pfam_uniprot.pl $OPTS
   echo "RUNNING ssn_blast_uniprot_pfam_uniref50"
   perl $DIR/ssn_blast_uniprot_pfam_uniref50.pl $OPTS
   echo "RUNNING ssn_blast_uniprot"
   perl $DIR/ssn_blast_uniprot.pl $OPTS
   echo "RUNNING ssn_blast_uniref50_pfam_uniref50"
   perl $DIR/ssn_blast_uniref50_pfam_uniref50.pl $OPTS
   echo "RUNNING ssn_blast_uniref50"
   perl $DIR/ssn_blast_uniref50.pl $OPTS
fi

if [[ -z "$1" || "$1" == "family" ]]; then
    echo "RUNNING ssn_family_uniprot_domain"
    perl $DIR/ssn_family_uniprot_domain.pl $OPTS
    echo "RUNNING ssn_family_uniprot_full"
    perl $DIR/ssn_family_uniprot_full.pl $OPTS
    echo "RUNNING ssn_family_uniref50_domain"
    perl $DIR/ssn_family_uniref50_domain.pl $OPTS
    echo "RUNNING ssn_family_uniref50_full"
    perl $DIR/ssn_family_uniref50_full.pl $OPTS
fi

if [[ -z "$1" || "$1" == "fasta" ]]; then
    echo "RUNNING ssn_fasta_headers_family_uniprot"
    perl $DIR/ssn_fasta_headers_family_uniprot.pl $OPTS
    echo "RUNNING ssn_fasta_headers_family_uniref90"
    perl $DIR/ssn_fasta_headers_family_uniref90.pl $OPTS
    echo "RUNNING ssn_fasta_headers"
    perl $DIR/ssn_fasta_headers.pl $OPTS
    echo "RUNNING ssn_fasta_no_headers"
    perl $DIR/ssn_fasta_no_headers.pl $OPTS
fi

if [[ -z "$1" || "$1" == "gnt" ]]; then
    echo "RUNNING gnt_gnd"
    perl $DIR/gnt_gnd.pl $OPTS
    echo "RUNNING gnt_gnn"
    perl $DIR/gnt_gnn.pl $OPTS
fi

if [[ "$1" == "identify" ]]; then
    echo "RUNNING cgfp_identify"
    perl $DIR/cgfp_identify.pl $OPTS
fi
if [[ "$1" == "quantify" ]]; then
    echo "RUNNING cgfp_quantify"
    PARENT=cgfp_identfy perl $DIR/cgfp_quantify.pl $OPTS
fi

