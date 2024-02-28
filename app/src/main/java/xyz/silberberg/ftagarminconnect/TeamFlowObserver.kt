package xyz.silberberg.ftagarminconnect

import android.util.Log
import com.microsoft.signalr.HubConnection
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.buffer
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.merge
import kotlinx.coroutines.flow.sample
import kotlin.time.DurationUnit
import kotlin.time.toDuration

data class TeamData(val team: Int, val battery: Float, val robotStatus: Status)

@OptIn(FlowPreview::class)
fun registerFieldMonitorDataReceived(hubConnection: HubConnection): Flow<Message> {
    val red1Flow = MutableStateFlow(TeamData(0, 0f, Status.ETH))
    val red2Flow = MutableStateFlow(TeamData(0, 0f, Status.ETH))
    val red3Flow = MutableStateFlow(TeamData(0, 0f, Status.ETH))
    val blue1Flow = MutableStateFlow(TeamData(0, 0f, Status.ETH))
    val blue2Flow = MutableStateFlow(TeamData(0, 0f, Status.ETH))
    val blue3Flow = MutableStateFlow(TeamData(0, 0f, Status.ETH))

    hubConnection.on("FieldMonitorDataChanged", {
        for (team in it) {
            val status: Status = when {
                team.isEStopped -> Status.ESTOP
                team.isBypassed -> Status.BYP
                !team.linkActive -> Status.ETH
                !team.dsLinkActive -> Status.DS
                !team.radioLink -> Status.RADIO
                !team.rioLink -> Status.RIO
                !team.connection -> Status.CODE
                else -> {
                    // Battery is more important than bandwidth, imo
                    if (team.battery < 7f) {
                        Status.BAT
                    } else {
                        Status.GOOD
                    }
                }
            }

            val teamData = TeamData(team.teamNumber, team.battery.toFloat(), status)
            when (team.alliance) {
                AllianceType.Red -> when (team.station) {
                    StationType.Station1 -> red1Flow.value = teamData
                    StationType.Station2 -> red2Flow.value = teamData
                    StationType.Station3 -> red3Flow.value = teamData
                    else -> {
                        Log.w("TeamFlowObserver", "Unknown alliance type: ${team.alliance}")
                    }
                }

                AllianceType.Blue -> when (team.station) {
                    StationType.Station1 -> blue1Flow.value = teamData
                    StationType.Station2 -> blue2Flow.value = teamData
                    StationType.Station3 -> blue3Flow.value = teamData
                    else -> {
                        Log.w("TeamFlowObserver", "Unknown alliance type: ${team.alliance}")
                    }
                }

                else -> {
                    Log.w("TeamFlowObserver", "Unknown station type: ${team.station}")
                }
            }
        }
    }, Array<FieldMonitorData>::class.java)

    val createBatteryFlow: (StateFlow<TeamData>, Int) -> Flow<Message> = { teamFlow, offset ->
        var lowestSeen = TeamData(0, 0f, Status.ETH)
        teamFlow
            .map {
                if (it.team != lowestSeen.team) {
                    lowestSeen = it
                } else if (it.battery < lowestSeen.battery) {
                    lowestSeen = it
                }

                lowestSeen.battery
            }
            .distinctUntilChanged()
            .sample(50.toDuration(DurationUnit.MILLISECONDS))
            .buffer(3, onBufferOverflow = BufferOverflow.DROP_OLDEST)
            .map { BatteryMessage(WatchMessageSender.BATTERY_START + offset, it, false) }
    }

    val red1BatteryFlow = createBatteryFlow(red1Flow, 0)
    val red2BatteryFlow = createBatteryFlow(red2Flow, 1)
    val red3BatteryFlow = createBatteryFlow(red3Flow, 2)
    val blue1BatteryFlow = createBatteryFlow(blue1Flow, 3)
    val blue2BatteryFlow = createBatteryFlow(blue2Flow, 4)
    val blue3BatteryFlow = createBatteryFlow(blue3Flow, 5)

    val createTeamFlow: (StateFlow<TeamData>, Int) -> Flow<Message> = { teamFlow, offset ->
        teamFlow
            .map { it.team }
            .distinctUntilChanged()
            .sample(50.toDuration(DurationUnit.MILLISECONDS))
            .buffer(3, onBufferOverflow = BufferOverflow.DROP_OLDEST)
            .map { TeamMessage(WatchMessageSender.NUMBER_START + offset, it, false) }
    }

    val red1TeamFlow = createTeamFlow(red1Flow, 0)
    val red2TeamFlow = createTeamFlow(red2Flow, 1)
    val red3TeamFlow = createTeamFlow(red3Flow, 2)
    val blue1TeamFlow = createTeamFlow(blue1Flow, 3)
    val blue2TeamFlow = createTeamFlow(blue2Flow, 4)
    val blue3TeamFlow = createTeamFlow(blue3Flow, 5)

    val createStatusFlow: (StateFlow<TeamData>, Int) -> Flow<Message> = { teamFlow, offset ->
        teamFlow
            .map { it.robotStatus }
            .distinctUntilChanged()
            .buffer(3, onBufferOverflow = BufferOverflow.DROP_OLDEST)
            .map { StatusMessage(WatchMessageSender.STATUS_START + offset, it) }
    }

    val red1StatusFlow = createStatusFlow(red1Flow, 0)
    val red2StatusFlow = createStatusFlow(red2Flow, 1)
    val red3StatusFlow = createStatusFlow(red3Flow, 2)
    val blue1StatusFlow = createStatusFlow(blue1Flow, 3)
    val blue2StatusFlow = createStatusFlow(blue2Flow, 4)
    val blue3StatusFlow = createStatusFlow(blue3Flow, 5)

    return merge(
        red1BatteryFlow,
        red2BatteryFlow,
        red3BatteryFlow,
        blue1BatteryFlow,
        blue2BatteryFlow,
        blue3BatteryFlow,
        red1TeamFlow,
        red2TeamFlow,
        red3TeamFlow,
        blue1TeamFlow,
        blue2TeamFlow,
        blue3TeamFlow,
        red1StatusFlow,
        red2StatusFlow,
        red3StatusFlow,
        blue1StatusFlow,
        blue2StatusFlow,
        blue3StatusFlow
    )
}