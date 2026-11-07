package xyz.silberberg.ftagarminconnect

import android.util.Log
import com.microsoft.signalr.HubConnection
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.channels.onFailure
import kotlinx.coroutines.channels.onSuccess
import kotlinx.coroutines.channels.trySendBlocking
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.buffer
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.consumeAsFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.runningFold
import kotlinx.coroutines.flow.sample
import kotlinx.coroutines.flow.shareIn
import kotlinx.coroutines.launch
import kotlin.time.Duration.Companion.milliseconds

data class TeamData(
    val team: Int,
    val battery: Float,
    val robotStatus: Status,
    val brownout: Boolean = false
)

private fun teamStatusMessages(
    teamFlow: Flow<TeamData>,
    matchStatusFlow: Flow<MatchStatus>,
    offset: Int
): Flow<TeamMessage> = flow {
    var currentTeam: Int? = null
    var previousMatchStatus: MatchStatus? = null
    var hasBrownedOut = false

    teamFlow
        .buffer(3, onBufferOverflow = BufferOverflow.DROP_OLDEST)
        .combine(matchStatusFlow) { team, matchStatus ->
            if (team.team != currentTeam
                || matchStatus == MatchStatus.PRESTART_INITIATED
                || (matchStatus == MatchStatus.AUTO && previousMatchStatus != MatchStatus.AUTO)
            ) {
                hasBrownedOut = false
            }
            currentTeam = team.team
            previousMatchStatus = matchStatus

            val inMatch = matchStatus == MatchStatus.AUTO
                || matchStatus == MatchStatus.TRANSITION
                || matchStatus == MatchStatus.TELEOP
            val firstBrownout = inMatch && team.brownout && !hasBrownedOut
            hasBrownedOut = hasBrownedOut || firstBrownout

            val status = if (team.robotStatus == Status.GOOD && hasBrownedOut) {
                Status.BAT_CONNECTED
            } else {
                team.robotStatus
            }
            val shouldVibrate = when (matchStatus) {
                // When we're about to ready or are in a match, I want an alert. Otherwise, I don't.
                MatchStatus.NOT_READY, MatchStatus.MATCH_READY, MatchStatus.SENDING_TEAM_DATA,
                MatchStatus.AUTO, MatchStatus.TRANSITION, MatchStatus.TELEOP -> true

                else -> false
            }
            val repeatedBrownout = hasBrownedOut && !firstBrownout
                && (status == Status.BAT || status == Status.BAT_CONNECTED)
            TeamMessage(STATUS_START + offset, status.value, shouldVibrate && !repeatedBrownout)
        }
        .distinctUntilChanged { old, new ->
            // Explicitly ignore shouldVibrate so that we don't send a message across match state
            // boundaries when shouldVibrate changes
            old.key == new.key && old.teamMessage == new.teamMessage
        }
        .collect { emit(it) }
}

private enum class BatteryResetStatus {
    DO_RESET,
    HAS_RESET_THIS_MATCH,
    NO_RESET_THIS_MATCH
}

