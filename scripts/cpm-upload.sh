#!/usr/bin/env bash
# Envia ao Cloudinary um Reel final do CPM aprovado pela política editorial (politica/).
# Uso: ./scripts/cpm-upload.sh entrada/<arquivo>.mp4 [--verificar]
#   --verificar  executa todas as checagens locais e para antes de qualquer acesso à rede.
# Reprovação na política = exceção (exit 3), registrada em registro/excecoes.jsonl.
source "$(dirname "${BASH_SOURCE[0]}")/lib/cpm-comum.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/cpm-envio.sh"
cpm_upload politica "$@"
