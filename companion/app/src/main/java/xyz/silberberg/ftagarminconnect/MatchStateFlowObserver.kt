package xyz.silberberg.ftagarminconnect

import com.microsoft.signalr.HubConnection
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.buffer
import kotlinx.coroutines.flow.shareIn

fun registerMatchStatusInfoChanged(hubConnection: HubConnection, observerScope: CoroutineScope): SharedFlow<MatchStatus> {
    val matchStateFlow = MutableStateFlow(MatchStatus.NOT_READY)

    hubConnection.on("MatchStatusInfoChanged", {
        matchStateFlow.value = it.matchState
    }, MatchStatusInfo::class.java)

    return matchStateFlow
        .buffer(3, onBufferOverflow = BufferOverflow.DROP_OLDEST)
        .shareIn(observerScope, SharingStarted.Lazily, replay = 1)
}