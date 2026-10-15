#!/usr/bin/env bash
# Relatório somente leitura: consumo do Cloudinary Free e vídeos ainda pendentes de exclusão.
# Uso: ./scripts/cpm-cota.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/cpm-comum.sh"
[ $# -eq 0 ] || erro "uso: scripts/cpm-cota.sh (sem argumentos)"
verificar_cota 0 0
