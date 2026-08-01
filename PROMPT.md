# Промпт для ИИ-агента на macOS

Скопируй всё, что ниже разделителя, в Claude Code / другого агента на маке.

---

## ЗАДАЧА

Собрать iOS-твик (Theos, `.deb`) под джейлбрейк **RootHide** и вернуть путь к готовому
пакету. Устанавливать на устройство не нужно — только сборка.

Исходники:

```bash
git clone git@github.com:kenzWeb/injustice-mod.git && cd injustice-mod
```

Перед работой прочитай `HANDOFF.md` — там весь контекст проекта: что за бинарь,
откуда взят каждый офсет и что уже проверено.

Проект `InjusticeMod`: оверлей-меню для игры Injustice 2 Mobile 6.7.1. Хукает две
нативные функции через `MSHookFunction` и рисует плавающее окно UIKit. Исходники
разложены по слоям в `src/`, точка входа — `Tweak.xm`.

## ОКРУЖЕНИЕ

macOS с Xcode Command Line Tools. Нужен **форк Theos от roothide** — в стоковом Theos
нет схемы упаковки `roothide`, сборка на ней падает.

```bash
xcode-select --install 2>/dev/null || true
brew install ldid xz

export THEOS=~/theos-roothide
git clone --recursive https://github.com/roothide/theos "$THEOS"
```

SDK скачивать не надо: на macOS Theos берёт iPhoneOS SDK из Xcode, а твик использует
только публичные фреймворки (UIKit, QuartzCore, Foundation) плюс `substrate.h`,
который лежит в самом Theos.

## СБОРКА

Основной способ — скрипт в репозитории:

```bash
cd injustice-mod
./build.sh          # обычная сборка
./build.sh -c       # чистая (сносит .theos)
./build.sh -p -c    # git pull, затем чистая сборка
```

Он нужен не для красоты: **Theos отказывается собирать из пути с пробелом**
(`common.mk:45: Your project is located at ... which contains spaces`), а
репозиторий у владельца лежит в `.../injustice 2/`. Скрипт зеркалит дерево во
временный каталог, собирает там и копирует `.deb` обратно в `packages/`.

Если путь заведомо без пробелов, можно и напрямую:

```bash
export THEOS=~/theos-roothide
make package FINALPACKAGE=1
```

Готовый пакет появится в `./packages/*.deb`.

**Про имя файла.** В форке roothide `vendor/mod/roothide/package/deb.mk`
безусловно выставляет `THEOS_PACKAGE_ARCH := iphoneos-arm64e`, перебивая поле
`Architecture:` из `control` и не завися от `ARCHS`. Поэтому пакет **всегда**
получает суффикс `_iphoneos-arm64e.deb`. Ориентируйся на поле `Version`, а не
на арх-суффикс.

## КРИТИЧНО

1. **Не менять значения в `src/Offsets.h`.** Это RVA, снятые статическим анализом
   конкретного бинаря Injustice2Mobile 6.7.1 (Mach-O UUID
   `2c66bd15-78e2-3cab-b3f6-2be3ff279a18`). Любая «поправка» их сломает.
2. **Не менять логику** в `IMDamage.m`, `IMHooks.m`, `IMRuntime.m` и
   `IMOverlayWindow.m`. Последнее особенно: без passthrough в `hitTest:` оверлей
   перехватывает все касания и игра становится некликабельной.
3. **Комментариев в исходниках нет намеренно** — не добавляй. Вся справочная
   информация в `HANDOFF.md`.
4. Если компилятор ругается — чини **минимально** (синтаксис, депрекейты, порядок
   объявлений) и в отчёте перечисли построчно, что именно поменял и почему.
5. Не добавлять никаких сетевых запросов, аналитики и обращений к ФС. Твик их не имеет
   намеренно: на RootHide рандомизированный jbroot, и любой хардкод путей всё сломает.

## ТИПОВЫЕ ОШИБКИ

| Симптом | Причина / что делать |
|---|---|
| `Unknown package scheme 'roothide'` | взят стоковый Theos — нужен форк roothide |
| `substrate.h: No such file` | Theos склонирован без `--recursive`, либо `$THEOS` не выставлен |
| `ldid: command not found` | `brew install ldid` |
| `Your project is located at ... which contains spaces` | собирать через `./build.sh`, он зеркалит дерево во временный каталог |
| `Undefined symbols`, `NOTE: found '_IMxxx' ... missing 'extern "C"'` | новый заголовок включён из `Tweak.xm` без обёртки `extern "C"` — см. `HANDOFF.md` |
| `No rule to make target` | запуск не из папки с Makefile |
| `ld: warning: -multiply_defined is obsolete` | ворнинг линкера Theos, к коду отношения не имеет |
| `Could not find or use auto-linked framework 'UIUtilities'` | авто-линковка модуля UIKit в SDK 26, на пакет не влияет |
| ворнинги на `atomic_*` / `MSHookFunction` | игнорировать, это не ошибки |

Обе архитектуры (`arm64`, `arm64e`) собираются без ошибок, убирать `arm64e` из
`ARCHS` не нужно. Игра arm64-only, поэтому в её процессе грузится arm64-слайс,
а arm64e-слайс в fat-dylib просто не используется.

## ЧТО ВЕРНУТЬ

1. Полный вывод сборки (или хотя бы все ошибки/ворнинги).
2. Абсолютный путь к собранному `.deb` и его размер.
3. Вывод `dpkg-deb -I <deb>` и `dpkg-deb -c <deb>` — сверять **`Version`**,
   имя файла всегда с суффиксом `arm64e`.
4. Список изменений, если что-то пришлось править.
