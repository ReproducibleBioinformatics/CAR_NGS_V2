FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC

RUN apt-get update && apt-get install -y --no-install-recommends \
    r-base \
    r-cran-data.table \
    r-cran-ggplot2 \
    r-bioc-deseq2 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY plot_pca.R /usr/local/bin/plot_pca.R
RUN chmod +x /usr/local/bin/plot_pca.R

COPY run_deseq2.R /usr/local/bin/run_deseq2.R
RUN chmod +x /usr/local/bin/run_deseq2.R

COPY start.sh /home/start.sh
RUN chmod +x /home/start.sh

WORKDIR /home

CMD ["bash"]