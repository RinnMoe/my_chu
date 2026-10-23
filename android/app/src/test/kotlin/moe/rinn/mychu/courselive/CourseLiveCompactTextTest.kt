package moe.rinn.mychu.courselive

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class CourseLiveCompactTextTest {
    @Test
    fun `room codes take precedence over verbose location descriptions`() {
        mapOf(
            "*WX2407" to "WX2407",
            "#WM2303机房" to "WM2303",
            "测试教室 A101" to "A101",
            "教学楼 305" to "305",
            "教学楼 wx2407" to "WX2407",
        ).forEach { (location, expected) ->
            assertEquals(expected, courseLiveCompactText(location, CourseLivePhase.ONGOING))
        }
    }

    @Test
    fun `short named locations remain useful without a room code`() {
        assertEquals("体育馆", courseLiveCompactText(" 体育馆 ", CourseLivePhase.PRE))
    }

    @Test
    fun `missing or oversized locations fall back to the current phase`() {
        val before = courseLiveCompactText("", CourseLivePhase.PRE)
        val ongoing = courseLiveCompactText("", CourseLivePhase.ONGOING)
        assertNotEquals(before, ongoing)
        assertTrue(before.length <= 7 && ongoing.length <= 7)
        assertEquals(ongoing, courseLiveCompactText("超出胶囊可显示长度的教学地点", CourseLivePhase.ONGOING))
        assertEquals(ongoing, courseLiveCompactText("ABCDEFGH12345678", CourseLivePhase.ONGOING))
    }
}
