# Envio de um Reel ao Cloudinary. Usado por cpm-upload.sh (modo politica) e
# cpm-upload-excecao.sh (modo excecao). Não executar diretamente.

# cpm_upload <politica|excecao> entrada/<arquivo>.mp4 [--verificar]
cpm_upload() {
  local modo="$1"; shift
  [ $# -ge 1 ] && [ $# -le 2 ] || erro "uso: scripts/cpm-upload.sh entrada/<arquivo>.mp4 [--verificar]"
  local rel="$1" verificar=0
  if [ $# -eq 2 ]; then
    [ "$2" = "--verificar" ] || erro "argumento desconhecido: $2"
    verificar=1
  fi

  # 1. Origem: somente arquivo regular dentro de entrada/
  [[ "$rel" =~ ^entrada/[A-Za-z0-9_.-]+\.mp4$ ]] || erro "o arquivo deve estar em entrada/ e terminar em .mp4"
  local f="$CPM_REPO/$rel"
  [ -f "$f" ] && [ ! -L "$f" ] || erro "arquivo inexistente ou link simbólico: $rel"
  [ "$(realpath -e "$f")" = "$f" ] || erro "caminho fora de entrada/"
  CPM_ARQUIVO=$(basename "$f")
  local tam; tam=$(stat -c %s "$f")
  [ "$tam" -le "$(pol tecnica.tamanho_max_bytes)" ] || excecao "arquivo de $tam bytes acima do limite"

  # 2. Política editorial (dispensada apenas no modo exceção, aprovado por humano)
  if [ "$modo" = politica ]; then
    [[ "$CPM_ARQUIVO" =~ $(pol editorial.padrao_nome) ]] || excecao "nome fora do padrão da série"
    validar_ficha "$f"
  fi

  # 3. Checagem técnica e cópia limpa: só 1 vídeo + até 1 áudio, sem metadados nem SEI
  validar_video "$f"
  local limpo="$CPM_TMP/$CPM_ARQUIVO"
  ffmpeg -v error -nostdin -i "$f" -map 0:v:0 -map '0:a:0?' -c copy \
    -bsf:v filter_units=remove_types=6 -map_metadata -1 -map_chapters -1 \
    -fflags +bitexact -flags:v +bitexact -flags:a +bitexact -movflags +faststart \
    -f mp4 "$limpo" || erro "falha ao gerar a cópia limpa"
  validar_video "$limpo"
  local sha bytes
  sha=$(sha256sum "$limpo" | cut -d' ' -f1)
  bytes=$(stat -c %s "$limpo")
  if ja_enviado "$sha"; then erro "este vídeo (sha256 $sha) já foi enviado e não foi excluído; não reenviar"; fi
  echo "OK local: $CPM_ARQUIVO | cópia limpa $bytes bytes | sha256 $sha | modo $modo"
  if [ "$verificar" -eq 1 ]; then echo "Modo --verificar: nenhum acesso à rede, nada enviado."; return 0; fi

  # 4. Cota (falha fechada)
  verificar_cota "$bytes" 1

  # 5. Envio único — sem nova tentativa automática
  local resp="$CPM_TMP/resposta.json" code
  code=$(http_json "$resp" -X POST \
    -F "file=@$limpo;type=video/mp4" -F "tags=$CPM_TAG" \
    -F "context=arquivo=$CPM_ARQUIVO|sha256=$sha" \
    "$CPM_API/video/upload") || erro "falha de rede no envio (não repetir automaticamente)"
  [ "$code" = 200 ] || erro "Cloudinary respondeu HTTP $code: $(jcampo "$resp" error.message)"
  local pid aid url rbytes dur
  pid=$(jcampo "$resp" public_id); aid=$(jcampo "$resp" asset_id)
  url=$(jcampo "$resp" secure_url); rbytes=$(jcampo "$resp" bytes)
  dur=$(duracao "$limpo")
  registrar enviados.jsonl "$(json_obj quando "$(agora)" arquivo "$CPM_ARQUIVO" sha256 "$sha" \
    bytes "$bytes" duracao "$dur" public_id "$pid" asset_id "$aid" secure_url "$url" modo "$modo")"
  [ "$rbytes" = "$bytes" ] || erro "Cloudinary registrou $rbytes bytes, enviados $bytes"
  [[ "$url" =~ ^https://res\.cloudinary\.com/vow9vkz5/video/upload/ ]] || erro "secure_url inesperada: $url"

  # 6. Conferência do link público
  local baixado="$CPM_TMP/conferencia.mp4" info
  info=$(http -o "$baixado" -w '%{http_code} %{content_type}' "$url") || erro "falha ao baixar o link público"
  [ "${info%% *}" = 200 ] || erro "link público respondeu HTTP ${info%% *}"
  [[ "${info#* }" == video/mp4* ]] || erro "tipo de conteúdo inesperado: ${info#* }"
  [ "$(sha256sum "$baixado" | cut -d' ' -f1)" = "$sha" ] || erro "arquivo entregue difere do enviado"

  echo "ENVIADO"
  echo "public_id:  $pid"
  echo "asset_id:   $aid"
  echo "bytes:      $bytes"
  echo "duracao_s:  $dur"
  echo "secure_url: $url"
  echo "link: HTTP 200 | ${info#* } | sha256 conferido"
}
