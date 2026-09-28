# Аппаратный Desktop-OpenGL на Zero 3W — zink поверх PowerVR Vulkan

> Как из «GLX всегда llvmpipe» получить **аппаратный desktop OpenGL**: zink (GL поверх Vulkan)
> + слой `VK_LAYER_PVR_strip`, снимающий два несовместимых требования.
> Проверено на Zero 3W: **28.09.2026**, Debian 13 trixie, ядро `6.6.98-sun60iw2`,
> Mesa `25.0.7-2+deb13u1`, вендорский DDK `24.2.6603887`, gcc 14.2, gdb 16.3.

> ⚠️ **Коротко о результате.** Аппаратный GL через zink работает — и **без окна**
> (`glmark2-es2 --off-screen`: 401 против 524 у вендорского GLES — 77 %), и **в окне**
> (`glmark2` через GLX — 319/325, `glmark2-es2` через EGL — 277/289, `glxheads` — работает).
> Но **часть старых GLX-демок аварийно падает**: `glxgears` и `glxdemo` завершаются SIGABRT
> **внутри вендорского компилятора шейдеров** — трейс в §5. Это дефект блоба на конкретных
> пайплайнах, а не отсутствие оконного GL.

---

## 1. Что было и что стало

| Проверка | До слоя | После слоя |
|---|---|---|
| `glxinfo -B` → renderer | `llvmpipe (LLVM 19.1.7, 128 bits)` | `zink Vulkan 1.3(PowerVR B-Series BXM-4-64 MC1 (IMAGINATION_PROPRIETARY))` |
| `glxinfo -B` → version | `4.5 (Compatibility Profile) Mesa 25.0.7` | `2.1 Mesa 25.0.7-2+deb13u1` |
| `GL_RENDERER` (EGL, вендорский стек) | PowerVR B-Series BXM-4-64 | не меняется (это не Mesa, а блоб из `/usr/local`) |
| `Accelerated` (GLX_MESA_query_renderer) | `no` | zink отдаёт профиль 2.1 |
| **Окно, GLX** (`glmark2`) | — | ✅ 319 / 325 (аппаратно) |
| **Окно, EGL/GLES** (`glmark2-es2`) | — | ✅ 277 / 289 (аппаратно) |
| **Окно, GLX** (`glxgears`) | ✅ 167,9 FPS (софт) | ❌ **SIGABRT** — известный падающий случай, §5 |
| `glxheads` (GLX, окно) | — | ✅ работает (20 с без падения) |
| `vulkaninfo --summary` | PowerVR, 1.3.277 | PowerVR, 1.3.277 |

Натуральная «база» (без слоя и **без принудительного софта**):

```
glx: failed to create dri3 screen
Vendor: Mesa, Device: llvmpipe (LLVM 19.1.7, 128 bits), Accelerated: no
```

До слоя Mesa прямо говорит, почему уходит в софт:

```
MESA: error: zink: Imagination proprietary driver w/o geometryShader is unsupported
```

## 2. Почему без слоя не получается

1. **Mesa не содержит GL-драйвера для этого GPU.** Аппаратный путь есть только у Vulkan
   (вендорский ICD `img_icd.json`) и GLES через вендорский EGL.
2. **zink — единственный мост** «GL → Vulkan», но он требует
   `VkPhysicalDeviceFeatures.geometryShader`, а блоб PowerVR сообщает по нему `false`.
   Без этого бита zink отказывается инициализироваться (строка выше) и Mesa падает в llvmpipe.
   Проверено отрицательным контролем: то же окружение zink без `PVR_FAKE_GS=1` даёт повтор
   ошибки `w/o geometryShader is unsupported` и **никакого** аппаратного рендерера.
3. **Решение (внешнее):** Vulkan-слой, который **на опросе** сообщает, что `geometryShader`
   есть, а перед `vkCreateDevice` **вырезает** этот бит из запроса — блоб никогда не просят
   включить то, чего у него нет. Второй бит, `VK_EXT_robustness2.nullDescriptor`, нужен только
   свежему zink (Mesa ≥ 26) и включается отдельно — см. §6.

