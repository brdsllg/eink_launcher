package com.example.eink_launcher

/** Pure policy so crash-loop decisions can be verified without a device. */
internal data class StartupHealthPolicy(
    val pending: Boolean = false,
    val failures: Int = 0,
    val windowStartMillis: Long = 0,
) {
    fun nextLaunch(now: Long): StartupHealthPolicy {
        val age = now - windowStartMillis
        val recentFailure = pending && age in 0..WINDOW_MILLIS
        return StartupHealthPolicy(
            pending = true,
            failures = if (recentFailure) failures.coerceIn(0, 3) + 1 else 0,
            windowStartMillis = if (recentFailure) windowStartMillis else now,
        )
    }

    val shouldRecover: Boolean get() = failures >= 3

    companion object {
        const val WINDOW_MILLIS = 10 * 60 * 1000L
    }
}