@OptIn(FlowPreview::class)
fun registerFieldMonitorDataReceived(
    hubConnection: HubConnection,
    matchStatusChannel: SharedFlow<MatchStatus>,
    observerScope: CoroutineScope
): Channel<Message> {
    val red1Channel = Channel<TeamData>(1, BufferOverflow.DROP_OLDEST)
    val red2Channel = Channel<TeamData>(1, BufferOverflow.DROP_OLDEST)
    val red3Channel = Channel<TeamData>(1, BufferOverflow.DROP_OLDEST)
    val blue1Channel = Channel<TeamData>(1, BufferOverflow.DROP_OLDEST)
    val blue2Channel = Channel<TeamData>(1, BufferOverflow.DROP_OLDEST)
    val blue3Channel = Channel<TeamData>(1, BufferOverflow.DROP_OLDEST)

    val outputChannel = Channel<Message>(20, BufferOverflow.DROP_OLDEST)

    hubConnection.on("FieldMonitorDataChanged", {
        for (team in it) {
            val status: Status = when {
                team.isEStopped -> Status.ESTOP
                team.isBypassed -> Status.BYP
                !team.connection -> Status.ETH
                team.stationStatus != DSStationStatus.Good -> Status.DS
                !team.radioLink -> Status.RADIO
                !team.rioLink -> Status.RIO
                !team.linkActive -> Status.CODE
                team.brownout -> Status.BAT
                else -> Status.GOOD
            }

            val teamData = TeamData(team.teamNumber, team.battery.toFloat(), status, team.brownout)
            when (team.alliance) {
                AllianceType.Red -> when (team.station) {
                    StationType.Station1 -> red1Channel.trySendBlocking(teamData)
                    StationType.Station2 -> red2Channel.trySendBlocking(teamData)
                    StationType.Station3 -> red3Channel.trySendBlocking(teamData)
                    else -> {
                        Log.w("TeamFlowObserver", "Unknown alliance type: ${team.alliance}")
                        return@on
                    }
                }

                AllianceType.Blue -> when (team.station) {
                    StationType.Station1 -> blue1Channel.trySendBlocking(teamData)
                    StationType.Station2 -> blue2Channel.trySendBlocking(teamData)
                    StationType.Station3 -> blue3Channel.trySendBlocking(teamData)
                    else -> {
                        Log.w("TeamFlowObserver", "Unknown alliance type: ${team.alliance}")
                        return@on
                    }
                }

                else -> {
                    Log.w("TeamFlowObserver", "Unknown station type: ${team.station}")
                    return@on
                }
            }
                .onSuccess {
                    Log.d("TeamFlowObserver", "Sent team data: $teamData")
                }
                .onFailure {
                    Log.w("TeamFlowObserver", "Failed to send team data: $teamData")
                }
        }
    }, Array<FieldMonitorData>::class.java)

    val red1Flow =
        red1Channel.consumeAsFlow().shareIn(observerScope, SharingStarted.Lazily, replay = 1)
    val red2Flow =
        red2Channel.consumeAsFlow().shareIn(observerScope, SharingStarted.Lazily, replay = 1)
    val red3Flow =
        red3Channel.consumeAsFlow().shareIn(observerScope, SharingStarted.Lazily, replay = 1)
    val blue1Flow =
        blue1Channel.consumeAsFlow().shareIn(observerScope, SharingStarted.Lazily, replay = 1)
    val blue2Flow =
        blue2Channel.consumeAsFlow().shareIn(observerScope, SharingStarted.Lazily, replay = 1)
    val blue3Flow =
        blue3Channel.consumeAsFlow().shareIn(observerScope, SharingStarted.Lazily, replay = 1)

    val didResetChannel = Channel<Unit>()

    val resetBatteryFlow = matchStatusChannel
        .combine(didResetChannel.consumeAsFlow()) { matchStatus, _ ->
            matchStatus
        }
        .runningFold(BatteryResetStatus.NO_RESET_THIS_MATCH) { acc, matchStatus ->
            when (matchStatus) {
                MatchStatus.AUTO -> when (acc) {
                    BatteryResetStatus.DO_RESET -> BatteryResetStatus.HAS_RESET_THIS_MATCH
                    BatteryResetStatus.NO_RESET_THIS_MATCH -> {
                        // Ensure that we'll go to the next state, as we won't get another Auto packet
                        didResetChannel.send(Unit)
                        BatteryResetStatus.DO_RESET
                    }
                    else -> acc
                }

                MatchStatus.PRESTART_INITIATED -> BatteryResetStatus.NO_RESET_THIS_MATCH
                else -> acc
            }
        }
        .shareIn(observerScope, SharingStarted.Lazily, replay = 1)

    fun createBatteryFlow(teamFlow: SharedFlow<TeamData>, offset: Int) {
        observerScope.launch {
            var lowestSeen = TeamData(0, 0f, Status.ETH)
            teamFlow
                .combine(resetBatteryFlow) { teamData, resetBatteryStatus ->
                    if (teamData.team != lowestSeen.team
                        || resetBatteryStatus == BatteryResetStatus.DO_RESET
                        || lowestSeen.battery == 0f
                        || (teamData.battery < lowestSeen.battery && teamData.battery != 0f)
                    ) {
                        lowestSeen = teamData
                    }

                    lowestSeen.battery
                }
                .distinctUntilChanged()
                .sample(50.milliseconds)
                .buffer(3, onBufferOverflow = BufferOverflow.DROP_OLDEST)
                .map { BatteryMessage(BATTERY_START + offset, it) }
                .collect {
                    outputChannel.send(it)
                }
        }
    }

    createBatteryFlow(red1Flow, 0)
    createBatteryFlow(red2Flow, 1)
    createBatteryFlow(red3Flow, 2)
    createBatteryFlow(blue1Flow, 3)
    createBatteryFlow(blue2Flow, 4)
    createBatteryFlow(blue3Flow, 5)

    fun createTeamFlow(teamChannel: SharedFlow<TeamData>, offset: Int) {
        observerScope.launch {
            teamChannel
                .map {
                    it.team
                }
                .distinctUntilChanged()
                .sample(50.milliseconds)
                .buffer(3, onBufferOverflow = BufferOverflow.DROP_OLDEST)
                .map { TeamMessage(NUMBER_START + offset, it, false) }
                .collect {
                    outputChannel.send(it)
                }
        }
    }

    createTeamFlow(red1Flow, 0)
    createTeamFlow(red2Flow, 1)
    createTeamFlow(red3Flow, 2)
    createTeamFlow(blue1Flow, 3)
    createTeamFlow(blue2Flow, 4)
    createTeamFlow(blue3Flow, 5)

    fun createStatusFlow(teamFlow: SharedFlow<TeamData>, offset: Int) {
        observerScope.launch {
            teamStatusMessages(teamFlow, matchStatusChannel, offset)
                .collect {
                    outputChannel.send(it)
                }
        }
    }

    createStatusFlow(red1Flow, 0)
    createStatusFlow(red2Flow, 1)
    createStatusFlow(red3Flow, 2)
    createStatusFlow(blue1Flow, 3)
    createStatusFlow(blue2Flow, 4)
    createStatusFlow(blue3Flow, 5)

    return outputChannel
}
