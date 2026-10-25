/* Test-process-only model of CGDisplayIsAsleep. It does not change any display.
 * Use only in the native regression subprocess, never in the game runner or its
 * real CoreGraphics observer. The original GLFW must lose its primary monitor;
 * the reviewed private copy must still render and read back a real NSGL pixel.
 */
#include <CoreGraphics/CoreGraphics.h>

static boolean_t report_asleep(CGDirectDisplayID display) {
    (void) display;
    return 1;
}

__attribute__((used)) static struct {
    const void *replacement;
    const void *original;
} interposition __attribute__((section("__DATA,__interpose"))) = {
    (const void *) report_asleep, (const void *) CGDisplayIsAsleep
};
