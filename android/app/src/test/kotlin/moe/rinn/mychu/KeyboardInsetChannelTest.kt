package moe.rinn.mychu

import org.junit.Assert.assertEquals
import org.junit.Test

class KeyboardInsetChannelTest {
    @Test
    fun edgeToEdgeComputesKeyboardOverlapExcludingNavBar() {
        val overlap = computeKeyboardOverlapDp(
            imeBottomPx = 900,
            decorHeightPx = 2400,
            contentBottomPx = 2400,
            navBottomPx = 72,
            density = 3f,
        )
        assertEquals(276.0, overlap, 0.001)
    }

    @Test
    fun earlyAnimationBelowNavBarClampsToZero() {
        val overlap = computeKeyboardOverlapDp(
            imeBottomPx = 60,
            decorHeightPx = 2400,
            contentBottomPx = 2400,
            navBottomPx = 72,
            density = 3f,
        )
        assertEquals(0.0, overlap, 0.001)
    }

    @Test
    fun alreadyResizedContentViewAvoidsDoubleInset() {
        val overlap = computeKeyboardOverlapDp(
            imeBottomPx = 900,
            decorHeightPx = 2400,
            contentBottomPx = 1500,
            navBottomPx = 72,
            density = 3f,
        )
        assertEquals(0.0, overlap, 0.001)
    }

    @Test
    fun nonEdgeToEdgeAboveNavBarStillReportsKeyboardOverlap() {
        val overlap = computeKeyboardOverlapDp(
            imeBottomPx = 900,
            decorHeightPx = 2400,
            contentBottomPx = 2328,
            navBottomPx = 72,
            density = 3f,
        )
        assertEquals(276.0, overlap, 0.001)
    }

    @Test
    fun hiddenKeyboardAndInvalidDensityReturnZero() {
        assertEquals(
            0.0,
            computeKeyboardOverlapDp(
                imeBottomPx = 0,
                decorHeightPx = 2400,
                contentBottomPx = 2400,
                navBottomPx = 72,
                density = 3f,
            ),
            0.001,
        )
        assertEquals(
            0.0,
            computeKeyboardOverlapDp(
                imeBottomPx = 900,
                decorHeightPx = 2400,
                contentBottomPx = 2400,
                navBottomPx = 72,
                density = 0f,
            ),
            0.001,
        )
    }
}
