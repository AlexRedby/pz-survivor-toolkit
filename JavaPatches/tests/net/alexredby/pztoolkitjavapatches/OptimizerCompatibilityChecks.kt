package net.alexredby.pztoolkitjavapatches

/** Policy regressions run against genuine native resources, without loading optimizer classes. */
object OptimizerCompatibilityChecks {
    private fun verify(value: Boolean, reason: String) {
        if (!value) throw AssertionError(reason)
    }

    @JvmStatic
    fun main(args: Array<String>) {
        val pinned = OptimizerCompatibility.profileProperties()
        val profile = OptimizerCompatibility.PROFILE_ID
        verify(
            pinned["pzopt.bakeBudget"] == "8",
            "FBO scheduler consumption requires a positive outer budget",
        )
        verify(pinned.size == 770, "complete reviewed configuration was not retained")
        verify(OptimizerCompatibility.alternatives.size == 20, "reviewed pair set changed")
        verify(
            OptimizerCompatibility.configurationMatches(profile, pinned),
            "exact profile rejected",
        )
        verify(
            !OptimizerCompatibility.configurationMatches(null, pinned),
            "implicit profile admitted",
        )
        verify(
            !OptimizerCompatibility.configurationMatches(profile + "-unknown", pinned),
            "unknown profile admitted",
        )
        verify(
            !OptimizerCompatibility.configurationMatches(profile, emptyMap()),
            "missing configuration admitted",
        )

        // Every key is required, including disabled feature pins and empty developer values.
        for ((key, value) in pinned) {
            val changed = HashMap(pinned)
            changed.remove(key)
            verify(
                !OptimizerCompatibility.configurationMatches(profile, changed),
                "missing pin admitted: $key",
            )
            changed[key] = value + "-changed"
            verify(
                !OptimizerCompatibility.configurationMatches(profile, changed),
                "changed pin admitted: $key",
            )
        }
        verify(
            !OptimizerCompatibility.configurationMatches(
                profile,
                pinned + ("pzopt.unknownFutureFeature" to "true"),
            ),
            "unknown optimizer configuration admitted",
        )

        for ((resource, pair) in OptimizerCompatibility.alternatives) {
            verify(
                OptimizerCompatibility.reviewedAlternative(
                    resource,
                    pair.nativeSha256,
                    pair.officialSha256,
                ),
                "reviewed exact triple rejected: $resource",
            )
            verify(
                !OptimizerCompatibility.reviewedAlternative(
                    resource + ".unknown",
                    pair.nativeSha256,
                    pair.officialSha256,
                ),
                "wrong resource admitted: $resource",
            )
            verify(
                !OptimizerCompatibility.reviewedAlternative(
                    resource,
                    pair.officialSha256,
                    pair.officialSha256,
                ),
                "wrong expected native contract admitted: $resource",
            )
            verify(
                !OptimizerCompatibility.reviewedAlternative(
                    resource,
                    pair.nativeSha256,
                    pair.officialSha256.reversed(),
                ),
                "unknown actual bytes admitted: $resource",
            )
        }
        verify(
            !OptimizerCompatibility.reviewedAlternative(null, null, null),
            "null triple admitted",
        )
        verify(
            !OptimizerCompatibility.pinnedResourcesMatch { null },
            "missing build resources admitted",
        )
        verify(
            !OptimizerCompatibility.pinnedResourcesMatch { "0".repeat(64) },
            "wrong build resources admitted",
        )

        val system = System.getProperties()
        synchronized(system) {
            val saved =
                system.entries
                    .filter {
                        it.key == OptimizerCompatibility.PROFILE_PROPERTY ||
                            (it.key as? String)?.startsWith("pzopt.") == true
                    }
                    .associate { it.key to it.value }
            try {
                for (key in saved.keys) system.remove(key)
                for ((resource, pair) in OptimizerCompatibility.alternatives) {
                    verify(
                        BytecodeSupport.supports(resource, pair.nativeSha256),
                        "native baseline changed: $resource",
                    )
                    verify(
                        !OptimizerCompatibility.supports(
                            resource,
                            pair.nativeSha256,
                            pair.officialSha256,
                        ),
                        "official alternative admitted without opt-in: $resource",
                    )
                }
                system[OptimizerCompatibility.PROFILE_PROPERTY] = profile
                for ((key, value) in pinned) system[key] = value
                // Claims about the ZIP/profile cannot replace the real classpath streams: this
                // test process has native classes, so the exact official resource set is absent.
                for ((resource, pair) in OptimizerCompatibility.alternatives) {
                    verify(
                        !OptimizerCompatibility.supports(
                            resource,
                            pair.nativeSha256,
                            pair.officialSha256,
                        ),
                        "profile substituted for actual official resources: $resource",
                    )
                    verify(
                        BytecodeSupport.supports(resource, pair.nativeSha256),
                        "opt-in changed native admission: $resource",
                    )
                    verify(
                        !BytecodeSupport.supports(resource, pair.officialSha256),
                        "expected-hash spoof admitted: $resource",
                    )
                }
                verify(
                    !BytecodeSupport.supports("missing/Unknown.class", "0".repeat(64)),
                    "missing class admitted",
                )
            } finally {
                for (key in system.keys.toList()) {
                    if (
                        key == OptimizerCompatibility.PROFILE_PROPERTY ||
                            (key as? String)?.startsWith("pzopt.") == true
                    ) {
                        system.remove(key)
                    }
                }
                system.putAll(saved)
            }
        }
        println(
            "OPTIMIZER_COMPATIBILITY_CHECKS_PASS (20 exact triples; every configuration pin missing/changed; real native resources retained)",
        )
    }
}
