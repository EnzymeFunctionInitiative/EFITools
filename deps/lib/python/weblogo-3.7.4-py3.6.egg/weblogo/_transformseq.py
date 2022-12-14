#!/usr/bin/env python

#  Copyright (c) 2006, The Regents of the University of California, through
#  Lawrence Berkeley National Laboratory (subject to receipt of any required
#  approvals from the U.S. Dept. of Energy).  All rights reserved.

#  This software is distributed under the new BSD Open Source License.
#  <http://www.opensource.org/licenses/bsd-license.html>
#  Please see the LICENSE.txt file that should have been included
#  as part of this package.


""" A tool for converting multiple sequence alignments from
one format to another.
"""

import sys
from optparse import OptionGroup

from weblogo import seq_io
from weblogo.seq import SeqList, Seq, nucleic_alphabet
from weblogo.utils.deoptparse import DeOptionParser
from weblogo.transform import mask_low_complexity

__version__ = "1.0.0"
description = """ A tool for converting multiple sequence alignments from
one format to another. """


def main():
    # ------ Parse Command line ------
    parser = _build_option_parser()
    (opts, args) = parser.parse_args(sys.argv[1:])
    if args:
        parser.error("Unparsable arguments: %s " % args)

    seqs = opts.reader.read(opts.fin)

    if opts.trans_seg:
        seqs = SeqList([mask_low_complexity(s) for s in seqs])

    if opts.subsample is not None:
        from random import random
        frac = opts.subsample
        ss = []
        for s in seqs:
            if random() < frac:
                ss.append(s)
        seqs = SeqList(ss)

    if opts.reverse:
        seqs = SeqList([s.reverse() for s in seqs])

    if opts.complement:
        seqs = SeqList([Seq(s, alphabet=nucleic_alphabet) for s in seqs])
        seqs = SeqList([s.complement() for s in seqs])

    opts.writer.write(opts.fout, seqs)


def _build_option_parser():
    parser = DeOptionParser(usage="%prog [options]  < sequence_data.fa > sequence_logo.eps",
                            description=description,
                            version=__version__,
                            add_verbose_options=False
                            )

    io_grp = OptionGroup(parser, "Input/Output Options", )
    parser.add_option_group(io_grp)

    io_grp.add_option("-f", "--fin",
                      dest="fin",
                      action="store",
                      type="file_in",
                      default=sys.stdin,
                      help="Sequence input file (default: stdin)",
                      metavar="FILENAME")

    io_grp.add_option("", "--format-in",
                      dest="reader",
                      action="store", type="dict",
                      default=seq_io,
                      choices=seq_io.format_names(),
                      help="Multiple sequence alignment format: (%s)" %
                           ', '.join([f.names[0] for f in seq_io.formats]),
                      metavar="FORMAT")

    io_grp.add_option("-o", "--fout", dest="fout",
                      type="file_out",
                      default=sys.stdout,
                      help="Output file (default: stdout)",
                      metavar="FILENAME")

    trans_grp = OptionGroup(parser, "Transformations", )
    parser.add_option_group(trans_grp)

    trans_grp.add_option("", "--seg",
                         dest="trans_seg",
                         action="store_true",
                         default=False,
                         help="Mask low complexity regions in protein sequences.",
                         metavar="TRUE/FALSE")

    trans_grp.add_option("", "--subsample",
                         dest="subsample",
                         action="store",
                         type="float",
                         default=None,
                         help="Return a random subsample of the sequences.",
                         metavar="FRACTION")

    trans_grp.add_option("", "--reverse",
                         dest="reverse",
                         action="store_true",
                         default=False,
                         help="reverse sequences",
                         metavar="TRUE/FALSE")

    trans_grp.add_option("", "--complement",
                         dest="complement",
                         action="store_true",
                         default=False,
                         help="complement DNA sequences",
                         metavar="TRUE/FALSE")

    # Writers
    out_formats = []
    for f in seq_io.formats:
        if hasattr(f, "write"):
            out_formats.append(f)
    out_choices = {}
    for f in out_formats:
        out_choices[f.names[0]] = f
    out_names = [f.names[0] for f in out_formats]

    io_grp.add_option("-F", "--format-out",
                      dest="writer",
                      action="store", type="dict",
                      default=seq_io.fasta_io,
                      choices=out_choices,
                      help="Multiple sequence alignment output format: (%s) (Default: fasta)" %
                           ', '.join(out_names),
                      metavar="FORMAT")

    return parser
