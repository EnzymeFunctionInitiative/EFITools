
Refer to `common.md` for documentation on the common parameters shared by all job creation scripts
and the general file format.

# GNN usage 

    submit_gnn.pl --job-setup=/path/to/setup_file.txt ...global_args... \
        

Optional args:

    --extra-ram D|#
        if 'D', attempts to determine RAM based on file size; otherwise use the specified numeric value
        if not specified, defaults to value in config file

(If run automatically from cron, the cron job that creates these jobs creates the output directory and
provides it to the script.  Otherwise you must specify it according to the `global_args` as documented
in `common.md`.

Output files are:

