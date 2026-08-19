FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC

RUN apt-get update && apt-get install -y --no-install-recommends \
    r-base \
    r-cran-data.table \
    r-cran-r.utils \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY extract_gene_mapping.R /usr/local/bin/extract_gene_mapping.R
RUN chmod +x /usr/local/bin/extract_gene_mapping.R
COPY generate_expression_tables.R /usr/local/bin/generate_expression_tables.R
RUN chmod +x /usr/local/bin/generate_expression_tables.R

COPY check_samplemetadata.R /usr/local/bin/check_samplemetadata.R
RUN chmod +x /usr/local/bin/check_samplemetadata.R


COPY start.sh /home/start.sh
RUN chmod +x /home/start.sh

WORKDIR /home

CMD ["bash"]