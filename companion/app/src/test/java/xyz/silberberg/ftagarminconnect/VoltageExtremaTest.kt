package xyz.silberberg.ftagarminconnect

import org.junit.Assert.assertEquals
import org.junit.Test

class VoltageExtremaTest {
    @Test
    fun minimum_discardsDominatedCandidates() {
        val minimum = VoltageExtrema(capacity = 4, minimum = true)
        minimum.add(sample(0, 9f))
        minimum.add(sample(1, 10f))
        minimum.add(sample(2, 11f))
        minimum.add(sample(3, 9.5f))

        assertEquals(9f, minimum.value, 0f)
        minimum.removeThrough(0)
        assertEquals(9.5f, minimum.value, 0f)
    }

    @Test
    fun maximum_discardsDominatedCandidates() {
        val maximum = VoltageExtrema(capacity = 4, minimum = false)
        maximum.add(sample(0, 15f))
        maximum.add(sample(1, 14f))
        maximum.add(sample(2, 13f))
        maximum.add(sample(3, 14.5f))

        assertEquals(15f, maximum.value, 0f)
        maximum.removeThrough(0)
        assertEquals(14.5f, maximum.value, 0f)
    }

    @Test
    fun minimum_reusesWrappedSlotsAndCanBeCleared() {
        val minimum = VoltageExtrema(capacity = 3, minimum = true)
        minimum.add(sample(0, 9f))
        minimum.add(sample(1, 10f))
        minimum.add(sample(2, 11f))
        minimum.removeThrough(0)
        minimum.add(sample(3, 12f))

        assertEquals(10f, minimum.value, 0f)
        minimum.removeThrough(1)
        assertEquals(11f, minimum.value, 0f)
        minimum.add(sample(4, 8f))
        assertEquals(8f, minimum.value, 0f)

        minimum.clear()
        minimum.add(sample(5, 7f))
        assertEquals(7f, minimum.value, 0f)
    }

    private fun sample(time: Long, battery: Float): TeamData =
        TeamData(team = 1, battery = battery, robotStatus = Status.GOOD, receivedAtMillis = time)
}
