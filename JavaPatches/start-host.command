#!/bin/bash
set -eu

fail() { echo "$*" >&2; exit 1; }
[ "$(uname -s)" = Darwin ] || fail 'This launcher requires macOS.'
[ "$#" -le 1 ] || fail 'Pass only the game directory containing projectzomboid.jar.'
game=${1:-"$HOME/Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents/Java"}
[ -d "$game" ] || fail "Game directory not found: $game"
cd "$game"
game=$PWD
for file in projectzomboid.jar ZombieBuddy.jar; do
    [ -f "$file" ] || fail "Missing $file in $game. Install the ZombieBuddy loader first."
done
case "$game" in *\"*) fail 'The game path cannot contain a double quote.' ;; esac
case "$(uname -m)" in
    arm64) runtime=jre-aarch64 ;;
    x86_64) runtime=jre-x86_64 ;;
    *) fail 'Unsupported macOS CPU architecture.' ;;
esac
java="../PlugIns/$runtime/Contents/Home/bin/java"
[ -x "$java" ] || fail "Bundled Java not found: $game/$java"
if printf '%s\n' "${JDK_JAVA_OPTIONS-}" "${JAVA_TOOL_OPTIONS-}" "${_JAVA_OPTIONS-}" | grep -qiE 'ZombieBuddy|zbNative'; then
    fail 'Remove the existing ZombieBuddy setting from JVM environment options to avoid loading it twice.'
fi

# Host's separate java process inherits this agent; bypass the client launcher and its plist options.
export JDK_JAVA_OPTIONS="${JDK_JAVA_OPTIONS:+$JDK_JAVA_OPTIONS }-javaagent:\"$game/ZombieBuddy.jar\""
export SteamAppId=108600 SteamGameId=108600
echo 'Leave Steam running, then select the required profile in Host.'
exec "$java" \
    -Djava.awt.headless=true \
    --enable-native-access=ALL-UNNAMED \
    --add-exports=java.base/jdk.internal.misc=ALL-UNNAMED \
    -XstartOnFirstThread \
    -Dzomboid.steam=1 -Dzomboid.znetlog=1 -Djava.library.path=. \
    -Xmx3072m -XX:+UseZGC -XX:-OmitStackTraceInFastThrow \
    -cp projectzomboid.jar zombie.gameStates.MainScreenState
