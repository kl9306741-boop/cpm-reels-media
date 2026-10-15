# Política editorial da ponte de vídeos do CPM (v1)

Parâmetros executáveis em [`editorial.json`](editorial.json). Alterações nesta pasta só por
pull request revisado pelo fundador.

## Aprovação automática

Um Reel é enviado ao Cloudinary sem revisão humana quando **todas** as condições abaixo valem:

1. O arquivo está em `entrada/` e o nome segue o padrão da série
   (`CPM_S<n>_R<n>_<tema>_IG[_<n>MB].mp4`).
2. Existe a ficha `entrada/<nome>.ficha.json` com os campos obrigatórios e todos os itens do
   checklist marcados como `true` (modelo em [`ficha-exemplo.json`](ficha-exemplo.json)).
3. O vídeo passa na checagem técnica: MP4, 1 fluxo H.264 1080×1920, no máximo 1 fluxo AAC, nenhum
   fluxo extra, 3–90 s, até 95 MB e decodificação completa sem erros.
4. A cota do Cloudinary Free está abaixo do limite preventivo, há menos de 5 vídeos pendentes de
   exclusão e o limite diário de envios não foi atingido.

O arquivo enviado é sempre uma **cópia limpa gerada pelo script** (somente vídeo e áudio, sem
metadados, capítulos ou unidades SEI), nunca o arquivo original.

## Exceções (revisão humana)

Qualquer reprovação nos itens 1–3 bloqueia o envio e fica registrada em `registro/excecoes.jsonl`.
Se o fundador aprovar a exceção, o envio usa `scripts/cpm-upload-excecao.sh`, que **não** tem
permissão automática e mantém as checagens técnicas, de integridade e de cota.

## Exclusão

O vídeo só é apagado do Cloudinary depois que `scripts/cpm-delete.sh` baixa a cópia do próprio
Metricool (host listado em `exclusao.hosts_copia_metricool`), confirma que é um vídeo válido com a
mesma duração e só então exclui com invalidação do CDN.
