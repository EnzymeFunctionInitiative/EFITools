#!/bin/bash

module load Perl

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
OPTS=""

if [[ -z "$1" || "$1" == "colorssn" ]]; then
    perl $DIR/color_uniprot_domain.pl $OPTS
fi

if [[ -z "$1" || "$1" == "accession" ]]; then
    perl $DIR/ssn_accession_domain_family.pl $OPTS
    perl $DIR/ssn_accession_domain_region.pl $OPTS
    perl $DIR/ssn_accession_family.pl $OPTS
    perl $DIR/ssn_accession.pl $OPTS
    perl $DIR/ssn_accession_uniref90.pl $OPTS
fi

if [[ "$1" == "analyze" ]]; then
    PARENT=ssn_family_uniprot_full perl $DIR/ssn_analyze_uniprot_full.pl $OPTS
    PARENT=ssn_family_uniprot_full perl $DIR/ssn_analyze_uniref50_full.pl $OPTS
fi

if [[ -z "$1" || "$1" == "blast" ]]; then
   perl $DIR/ssn_blast_uniprot_pfam_uniprot.pl $OPTS
   perl $DIR/ssn_blast_uniprot_pfam_uniref50.pl $OPTS
   perl $DIR/ssn_blast_uniprot.pl $OPTS
   perl $DIR/ssn_blast_uniref50_pfam_uniref50.pl $OPTS
   perl $DIR/ssn_blast_uniref50.pl $OPTS
fi

if [[ -z "$1" || "$1" == "family" ]]; then
    perl $DIR/ssn_family_uniprot_domain.pl $OPTS
    perl $DIR/ssn_family_uniprot_full.pl $OPTS
    perl $DIR/ssn_family_uniref50_domain.pl $OPTS
    perl $DIR/ssn_family_uniref50_full.pl $OPTS
fi

if [[ -z "$1" || "$1" == "fasta" ]]; then
    perl $DIR/ssn_fasta_headers_family_uniprot.pl $OPTS
    perl $DIR/ssn_fasta_headers_family_uniref90.pl $OPTS
    perl $DIR/ssn_fasta_headers.pl $OPTS
    perl $DIR/ssn_fasta_no_headers.pl $OPTS
fi

if [[ -z "$1" || "$1" == "identify" ]]; then
    perl $DIR/cgfp_identify.pl $OPTS
fi
if [[ -z "$1" || "$1" == "quantify" ]]; then
    PARENT=cgfp_identfy perl $DIR/cgfp_quantify.pl $OPTS
fi

