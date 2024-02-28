package xyz.silberberg.ftagarminconnect

import android.os.ConditionVariable
import android.util.Log
import java.util.concurrent.atomic.AtomicInteger
import kotlin.collections.HashMap

abstract class Message

enum class Status(val value: Byte) {
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

data class StatusMessage(val key: Int, val status: Status) : Message()
data class BatteryMessage(val key: Int, val battery: Float, val shouldVibrate: Boolean) : Message()
data class TeamMessage(val key: Int, val teamMessage: Int, val shouldVibrate: Boolean) : Message()
data class MatchMessage(val key: Int, val matchState: Int) : Message()
interface WatchMessageSender : Runnable {
    fun startApp()
    fun addMessage(key: Int, message: Message)
    fun addMessages(messages: Map<Int, Message>)
    fun shutdown()

    companion object {
        const val STATUS_START = 1
        const val NUMBER_START = 9
        const val BATTERY_START = 15
        const val MATCH_STATE = 21
    }
}
/*

abstract class RateLimitedRetryingWatchMessageSender<TMessage, TSendDictionary>(protected val service: CommunicationsService) :
    WatchMessageSender {
    private val sendSignal = Object()
    private val messageReadyCondition = ConditionVariable()
    private val lock = Any()

    @Volatile
    protected var running = false

    @Volatile
    private var sendInProgress = false

    @Volatile
    private var queuedMap: MutableMap<Int, TMessage> = HashMap()

    @Volatile
    private var sendMap: MutableMap<Int, TMessage> = HashMap()

    @Volatile
    private var lastSent: TSendDictionary? = null
    private val retries: AtomicInteger = AtomicInteger(0)

    /**
     * This function is to be called in a loop by implementors to handle sending messages to the connected
     * watch app
     */
    protected fun processMessages() {
        synchronized(sendSignal) {
            if (sendInProgress) {
                try {
                    sendSignal.wait()
                } catch (e: InterruptedException) {
                    Thread.currentThread().interrupt()
                    Log.w(TAG, "Interrupted while waiting for send to end", e)
                    running = false
                    return
                }
            }

            sendInProgress = true
        }

        checkInterrupted()
        if (!running) return

        messageReadyCondition.block()

        checkInterrupted()
        if (!running) return

        synchronized(lock) {
            val saved = queuedMap
            queuedMap = sendMap
            sendMap = saved
            messageReadyCondition.close()
        }

        if (sendMap.isNotEmpty()) {
            sendMessages()
        } else {
            endSend()
        }
    }

    private fun sendMessages() {
        Log.d(TAG, "Sending messages")
        lastSent = packMessages(sendMap)
        retries.set(0)
        sendMessages(lastSent!!)
        sendMap.clear()
    }

    protected fun retry() {
        assert(lastSent != null)

        if (!running) {
            endSend()
            return
        }

        // Attempt to resend, after giving a 10 ms backoff window
        if (retries.getAndAdd(1) < 3) {
            Log.w(TAG, "Retrying transmission")
            try {
                Thread.sleep((10 * retries.get()).toLong())
            } catch (e: InterruptedException) {
                Log.e(TAG, "Interrupted while attempting to retransmit!", e)
                running = false
                endSend()
            }

            checkInterrupted()
            if (!running) {
                endSend()
                return
            }

            sendMessages(lastSent!!)
        } else {
            // At this point, we've been blocked for a while. Back off for half a second and fully
            // update all data
            Log.w(TAG, "Exceeded max transmission retries!")
            try {
                Thread.sleep(50)
            } catch (e: InterruptedException) {
                Log.e(TAG, "Interrupted while attempting to retransmit!", e)
                running = false
                endSend()
                return
            }

            checkInterrupted()
            if (!running) {
                endSend()
                return
            }

            service.updateAllObservers()
            endSend()
        }
    }

    protected fun endSend() {
        synchronized(sendSignal) {
            sendInProgress = false
            retries.set(0)
            sendSignal.notify()
        }
    }

    final override fun addMessages(messages: Map<Int, Message>) {
        synchronized(lock) {
            queuedMap.putAll(messages.mapValues { it.value.convertMessage() })
            messageReadyCondition.open()
        }
    }

    final override fun addMessage(key: Int, message: Message) {
        synchronized(lock) {
            queuedMap[key] = message.convertMessage()
            messageReadyCondition.open()
        }
    }

    override fun shutdown() {
        running = false
        messageReadyCondition.open()
        synchronized(sendSignal) {
            sendSignal.notifyAll()
        }
    }

    protected fun checkInterrupted() {
        if (Thread.interrupted()) {
            Log.w(TAG, "Watch sender interrupted!")
            Thread.currentThread().interrupt()
            running = false
        }
    }

    /**
     * Converts a given message to the implementation type used by this sender
     */
    abstract fun Message.convertMessage(): TMessage

    /**
     * Packs a map of messages to the send type used by this sender
     */
    abstract fun packMessages(messages: Map<Int, TMessage>): TSendDictionary

    /**
     * Sends a set of values to the connected app
     */
    abstract fun sendMessages(messages: TSendDictionary)

    companion object {
        private val TAG = RateLimitedRetryingWatchMessageSender::class.java.name
    }
}
*/