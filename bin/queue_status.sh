#!/bin/bash

/usr/bin/squeue -o "%25j %.2t %.15M %.6D %15R %.6m %.8u %.18i %9P" | /usr/bin/grep '\<efi\(mem\)\?\>' | sort -k1 | sed 's/^\([0-9]\+\)\([^0-9]\)/<b class="c">\1<\/b>\2/' > /private_stores/gerlt/jobs/temp/efi.queue
/usr/bin/squeue -o "%j	%t	%P" | grep '\<efi\|\(mem\)\>' | grep '^[0-9]' | sed 's/^\([0-9]\+\)_[^\t]\+\t\([^\t]\+\)\t.*$/\1-\2/' | sort | uniq | grep '\-R' | wc -l > /private_stores/gerlt/jobs/temp/efi.queue.running

