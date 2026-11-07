package xyz.silberberg.ftagarminconnect

import android.app.Service
import android.os.Binder

class LocalBinder(val service: Service) : Binder()

