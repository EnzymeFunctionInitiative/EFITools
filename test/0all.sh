#!/bin/bash

module load Perl

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

perl $DIR/color_uniprot_domain.pl
perl $DIR/ssn_accession_domain_family.pl
perl $DIR/ssn_accession_domain_region.pl
perl $DIR/ssn_accession_family.pl
perl $DIR/ssn_accession.pl
perl $DIR/ssn_accession_uniref90.pl
perl $DIR/ssn_analyze_uniprot_full.pl
perl $DIR/ssn_analyze_uniref50_full.pl
perl $DIR/ssn_blast_uniprot_pfam_uniprot.pl
perl $DIR/ssn_blast_uniprot_pfam_uniref50.pl
perl $DIR/ssn_blast_uniprot.pl
perl $DIR/ssn_blast_uniref50_pfam_uniref50.pl
perl $DIR/ssn_blast_uniref50.pl
perl $DIR/ssn_family_uniprot_domain.pl
perl $DIR/ssn_family_uniprot_full_hdrs.pl
perl $DIR/ssn_family_uniprot_full.pl
perl $DIR/ssn_family_uniref50_domain.pl
perl $DIR/ssn_family_uniref50_full.pl
perl $DIR/ssn_fasta_headers_family_uniprot.pl
perl $DIR/ssn_fasta_headers_family_uniref90.pl
perl $DIR/ssn_fasta_headers.pl
perl $DIR/ssn_fasta_no_headers.pl

