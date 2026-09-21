package lk.ziggo.app

import android.animation.ValueAnimator
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.util.DisplayMetrics
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.view.animation.DecelerateInterpolator
import kotlin.math.hypot

class FloatingWidgetService : Service() {

    companion object {
        const val ACTION_SHOW = "lk.ziggo.app.ACTION_SHOW_FLOATING_WIDGET"
        const val ACTION_HIDE = "lk.ziggo.app.ACTION_HIDE_FLOATING_WIDGET"
        private const val NOTIFICATION_ID = 8891
        private const val CHANNEL_ID = "ziggo_floating_overlay_v2"

        @Volatile
        var isShowing: Boolean = false
            private set

        fun show(context: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(context)) {
                return
            }
            val intent = Intent(context, FloatingWidgetService::class.java).apply {
                action = ACTION_SHOW
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: Exception) {
                try {
                    context.startService(intent)
                } catch (_: Exception) {}
            }
        }

        fun hide(context: Context) {
            try {
                val intent = Intent(context, FloatingWidgetService::class.java)
                context.stopService(intent)
            } catch (e: Exception) {
                // Ignore
            }
        }
    }

    private var windowManager: WindowManager? = null
    private var floatingView: View? = null
    private var layoutParams: WindowManager.LayoutParams? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        windowManager = (getSystemService(Context.WINDOW_SERVICE) as? WindowManager)
            ?: (getSystemService(WindowManager::class.java))
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_SHOW

        if (action == ACTION_HIDE) {
            removeFloatingWidget()
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                } else {
                    @Suppress("DEPRECATION")
                    stopForeground(true)
                }
            } catch (_: Exception) {}
            stopSelf()
            return START_NOT_STICKY
        }

        if (action == ACTION_SHOW) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
                stopSelf()
                return START_NOT_STICKY
            }

            try {
                val notification = buildForegroundNotification()
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    startForeground(
                        NOTIFICATION_ID,
                        notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
                    )
                } else {
                    startForeground(NOTIFICATION_ID, notification)
                }
            } catch (e: Exception) {
                try {
                    startForeground(NOTIFICATION_ID, buildForegroundNotification())
                } catch (_: Exception) {}
            }

            addOrUpdateFloatingWidget()
        }

        return START_STICKY
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Ziggo Driver Overlay",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows floating shortcut when driver is online"
                setShowBadge(false)
                enableLights(false)
                enableVibration(false)
                setSound(null, null)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }

    private fun buildForegroundNotification(): Notification {
        createNotificationChannel()

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
        }
        val pendingIntent = if (launchIntent != null) {
            PendingIntent.getActivity(
                this,
                0,
                launchIntent,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                } else {
                    PendingIntent.FLAG_UPDATE_CURRENT
                }
            )
        } else null

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        builder
            .setContentTitle("Ziggo Driver Online")
            .setContentText("Tap to return to Ziggo")
            .setSmallIcon(R.mipmap.launcher_icon)
            .setOngoing(true)

        if (pendingIntent != null) {
            builder.setContentIntent(pendingIntent)
        }

        return builder.build()
    }

    private fun addOrUpdateFloatingWidget() {
        val wm = (getSystemService(Context.WINDOW_SERVICE) as? WindowManager)
            ?: windowManager
            ?: return
        windowManager = wm

        if (floatingView != null && isShowing) {
            return
        }

        if (floatingView != null) {
            try {
                if (floatingView?.isAttachedToWindow == true) {
                    wm.removeView(floatingView)
                }
            } catch (_: Exception) {}
            floatingView = null
        }

        val displayMetrics = resources.displayMetrics
        val screenHeight = displayMetrics.heightPixels

        val layoutType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            layoutType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 0
            y = (screenHeight * 0.35).toInt()
        }

        layoutParams = params

        val inflater = LayoutInflater.from(this)
        val view = inflater.inflate(R.layout.layout_floating_widget, null)
        floatingView = view

        val bubbleContainer = view.findViewById<View>(R.id.floating_bubble_container)
        val touchSlop = ViewConfiguration.get(this).scaledTouchSlop

        view.setOnTouchListener(object : View.OnTouchListener {
            private var initialX = 0
            private var initialY = 0
            private var initialTouchX = 0f
            private var initialTouchY = 0f
            private var touchStartTime = 0L

            override fun onTouch(v: View, event: MotionEvent): Boolean {
                val currentParams = layoutParams ?: return false
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        initialX = currentParams.x
                        initialY = currentParams.y
                        initialTouchX = event.rawX
                        initialTouchY = event.rawY
                        touchStartTime = System.currentTimeMillis()

                        bubbleContainer?.animate()?.scaleX(0.92f)?.scaleY(0.92f)?.setDuration(100)?.start()
                        return true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val dx = (event.rawX - initialTouchX).toInt()
                        val dy = (event.rawY - initialTouchY).toInt()
                        currentParams.x = initialX + dx
                        currentParams.y = initialY + dy
                        try {
                            if (view.isAttachedToWindow) {
                                wm.updateViewLayout(view, currentParams)
                            }
                        } catch (e: Exception) {
                            // ignore
                        }
                        return true
                    }
                    MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                        bubbleContainer?.animate()?.scaleX(1.0f)?.scaleY(1.0f)?.setDuration(100)?.start()

                        val deltaDist = hypot(
                            (event.rawX - initialTouchX).toDouble(),
                            (event.rawY - initialTouchY).toDouble()
                        )
                        val duration = System.currentTimeMillis() - touchStartTime

                        if (deltaDist <= (touchSlop * 1.5) && duration < 500) {
                            // Click event — Bring Ziggo Driver app to front
                            openApp()
                        } else {
                            // Drag ended — Snap to left or right screen edge
                            snapToEdge()
                        }
                        return true
                    }
                }
                return false
            }
        })

        try {
            wm.addView(view, params)
            isShowing = true
        } catch (e: Exception) {
            isShowing = false
        }
    }

    private fun snapToEdge() {
        val wm = windowManager ?: return
        val view = floatingView ?: return
        val params = layoutParams ?: return

        val displayMetrics = resources.displayMetrics
        val screenWidth = displayMetrics.widthPixels
        val screenHeight = displayMetrics.heightPixels

        val viewWidth = if (view.width > 0) view.width else (64 * displayMetrics.density).toInt()
        val viewHeight = if (view.height > 0) view.height else (64 * displayMetrics.density).toInt()

        val targetX = if (params.x + viewWidth / 2 < screenWidth / 2) {
            0
        } else {
            screenWidth - viewWidth
        }

        val minY = (30 * displayMetrics.density).toInt()
        val maxY = screenHeight - viewHeight - (40 * displayMetrics.density).toInt()
        if (params.y < minY) params.y = minY
        if (params.y > maxY) params.y = maxY

        val animator = ValueAnimator.ofInt(params.x, targetX).apply {
            duration = 220
            interpolator = DecelerateInterpolator()
            addUpdateListener { animation ->
                params.x = animation.animatedValue as Int
                try {
                    if (view.isAttachedToWindow) {
                        wm.updateViewLayout(view, params)
                    }
                } catch (e: Exception) {
                    // ignore
                }
            }
        }
        animator.start()
    }

    private fun openApp() {
        try {
            val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
                )
            } ?: Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
            startActivity(launchIntent)
        } catch (e: Exception) {
            // ignore
        }
    }

    private fun removeFloatingWidget() {
        val wm = windowManager ?: return
        val view = floatingView ?: return
        try {
            if (view.isAttachedToWindow) {
                wm.removeView(view)
            }
        } catch (e: Exception) {
            // ignore
        } finally {
            floatingView = null
            isShowing = false
        }
    }

    override fun onDestroy() {
        removeFloatingWidget()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (_: Exception) {}
        super.onDestroy()
    }
}
