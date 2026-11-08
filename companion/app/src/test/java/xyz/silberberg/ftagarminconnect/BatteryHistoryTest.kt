package xyz.silberberg.ftagarminconnect

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BatteryHistoryTest {
    @Test
    fun hasNoMovement_requiresFiveSecondsOfReadings() {
        val history = BatteryHistory()

        assertFalse(history.hasNoMovement())
        history.add(sample(0, 12f))
        history.add(sample(4_999, 12f))
        assertFalse(history.hasNoMovement())

        history.add(sample(5_000, 12f))
        assertTrue(history.hasNoMovement())
    }

    @Test
    fun hasNoMovement_acceptsOneVoltRangeButRejectsLargerRange() {
        val history = BatteryHistory()
        history.add(sample(0, 12f))
        history.add(sample(1, 13f))
        history.add(sample(4_999, 12f))
        history.add(sample(5_000, 12f))
        assertTrue(history.hasNoMovement())

        history.add(sample(5_001, 13.01f))
        assertFalse(history.hasNoMovement())
    }

    @Test
    fun hasNoMovement_trimsAllExpiredReadings() {
        val history = BatteryHistory()
        history.add(sample(0, 12f))
        history.add(sample(1, 14f))
        history.add(sample(2, 12f))
        history.add(sample(1_000, 12f))
        history.add(sample(4_999, 12f))
        history.add(sample(5_000, 12f))
        assertFalse(history.hasNoMovement())

        history.add(sample(5_002, 12f))
        assertTrue(history.hasNoMovement())
    }

    @Test
    fun add_gapOfFiveSecondsRestartsTheWindow() {
        val history = BatteryHistory()
        history.add(sample(0, 12f))
        history.add(sample(2_500, 12f))
        history.add(sample(5_000, 12f))
        assertTrue(history.hasNoMovement())

        history.add(sample(10_000, 12f))
        assertFalse(history.hasNoMovement())
        history.add(sample(14_999, 12f))
        assertFalse(history.hasNoMovement())
        history.add(sample(15_000, 12f))
        assertTrue(history.hasNoMovement())
    }

    @Test
    fun add_outOfOrderReadingRestartsTheWindow() {
        val history = BatteryHistory()
        history.add(sample(0, 12f))
        history.add(sample(2_500, 12f))
        history.add(sample(5_000, 12f))
        assertTrue(history.hasNoMovement())

        history.add(sample(1_000, 12f))
        assertFalse(history.hasNoMovement())
        history.add(sample(5_999, 12f))
        assertFalse(history.hasNoMovement())
        history.add(sample(6_000, 12f))
        assertTrue(history.hasNoMovement())
    }

    @Test
    fun clear_discardsHistoryAndOldExtrema() {
        val history = BatteryHistory()
        history.add(sample(0, 12f))
        history.add(sample(2_500, 14f))
        history.add(sample(5_000, 12f))
        assertFalse(history.hasNoMovement())

        history.clear()
        assertFalse(history.hasNoMovement())
        history.add(sample(5_001, 12f))
        history.add(sample(7_500, 12f))
        history.add(sample(10_001, 12f))
        assertTrue(history.hasNoMovement())
    }

    @Test
    fun add_sameMillisecondExtremaExpireWithTheirTimestamp() {
        val history = BatteryHistory()
        history.add(sample(0, 14f))
        history.add(sample(0, 12f))
        history.add(sample(10, 12f))
        history.add(sample(4_999, 12f))
        history.add(sample(5_000, 12f))

        history.add(sample(5_010, 12f))
        assertTrue(history.hasNoMovement())
    }

    @Test
    fun add_sameMillisecondLastReadingCanIntroduceMovement() {
        val history = BatteryHistory()
        history.add(sample(0, 12f))
        history.add(sample(2_500, 12f))
        history.add(sample(2_500, 14f))
        history.add(sample(4_999, 12f))
        history.add(sample(5_000, 12f))

        assertFalse(history.hasNoMovement())
    }

    @Test
    fun hasNoMovement_expiresBoundaryOutlierAfterBufferWraps() {
        val history = BatteryHistory()

        for (index in 0..1_151) {
            history.add(sample(index * 10L, if (index == 650) 14f else 12f))
            when (index) {
                500 -> assertTrue(history.hasNoMovement())
                650, 1_150 -> assertFalse(history.hasNoMovement())
                1_151 -> assertTrue(history.hasNoMovement())
            }
        }
    }

    private fun sample(time: Long, battery: Float): TeamData =
        TeamData(team = 1, battery = battery, robotStatus = Status.GOOD, receivedAtMillis = time)
}
