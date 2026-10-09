# PZ Network Fix (Experimental)

`PZNetworkFix` — необязательный Java-мод для Project Zomboid B42.21. Нужен ZombieBuddy версии 2.3.4 или новее; сам PZ Survivor Toolkit мод не включает. Это экспериментальный патч: он не обещает исправить минутные зависания машин или все сетевые рывки.

## Сборка (Windows)

На компьютере для сборки нужны Python 3 и **JDK 25 или новее**: JDK 21 не читает классы этой версии игры. Встроенной Java игры для сборки недостаточно. Установите ZombieBuddy на каждый клиент, включая Host, по [инструкции разовой настройки](../MOD_INSTALL.md#zombiebuddy-разовая-настройка-клиента).

Для сборки `ZombieBuddy.jar` должен находиться в той же Java-папке игры, что и `projectzomboid.jar`. Из корня репозитория выполните:

```powershell
py -3 NetworkFix/build.py --game "D:\SteamLibrary\steamapps\common\ProjectZomboid"
```

Замените пример своим путём. `--game` указывает папку, содержащую оба файла: `projectzomboid.jar` и `ZombieBuddy.jar`. JDK ищется через `JAVA_HOME`, системный механизм macOS или `PATH`. Если выбран старый JDK, добавьте `--jdk "C:\path\to\jdk-25"` с путём к установленному JDK 25.

Скрипт читает игровые зависимости и записывает результат в `NetworkFix/build/`. Необязательная проверка совместимости: добавьте `--check`.

## Установка

При закрытой игре скопируйте всю папку `NetworkFix/build/PZNetworkFix` в `%USERPROFILE%\Zomboid\mods` на Windows (`~/Zomboid/mods` на macOS/Linux). Одну и ту же собранную папку передайте всем игрокам и на Host/сервер, если его профиль включает этот мод.

В меню Mods каждого клиента включите сначала **ZombieBuddy**, затем **PZ Network Fix (Experimental)**. В выбранном профиле Host включите оба мода. В запросе ZombieBuddy разрешите загрузку JAR **PZNetworkFix**.

У мода нет Workshop ID; не добавляйте его в `WorkshopItems=`. Серверный INI по умолчанию в Toolkit остаётся без Network Fix.
