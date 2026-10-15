#!/usr/bin/env bash
# Gancho PreToolUse (Bash) da ponte CPM. Recebe o JSON da chamada na entrada padrão.
# É executado pelo comando inline de .claude/settings.json SOMENTE depois que a integridade
# de scripts/, politica/ e .claude/settings.json foi conferida contra origin/main.
# Nunca concede permissão: apenas bloqueia (exit 2) ou devolve ao fluxo normal (exit 0).
export PATH=/usr/bin:/bin
IN=$(cat)
exec python3 -I -c '
import json, re, sys
try:
    cmd = json.loads(sys.argv[1]).get("tool_input", {}).get("command", "")
except Exception:
    sys.exit(0)

def bloquear(msg):
    print("CPM guarda: " + msg, file=sys.stderr)
    sys.exit(2)

# 1. Os scripts CPM só podem ser chamados de forma simples e isolada.
PROTEGIDOS = r"(^|[\s\x27\"=/:])(scripts|politica|\.claude|config-proposta)(/|\s|$)|\.gitignore|\.git/"
ESCRITA = (r"(>|\btee\b|\bsed\b|\bperl\b|\bpython[0-9.]*\b|\bruby\b|\bnode\b|\bawk\b|\bcp\b|\bmv\b|"
           r"\brm\b|\brmdir\b|\bln\b|\bchmod\b|\bchown\b|\bchattr\b|\btouch\b|\btruncate\b|\bdd\b|"
           r"\binstall\b|\bpatch\b|\bunzip\b|\btar\b|\brsync\b|\bgit\s+(checkout|restore|reset|apply|"
           r"am|stash|cherry-pick|rebase|merge|mv|rm|update-index|filter-branch|worktree|clean))")
METACARACTERES = re.compile(r"[;&|`$<>(){}\\\n]")
LEITURA = re.compile(r"^\s*(cat|head|tail|less|grep|rg|wc|sha256sum|ls|stat|file|"
                     r"git\s+(diff|log|show|status|blame))\b")

CPM = re.compile(r"cpm-(upload|upload-excecao|delete|cota)\.sh|scripts/lib/cpm-")
SIMPLES = re.compile(r"^\s*\./scripts/cpm-(upload|upload-excecao|delete|cota)\.sh(\s+[^;&|`$<>(){}\\\n\x27\"*?~]*)?\s*$")
if CPM.search(cmd):
    if LEITURA.match(cmd) and not METACARACTERES.search(cmd) and not re.search(ESCRITA, cmd):
        sys.exit(0)
    if not SIMPLES.match(cmd):
        bloquear("chame os scripts CPM de forma simples: ./scripts/cpm-<nome>.sh <args>, "
                 "sem encadear, redirecionar, usar variáveis ou outro interpretador.")
    sys.exit(0)

# 2. Nada de alterar arquivos protegidos por Bash.
if re.search(PROTEGIDOS, cmd) and re.search(ESCRITA, cmd):
    bloquear("comando que pode alterar arquivos protegidos da ponte CPM. "
             "Mudanças em scripts/, politica/ e .claude/ só por pull request revisado pelo fundador.")

# 3. Nada de adulterar a referência usada na verificação de integridade.
if re.search(r"\bgit\s+(update-ref|replace|remote\s+(set-url|add|rename|remove)|"
             r"config\b[^\n]*(remote\.|url\.|core\.hookspath|core\.worktree|include))", cmd, re.I):
    bloquear("comando git que pode adulterar a referência de integridade (origin/main).")

# 4. Nada de mexer em proteções do repositório pela API.
if re.search(r"\b(gh|curl|wget)\b", cmd) and re.search(
        r"(/protection|/rulesets|/collaborators|/keys|/hooks|/actions|/environments)", cmd):
    bloquear("alterações de proteção ou configuração do repositório não são permitidas nesta sessão.")

sys.exit(0)
' "$IN"