Отдельно, чтобы не смешивать: **вендорский GL-блоб** (`libEGL`/`pvr_dri.so` из `/usr/local`)
ломает создание GL-контекста в приложениях — у Wine это `err:wgl:internal_context_create`.
Зависание `wineboot` — **другая история** (пустой реестр профиля: ноль `InprocServer32`,
незапускающийся `RpcSs`, незарегистрированный `MMDeviceEnumerator`) и разобрано в соседнем
репозитории: [`opi-zero-3w-disciples2`](https://github.com/Haidegger22/opi-zero-3w-disciples2),
там же `reg/rpcss-service.reg` и `scripts/fix-rpcss-service.sh`.

Автор рецепта и среды сборки слоя — внешний проект, мы воспроизвели и проверили на плате
(§9 «Источники и авторство»).

## 3. Установка

**Предпосылки:** работает вендорский Vulkan (`vulkaninfo --summary` → PowerVR 1.3.277,
см. основной README), Mesa из trixie стоит и не менялась, есть `gcc`.

```bash
# 1) исходник слоя
git clone -b trixie https://github.com/ayiejosh/a733-powervr-fex.git ~/pvr-work/a733-powervr-fex

# 2) сборка + установка (кладутся только манифест и .so в домашний каталог)
cd ~/pvr-work/a733-powervr-fex/gpu/vk-feature-strip
./install.sh
#   → ${XDG_DATA_HOME:-$HOME/.local/share}/vulkan/implicit_layer.d/libVkLayer_PVR_strip.so
#     ${XDG_DATA_HOME:-$HOME/.local/share}/vulkan/implicit_layer.d/VkLayer_PVR_strip.json
```

То же самое делает наш скрипт (плюс проверка результата сразу после установки):

```bash
scripts/opengl-zink-install.sh            # клонировать/обновить слой, собрать, установить, проверить
scripts/opengl-zink-install.sh --check    # только предпосылки и коллизии имён
scripts/opengl-zink-install.sh --uninstall
```

**Важно:** слой нельзя ставить вместе с другой реализацией под тем же именем
`VK_LAYER_PVR_strip` (в природе есть более старая версия на переменных
`PVR_STRIP_ENABLE`/`PVR_STRIP_DISABLE`). Лоадер выберет одну и **молча проигнорирует**
переменные второй — слой будет «как будто ничего не делать». `install.sh` такую коллизию
находит и отказывается ставить.

## 4. Включение и проверка

**Проверено на плате 28.09.2026:** при implicit-установке (манифест в
`~/.local/share/vulkan/implicit_layer.d`, есть `enable_environment` + `disable_environment`)
**достаточно одной переменной**:

```bash
PVR_FAKE_GS=1 glxinfo -B        # → zink Vulkan 1.3(PowerVR B-Series BXM-4-64 MC1 ...)
```

Замерено: `VK_LAYER_PATH` и `VK_INSTANCE_LAYERS` при этом **не выставлялись**. Тот же запуск
без `PVR_FAKE_GS` даёт ошибку zink про `geometryShader` (§2.2) — то есть работает именно слой.

**Вариант с явным подключением** (если манифест доступен только как *explicit*) — нужны три
переменные, потому что explicit-слой не включается автоматически, и помните про замену
каталогов поиска (таблица ниже):

```bash
PVR_FAKE_GS=1 \
VK_LAYER_PATH=$HOME/.local/share/vulkan/implicit_layer.d \
VK_INSTANCE_LAYERS=VK_LAYER_PVR_strip \
glxinfo -B
```

Полное рабочее окружение — `scripts/opengl-zink-env.sh`; проверка «до/после» —
`scripts/opengl-zink-verify.sh`:

```bash
env -u LD_LIBRARY_PATH \
    PVR_FAKE_GS=1 \
    GALLIUM_DRIVER=zink MESA_LOADER_DRIVER_OVERRIDE=zink \
    LD_LIBRARY_PATH=/usr/lib/aarch64-linux-gnu:/lib/aarch64-linux-gnu \
    LIBGL_DRIVERS_PATH=/usr/lib/aarch64-linux-gnu/dri \
    VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/img_icd.json \
    DISPLAY=:0 glxinfo -B
```

Ждём: `OpenGL renderer string: zink Vulkan 1.3(PowerVR B-Series BXM-4-64 MC1 (IMAGINATION_PROPRIETARY))`.

**Доказать, что загрузился именно слой:**

```bash
VK_LOADER_DEBUG=layer PVR_FAKE_GS=1 <ваше GL-приложение> 2>&1 | grep -i pvr_strip
```

На нашей плате это даёт `Found manifest file …/implicit_layer.d/VkLayer_PVR_strip.json`.

⚠️ Найденный манифест — это ещё **не включённый** слой: `grep` доказывает лишь, что лоадер
видит файл. Что слой реально работает, доказывает функциональный тест — `glxinfo -B` даёт
`zink Vulkan 1.3(PowerVR …)`, а без `PVR_FAKE_GS=1` рендерера нет вовсе (§2.2). Обе проверки
собраны в `scripts/opengl-zink-verify.sh` (шаги 2 и 3).

### Ловушки манифеста (каждая стоила отладки)

| Ловушка | Что происходит |
|---|---|
| нет `disable_environment` в implicit-манифесте | лоадер молча пропускает слой: `Didn't find required layer object disable_environment in manifest JSON file, skipping this layer` |
| **есть блок `device_extensions` с `VK_EXT_robustness2`** | лоадер подмешивает расширение приложениям **независимо** от `PVR_FAKE_R2`, и `vkCreateDevice` падает с `VK_ERROR_FEATURE_NOT_PRESENT` (замер: 115 расширений вместо 114) |
| два манифеста с одним именем | выбран будет один, переменные второго молча проигнорированы |
| `VK_LAYER_PATH` без `VK_INSTANCE_LAYERS` | explicit-слой не поднимается: результат как без слоя вообще |
| **`VK_LAYER_PATH` ЗАМЕНЯЕТ стандартные каталоги explicit-слоёв, а не дополняет их** | пока переменная выставлена, для процесса **невидимы любые чужие explicit-слои**: валидация, RenderDoc, MangoHud отвечают `Layer "VK_LAYER_KHRONOS_validation" was not found but was requested by env var VK_INSTANCE_LAYERS!`. Лечится снятием переменной (implicit-путь её не требует) либо перечислением обоих каталогов: `VK_LAYER_PATH=$HOME/.local/share/vulkan/implicit_layer.d:/usr/share/vulkan/explicit_layer.d` |

⚠️ Про `device_extensions` — это **не гипотеза**: из двух опубликованных реализаций блок
`device_extensions` с `VK_EXT_robustness2` реально прописан в манифесте варианта
[`davidhfrankelcodes/pvr-a733-armbian`](https://github.com/davidhfrankelcodes/pvr-a733-armbian),
а в варианте [`ayiejosh/a733-powervr-fex`](https://github.com/ayiejosh/a733-powervr-fex) —
нет. Мы берём слой из второго. Если по недоразумению взяли первый — **удалите блок
`device_extensions`** из манифеста, иначе приложение получит `VK_ERROR_FEATURE_NOT_PRESENT`.

### Способы включения и отключения

| Способ | Как | Когда нужен |
|---|---|---|
| implicit (**рекомендуется**) | `./install.sh` → `PVR_FAKE_GS=1 <app>` | обычный случай (проверено) |
| explicit | `VK_LAYER_PATH=<каталог> VK_INSTANCE_LAYERS=VK_LAYER_PVR_strip PVR_FAKE_GS=1 <app>` | если манифест не установлен как implicit; помните про замену каталогов |
| выключить на процесс | `PVR_STRIP_DISABLE=1 <app>` | разовая проверка |
| снять совсем | `.../vk-feature-strip/install.sh --uninstall` | откат |

### ⚠️ Область действия `PVR_FAKE_GS` — не «на всю сессию»

Не выставляйте `PVR_FAKE_GS` глобально (`~/.profile`, autostart, окружение systemd).
Переменная говорит **любому** Vulkan-приложению, что `geometryShader` доступен; приложение,
которое на это поверит и создаст настоящий GS-конвейер, уронит блоб. Слой инертен ровно до тех
пор, пока переменной нет — включать только на конкретный запуск.

И наоборот: `LIBGL_ALWAYS_SOFTWARE=1` для рабочего стола — часть защиты от дедлока ядра (§6),
её нельзя «заодно почистить» вместе с остальными переменными.

## 5. Замеры

**Наш Zero 3W (28.09.2026, GPU 400 МГц, governor `simple_ondemand`; частота внутри прогонов
не менялась — скрипт читает её до и после каждого теста):**

| Тест | Без слоя | Со слоем (zink) |
|---|---|---|
| `glxinfo -B` renderer | llvmpipe (LLVM 19.1.7), GL 4.5 | zink Vulkan 1.3(PowerVR B-Series BXM-4-64 MC1), GL 2.1 |
| `glmark2-es2 --off-screen` (чистые **чередующиеся** пары, 3 прогона) | 521 / 527 / 524, медиана **524** | 400 / 401 / 417, медиана **401** |
| `glmark2` **в окне** (GLX) | — | ✅ 319 / 325 |
| `glmark2-es2` **в окне** (EGL/GLES) | ✅ 621 | ✅ 277 / 289 |
| `glxheads` в окне (GLX) | — | ✅ работает (20 с без падения) |
| `glxgears -info` в окне (GLX) | ✅ 167,9 FPS (llvmpipe) | ❌ **SIGABRT (134)**, стабильно, в том числе в чистом окружении |
| `glxdemo` в окне (GLX) | — | ❌ **SIGABRT (134)** |
| `vblank_mode=0 glxgears` (без вертикальной синхронизации) | — | ❌ SIGABRT — значит дело не в vsync |
| `VK_LOADER_DEBUG` | слой не найден | `Found manifest file …/VkLayer_PVR_strip.json` |
| ядро после опытов | — | без ошибок `pvrsrvkm`, дедлока нет (uptime не сброшен) |

**Главное: оконный аппаратный GL работает** (и GLX, и EGL), а падают **отдельные старые
GLX-демки** — аварийно, внутри вендорского драйвера.

### Трейс падения (`glxgears`), снят через gdb без root

```bash
env -u LD_LIBRARY_PATH PVR_FAKE_GS=1 GALLIUM_DRIVER=zink MESA_LOADER_DRIVER_OVERRIDE=zink \
    LD_LIBRARY_PATH=/usr/lib/aarch64-linux-gnu:/lib/aarch64-linux-gnu \
    LIBGL_DRIVERS_PATH=/usr/lib/aarch64-linux-gnu/dri \
    VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/img_icd.json DISPLAY=:0 \
    VK_LAYER_PATH=$HOME/.local/share/vulkan/implicit_layer.d VK_INSTANCE_LAYERS=VK_LAYER_PVR_strip \
    gdb -batch -ex run -ex "bt 25" --args glxgears -info
```

Результат:

```
Thread 8 "glxgears:gdrv0" received signal SIGABRT, Aborted.
#0  abort ()                                   /usr/lib/aarch64-linux-gnu/libc.so.6
#1..#11  ?? () from /usr/lib/libufwriter.so    кадр #11: BILParseStream()
#12..#14 ?? () from /lib/libVK_IMG.so          вендорский драйвер
#15..#21 ?? () from libgallium-25.0.7-...so    Mesa (zink)
```

Аварийное завершение приходит из **вендорского шейдерного компилятора** (`libufwriter.so`,
`BILParseStream` — часть стека Imagination), вызванного из Mesa, на потоке драйвера `gdrv0`.
То есть падает **блоб**, а не слой и не zink: слой лишь доводит процесс до этого места (без
него zink не инициализируется вовсе). Точный путь по этому стеку не разводится — кадры
`libgallium` без символов, и как доказательство «это презентация в X11» они не годятся.
Что проверили отдельно:

- `vblank_mode=0` (без vsync) — падает так же, значит дело не в обмене буферов с синхронизацией;
- **слой валидации Khronos** (`vulkan-validationlayers`), подключённый правильно, до падения
  **никаких ошибок Vulkan API не сообщает** — то есть это не misuse API, а внутренний abort драйвера;
- отсутствие DRI3 (в базовой линии `glx: failed to create dri3 screen` при **софтверном**
  рендере) само по себе оконный GL не блокирует — доказано работающими `glmark2` и `glxheads`.

### Оговорки к числам (важно для воспроизводимости)

- **Методика:** чередующиеся пары «zink → вендорский GLES» в одной сессии, и в каждом запуске
  **все** переменные снимаются и выставляются явно
  (`env -u LD_LIBRARY_PATH -u LIBGL_DRIVERS_PATH -u GALLIUM_DRIVER -u MESA_LOADER_DRIVER_OVERRIDE
  -u PVR_FAKE_GS -u VK_LAYER_PATH -u VK_INSTANCE_LAYERS …`). На этом мы наступали: если в
  оболочке остались `GALLIUM_DRIVER=zink`, `PVR_FAKE_GS=1`, `LD_LIBRARY_PATH` из предыдущих
  опытов, то «вендорский» прогон на самом деле идёт через zink или падает с
  `libEGL fatal: did not find extension DRI_Mesa version 1` — и числа врут.
- **Частота GPU не фиксирована**: governor `simple_ondemand`, наблюдали **400 МГц** в простое и
  до **1008 МГц** под нагрузкой (Шаг 3 плана предполагал «жёсткие 600 МГц» — на практике нет).
  Поэтому абсолютные баллы сравнимы только внутри одной серии; в `scripts/opengl-zink-bench.sh`
  частота сэмплируется **во время** прогона, а не только до и после.
- **Воспроизводимость:** тот же замер, повторённый нашим скриптом после правок, дал zink **426**
  и вендорский GLES **542** (79 %), частота во время прогонов — 400 МГц (сэмплирование −
  см. `scripts/opengl-zink-bench.sh`). То есть порядок и соотношение устойчивы, абсолютные
  баллы гуляют на ±5–10 % между сессиями.
- Софт через EGL на нашей плате не поднимается вовсе: `glmark2-es2 --off-screen` на llvmpipe
  падает с `eglInitialize() failed with error: 0x3001`. Поэтому софтверный GL здесь живёт в
  GLX-окне (`glxgears` 167,9 FPS), а EGL/off-screen — аппаратный.

**Референсная плата с той же GPU и тем же DDK** (Radxa Cubie A7A, Debian 13 trixie,
`glmark2-es2 --off-screen -b build:duration=2`):

| Конфигурация | Результат |
|---|---|
| без слоя | оценки нет — блоб отклоняет `geometryShader` |
| zink через слой (GPU 1104 МГц) | **581** |
| вендорский GLES (GPU 1104 МГц) | **826** |
| zink через слой (стоковые 600 МГц) | **454** |
| вендорский GLES (стоковые 600 МГц) | **659** |
| `PVR_FAKE_GS=1 PVR_FAKE_R2=1` | **SIGSEGV** внутри `libVK_IMG.so` (без падения ядра) |

Вывод: аппаратный GL через zink даёт примерно **70–80 %** от вендорского GLES на той же плате.
Потолок аппаратного GL на этом блобе — **GL 2.1 / GLES 2.0**.

## 6. Грабли (каждая проверена и стоила времени)

- **`zink` без слоя не стартует** — `geometryShader` у блоба `false` (§2.2).
- **Часть старых GLX-программ аварийно падает** (`glxgears`, `glxdemo`): `abort()` внутри
  вендорского шейдерного компилятора (`libufwriter.so` → `BILParseStream`, трейс в §5). При
  этом `glmark2` (GLX), `glmark2-es2` (EGL) и `glxheads` в окне работают. Что общего у падающих
  программ, не установлено — нужен разбор создаваемых ими пайплайнов; проверяйте конкретное
  приложение, а не «в целом работает».
- **`fillModeNonSolid` у блоба нет.** zink предупреждает об этом при инициализации: сплошная
  заливка рисуется корректно, каркас и неполная заливка (`glPolygonMode`) — ненадёжны.
- **Mesa ≥ 26 не обновлять.** zink 26+ требует `VK_EXT_robustness2.nullDescriptor`, а блоб
  этого расширения не знает вовсе: `PVR_FAKE_R2=1` проходит проверку и **падает** внутри
  `libVK_IMG.so` при первом же null descriptor. Рабочая версия — системная **25.0.7**.
- **GPU-композитор запрещён.** Композитор, рисующий на GPU через `pvrsrvkm`, вешает ядро
  (`mutex_spin_on_owner` в IRQ → лечится только power-cycle). Поэтому программный рабочий стол
  и `LIBGL_ALWAYS_SOFTWARE=1` — это **защита, а не костыль**: не включать glamor, не поднимать
  Wayland-композитор на GPU, **не ставить `DXVK_HUD`** (тот же класс отказа).
- **Двойная Mesa.** Вендорский стек в `/usr/local` имеет приоритет по `ldconfig`, поэтому путь
  zink обязан запускаться со scoped `LD_LIBRARY_PATH` на системную Mesa (в блоках выше —
  `env -u LD_LIBRARY_PATH LD_LIBRARY_PATH=/usr/lib/aarch64-linux-gnu:...`).
- **Блоб сообщает 114 device extensions** и не имеет `descriptor_buffer`, resizable BAR и
  `non_seamless_cube_map` — отсюда вывод «просто поставить новее Mesa» ничего не даёт.
- **Слой одноустройственный**: одна статическая пара `g_inst`/`g_dev`, без карты
  dispatch-таблиц по хэндлу. Годится для `glxinfo`/`eglinfo`/`glmark2` и однопроцессных
  приложений; для многопоточных/многопрефиксных — не универсален.
- **Фейк настоящих geometry-шейдеров уронил бы блоб** (на headless-плате это power-cycle),
  поэтому подделка — исключительно на опрос, а не на исполнение. Отдельно не проверялось и
  проверять не советуем.

## 7. Что это даёт и чего не даёт

- ✅ **Аппаратный desktop OpenGL — и без окна, и в окне**: off-screen/EGL (рендер в FBO,
  headless-сцены, GL-вычисления) и оконные приложения, не попадающие на дефект блоба
  (`glmark2`, `glmark2-es2`, `glxheads`).
- ⚖️ **Быстрее — но уже.** zink даёт **GL 2.1**, llvmpipe — **GL 4.5**. Приложению, которому
  нужен GL ≥ 3.x, zink не подойдёт; для такого остаётся софт-путь (медленнее, зато 4.5).
- ⚠️ **Падения отдельных программ не исключены** (§5/§6): проверять конкретное приложение.
- ❌ **GPU-композитор и GPU-рабочий стол** — нельзя (дедлок ядра).
- ℹ️ **Игры с окном — это не GL, а Direct3D**: маршрут — DXVK-Sarek (arm64ec) поверх того же
  Vulkan + этот же слой; `DXVK_HUD` — нельзя.

### Практический пример: Disciples II (DirectDraw, 2D)

Наличие аппаратного GL само по себе игру не ускоряет. Проверено на нашей плате:

| Попытка | Результат |
|---|---|
| `cnc-ddraw` (подмена `ddraw.dll` в каталоге игры) | чёрный экран при работающем звуке, откачено |
| родной D3D-рендерер игры `UseD3D=1` (через zink/PowerVR) | белый экран, откачено |
| встроенный `ddraw` Wine (софт) | ✅ работает: полный экран 1024×600, без артефактов |

Разбор попыток — в репозитории игры:
[`opi-zero-3w-disciples2/docs/RENDERER-EXPERIMENTS.md`](https://github.com/Haidegger22/opi-zero-3w-disciples2/blob/main/docs/RENDERER-EXPERIMENTS.md).
Причина: игра оборачивает DirectDraw сама (`C4dll-R.dll`). С учётом того, что отдельные
GLX-программы падают в вендорском компиляторе шейдеров, белый экран `UseD3D=1` тоже разумно
списать на блоб, а не на настройку игры.

## 8. Откат

```bash
PVR_STRIP_DISABLE=1 <app>                                                 # на один процесс
~/pvr-work/a733-powervr-fex/gpu/vk-feature-strip/install.sh --uninstall    # снять слой совсем
```

Вне `$HOME` ничего не меняется: без `PVR_FAKE_GS=1` слой инертен, манифест можно просто удалить.

## 9. Источники и авторство

- [`ayiejosh/a733-powervr-fex`](https://github.com/ayiejosh/a733-powervr-fex), ветка **trixie**
  (MIT) — рецепт zink для trixie, исходник слоя (`gpu/vk-feature-strip/`), разбор стен:
  `docs/FINDINGS.md`, `gpu/zink-trixie.md`, `docs/GPU-RESEARCH-2026-09-22.md`.
- [`davidhfrankelcodes/pvr-a733-armbian`](https://github.com/davidhfrankelcodes/pvr-a733-armbian)
  (MIT) — второй вариант слоя и лог воспроизведения на Armbian (вариант с блоком
  `device_extensions`, см. §4).
- Воспроизведение и проверка на Zero 3W: **28.09.2026**, Зеро (плата) и Джарвис (Pi 5) —
  сборка слоя, замеры `glxinfo`/`glmark2`/`glxgears`, трейс через gdb, разбор грабель,
  взаимная сверка документа.
- **Проприетарные бинарники здесь не публикуются** (DDK, `libVK_IMG.so`, firmware, `pvrsrvkm.ko`):
  они берутся из образа/репозитория производителя, см. основной README.
- Чужие документы целиком не копируются — только ссылки и выводы, с указанием авторства (MIT).
