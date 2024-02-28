package xyz.silberberg.ftagarminconnect

import com.fasterxml.jackson.annotation.JsonProperty
import com.fasterxml.jackson.annotation.JsonCreator

data class FieldMonitorData @JsonCreator constructor(
    @JsonProperty("p1") val alliance: AllianceType,
    @JsonProperty("p2") val station: StationType,
    @JsonProperty("p3") val teamNumber: Int,
    @JsonProperty("p4") val connection: Boolean,
    @JsonProperty("p5") val linkActive: Boolean,
    @JsonProperty("p6") val dsLinkActive: Boolean,
    @JsonProperty("p7") val radioLink: Boolean,
    @JsonProperty("p8") val rioLink: Boolean,
    @JsonProperty("p9") val isEnabled: Boolean,
    @JsonProperty("pa") val isAuto: Boolean,
    @JsonProperty("pb") val isBypassed: Boolean,
    @JsonProperty("pc") val isEStopPressed: Boolean,
    @JsonProperty("pd") val isEStopped: Boolean,
    @JsonProperty("pe") val battery: Double,
    @JsonProperty("pf") val monitorStatus: Int,
    @JsonProperty("pg") val averageTripTime: Byte,
    @JsonProperty("ph") val lostPackets: Int,
    @JsonProperty("pi") val signal: Int?,
    @JsonProperty("pj") val noise: Int?,
    @JsonProperty("pk") val snr: Int,
    @JsonProperty("pl") val inactivity: Int,
    @JsonProperty("pm") val macAddress: String?,
    @JsonProperty("pn") val txRate: Double?,
    @JsonProperty("po") val txMCS: Int?,
    @JsonProperty("pp") val txMCSBandWidth: Int?,
    @JsonProperty("pq") val txVHT: Boolean?,
    @JsonProperty("pr") val txVHTNSS: Int?,
    @JsonProperty("ps") val txPackets: Int,
    @JsonProperty("pt") val rxRate: Double?,
    @JsonProperty("pu") val rxMCS: Int?,
    @JsonProperty("pv") val rxMCSBandWidth: Int?,
    @JsonProperty("pw") val rxVHT: Boolean?,
    @JsonProperty("px") val rxVHTNSS: Int?,
    @JsonProperty("py") val rxPackets: Int,
    @JsonProperty("pz") val dataRateTotal: Double,
    @JsonProperty("paa") val dataRateToRobot: Double,
    @JsonProperty("pbb") val dataRateFromRobot: Double,
    @JsonProperty("pcc") val bwUtilization: BWUtilizationType,
    @JsonProperty("pdd") val wpaKeyStatus: WPAKeyStatusType,
    @JsonProperty("pee") val driverStationIsOfficial: Boolean,
    @JsonProperty("pff") val stationStatus: DSConnectionStatusType,
    @JsonProperty("pgg") val brownout: Boolean,
    @JsonProperty("phh") val eStopSource: String?,
    @JsonProperty("pii") val isAStopPressed: Boolean,
    @JsonProperty("pjj") val isAStopped: Boolean,
    @JsonProperty("pjk") val moveToStation: String?
)

data class MatchStatusInfo(
    @JsonProperty("p1") val matchState: MatchStatus,
    @JsonProperty("p2") val matchNumber: Int,
    @JsonProperty("p3") val playNumber: Int,
    @JsonProperty("p4") val level: Int
)

enum class AllianceType {
    None,
    Red,
    Blue;

    companion object {
        @JsonCreator
        @JvmStatic
        fun fromValue(value: Int) = when (value) {
            0 -> None
            1 -> Red
            2 -> Blue
            else -> None
        }
    }
}

enum class StationType {
    None,
    Station1,
    Station2,
    Station3;

    companion object {
        @JsonCreator
        @JvmStatic
        fun fromValue(value: Int) = when (value) {
            0 -> None
            1 -> Station1
            2 -> Station2
            3 -> Station3
            else -> None
        }
    }
}

enum class MonitorStatusType {
    Unknown,
    EStopped,
    DisabledAuto,
    DisabledTeleop,
    EnabledAuto,
    EnabledTeleop;

    companion object {
        @JsonCreator
        @JvmStatic
        fun fromValue(value: Int) = when (value) {
            0 -> Unknown
            1 -> EStopped
            2 -> DisabledAuto
            3 -> DisabledTeleop
            4 -> EnabledAuto
            5 -> EnabledTeleop
            else -> Unknown
        }
    }
}

enum class BWUtilizationType {
    Low,
    Medium,
    High,
    VeryHigh;

    companion object {
        @JsonCreator
        @JvmStatic
        fun fromValue(value: Int) = when (value) {
            0 -> Low
            1 -> Medium
            2 -> High
            3 -> VeryHigh
            else -> Low
        }
    }
}

enum class WPAKeyStatusType {
    NotTested,
    UsedInConnectionTest,
    UsedInMatch;

    companion object {
        @JsonCreator
        @JvmStatic
        fun fromValue(value: Int) = when (value) {
            0 -> NotTested
            1 -> UsedInConnectionTest
            2 -> UsedInMatch
            else -> NotTested
        }
    }
}

enum class DSConnectionStatusType {
    NotConnected,
    ConnectedDSNotRunning,
    ConnectedWaiting,
    ConnectedWrongStation,
    Connected;

    companion object {
        @JsonCreator
        @JvmStatic
        fun fromValue(value: Int) =
            when (value) {
                0 -> NotConnected
                1 -> ConnectedDSNotRunning
                2 -> ConnectedWaiting
                3 -> ConnectedWrongStation
                4 -> Connected
                else -> NotConnected
            }
    }
}

// Younger me mapped these, and it's easier to just continue using this mapping
enum class MatchStatus {
    NOT_READY,
    TIMEOUT,
    READY_TO_PRESTART,
    PRESTART_INITIATED,
    PRESTART_COMPLETED,
    MATCH_READY,
    SENDING_TEAM_DATA,
    AUTO,
    TRANSITION,
    TELEOP,
    OVER,
    ABORTED;

    companion object {
        @JsonCreator
        @JvmStatic
        fun fromValue(value: Int) = when (value) {
            0, 1 -> OVER // No currently active event or tournament level
            2, 3 -> READY_TO_PRESTART // WaitingForPrestart or WaitingForPrestartTO
            4, 5 -> PRESTART_INITIATED // Prestarting or PrestartingTO
            6, 7, 18, 19 -> PRESTART_COMPLETED // WaitingForSetAudience or WaitingForSetAudienceTO, WaitingForMatchPreview or WaitingForMatchPreviewTO
            8 -> NOT_READY // WaitingForMatchReady
            9 -> MATCH_READY // WaitingForMatchStart
            10 -> SENDING_TEAM_DATA // Sending plate data to teams. This is 2018 specific
            11 -> AUTO // Match Auto
            12 -> TRANSITION // Match Transition
            13 -> TELEOP // Match Teleop
            14, // WaitingForCommit
            15, // WaitingForPostResults
            16 // Tournament Level Complete
            -> OVER
            // 17 is cancelled, treat anything else as cancelled as well
            else -> ABORTED // Match cancelled
        }
    }
}
