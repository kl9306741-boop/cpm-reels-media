#!/usr/bin/env bash
# Envio de EXCEÇÃO aprovada por humano: dispensa nome e ficha editorial, mantém checagem
# técnica, cópia limpa, integridade e cota. NÃO tem permissão automática: cada execução
# passa pelo cartão de aprovação.
# Uso: ./scripts/cpm-upload-excecao.sh entrada/<arquivo>.mp4 [--verificar]
source "$(dirname "${BASH_SOURCE[0]}")/lib/cpm-comum.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/cpm-envio.sh"
cpm_upload excecao "$@"
