package xyz.silberberg.ftagarminconnect

enum class Status(val value: Int) {
    ETH(0),
    DS(1),
    RADIO(2),
    RIO(3),
    CODE(4),
    ESTOP(5),
    GOOD(6),
    BWU(7),
    BYP(8),
    BAT(9),
    BAT_CONNECTED(10)
}

const val STATUS_START = 1
const val NUMBER_START = 9
const val BATTERY_START = 15
const val MATCH_STATE = 21

abstract class Message {
    abstract val key: Int
    abstract val value: Any
    abstract val shouldVibrate: Boolean
}

data class BatteryMessage(override val key: Int, val battery: Float) : Message() {
    override val value: Any
        get() = battery
    override val shouldVibrate: Boolean
        get() = false
}

data class TeamMessage(override val key: Int, val teamMessage: Int, override val shouldVibrate: Boolean) : Message() {
    override val value: Any
        get() = teamMessage
}
data class MatchMessage(override val key: Int, val matchState: Int) : Message() {
    override val value: Any
        get() = matchState
    override val shouldVibrate: Boolean
        get() = false
}