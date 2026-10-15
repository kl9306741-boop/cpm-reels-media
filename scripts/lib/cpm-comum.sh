# Biblioteca comum da ponte CPM -> Cloudinary -> Metricool. Não executar diretamente.
# Não contém credenciais: o proxy do ambiente injeta a autenticação do Cloudinary
# (segredo de rede CPM-CLOUDINARY) nas requisições para api.cloudinary.com.
set -euo pipefail
umask 077
export PATH=/usr/local/bin:/usr/bin:/bin
export LC_ALL=C.UTF-8

CPM_REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
CPM_POLITICA="$CPM_REPO/politica/editorial.json"
CPM_REGISTRO="$CPM_REPO/registro"
CPM_API="https://api.cloudinary.com/v1_1/vow9vkz5"
CPM_TAG="cpm-reels"
CPM_ARQUIVO=""

CPM_TMP=$(mktemp -d)
trap 'rm -rf "$CPM_TMP"' EXIT

erro() { echo "CPM ERRO: $*" >&2; exit 1; }

agora() { date -u +%FT%TZ; }

json_obj() {
  python3 -I -c 'import json,sys; a=sys.argv[1:]; print(json.dumps(dict(zip(a[::2], a[1::2])), ensure_ascii=False))' "$@"
}

registrar() {  # registrar <arquivo.jsonl> <linha-json>
  mkdir -p "$CPM_REGISTRO"
  printf '%s\n' "$2" >> "$CPM_REGISTRO/$1"
}

excecao() {
  registrar excecoes.jsonl "$(json_obj quando "$(agora)" arquivo "$CPM_ARQUIVO" motivo "$1")"
  echo "CPM EXCEÇÃO: $1" >&2
  echo "Envio bloqueado. Exige revisão humana; se aprovado, usar scripts/cpm-upload-excecao.sh (sem permissão automática)." >&2
  exit 3
}

# pol <chave.com.pontos> -> valor da política
pol() {
  python3 -I -c 'import json,sys
v = json.load(open(sys.argv[1]))
for k in sys.argv[2].split("."):
    v = v[k]
print(json.dumps(v) if isinstance(v, (list, dict)) else v)' "$CPM_POLITICA" "$1"
}

# jcampo <arquivo.json> <chave.com.pontos> -> valor ou vazio
jcampo() {
  python3 -I -c 'import json,sys
try:
    v = json.load(open(sys.argv[1]))
except Exception:
    print(""); sys.exit()
for k in sys.argv[2].split("."):
    v = v.get(k) if isinstance(v, dict) else None
print("" if v is None else v)' "$1" "$2"
}

# curl restrito: só HTTPS, ignora .curlrc, sem redirecionamentos, sem cabeçalhos na saída.
http() { curl -q -sS --proto '=https' --max-redirs 0 --max-time 300 "$@"; }

# http_json <saida> <args...> -> grava o corpo e imprime o código HTTP
http_json() { local out="$1"; shift; http -o "$out" -w '%{http_code}' "$@"; }

