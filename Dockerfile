FROM alpine:latest

RUN apk add bash 
RUN apk add curl 
RUN apk add tar
RUN apk add build-base
RUN apk add sqlite
RUN apk add gd
RUN apk add R
RUN apk add libxml2
RUN apk add sed
RUN apk add grep
RUN apk add perl
RUN apk add perl-app-cpanminus
RUN apk add perl-dbi
RUN apk add perl-dbd-sqlite
RUN apk add perl-dbd-mysql
RUN apk add perl-capture-tiny
RUN apk add perl-log-any
RUN apk add perl-getopt-long
RUN apk add perl-list-moreutils
RUN apk add perl-xml-writer
RUN apk add perl-xml-libxml
RUN apk add perl-xml-parser
RUN apk add perl-file-slurp
RUN apk add perl-json
RUN apk add perl-scalar-list-utils
RUN apk add perl-config-inifiles
RUN apk add perl-gd
RUN apk add zlib-dev

RUN mkdir -p /app/deps/build

WORKDIR /app

COPY . /app/EFITools
COPY ../deps/*.sqlite /app/db/efi.sqlite

RUN curl -Ls https://ftp.ncbi.nlm.nih.gov/blast/executables/legacy.NOTSUPPORTED/2.2.26/blast-2.2.26-x64-linux.tar.gz | tar -xzO blast-2.2.26/bin/blastall > /app/deps/blastall
RUN curl -Ls https://ftp.ncbi.nlm.nih.gov/blast/executables/blast+/2.2.28/ncbi-blast-2.2.28+-x64-linux.tar.gz | tar -xzO ncbi-blast-2.2.28+/bin/blastp > /app/deps/blastp

RUN mkdir /app/deps/build/cd-hit
RUN curl -Ls https://github.com/weizhongli/cdhit/releases/download/V4.8.1/cd-hit-v4.8.1-2019-0228.tar.gz | tar -xzC /app/deps/build/cd-hit
RUN make -C /app/deps/build/cd-hit/cd-hit-v4.8.1-2019-0228/
RUN cp /app/deps/build/cd-hit/cd-hit-v4.8.1-2019-0228/cd-hit /app/deps

RUN curl -Ls http://www.drive5.com/downloads/usearch11.0.667_i86linux32.gz | gunzip -c > /app/deps/usearch

RUN curl -Ls https://github.com/bbuchfink/diamond/releases/download/v2.0.9/diamond-linux64.tar.gz | tar -xzO diamond > /app/deps/diamond

RUN curl -Ls http://www.drive5.com/muscle/downloads3.8.31/muscle3.8.31_i86linux64.tar.gz | tar -xzO muscle3.8.31_i86linux64 > /app/deps/muscle

RUN chmod +x /app/deps/*

# Get data
RUN mkdir -p /app/tmp
RUN mkdir -p /app/db
#RUN curl -Ls https://efi.igb.illinois.edu/databases/20200817sp/blast_diamond_db.zip > /app/tmp/blast.zip
#RUN unzip -d /app/db /app/tmp/blast.zip
#RUN curl -Ls https://efi.igb.illinois.edu/databases/20200817sp/efi_202008sp.sqlite.tar.gz > /app/tmp/db.tar.gz
#RUN unzip -d /app/db /app/tmp/db.zip
#RUN tar -xzfO /app/tmp/db.tar.gz > /app/db/efi.sqlite
#RUN rm -rf /app/tmp

