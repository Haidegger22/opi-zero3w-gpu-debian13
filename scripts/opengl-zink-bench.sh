#!/bin/bash
# opengl-zink-bench.sh — собственные замеры off-screen на Zero 3W: zink (аппаратно через слой)
# против вендорского GLES. Заодно проверяется, что дело в пути вывода, а не в слое:
# off-screen окна не создаёт вообще.
#
#   scripts/opengl-zink-bench.sh
#
# Замеры на нашей плате 28.09.2026 (GPU 400 МГц): zink 251, вендорский GLES 332 (76 %);
# софт (llvmpipe) через EGL не поднимается вовсе — eglInitialize() failed 0x3001.
set -u
export DISPLAY="${DISPLAY:-:0}"
OUT="${TMPDIR:-/tmp}/glmark2-ours"
mkdir -p "$OUT"

gpu_state() { # частота и governor GPU: числа сравнимы только при одной частоте,
              # у devfreq частота «дышит» прямо внутри теста
    for d in /sys/class/devfreq/*gpu*; do
        [ -d "$d" ] || continue
        printf '   %s: cur=%s Hz, governor=%s\n' "$(basename "$d")" \
            "$(cat "$d/cur_freq" 2>/dev/null || echo '?')" \
            "$(cat "$d/governor" 2>/dev/null || echo '?')"
    done
}

run() { # $1=метка, дальше — окружение для env(1)
    label=$1; shift
    echo "=== $label ==="
    echo "   частота ДО прогона:"; gpu_state
    # Частота у devfreq ГУЛЯЕТ (governor simple_ondemand: 400 МГц в простое, до ~1008 МГц под
    # нагрузкой), поэтому сэмплируем её во время прогона, а не только до/после.
    ( while :; do cat /sys/class/devfreq/1800000.gpu/cur_freq 2>/dev/null || break; sleep 1; done > "$OUT/$label.freq" ) &
    sampler=$!
    env "$@" timeout -s KILL 300 glmark2-es2 --off-screen -b build:duration=2 \
        > "$OUT/$label.log" 2>&1
    status=$?
    kill "$sampler" 2>/dev/null; wait "$sampler" 2>/dev/null
    echo "   код возврата: $status"
    grep -aE 'GL_RENDERER|GL_VERSION|glmark2 Score' "$OUT/$label.log" | tail -3 | sed 's/^/      /'
    grep -aiE 'error|fail|abort|segmentation' "$OUT/$label.log" | head -3 | sed 's/^/      ⚠ /'
    if [ -s "$OUT/$label.freq" ]; then
        echo "   частота ВО ВРЕМЯ прогона: min=$(sort -n "$OUT/$label.freq" | head -1) Гц, max=$(sort -n "$OUT/$label.freq" | tail -1) Гц"
    fi
    echo "   частота ПОСЛЕ прогона:"; gpu_state
}

command -v glmark2-es2 >/dev/null || { echo "нет glmark2-es2 (Debian: пакет glmark2)"; exit 1; }

run zink \
    -u LD_LIBRARY_PATH PVR_FAKE_GS=1 GALLIUM_DRIVER=zink MESA_LOADER_DRIVER_OVERRIDE=zink \
    LD_LIBRARY_PATH=/usr/lib/aarch64-linux-gnu:/lib/aarch64-linux-gnu \
    LIBGL_DRIVERS_PATH=/usr/lib/aarch64-linux-gnu/dri \
    VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/img_icd.json

echo
# Вендорский и софтверный прогоны обязаны снять ВСЕ zink-переменные, включая LIBGL_DRIVERS_PATH:
# если она осталась от предыдущих опытов, Mesa ищет DRI-драйверы в системном каталоге и вендорский
# EGL падает с 'failed to open sunxi-drm' / 'libEGL fatal: did not find extension DRI_Mesa version 1'.
run vendor-gles -u LD_LIBRARY_PATH -u LIBGL_DRIVERS_PATH -u LIBGL_ALWAYS_SOFTWARE \
    -u PVR_FAKE_GS -u GALLIUM_DRIVER -u MESA_LOADER_DRIVER_OVERRIDE \
    -u VK_LAYER_PATH -u VK_INSTANCE_LAYERS

echo
run llvmpipe -u LD_LIBRARY_PATH -u LIBGL_DRIVERS_PATH -u PVR_FAKE_GS \
    -u VK_LAYER_PATH -u VK_INSTANCE_LAYERS \
    LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe MESA_LOADER_DRIVER_OVERRIDE=llvmpipe

echo
echo "=== частота GPU в момент замеров (числа сравнимы только при одной частоте) ==="
for f in /sys/class/devfreq/*gpu*/cur_freq; do
    [ -f "$f" ] && echo "   $f = $(cat "$f")"
done

echo
echo "=== итоги ==="
for f in "$OUT"/*.log; do
    printf '   %-14s %s\n' "$(basename "$f" .log):" "$(grep -a 'glmark2 Score' "$f" | tail -1 | xargs || echo 'оценки нет')"
done
