#!/usr/bin/env bash
# Exclui do Cloudinary um Reel que o Metricool já copiou para o próprio armazenamento.
# Antes de excluir, baixa a cópia do Metricool (host autorizado na política) e confere que é
# um vídeo válido com a mesma duração do enviado.
# Uso: ./scripts/cpm-delete.sh <public_id> <url_da_copia_no_metricool>
source "$(dirname "${BASH_SOURCE[0]}")/lib/cpm-comum.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/cpm-exclusao.sh"
cpm_excluir "$@"
