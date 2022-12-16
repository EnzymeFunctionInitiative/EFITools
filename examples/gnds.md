
Refer to `common.md` for documentation on the common parameters shared by all job creation scripts
and the general file format.

# GND usage 

    submit_diagram.pl --job-setup=/path/to/setup_file.txt ...global_args...

(If run automatically from cron, the cron job that creates these jobs creates the output directory and
provides it to the script.  Otherwise you must specify it according to the `global_args` as documented
in `common.md`.

Output file is automatically `$job_id.sqlite`, and zip file `$job_id.sqlite.zip` will also be created.
These will be stored in the `$output_dir` global argument.


## Shared parameters

    nb-size=the number of neighbors on each side of the query sequence to return
    title=text that shows up in the GND viewer
    seq-db-type=uniprot, uniprot-nf, uniref{50,90}[-nf]
    ; If --seq-db-type is uniref{50,90][-nf], and if this entry is present, then assume input ID list
    ; is UniProt; otherwise assume input ID list are UniRef cluster IDs.
    reverse-uniref=1 

## Mode 1: file upload to view prior results

Uploaded file must either be a plain SQLite3 or a zipped SQLite3 file

    job-type=unzip
    upload-file=/path/to/uploaded_file
    ; shared parameters are ignored here

## Mode 2: BLAST

Input a sequence, run BLAST, and create a GND from that

    job-type=BLAST
    seq-file=path to file containing the sequence for BLAST
    evalue=the evalue to use for the BLAST
    max-seq=max number of seq to return from the BLAST


## Mode 3: ID file

Input a file containing a list of sequences and create a GND from that

    job-type=ID_LOOKUP
    upload-file=/path/to/uploaded_file


## Mode 4: FASTA (like mode 3, but gets IDs from the FASTA headers)

    job-type=ID_LOOKUP
    upload-file=/path/to/uploaded_file


## Mode 5: Taxonomy lookup (like mode 3, but gets IDs from the taxonomy JSON file)

    job-type=TAXONOMY
    upload-file=/path/to/uploaded_file
    tax-tree-id=the node ID to start descending at
    tax-id-type=uniprot, uniref50, uniref90


