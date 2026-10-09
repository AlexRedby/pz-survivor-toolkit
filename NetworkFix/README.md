# PZ Network Fix (Experimental)

Отдельный Java-мод в этом репозитории. Mod ID: `PZNetworkFix`. Его можно использовать независимо от PZ Survivor Toolkit; включение Toolkit само по себе Network Fix не включает.

Версия 0.1.0 рассчитана на **Project Zomboid B42.21** и **ZombieBuddy 2.3.4 или новее**. Сейчас мод исправляет два конкретных случая: неверный масштаб скорости удалённых зомби и скачок интерполяции машины после опустошения буфера обновлений. При изменении байткода соответствующих классов исправления отключаются.

Это экспериментальный патч. Он пока **не исправляет подтверждённо** минутное зависание машины у хоста, дальние телепортации или все рывки при совместном бою. Проверены нативная регрессия интерполяции и короткий локальный MP-тест с двумя клиентами и передачей управления зомби. Езда с задержкой/потерями пакетов, длительные сессии и полный набор модов ещё не проверены.

## 1. Установить ZombieBuddy

Каждому игроку, включая владельца Host, нужен Java-загрузчик ZombieBuddy. Одной подписки в Workshop недостаточно.

1. Закройте игру, подпишитесь на [ZombieBuddy](https://steamcommunity.com/sharedfiles/filedetails/?id=3619862853) и дождитесь загрузки.
2. На Windows используйте официальный [ZombieBuddyInstaller.exe](https://github.com/zed-0xff/ZombieBuddy/releases/tag/windows_installer): **Install or update ZombieBuddy**, затем **Both** для обычного и альтернативного запуска.
3. На macOS/Linux скопируйте `ZombieBuddy.jar` из `steamapps/workshop/content/108600/3619862853/mods/ZombieBuddy/libs/` в Java-папку игры и задайте в Steam параметры запуска `-javaagent:ZombieBuddy.jar --`. На macOS Java-папка находится внутри `Project Zomboid.app/Contents/Java/`, на Linux обычно это `ProjectZomboid/projectzomboid/`. Последние два дефиса обязательны.

Если загрузчик уже установлен для другого мода, повторная настройка не нужна. Подробности есть в [инструкции ZombieBuddy](https://github.com/zed-0xff/ZombieBuddy/blob/master/doc/Installation.md) и [нашем руководстве](../MOD_INSTALL.md#zombiebuddy-разовая-настройка-клиента). После проверки файлов игры Steam может понадобиться восстановить загрузчик.

## 2. Собрать Network Fix

В Git находятся исходники; готовые JAR/ZIP и библиотеки игры не включены. Достаточно собрать мод на одном компьютере и передать полученную папку остальным участникам.

Нужны **Python 3**, **JDK 17 или новее** с `javac` и `jar`, установленная B42.21 и `ZombieBuddy.jar` в Java-папке игры. Встроенной в игру JRE недостаточно для сборки. Скрипт не скачивает зависимости.

Из корня репозитория на macOS с обычной Steam-библиотекой:

```sh
python3 NetworkFix/build.py --check
```

Для другой установки укажите **папку, содержащую `projectzomboid.jar` и `ZombieBuddy.jar`**, и папку JDK, содержащую `bin`:

```sh
python3 NetworkFix/build.py --game "/path/to/game/Java" --jdk "/path/to/jdk" --check
```

На Windows пример для PowerShell; замените пути на свои:

```powershell
py -3 NetworkFix/build.py --game "C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid" --jdk "C:\path\to\jdk"
```

Без `--jdk` скрипт использует `JAVA_HOME`, затем системный JDK. `--check` дополнительно запускает регрессию на установленном движке; успешное завершение отмечается строкой `NATIVE_CHECKS_PASS`, результат сохраняется в `NetworkFix/build/native-checks.log`. Эта проверка не заменяет игру по сети и проверена на macOS B42.21.

Результат сборки:

```text
NetworkFix/build/PZNetworkFix/
  common/
  42/mod.info
  42/media/java/client/PZNetworkFix.jar
```

## 3. Установить и включить

1. При закрытой игре скопируйте **`NetworkFix/build/PZNetworkFix` целиком** в папку модов. На Windows это `%USERPROFILE%\Zomboid\mods`, на macOS/Linux — `~/Zomboid/mods`; при `-cachedir` используйте папку `mods` внутри указанного каталога.
2. Проверьте файл `Zomboid/mods/PZNetworkFix/42/mod.info` и JAR рядом с ним по пути `42/media/java/client/PZNetworkFix.jar`. Сохраните подпапки `common` и `42`; двойной вложенности `PZNetworkFix/PZNetworkFix` быть не должно.
3. В меню **Mods** включите **ZombieBuddy**, затем **PZ Network Fix (Experimental)**. Для Host добавьте оба мода также в настройки выбранного серверного профиля. При ручном редактировании INI добавьте `PZNetworkFix` в существующую строку `Mods=` после `ZombieBuddy`, сохранив остальные моды и их порядок. Для профиля только с этими модами строка выглядит так:

   ```ini
   Mods=ZombieBuddy;PZNetworkFix
   WorkshopItems=3619862853
   ```

   Network Fix не имеет Workshop ID. Не добавляйте выдуманный ID в `WorkshopItems=` и не заменяйте этими двумя строками список своего набора. Наш `SurvivorQoL-selected.ini` не включает экспериментальный патч автоматически.
4. Одну и ту же собранную папку передайте **всем игрокам**, включая владельца Host. При подключении Network Fix автоматически не скачивается. Серверу также нужна копия папки, если его профиль включает этот Mod ID; для выделенного сервера Java-загрузчик ради Network Fix не требуется: исправления действуют только на клиентах.
5. Полностью перезапустите игру. В запросе ZombieBuddy разрешите загрузку JAR мода **PZNetworkFix**. После замены JAR он может запросить разрешение снова.

## Проверить загрузку и удалить

На экране загрузки/в главном меню должна появиться надпись **ZombieBuddy … loaded**. В клиентском логе `Zomboid/console.txt` найдите:

```text
[PZNetworkFix] Experimental B42.21 patch: zombie=true, vehicle=true
```

Строка подтверждает загрузку и совпадение поддерживаемых классов, а не устранение всех сетевых проблем. `false` означает, что соответствующий патч отключён. Если строки нет, проверьте включение мода, установку загрузчика и разрешение JAR. После обновления игры не отключайте проверку совместимости вручную.

Чтобы удалить патч, закройте игру, уберите `PZNetworkFix` из выбранных модов и `Mods=` серверного профиля, затем удалите папку `Zomboid/mods/PZNetworkFix`. ZombieBuddy оставьте, если он нужен другим модам. Патч не заменяет JAR игры и не записывает исправления в сохранение.
