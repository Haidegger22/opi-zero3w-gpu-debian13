# Аппаратный Desktop-OpenGL на Zero 3W — zink поверх PowerVR Vulkan

> Как из «GLX всегда llvmpipe» получить **аппаратный desktop OpenGL**: zink (GL поверх Vulkan)
> + слой `VK_LAYER_PVR_strip`, который снимает два несовместимых требования.
> Проверено на Zero 3W: **28.09.2026**, Debian 13 trixie, ядро `6.6.98-sun60iw2`,
> Mesa `25.0.7-2+deb13u1`, вендорский DDK `24.2.6603887`, gcc 14.2.

> ⚠️ Это **дополнение** к основному README. Он остаётся верным: вендорский стек даёт
> аппаратные Vulkan / GLES(EGL) / OpenCL, а **GLX-окно** у проприетарного драйвера как не
> работало, так и не работает. Новое здесь только одно: сам **рендерер** desktop-OpenGL
> может быть аппаратным (zink), если приложению достаточно off-screen/EGL.

---

## 1. Что было и что стало

| Проверка | До слоя | После слоя |
|---|---|---|
| `glxinfo -B` → renderer | `llvmpipe (LLVM 19.1.7, 128 bits)` | `zink Vulkan 1.3(PowerVR B-Series BXM-4-64 MC1 (IMAGINATION_PROPRIETARY))` |
| `glxinfo -B` → version | `4.5 (Compatibility Profile) Mesa 25.0.7` | `2.1 Mesa 25.0.7` (**аппаратно**) |
| `GL_RENDERER` (EGL) | PowerVR B-Series BXM-4-64 | PowerVR B-Series BXM-4-64 |
| `vulkaninfo --summary` | PowerVR, 1.3.277 | PowerVR, 1.3.277 |

До слоя Mesa прямо говорит, почему уходит в софт:

```
MESA: error: zink: Imagination proprietary driver w/o geometryShader is unsupported
libEGL warning: egl: failed to create dri2 screen
```

## 2. Почему без слоя не получается

1. **Mesa не содержит GL-драйвера для этого GPU.** Аппаратный путь есть только у Vulkan
   (вендорский ICD `img_icd.json`) и GLES через вендорский EGL.
2. **zink — единственный мост** «GL → Vulkan», но он требует
   `VkPhysicalDeviceFeatures.geometryShader`, а блоб PowerVR сообщает по нему `false`.
   Без этого бита zink отказывается инициализироваться (строка выше) и Mesa падает в llvmpipe.
3. **Вендорский GL-блоб для окна не годится:** его `libEGL`/`pvr_dri.so` из `/usr/local`
   вешают инициализацию графики у GLX-приложений (у Wine это `err:wgl:internal_context_create`
   и зависший `wineboot`). Трогать его не нужно — маршрут другой.
4. **Решение (внешнее):** Vulkan-слой, который **на опросе** сообщает, что `geometryShader`
   есть, а перед `vkCreateDevice` **вырезает** этот бит из запроса — блоб никогда не просят
   включить то, чего у него нет. Второй бит, `VK_EXT_robustness2.nullDescriptor`, нужен только
   свежему zink (Mesa ≥ 26) и включается отдельно — см. грабли.

Автор рецепта и среды сборки слоя — внешний проект, мы воспроизвели и проверили на плате
(раздел «Источники и авторство»).

## 3. Установка

**Предпосылки:** работает вендорский Vulkan (`vulkaninfo --summary` → PowerVR 1.3.277,
см. основной README), Mesa из trixie стоит и не менялась, есть `gcc`.

```bash
# 1) исходник слоя
git clone -b trixie https://github.com/ayiejosh/a733-powervr-fex.git ~/pvr-work/a733-powervr-fex

# 2) сборка + установка (кладутся только манифест и .so в домашний каталог)
cd ~/pvr-work/a733-powervr-fex/gpu/vk-feature-strip
./install.sh
#   → ~/.local/share/vulkan/implicit_layer.d/libVkLayer_PVR_strip.so
#     ~/.local/share/vulkan/implicit_layer.d/VkLayer_PVR_strip.json
```

То же самое делает наш скрипт (плюс проверка результата сразу после установки):

```bash
scripts/opengl-zink-install.sh            # клонировать/обновить слой, собрать, установить, проверить
scripts/opengl-zink-install.sh --uninstall
```

**Важно:** слой нельзя ставить вместе с другой реализацией под тем же именем
`VK_LAYER_PVR_strip` (в природе есть более старая версия на переменных
`PVR_STRIP_ENABLE`/`PVR_STRIP_DISABLE`). Лоадер выберет одну и **молча проигнорирует**
переменные второй — слой будет «как будто ничего не делать». `install.sh` такую коллизию
находит и отказывается ставить.

