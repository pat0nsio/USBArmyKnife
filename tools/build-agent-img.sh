#!/usr/bin/env bash
# Reconstruye agent.img desde el source del repo. Sin blob en git.
#
# Qué hace:
#   1. dotnet publish de tools/Agent (PortableApp.dll + deps + in1.bat)
#   2. crea una imagen de disco, una particion FAT32, y copia el publish a la raiz
#
# El .ds de instalacion corre "%d:\in1.bat" en cada unidad, asi que in1.bat
# y todos los binarios tienen que quedar en la RAIZ de la imagen (lo hace el publish).
set -euo pipefail

# --- knobs (calibracion) ---------------------------------------------------
REPO="${REPO:-$(cd "$(dirname "$0")/.." && pwd)}"   # raiz del repo (default: ../ de este script)
OUT="${OUT:-$REPO/sd-latam/agent.img}"              # imagen de salida
RID="${RID:-win-x64}"                               # runtime target del Agent
SELF_CONTAINED="${SELF_CONTAINED:-true}"            # incluir runtime .NET (victima sin .NET 8)
IMG_SIZE_MB="${IMG_SIZE_MB:-500}"                   # ponytail: 500 matchea la img que ya funcionaba; bajalo al tamaño del publish + margen si querés
PART_OFFSET_MB="${PART_OFFSET_MB:-1}"               # inicio de particion (1MiB = sector 2048, como la img original)
PART_TYPE="${PART_TYPE:-0c}"                         # 0x0c = FAT32 LBA (lo correcto para FAT removible en Windows)
# ---------------------------------------------------------------------------

AGENT_CSPROJ="$REPO/tools/Agent/Agent.csproj"
[ -f "$AGENT_CSPROJ" ] || { echo "No encuentro $AGENT_CSPROJ"; exit 1; }

# dotnet suele estar en ~/.dotnet sin estar en el PATH
export PATH="$PATH:$HOME/.dotnet:$HOME/.dotnet/tools"

for bin in dotnet mformat mcopy sfdisk; do
  command -v "$bin" >/dev/null || { echo "Falta '$bin' (mtools: mformat/mcopy; util-linux: sfdisk)"; exit 1; }
done

PUB="$(mktemp -d)"; trap 'rm -rf "$PUB"' EXIT

echo ">> dotnet publish ($RID, self-contained=$SELF_CONTAINED)"
dotnet publish "$AGENT_CSPROJ" -c Release -r "$RID" \
  --self-contained "$SELF_CONTAINED" -o "$PUB"

# in1.bat es el instalador que corre el .ds; sin el, la imagen no sirve
[ -f "$PUB/in1.bat" ] || { echo "ERROR: in1.bat no quedo en el publish (revisa tools/Agent/in1.bat y el <Content> del csproj)"; exit 1; }

mkdir -p "$(dirname "$OUT")"
echo ">> creando imagen $OUT (${IMG_SIZE_MB}MB)"
rm -f "$OUT"
truncate -s "${IMG_SIZE_MB}M" "$OUT"

# tabla de particiones: una sola particion FAT32 arrancando en PART_OFFSET_MB
echo ">> particionando (start ${PART_OFFSET_MB}MiB, type 0x${PART_TYPE})"
printf '%s\n' "${PART_OFFSET_MB}MiB,,${PART_TYPE}" | sfdisk --label dos "$OUT" >/dev/null

# formatear FAT32 en el offset de la particion y copiar el publish a la raiz
# mtools apunta a un offset con img@@<offset>
IMG_AT="$OUT@@${PART_OFFSET_MB}M"
echo ">> mformat + mcopy"
mformat -F -v AGENT -i "$IMG_AT" ::
mcopy -s -i "$IMG_AT" "$PUB"/* ::

echo ">> OK"
mdir -i "$IMG_AT" :: | head -20
ls -lh "$OUT"
