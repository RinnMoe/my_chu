package moe.rinn.mychu

import org.junit.Assert.assertEquals
import org.junit.Test

class ScheduledAlertModeResolverTest {
    @Test
    fun exactRequiresUserRequestAndSystemAuthorization() {
        assertEquals(
            ScheduledAlertAlarmMode.EXACT,
            ScheduledAlertModeResolver.resolve(requested = true, authorized = true),
        )
        assertEquals(
            ScheduledAlertAlarmMode.INEXACT,
            ScheduledAlertModeResolver.resolve(requested = false, authorized = true),
        )
        assertEquals(
            ScheduledAlertAlarmMode.INEXACT,
            ScheduledAlertModeResolver.resolve(requested = true, authorized = false),
        )
    }
}