## 4. Включение и проверка

**Наш проверенный вариант** (полное окружение, так сняты все замеры ниже):

```bash
env -u LD_LIBRARY_PATH \
    PVR_FAKE_GS=1 \
    VK_LAYER_PATH=$HOME/.local/share/vulkan/implicit_layer.d \
    VK_INSTANCE_LAYERS=VK_LAYER_PVR_strip \
    GALLIUM_DRIVER=zink MESA_LOADER_DRIVER_OVERRIDE=zink \
    LD_LIBRARY_PATH=/usr/lib/aarch64-linux-gnu:/lib/aarch64-linux-gnu \
    LIBGL_DRIVERS_PATH=/usr/lib/aarch64-linux-gnu/dri \
    VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/img_icd.json \
    DISPLAY=:0 glxinfo -B
```

Ждём в выводе:
`OpenGL renderer string: zink Vulkan 1.3(PowerVR B-Series BXM-4-64 MC1 (IMAGINATION_PROPRIETARY))`.

Окружение без повторения руками — в `scripts/opengl-zink-env.sh` (`. scripts/opengl-zink-env.sh`),
полная проверка «до/после» — `scripts/opengl-zink-verify.sh`.

**Доказать, что загрузился именно слой:**

```bash
VK_LOADER_DEBUG=layer PVR_FAKE_GS=1 <ваше GL-приложение> 2>&1 | grep -i pvr_strip
```

**Вариант «одной переменной»** (по документации слоя: манифест установлен как *implicit*,
поэтому достаточно `PVR_FAKE_GS=1 <app>`) — на нашей плате он проходит, но замеры сняты
полным окружением выше.

### Способы включения и их ловушки

| Способ | Как | Нюанс |
|---|---|---|
| implicit (**рекомендуется**) | `./install.sh` → манифест в `~/.local/share/vulkan/implicit_layer.d/` → `PVR_FAKE_GS=1 <app>` | у implicit-манифеста **обязателен** `disable_environment`, иначе лоадер молча пропускает слой (`Didn't find required layer object disable_environment ... skipping`) |
| explicit | `VK_LAYER_PATH=<каталог> VK_INSTANCE_LAYERS=VK_LAYER_PVR_strip PVR_FAKE_GS=1 <app>` | explicit-слой не включается сам: `enable_environment` для него не работает, имя обязательно в `VK_INSTANCE_LAYERS` |
| выключить на процесс | `PVR_STRIP_DISABLE=1 <app>` | — |
| снять совсем | `.../vk-feature-strip/install.sh --uninstall` | удаляет `.so` + манифест, всё в `$HOME` |

Ещё две ловушки манифеста (обе стоили отладки на `libvulkan1 1.4.309`):

- не перечислять `VK_EXT_robustness2` в `device_extensions` манифеста: лоадер добавит его
  приложениям **независимо от переключателя**, и `vkCreateDevice` упадёт с
  `VK_ERROR_FEATURE_NOT_PRESENT` (замер: 115 расширений вместо 114);
- имя слоя одно: два манифеста с одним именем → выбран будет один.

## 5. Замеры

**Наш Zero 3W** (28.09.2026) — строки `glxinfo -B`, см. таблицу в разделе 1.

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

Вывод: аппаратный GL через zink даёт примерно **70 %** от вендорского GLES на той же плате.
Потолок аппаратного GL на этом блобе — **GL 2.1 / GLES 2.0**.

## 6. Грабли (каждая проверена и стоила времени)

- **`zink` без слоя не стартует** — `geometryShader` у блоба `false`.
- **`fillModeNonSolid` у блоба нет.** zink предупреждает об этом при инициализации: сплошная
  заливка рисуется корректно, каркас и неполная заливка (`glPolygonMode`) — ненадёжны.
- **Mesa ≥ 26 не обновлять.** zink 26+ требует `VK_EXT_robustness2.nullDescriptor`, а блоб
  этого расширения не знает вовсе: `PVR_FAKE_R2=1` проходит проверку и **падает** внутри
  `libVK_IMG.so` при первом же null descriptor. Рабочая версия — системная **25.0.7**.
- **GPU-композитор запрещён.** Композитор, рисующий на GPU через `pvrsrvkm`, вешает ядро
  (`mutex_spin_on_owner` в IRQ → лечится только power-cycle). Поэтому программный рабочий стол
  и `LIBGL_ALWAYS_SOFTWARE=1` — это **защита, а не костыль**: не включать glamor, не поднимать
  Wayland-композитор на GPU, **не ставить `DXVK_HUD`** (тот же класс отказа).
