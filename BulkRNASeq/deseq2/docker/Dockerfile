FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC

RUN apt-get update && apt-get install -y --no-install-recommends \
    r-base \
    r-bioc-deseq2 \
    r-cran-data.table \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY core.R /usr/local/bin/core.R
RUN chmod +x /usr/local/bin/core.R

COPY check_samplemetadata.R /usr/local/bin/check_samplemetadata.R
RUN chmod +x /usr/local/bin/check_samplemetadata.R

COPY start.sh /home/start.sh
RUN chmod +x /home/start.sh

WORKDIR /home

CMD ["bash"]