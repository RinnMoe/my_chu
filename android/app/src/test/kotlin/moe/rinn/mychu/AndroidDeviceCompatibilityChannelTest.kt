package moe.rinn.mychu

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AndroidDeviceCompatibilityChannelTest {
    @Test
    fun onlyKnownDeviceOsSignalsAreAccepted() {
        assertTrue(AndroidDeviceCompatibilityChannel.isKnownFeature("hyper_os"))
        assertTrue(AndroidDeviceCompatibilityChannel.isKnownFeature("harmony_os"))
        assertTrue(AndroidDeviceCompatibilityChannel.isKnownFeature("ui_360"))
        assertFalse(AndroidDeviceCompatibilityChannel.isKnownFeature("ro.product.model"))
        assertFalse(AndroidDeviceCompatibilityChannel.isKnownFeature("getprop ro.product.model"))
        assertFalse(AndroidDeviceCompatibilityChannel.isKnownFeature("SystemProperties"))
        assertFalse(AndroidDeviceCompatibilityChannel.isKnownFeature("shell"))
        assertFalse(AndroidDeviceCompatibilityChannel.isKnownFeature(null))
    }
}
