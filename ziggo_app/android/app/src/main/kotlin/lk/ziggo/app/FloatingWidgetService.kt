package lk.ziggo.app

import android.animation.ValueAnimator
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.util.DisplayMetrics
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.animation.DecelerateInterpolator
import kotlin.math.abs
import kotlin.math.hypot

class FloatingWidgetService : Service() {

    companion object {
        const val ACTION_SHOW = "lk.ziggo.app.ACTION_SHOW_FLOATING_WIDGET"
        const val ACTION_HIDE = "lk.ziggo.app.ACTION_HIDE_FLOATING_WIDGET"

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
                context.startService(intent)
            } catch (e: Exception) {
                // Ignore if background start restriction on Android 12+
            }
        }

        fun hide(context: Context) {
            val intent = Intent(context, FloatingWidgetService::class.java).apply {
                action = ACTION_HIDE
            }
            try {
                context.startService(intent)
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
        windowManager = getSystemService(Context.WINDOW_SERVICE) as? WindowManager
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_SHOW

        if (action == ACTION_HIDE) {
            removeFloatingWidget()
            stopSelf()
            return START_NOT_STICKY
        }

        if (action == ACTION_SHOW) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
                stopSelf()
                return START_NOT_STICKY
            }
            addOrUpdateFloatingWidget()
        }

        return START_NOT_STICKY
    }

    private fun addOrUpdateFloatingWidget() {
        if (floatingView != null && isShowing) {
            return
        }

        val wm = windowManager ?: return

        val displayMetrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        wm.defaultDisplay.getMetrics(displayMetrics)
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

                        if (deltaDist < 25 && duration < 350) {
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

        val displayMetrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        wm.defaultDisplay.getMetrics(displayMetrics)
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
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        if (launchIntent != null) {
            startActivity(launchIntent)
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
        super.onDestroy()
    }
}