# Checagem técnica de um MP4. Reprovação vira exceção.
validar_video() {
  local f="$1" info="$CPM_TMP/probe.json" motivos
  ffprobe -v error -print_format json -show_format -show_streams "$f" > "$info" 2>/dev/null \
    || excecao "não é um arquivo de vídeo legível"
  motivos=$(python3 -I -c 'import json,sys
p = json.load(open(sys.argv[1])); t = json.load(open(sys.argv[2]))["tecnica"]
m = []
fmt = p.get("format", {})
if "mp4" not in fmt.get("format_name", ""): m.append("contêiner não é MP4")
ss = p.get("streams", [])
v = [s for s in ss if s.get("codec_type") == "video"]
a = [s for s in ss if s.get("codec_type") == "audio"]
if len(v) != 1: m.append(f"esperado 1 fluxo de vídeo, há {len(v)}")
if len(a) > 1: m.append(f"mais de 1 fluxo de áudio ({len(a)})")
if len(ss) != len(v) + len(a): m.append("há fluxos extras (dados, legenda ou anexo)")
if v:
    s = v[0]
    cod, w, h = s.get("codec_name"), s.get("width"), s.get("height")
    if cod != t["video_codec"]: m.append("vídeo %s em vez de %s" % (cod, t["video_codec"]))
    if (w, h) != (t["largura"], t["altura"]):
        m.append("resolução %sx%s fora do padrão %sx%s" % (w, h, t["largura"], t["altura"]))
    n, d = (s.get("avg_frame_rate") or "0/1").split("/")
    fps = float(n) / float(d) if float(d) else 0
    if not t["fps_min"] <= fps <= t["fps_max"]: m.append("%.2f fps fora da faixa" % fps)
if a and a[0].get("codec_name") != t["audio_codec"]:
    m.append("áudio %s em vez de %s" % (a[0].get("codec_name"), t["audio_codec"]))
if t["audio_obrigatorio"] and not a: m.append("sem áudio")
dur = float(fmt.get("duration") or 0)
if not t["duracao_min_s"] <= dur <= t["duracao_max_s"]: m.append(f"duração {dur:.2f}s fora da faixa")
print("; ".join(m))' "$info" "$CPM_POLITICA")
  [ -z "$motivos" ] || excecao "$motivos"
  ffmpeg -v error -nostdin -xerror -i "$f" -map 0:v:0 -map '0:a?' -f null - 2>/dev/null \
    || excecao "o vídeo não decodifica por inteiro sem erros"
}

duracao() { ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$1"; }

# Política editorial: ficha <nome>.ficha.json ao lado do vídeo.
validar_ficha() {
  local f="$1" ficha="${1%.mp4}.ficha.json" motivos
  [ -f "$ficha" ] && [ ! -L "$ficha" ] || excecao "falta a ficha editorial $(basename "$ficha")"
  motivos=$(python3 -I -c 'import json,sys
try:
    fi = json.load(open(sys.argv[1]))
except Exception:
    print("ficha não é um JSON válido"); sys.exit()
e = json.load(open(sys.argv[2]))["editorial"]
m = [f"campo {c} ausente" for c in e["ficha_campos_obrigatorios"] if not str(fi.get(c, "")).strip()]
if fi.get("arquivo") != sys.argv[3]: m.append("campo arquivo não corresponde ao vídeo")
ck = fi.get("checklist") or {}
m += [f"checklist {c} não confirmado" for c in e["ficha_checklist_obrigatorio"] if ck.get(c) is not True]
print("; ".join(m))' "$ficha" "$CPM_POLITICA" "$(basename "$f")")
  [ -z "$motivos" ] || excecao "$motivos"
}

# Já existe envio deste sha256 sem exclusão registrada nesta sessão?
ja_enviado() {
  python3 -I -c 'import json,sys,os
env, exc, sha = sys.argv[1:]
ler = lambda p: [json.loads(l) for l in open(p) if l.strip()] if os.path.exists(p) else []
excl = {r.get("public_id") for r in ler(exc)}
sys.exit(0 if any(r.get("sha256") == sha and r.get("public_id") not in excl for r in ler(env)) else 1)' \
    "$CPM_REGISTRO/enviados.jsonl" "$CPM_REGISTRO/excluidos.jsonl" "$1"
}

# Controle de consumo do Cloudinary Free. Falha fechada: sem leitura da cota, não envia.
# verificar_cota <bytes_previstos> <bloquear:1|0>
verificar_cota() {
  local previstos="$1" bloquear="$2" u="$CPM_TMP/usage.json" p="$CPM_TMP/pendentes.json" code
  code=$(http_json "$u" "$CPM_API/usage") || erro "não foi possível consultar a cota; envio bloqueado"
  [ "$code" = 200 ] || erro "consulta de cota respondeu HTTP $code; envio bloqueado"
  code=$(http_json "$p" "$CPM_API/resources/video/tags/$CPM_TAG?max_results=100") \
    || erro "não foi possível listar os vídeos pendentes; envio bloqueado"
  [ "$code" = 200 ] || erro "lista de pendentes respondeu HTTP $code; envio bloqueado"
  python3 -I -c 'import json,sys,os,datetime
u, r, c = (json.load(open(x)) for x in sys.argv[1:4]); c = c["cota"]
reg, previstos, bloquear = sys.argv[4], int(sys.argv[5]), sys.argv[6] == "1"
cred = u.get("credits") or {}
uso, lim, pct = cred.get("usage"), cred.get("limit"), cred.get("used_percent")
if pct is None and uso is not None and lim: pct = 100 * uso / lim
if pct is None: sys.exit("CPM ERRO: resposta de cota sem créditos; envio bloqueado")
lim = lim or c["limite_creditos_plano"]
# custo previsto: armazenamento + download pelo Metricool + conferência (3 x tamanho), 1 crédito = 1 GB
pct_prev = pct + 100 * (3 * previstos / 1e9) / lim
pend = r.get("resources", [])
hoje = datetime.datetime.now(datetime.timezone.utc).date().isoformat()
n = sum(1 for l in open(reg) if l.strip() and json.loads(l).get("quando", "").startswith(hoje)) if os.path.exists(reg) else 0
print(f"Cota Cloudinary: {pct:.2f}% dos créditos ({uso}/{lim}); após este envio ~{pct_prev:.2f}% | pendentes: {len(pend)} | envios hoje: {n}")
for x in pend: print("  pendente: %s (%s bytes, %s)" % (x.get("public_id"), x.get("bytes"), x.get("created_at")))
if lim > c["limite_creditos_plano"]: print("  aviso: limite de créditos acima do plano Free esperado", file=sys.stderr)
if not bloquear: sys.exit()
teto = c["parar_em_percentual"]
if pct_prev >= teto: sys.exit("CPM ERRO: cota prevista %.2f%% >= %s%%; envio bloqueado" % (pct_prev, teto))
if len(pend) >= c["max_pendentes"]: sys.exit(f"CPM ERRO: {len(pend)} vídeos aguardam exclusão; exclua os já importados antes de enviar")
if n >= c["max_envios_dia"]: sys.exit("CPM ERRO: limite diário de envios atingido")' \
    "$u" "$p" "$CPM_POLITICA" "$CPM_REGISTRO/enviados.jsonl" "$previstos" "$bloquear"
}
