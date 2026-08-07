#!/bin/bash

# ==============================================================================
# test.sh
# Avvio del modulo QC Report
# ==============================================================================

echo "==========================================="
echo " Docker4Seq - QC Report Test"
echo "==========================================="

# Verifica presenza di Docker
if ! command -v docker >/dev/null 2>&1; then
    echo "Errore: Docker non è installato o non è presente nel PATH."
    exit 1
fi

echo "Docker trovato."

# Esecuzione del wrapper Python
python3 qc_report.py \
    workdir \
    ../testdata/raw_data/ \
    results/ \
    ../testdata/raw_data/sampleMetaData.csv \
    "," \
    10 \
    false

exit $?