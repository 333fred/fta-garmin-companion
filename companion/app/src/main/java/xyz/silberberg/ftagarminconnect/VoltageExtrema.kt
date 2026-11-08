package xyz.silberberg.ftagarminconnect

internal class VoltageExtrema(capacity: Int, private val minimum: Boolean) {
    // Keep only candidates for the current extremum, in arrival order.
    private val candidates = arrayOfNulls<TeamData>(capacity)
    private var startIndex = 0
    private var endIndex = 0
    private var size = 0

    val value: Float
        get() = candidateAt(startIndex).battery

    fun clear() {
        while (size > 0) {
            removeFirst()
        }
        startIndex = 0
        endIndex = 0
    }

    fun add(team: TeamData) {
        while (size > 0) {
            val last = candidateAt(previousIndex(endIndex))
            if ((minimum && last.battery < team.battery) || (!minimum && last.battery > team.battery)) {
                break
            }
            removeLast()
        }
        check(size < candidates.size)
        candidates[endIndex] = team
        endIndex = nextIndex(endIndex)
        size++
    }

    fun removeThrough(receivedAtMillis: Long) {
        while (size > 0 && candidateAt(startIndex).receivedAtMillis <= receivedAtMillis) {
            removeFirst()
        }
    }

    private fun removeFirst() {
        candidates[startIndex] = null
        startIndex = nextIndex(startIndex)
        size--
    }

    private fun removeLast() {
        endIndex = previousIndex(endIndex)
        candidates[endIndex] = null
        size--
    }

    private fun candidateAt(index: Int): TeamData = checkNotNull(candidates[index])

    private fun nextIndex(index: Int): Int = if (index == candidates.lastIndex) 0 else index + 1

    private fun previousIndex(index: Int): Int = if (index == 0) candidates.lastIndex else index - 1
}
