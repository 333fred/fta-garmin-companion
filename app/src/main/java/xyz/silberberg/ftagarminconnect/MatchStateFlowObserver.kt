package xyz.silberberg.ftagarminconnect

import com.microsoft.signalr.HubConnection
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.buffer
import kotlinx.coroutines.flow.map

fun registerMatchStatusInfoChanged(hubConnection: HubConnection): Flow<Message> {
    val matchStateFlow = MutableStateFlow(MatchStatus.NOT_READY)

    hubConnection.on("MatchStatusInfoChanged", {
        matchStateFlow.value = it.matchState
    }, MatchStatusInfo::class.java)

    return matchStateFlow
        .buffer(3, onBufferOverflow = BufferOverflow.DROP_OLDEST)
        .map { MatchMessage(MATCH_STATE, it.ordinal) }
}
