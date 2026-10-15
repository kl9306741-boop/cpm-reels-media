# Exclusão de um Reel do Cloudinary após comprovar a cópia do Metricool. Não executar diretamente.

host_permitido() {
  python3 -I -c 'import json,sys
h = sys.argv[2].lower()
hs = [x.lower() for x in json.load(open(sys.argv[1]))["exclusao"]["hosts_copia_metricool"]]
ok = "cloudinary" not in h and any(h == x or h.endswith("." + x) for x in hs)
sys.exit(0 if ok else 1)' "$CPM_POLITICA" "$1"
}

# cpm_excluir <public_id> <url_da_copia_no_metricool>
cpm_excluir() {
  [ $# -eq 2 ] || erro "uso: scripts/cpm-delete.sh <public_id> <url_da_copia_no_metricool>"
  local pid="$1" murl="$2"
  [[ "$pid" =~ ^[A-Za-z0-9_-]{6,64}$ ]] || erro "public_id inválido"
  [[ "$murl" =~ ^https://([A-Za-z0-9.-]+)(/[^[:space:]]*)?$ ]] || erro "a URL da cópia do Metricool deve ser https"
  host_permitido "${BASH_REMATCH[1]}" \
    || erro "host ${BASH_REMATCH[1]} não consta em exclusao.hosts_copia_metricool da política"

  # 1. O recurso existe e foi enviado pela ponte (etiqueta cpm-reels)
  local rec="$CPM_TMP/recurso.json" code
  code=$(http_json "$rec" "$CPM_API/resources/video/upload/$pid") || erro "falha ao consultar o recurso"
  [ "$code" = 200 ] || erro "recurso $pid não encontrado no Cloudinary (HTTP $code)"
  python3 -I -c 'import json,sys; sys.exit(0 if sys.argv[2] in (json.load(open(sys.argv[1])).get("tags") or []) else 1)' \
    "$rec" "$CPM_TAG" || erro "recurso sem a etiqueta $CPM_TAG: não foi enviado pela ponte"
  local dur_ref
  dur_ref=$(jcampo "$rec" duration)
  if [ -z "$dur_ref" ] && [ -f "$CPM_REGISTRO/enviados.jsonl" ]; then
    dur_ref=$(python3 -I -c 'import json,sys
for l in open(sys.argv[1]):
    r = json.loads(l)
    if r.get("public_id") == sys.argv[2]: print(r.get("duracao", ""))' "$CPM_REGISTRO/enviados.jsonl" "$pid" | tail -n1)
  fi
  [ -n "$dur_ref" ] || erro "duração de referência indisponível; exclusão bloqueada"

  # 2. A cópia do Metricool existe fora do Cloudinary e é o mesmo vídeo
  local copia="$CPM_TMP/copia_metricool.mp4" info final dur_m
  info=$(curl -q -sS --proto '=https' --proto-redir '=https' --max-redirs 3 --max-time 300 \
    --max-filesize 209715200 -o "$copia" -w '%{http_code} %{url_effective}' "$murl") \
    || erro "falha ao baixar a cópia do Metricool; exclusão bloqueada"
  [ "${info%% *}" = 200 ] || erro "cópia do Metricool respondeu HTTP ${info%% *}; exclusão bloqueada"
  final="${info#* }"
  [[ "$final" =~ ^https://([A-Za-z0-9.-]+) ]] && host_permitido "${BASH_REMATCH[1]}" \
    || erro "a cópia redirecionou para host não autorizado: $final"
  ffprobe -v error "$copia" >/dev/null 2>&1 || erro "a cópia do Metricool não é um vídeo legível"
  ffmpeg -v error -nostdin -xerror -i "$copia" -f null - 2>/dev/null || erro "a cópia do Metricool não decodifica por inteiro"
  dur_m=$(duracao "$copia")
  python3 -I -c 'import sys; a, b, t = map(float, sys.argv[1:]); sys.exit(0 if abs(a - b) <= t else 1)' \
    "$dur_m" "$dur_ref" "$(pol exclusao.tolerancia_duracao_s)" \
    || erro "duração da cópia ($dur_m s) difere da original ($dur_ref s); exclusão bloqueada"
  echo "Cópia do Metricool confirmada: $final ($(stat -c %s "$copia") bytes, ${dur_m}s)"

  # 3. Exclusão com invalidação do CDN
  local del="$CPM_TMP/exclusao.json"
  code=$(http_json "$del" -X DELETE "$CPM_API/resources/video/upload?public_ids%5B%5D=$pid&invalidate=true") \
    || erro "falha de rede na exclusão (não repetir automaticamente)"
  [ "$code" = 200 ] || erro "exclusão respondeu HTTP $code: $(jcampo "$del" error.message)"
  [ "$(jcampo "$del" "deleted.$pid")" = deleted ] || erro "Cloudinary não confirmou a exclusão de $pid"

  # 4. Confirmação
  code=$(http_json "$CPM_TMP/confirmacao.json" "$CPM_API/resources/video/upload/$pid") || erro "falha ao confirmar a exclusão"
  [ "$code" = 404 ] || erro "recurso $pid ainda existe após a exclusão (HTTP $code)"
  registrar excluidos.jsonl "$(json_obj quando "$(agora)" public_id "$pid" copia_metricool "$final")"
  echo "EXCLUÍDO: $pid (confirmado HTTP 404 na API)"
}