- **GLX-окно не поднимается**: у X-сервера нет подходящих визуалов
  (`couldn't get an RGB double-buffered visual`). Доступен только off-screen/EGL. После
  успешного определения рендерера `eglinfo` всё равно заканчивается `eglInitialize failed` —
  это не дефект слоя, а следующая стена.
- **Двойная Mesa.** Вендорский стек в `/usr/local` имеет приоритет по `ldconfig`, поэтому
  путь zink обязан запускаться со scoped `LD_LIBRARY_PATH` на системную Mesa (в блоке выше —
  `env -u LD_LIBRARY_PATH LD_LIBRARY_PATH=/usr/lib/aarch64-linux-gnu:...`).
- **Блоб сообщает 114 device extensions** и не имеет `descriptor_buffer`, resizable BAR и
  `non_seamless_cube_map` — отсюда вывод «просто поставить новее Mesa» ничего не даёт.
- **Слой одноустройственный**: одна статическая пара `g_inst`/`g_dev`, без карты
  dispatch-таблиц по хэндлу. Годится для `glxinfo`/`eglinfo`/`glmark2` и однопроцессных
  приложений; для многопоточных/многопрефиксных — не универсален.
- **Фейк настоящих geometry-шейдеров уронил бы блоб** (на headless-плате это power-cycle),
  поэтому подделка — исключительно на опрос, а не на исполнение. Отдельно это не проверялось
  и проверять не советуем.

## 7. Что это даёт и чего не даёт

- ✅ **Аппаратный desktop OpenGL** приложениям, которым достаточно **off-screen/EGL**
  (рендер в FBO, headless-сцены, GL-вычисления). Быстрее llvmpipe.
- ✅ Потолок **GL 2.1 / GLES 2.0** — этого хватает 2D-графике и старому софту, но не
  современным GL-играм.
- ❌ **Окно через GLX** — нет (нет визуалов у X-сервера). Приложения с окном идут другим
  маршрутом.
- ❌ **Игры с окном — это не GL, а Direct3D**: route = DXVK-Sarek (arm64ec) поверх того же
  Vulkan + этот же слой. Тот же слой обязателен, `DXVK_HUD` — нельзя.
- ❌ **GPU-композитор и GPU-рабочий стол** — нельзя (дедлок ядра).

### Практический пример: Disciples II (DirectDraw, 2D)

Наличие аппаратного GL само по себе игру не ускоряет. Проверено на нашей плате:

| Попытка | Результат |
|---|---|
| `cnc-ddraw` (подмена `ddraw.dll` в каталоге игры) | чёрный экран при работающем звуке, откачено |
| родной D3D-рендерер игры `UseD3D=1` (через zink/PowerVR) | белый экран, откачено |
| встроенный `ddraw` Wine (софт) | ✅ работает: полный экран 1024×600, без артефактов |

Разбор попыток — в репозитории игры:
[`opi-zero-3w-disciples2/docs/RENDERER-EXPERIMENTS.md`](https://github.com/Haidegger22/opi-zero-3w-disciples2/blob/main/docs/RENDERER-EXPERIMENTS.md).
Причина: игра оборачивает DirectDraw сама (`C4dll-R.dll`), а D3D7-путь через zink без
`fillModeNonSolid` не рисует. То есть для DirectDraw-игр окно закрыто.

## 8. Откат

```bash
PVR_STRIP_DISABLE=1 <app>                                        # на один процесс
~/pvr-work/a733-powervr-fex/gpu/vk-feature-strip/install.sh --uninstall   # снять слой совсем
```

Вне `$HOME` ничего не меняется: без `PVR_FAKE_GS=1` слой инертен, манифест можно просто удалить.
Замеры и скриншоты — в репозитории игры, раздел графики.

## 9. Источники и авторство

- [`ayiejosh/a733-powervr-fex`](https://github.com/ayiejosh/a733-powervr-fex), ветка **trixie**
  (MIT) — рецепт zink для trixie, исходник слоя (`gpu/vk-feature-strip/`), разбор стен:
  `docs/FINDINGS.md`, `gpu/zink-trixie.md`, `docs/GPU-RESEARCH-2026-09-22.md`.
- [`davidhfrankelcodes/pvr-a733-armbian`](https://github.com/davidhfrankelcodes/pvr-a733-armbian)
  (MIT) — второй вариант слоя и лог воспроизведения на Armbian.
- Воспроизведение и проверка на Zero 3W: **28.09.2026**, Зеро (плата) и Джарвис (Pi 5) —
  сборка слоя, замеры, разбор грабель.
- **Проприетарные бинарники здесь не публикуются** (DDK, `libVK_IMG.so`, firmware, `pvrsrvkm.ko`):
  они берутся из образа/репозитория производителя, см. основной README.
- Чужие документы целиком не копируются — только ссылки и выводы, с указанием авторства (MIT).
