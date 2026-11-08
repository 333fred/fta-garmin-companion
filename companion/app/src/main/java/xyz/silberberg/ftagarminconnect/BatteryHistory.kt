package xyz.silberberg.ftagarminconnect

private const val NO_MOVEMENT_WINDOW_MILLIS = 5_000L
private const val NO_MOVEMENT_VOLTAGE_RANGE = 1f
private const val EXPECTED_READING_INTERVAL_MILLIS = 10L
// Allow twice the expected rate while retaining the window boundary.
private val NO_MOVEMENT_HISTORY_CAPACITY =
    (NO_MOVEMENT_WINDOW_MILLIS / EXPECTED_READING_INTERVAL_MILLIS).toInt() * 2 + 2

internal class BatteryHistory {
    private val samples = arrayOfNulls<TeamData>(NO_MOVEMENT_HISTORY_CAPACITY)
    private val min = VoltageExtrema(samples.size, minimum = true)
    private val max = VoltageExtrema(samples.size, minimum = false)
    private var startIndex = 0
    private var endIndex = 0
    private var size = 0

    fun clear() {
        while (size > 0) {
            samples[startIndex] = null
            startIndex = nextIndex(startIndex)
            size--
        }
        startIndex = 0
        endIndex = 0
        min.clear()
        max.clear()
    }

    fun add(team: TeamData) {
        val previous = if (size == 0) null else sampleAt(lastIndex())
        if (previous === team) return
        if (previous != null && team.receivedAtMillis == previous.receivedAtMillis) {
            samples[lastIndex()] = team
        } else {
            if (previous != null && (team.receivedAtMillis < previous.receivedAtMillis
                    // If it's been more than the window since we saw a voltage, don't assume it didn't move
                    || team.receivedAtMillis - previous.receivedAtMillis >= NO_MOVEMENT_WINDOW_MILLIS)
            ) {
                clear()
            }

            val windowStart = team.receivedAtMillis - NO_MOVEMENT_WINDOW_MILLIS
            while (size > 1 && sampleAt(nextIndex(startIndex)).receivedAtMillis <= windowStart) {
                removeFirst()
            }

            if (size == samples.size) removeFirst()
            samples[endIndex] = team
            endIndex = nextIndex(endIndex)
            size++
        }
        min.add(team)
        max.add(team)
    }

    fun hasNoMovement(): Boolean {
        if (size == 0) return false
        return sampleAt(lastIndex()).receivedAtMillis - sampleAt(startIndex).receivedAtMillis >= NO_MOVEMENT_WINDOW_MILLIS
            && max.value - min.value <= NO_MOVEMENT_VOLTAGE_RANGE
    }

    private fun removeFirst() {
        val receivedAtMillis = sampleAt(startIndex).receivedAtMillis
        min.removeThrough(receivedAtMillis)
        max.removeThrough(receivedAtMillis)
        samples[startIndex] = null
        startIndex = nextIndex(startIndex)
        size--
    }

    private fun sampleAt(index: Int): TeamData = checkNotNull(samples[index])

    private fun lastIndex(): Int = if (endIndex == 0) samples.lastIndex else endIndex - 1

    private fun nextIndex(index: Int): Int = if (index == samples.lastIndex) 0 else index + 1
}
