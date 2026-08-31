package com.example.eink_launcher

import org.junit.Assert.*
import org.junit.Test

class StartupHealthPolicyTest {
    @Test fun threeUnfinishedLaunchesEnterRecoveryOnTheFourth() {
        var state = StartupHealthPolicy()
        for (launch in 0..2) {
            state = state.nextLaunch(1000L + launch * 1000)
            assertFalse(state.shouldRecover)
        }
        state = state.nextLaunch(4000)
        assertTrue(state.shouldRecover)
    }

    @Test fun healthyLaunchResetsTheFailureSequence() {
        val healthy = StartupHealthPolicy(pending = false, failures = 2, windowStartMillis = 1000)
        assertEquals(0, healthy.nextLaunch(2000).failures)
    }

    @Test fun oldFailuresAndClockRollbackDoNotTriggerRecovery() {
        val failed = StartupHealthPolicy(pending = true, failures = 3, windowStartMillis = 1000)
        assertFalse(failed.nextLaunch(1001 + StartupHealthPolicy.WINDOW_MILLIS).shouldRecover)
        assertFalse(failed.nextLaunch(500).shouldRecover)
    }

    @Test fun malformedCountsCannotOverflow() {
        assertTrue(StartupHealthPolicy(true, Int.MAX_VALUE, 1000).nextLaunch(2000).shouldRecover)
        assertFalse(StartupHealthPolicy(true, Int.MIN_VALUE, 1000).nextLaunch(2000).shouldRecover)
    }

    @Test fun repeatedLaunchesDoNotExtendTheTenMinuteWindow() {
        var state = StartupHealthPolicy().nextLaunch(1000)
        state = state.nextLaunch(1000 + 4 * 60 * 1000L)
        state = state.nextLaunch(1000 + 8 * 60 * 1000L)
        state = state.nextLaunch(1000 + 12 * 60 * 1000L)
        assertFalse(state.shouldRecover)
        assertEquals(0, state.failures)
    }
}
