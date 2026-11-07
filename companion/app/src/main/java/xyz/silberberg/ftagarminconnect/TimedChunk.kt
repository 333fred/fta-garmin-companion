package xyz.silberberg.ftagarminconnect

import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.sample
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock
import kotlin.time.Duration

// Taken from https://github.com/Kotlin/kotlinx.coroutines/issues/1302#issuecomment-783108091

private class TimedChunkFlow<T>(sourceFlow: Flow<T>, period: Duration) {
    private val chunkLock = ReentrantLock()
    private var chunk = mutableListOf<T>()

    @OptIn(FlowPreview::class)
    val resultFlow = flow {
        sourceFlow.collect {
            // the chunk is reused before it's collected by "sample()"
            val localChunk = chunkLock.withLock {
                chunk.add(it)
                chunk
            }
            emit(localChunk)
        }
    }.sample(period).onEach {
        chunkLock.withLock {
            chunk = mutableListOf()
        }
    }
}

fun <T> Flow<T>.timedChunk(period: Duration): Flow<List<T>> = TimedChunkFlow(this, period).resultFlow