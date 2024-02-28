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
    BAT(9)
}

const val STATUS_START = 1
const val NUMBER_START = 9
const val BATTERY_START = 15
const val MATCH_STATE = 21

abstract class Message {
    abstract val key: Int
}

data class StatusMessage(override val key: Int, val status: Status) : Message()
data class BatteryMessage(override val key: Int, val battery: Float, val shouldVibrate: Boolean) : Message()
data class TeamMessage(override val key: Int, val teamMessage: Int, val shouldVibrate: Boolean) : Message()
data class MatchMessage(override val key: Int, val matchState: Int) : Message()