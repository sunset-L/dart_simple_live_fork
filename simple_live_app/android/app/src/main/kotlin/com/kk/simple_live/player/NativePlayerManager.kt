package com.kk.simple_live.player

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import android.view.OrientationEventListener
import android.view.Surface
import android.view.animation.AccelerateDecelerateInterpolator
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.TransferListener
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.ui.PlayerView
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * 全局唯一播放器。竖屏与全屏复用同一张原生 PlayerView，小窗使用自己的 TextureView。
 * 视频不进入 Flutter 合成：横竖屏只由 Android 布局改变播放器区域。
 * 输出仅在完整播放页与小窗之间交接，不重建播放器、解码器或网络流。
 */
class NativePlayerManager private constructor() {

    companion object {
        val instance: NativePlayerManager by lazy { NativePlayerManager() }

        const val METHOD_CHANNEL = "simple_live/native_player"
        const val EVENT_CHANNEL = "simple_live/native_player/events"

        private const val TAG = "NativePlayer"
    }

    private var activity: Activity? = null
    private var appContext: Context? = null
    private var methodChannel: MethodChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    private var engine: FlutterEngine? = null

    /** 上次 attach 的引擎，用于识别「引擎已重建」 */
    private var attachedEngine: FlutterEngine? = null

    /**
     * 小窗当前播放的房间。
     *
     * 为什么原生侧也要存一份：
     * 一路返回退到桌面会把 Activity 连同 Flutter 引擎一起销毁，
     * 而小窗是系统级 Window、播放器是本单例，两者都还活着。
     * 重新进入 App 时 Dart 侧是全新的 isolate，FloatingSession 里
     * 房间信息全部丢失，点击小窗就不知道该回哪个直播间。
     * 所以房间里必须由原生侧保管，Dart 启动后再读回去。
     */
    private var floatingSiteId: String? = null
    private var floatingRoomId: String? = null

    /**
     * 用户点了小窗，但当时没有 Dart 侧在监听事件。
     *
     * 场景：一路返回退到桌面后 Activity 与引擎都被销毁，
     * 此时点小窗会触发 [onFloatingTap]，但 eventSink 是 null，
     * emit 出去的 floatingTap 事件直接被丢弃——App 启动后完全不知道
     * 用户点过小窗，于是「点小窗回不到播放页」。
     *
     * 这里记一个标记，等新 Dart 侧订阅上事件流时补发。
     */
    private var pendingFloatingTap = false

    private var player: ExoPlayer? = null
    private var fullscreenView: PlayerView? = null
    var onPrepareFloatingReturn: (() -> Unit)? = null
    var onHoldFullscreenFrame: ((android.graphics.Bitmap?) -> Unit)? = null
    private var returningFromFloating = false
    private var floatingReturnListener: Player.Listener? = null
    fun captureFloatingFrame(): android.graphics.Bitmap? = floatingWindow?.captureFrame()
    fun captureFullscreenFrame(): android.graphics.Bitmap? =
        (fullscreenView?.videoSurfaceView as? android.view.TextureView)?.bitmap


    fun attachFullscreenView(view: PlayerView) {
        fullscreenView = view
        applySurface()
    }

    fun detachFullscreenView(view: PlayerView) {
        if (fullscreenView !== view) return
        view.player = null
        fullscreenView = null
        floatingReturnListener?.let { player?.removeListener(it) }
        floatingReturnListener = null
        returningFromFloating = false
        boundSurface = null
        applySurface()
    }

    fun fullscreenPlayer(): ExoPlayer? = ensurePlayer()

    /** 悬浮窗画面输出 */
    private var floatingSurface: Surface? = null

    /** 当前实际绑定到播放器的 Surface，用于去重 */
    private var boundSurface: Surface? = null

    /** 当前播放地址，重复 open 同一个地址时直接忽略 */
    private var currentUrl: String? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    private var floatingWindow: FloatingPlayerWindow? = null
    private var floatingWindowEnabled = true
    private var floatingWindowCornerRadius = 0f
    private var floatingWindowDockEnabled = true
    private var floatingWindowDockVolumePercent = 30
    // 基准音量与贴边增益独立，避免反复贴边累积压低，也不触碰 AudioManager。
    private var playbackVolume = 1f
    private var floatingDocked = false
    private var floatingVolumeGain = 1f
    private var floatingVolumeTarget = 1f
    private var floatingVolumeAnimator: ValueAnimator? = null

    fun onFloatingDockStateChanged(docked: Boolean, animate: Boolean = true) {
        floatingDocked = docked
        updateFloatingVolumeGain(animate)
    }

    fun setPlaybackVolume(value: Float) {
        playbackVolume = if (value.isFinite()) value.coerceIn(0f, 1f) else 1f
        applyPlaybackVolume()
    }

    private fun applyPlaybackVolume() {
        player?.volume = (playbackVolume * floatingVolumeGain).coerceIn(0f, 1f)
    }

    private fun updateFloatingVolumeGain(animate: Boolean = true) {
        val target = if (floatingDocked) floatingWindowDockVolumePercent / 100f else 1f
        if (animate && target == floatingVolumeTarget) return
        floatingVolumeAnimator?.cancel()
        floatingVolumeAnimator = null
        floatingVolumeTarget = target
        if (!animate || floatingVolumeGain == target) {
            floatingVolumeGain = target
            applyPlaybackVolume()
            return
        }
        val animator = ValueAnimator.ofFloat(floatingVolumeGain, target).apply {
            duration = 800L
            interpolator = AccelerateDecelerateInterpolator()
            addUpdateListener {
                floatingVolumeGain = it.animatedValue as Float
                applyPlaybackVolume()
            }
        }
        floatingVolumeAnimator = animator
        animator.addListener(object : AnimatorListenerAdapter() {
            override fun onAnimationEnd(animation: Animator) {
                if (floatingVolumeAnimator === animator) floatingVolumeAnimator = null
            }
        })
        animator.start()
    }

    /** 全屏原生页面只响应稳定的横向姿态，退出方向由页面宿主管理。 */
    private var deviceOrientationListener: OrientationEventListener? = null
    private var deviceOrientation: Int = OrientationEventListener.ORIENTATION_UNKNOWN
    private var naturalLandscapeDisplay = false
    private var landscapeFullscreen = false
    private var pendingLandscapeOrientation: Int? = null
    private var pendingLandscapeChange: Runnable? = null
    private var orientationChangeAllowedAt = 0L

    /** 悬浮窗是否显示中 */
    var isFloating: Boolean = false
        private set

    /** 是否处于错误状态 */
    private var hasError = false

    /**
     * 「离开前台自动暂停」是否启用。
     *
     * 由 Dart 侧设置项同步过来。原生侧需要自己存，
     * 是因为判断时机在 Activity 离开前台的瞬间，那时 Dart 侧可能已经不在前台。
     */
    private var pauseOnHome = false

    /**
     * 是否已被「离开前台」自动暂停过（用于回来时自动续播）。
     *
     * 【为什么需要这个标记】
     * 只恢复「自己暂停的那一次」。用户手动暂停的播放，回到前台不该被拉起来。
     *
     * 判断「是否小窗播放」**必须问窗口自己**（`floatingWindow?.isWindowShowing()`），
     * 不能用 `floatingWindow != null`：那个对象只在第一次进小窗时创建，
     * 之后不会置空。用它判断会让「离开自动暂停」在用户进过一次小窗后永久失效。
     */
    private var pausedByHome = false
    private var stoppedPageInBackground = false

    /** 最近一次已知的**显示**视频尺寸（只由 VideoSize 回调写入） */
    private var videoWidth = 0
    private var videoHeight = 0

    /**
     * 由 `Format.width/height` 得到的**编码**尺寸，只给播放信息面板兜底用。
     *
     * 【为什么必须和 [videoWidth] 分开存】
     * H.264 的编码尺寸按宏块对齐，1080p 实际编码成 1920×**1088**
     * （多出的 8 行是填充，播放时会被裁掉）。ExoPlayer 的
     * `onVideoSizeChanged` 给的是**裁切后的显示尺寸**（1920×1080），
     * 而 `Format.width/height` 是**编码尺寸**（1920×1088）。
     *
     * 这两个值一旦共用一个字段，就会出现「用一段时间后画面被拉伸」：
     * 打开播放信息面板 → onVideoInputFormatChanged 把 1920×1088 写进
     * videoWidth/videoHeight → Dart 侧 `_syncVideoSize()` 读到 1088，
     * 算出宽高比 1.765（正确是 1.778）→ 画面被轻微拉伸；
     * 而且原来的 VideoSize 回调因为「尺寸没变化」不会再发一次，
     * 所以这个错误值会一直粘住，重启应用才恢复。
     */
    private var metricsWidth = 0
    private var metricsHeight = 0

    /**
     * 当前播放流的显示宽高比（含 SAR 修正），0 表示未知。
     *
     * 单独缓存一份而不是让 Dart 自己用 width/height 相除，
     * 是因为横屏流带 `pixelWidthHeightRatio != 1`（变形宽银幕）时，
     * 直接相除偏差很大，必须乘上 SAR 才是真实显示比例。
     */
    private var videoAspect = 0.0

    // ------------------------------------------------ 播放参数（信息面板用）
    //
    // 【为什么不能只读 Format】
    // 直播流的 Format 里 bitrate / frameRate 基本都是 -1（未知）：
    // FLV/HLS 的 manifest 与首个媒体包并不携带这两个值，
    // ExoPlayer 只把 mimeType / codecs / 分辨率填进去。
    // 所以「用户选了 1080P 就显示 1080P」那种做法只能拿到**期望值**，
    // 不是这条流真实的样子。
    //
    // 要拿到真实数据只能实测：
    // - 码率：统计 HTTP 实际收到的字节数 / 经过的时间
    //   （TransferListener 拿到的是真正的网络字节，含容器开销，
    //    这才是用户说的「视频流的信息」）；
    // - 帧率：数一共渲染了多少帧 / 经过的时间
    //   （AnalyticsListener.onRenderedFirstFrame + FrameProcessingOffset
    //    不够用，直接按解码输出帧计数更准）。
    //
    // 这些字段只在面板打开时维护，[metricsListening] 为 false 时全部短路。

    /** 面板是否打开中；false 时指标采集全部短路 */
    @Volatile
    private var metricsListening = false

    /** 视频编码格式名，如 avc1.640028 / hvc1.1.6.L120 */
    private var videoCodec = ""

    /** 实测码率（bps）：0 表示还没采到 */
    private var measuredBitrate = 0L

    /** 实测帧率 */
    private var measuredFrameRate = 0f

    /** 静态信息里能拿到的标称码率（常常是 -1，仅作参考） */
    private var declaredBitrate = 0

    /** 静态信息里能拿到的标称帧率（常常是 0，仅作参考） */
    private var declaredFrameRate = 0f

    /** 音频编码格式名 */
    private var audioCodec = ""

    /** 音频声道数 */
    private var audioChannels = 0

    /** 音频采样率 */
    private var audioSampleRate = 0

    // --- 码率统计：累计字节 + 起始时刻
    private var loadStartBytes = 0L
    private var loadStartTime = 0L
    private var totalLoadedBytes = 0L

    // --- 帧率统计：累计渲染帧数 + 起始时刻
    private var totalRenderedFrames = 0L
    private var frameCountStartTime = 0L
    private var frameCountBaseline = 0L

    // ---------------------------------------------------------------- 初始化

    fun attach(activity: Activity, engine: FlutterEngine) {
        if (this.activity !== activity) {
            deviceOrientationListener?.disable()
            deviceOrientationListener = null
            stopLandscapeOrientationChanges()
        }
        this.activity = activity
        this.appContext = activity.applicationContext
        if (deviceOrientationListener == null) {
            initDeviceOrientationListener(activity)
        }

        // 引擎重建只重绑业务通道，不改变原生播放页/小窗的视频输出。
        if (attachedEngine !== engine) {
            methodChannel = null
            eventSink = null
            attachedEngine = engine
        }

        this.engine = engine

        if (methodChannel == null) {
            methodChannel = MethodChannel(
                engine.dartExecutor.binaryMessenger,
                METHOD_CHANNEL
            ).also { channel ->
                channel.setMethodCallHandler { call, result ->
                    handleMethodCall(call.method, call.arguments, result)
                }
            }

            EventChannel(engine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
                .setStreamHandler(object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                        eventSink = events
                        // 新 Dart 侧刚订阅上事件流：如果小窗还开着，
                        // 立刻补发一次「小窗还在」的信号，
                        // 否则 Dart 侧不知道播放器还在跑。
                        if (isFloating) {
                            emit("floatingRestored")
                        }
                        // 如果用户在引擎销毁期间点过小窗，这里补发，
                        // 否则这次点击就永远丢了。
                        if (pendingFloatingTap) {
                            pendingFloatingTap = false
                            emit("floatingTap")
                        }
                    }

                    override fun onCancel(arguments: Any?) {
                        eventSink = null
                    }
                })
        } else {
            // Channel 已存在但监听的引擎变了，重建一次
            methodChannel?.setMethodCallHandler { call, result ->
                handleMethodCall(call.method, call.arguments, result)
            }
        }

        // 注意：这里不做任何「关闭悬浮窗」的清理。
        // 悬浮窗代表正在进行的播放，Activity 重建不应该把它关掉。
    }

    /**
     * Activity 销毁时由 MainActivity 调用。
     *
     * 必须把 Channel / Sink / engine 引用一起清掉，原因：
     *
     * 直播页返回进小窗后一路退到桌面，Activity 与 FlutterEngine 会被销毁，
     * 但系统级悬浮窗还挂在 WindowManager 上，进程因此不会退出。
     * 此时如果用户点小窗，[onFloatingTap] 会走 emit 把事件发给 eventSink——
     * 那个 sink 属于**已经销毁的引擎**，往它的 messenger 上发消息会直接崩
     * （这就是「多次小窗测试偶现闪退」的来源），
     * 而且就算没崩，事件也已经丢了，Dart 侧永远不知道该回哪个直播间
     * （「点小窗回不去」）。
     *
     * 清空之后 eventSink 为 null，onFloatingTap 会正确地把点击记成
     * pendingFloatingTap，等新引擎的 Dart 侧订阅时补发。
     */
    fun detachActivity() {
        onPrepareFloatingReturn = null
        onHoldFullscreenFrame = null
        fullscreenView?.let { detachFullscreenView(it) }
        deviceOrientationListener?.disable()
        deviceOrientationListener = null
        stopLandscapeOrientationChanges()
        activity = null
    }

    /**
     * 小窗此刻是否真的显示在屏幕上。
     *
     * 【绝不能写成 `floatingWindow != null`】
     * 那个字段只是个可复用的窗口对象，用户第一次进小窗时创建，
     * 之后**永远不会被置空**。用它判断「现在是不是小窗播放」，
     * 会让「离开前台自动暂停」在用户进过一次小窗之后永远失效——
     * 这正是「开了开关却不生效」的根因。
     * 必须问窗口自己当前是否可见。
     */
    private fun isFloatingVisible(): Boolean = floatingWindow?.isWindowShowing() == true

    /**
     * Activity 离开前台时调用（由 MainActivity 的 onPause / onUserLeaveHint 转发）。
     *
     * 【触发条件：只有例外，没有白名单】
     * 需求是「进入后台就暂停」，只有这一种情况**不暂停**：
     * - **小窗正在显示**：小窗存在的意义就是退到后台继续看，
     *   暂停了用户点回来还得手动点一下，比不暂停更糟。
     *
     * 拉下通知栏不暂停，但这不是靠「识别通知栏」做到的：
     * 通知栏展开**不会**让 Activity 离开前台，系统根本不回调 onPause，
     * 所以天然不受影响，不需要额外判断，也不会被这里误伤。
     *
     * 来电、锁屏、按 Home 键、按最近任务键都会走到这里，一律暂停。
     *
     * 后台暂停不清原生视频输出，回前台后直接恢复。
     */
    fun onBackground() {
        // 完整播放页退到后台必须停网络/解码，不受旧的“按 Home 暂停”选项影响。
        if (fullscreenView != null && !isFloatingVisible() && !isFloating) {
            if (!stoppedPageInBackground) {
                stoppedPageInBackground = true
                stop()
                Log.d(TAG, "player page suspended: stream stopped")
            }
            return
        }
        if (!pauseOnHome) {
            return
        }
        // 小窗在播时无论什么原因都不暂停
        if (isFloatingVisible() || isFloating) {
            return
        }
        val p = player ?: return
        // 已经暂停就不要再改标记：那可能是用户自己停的
        if (!p.playWhenReady) {
            return
        }
        p.playWhenReady = false
        pausedByHome = true
        Log.d(TAG, "app went background, paused playback")
    }

    /**
     * App 回到前台时调用（由 MainActivity.onResume 转发）。
     *
     * 只为「自动暂停」这一种情况恢复播放：
     * 用 [pausedByHome] 标记，就不会把用户自己手动暂停的播放重新拉起来。
     * 恢复放在这里而不是靠 Dart 侧，是因为此时页面可能还没构建完，
     * 早点让播放器重新拉流，画面能更早回来。
     */
    fun onUserReturn() {
        if (stoppedPageInBackground) {
            // Dart 重新读取房间及最新地址；不能直接重播可能过期的旧地址。
            stoppedPageInBackground = false
            return
        }
        if (!pausedByHome) {
            return
        }
        pausedByHome = false
        // 小窗期间被打开的话不要抢：小窗自己有播放状态
        if (isFloating || isFloatingVisible()) {
            return
        }
        player?.playWhenReady = true
        Log.d(TAG, "app returned to foreground, resumed playback")
    }

    private fun windowOrientation(act: Activity): Int {
        val view = act.window.decorView
        if (view.width > 0 && view.height > 0) {
            return if (view.width > view.height) {
                Configuration.ORIENTATION_LANDSCAPE
            } else {
                Configuration.ORIENTATION_PORTRAIT
            }
        }
        return act.resources.configuration.orientation
    }

    fun clearFullscreenOrientation() { stopLandscapeOrientationChanges() }

    private fun stopLandscapeOrientationChanges() {
        landscapeFullscreen = false
        cancelPendingLandscapeChange()
    }

    private fun cancelPendingLandscapeChange() {
        pendingLandscapeChange?.let { mainHandler.removeCallbacks(it) }
        pendingLandscapeChange = null
        pendingLandscapeOrientation = null
    }

    private fun initDeviceOrientationListener(act: Activity) {
        val rotation = act.window.decorView.display?.rotation ?: Surface.ROTATION_0
        val quarterTurn = rotation == Surface.ROTATION_90 || rotation == Surface.ROTATION_270
        naturalLandscapeDisplay =
            (windowOrientation(act) == Configuration.ORIENTATION_LANDSCAPE) != quarterTurn
        deviceOrientation = OrientationEventListener.ORIENTATION_UNKNOWN
        deviceOrientationListener = object : OrientationEventListener(act.applicationContext) {
            override fun onOrientationChanged(orientation: Int) {
                deviceOrientation = orientation
                val target = landscapeOrientationForDevice(orientation)
                if (!landscapeFullscreen || activity !== act || !act.hasWindowFocus() ||
                    target == null || target == act.requestedOrientation
                ) {
                    cancelPendingLandscapeChange()
                    return
                }
                if (target == pendingLandscapeOrientation) return
                cancelPendingLandscapeChange()
                pendingLandscapeOrientation = target
                pendingLandscapeChange = Runnable {
                    pendingLandscapeChange = null
                    pendingLandscapeOrientation = null
                    if (landscapeFullscreen && activity === act && act.hasWindowFocus() &&
                        landscapeOrientationForDevice(deviceOrientation) == target
                    ) {
                        // 有效横向姿态持续 300ms 才翻向，竖着拿或平放时保持点击方向。
                        orientationChangeAllowedAt = SystemClock.uptimeMillis() + 600L
                        act.requestedOrientation = target
                    }
                }.also {
                    val delay = maxOf(300L, orientationChangeAllowedAt - SystemClock.uptimeMillis())
                    mainHandler.postDelayed(it, delay)
                }
            }
        }.also { it.enable() }
    }

    private fun landscapeOrientationForDevice(degrees: Int): Int? {
        if (degrees == OrientationEventListener.ORIENTATION_UNKNOWN) return null
        val rotation = when (degrees) {
            in 0..30, in 330..359 -> Surface.ROTATION_0
            in 60..120 -> Surface.ROTATION_270
            in 150..210 -> Surface.ROTATION_180
            in 240..300 -> Surface.ROTATION_90
            else -> return null
        }
        val normal = if (naturalLandscapeDisplay) Surface.ROTATION_0 else Surface.ROTATION_90
        val reverse = if (naturalLandscapeDisplay) Surface.ROTATION_180 else Surface.ROTATION_270
        return when (rotation) {
            normal -> ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
            reverse -> ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE
            else -> null
        }
    }

    private fun orientationForWindow(orientation: Int, rotation: Int?): Int {
        val landscape = orientation == Configuration.ORIENTATION_LANDSCAPE
        val normal = if (landscape) ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
            else ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        val reverse = if (landscape) ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE
            else ActivityInfo.SCREEN_ORIENTATION_REVERSE_PORTRAIT
        val reverseRotation = if (landscape) {
            if (naturalLandscapeDisplay) Surface.ROTATION_180 else Surface.ROTATION_270
        } else {
            if (naturalLandscapeDisplay) Surface.ROTATION_270 else Surface.ROTATION_180
        }
        return if (rotation == reverseRotation) reverse else normal
    }

    /** 原生页面的横向姿态稳定后翻向；退出/离房的方向恢复由 NativePlayerHost 单独负责。 */
    fun setScreenOrientation(mode: String?) {
        val act = activity ?: return
        cancelPendingLandscapeChange()
        landscapeFullscreen = mode == "landscape"
        orientationChangeAllowedAt = SystemClock.uptimeMillis() + 600L
        act.requestedOrientation = if (landscapeFullscreen) {
            landscapeOrientationForDevice(deviceOrientation)
                ?: if (windowOrientation(act) == Configuration.ORIENTATION_LANDSCAPE) {
                    orientationForWindow(Configuration.ORIENTATION_LANDSCAPE, act.window.decorView.display?.rotation)
                } else ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
        } else ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
    }

    /** 引擎已销毁：把所有与引擎绑定的引用清空 */
    fun detachEngine() {
        // 播放页由宿主解绑，小窗输出不属于 FlutterEngine，不能在此清掉。
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        eventSink = null
        engine = null
        attachedEngine = null
    }

    // ---------------------------------------------------------------- Channel

    private fun handleMethodCall(method: String, arguments: Any?, result: MethodChannel.Result) {
        when (method) {
            "open" -> {
                val args = arguments as? Map<*, *>
                if (args == null) {
                    result.error("bad_args", "参数缺失", null)
                    return
                }
                val url = args["url"] as? String
                if (url.isNullOrEmpty()) {
                    result.error("bad_args", "播放地址为空", null)
                    return
                }
                val headers = (args["headers"] as? Map<*, *>)?.entries
                    ?.associate { it.key.toString() to it.value.toString() }
                open(url, headers, args["forceReload"] == true)
                result.success(true)
            }

            "play" -> {
                player?.playWhenReady = true
                result.success(true)
            }

            // 无缝换源：保持播放器实例、Surface、解码器不变，只替换媒体源。
            // 用于直播地址签名过期后的续播——不重建播放器就不会出现黑屏加载。
            "switchSource" -> {
                val args = arguments as? Map<*, *>
                val url = args?.get("url") as? String
                if (url.isNullOrEmpty()) {
                    result.error("bad_args", "播放地址为空", null)
                    return
                }
                val headers = (args["headers"] as? Map<*, *>)?.entries
                    ?.associate { it.key.toString() to it.value.toString() }
                if (player == null) {
                    result.error("no_player", "播放器已关闭", null)
                    return
                }
                switchSource(url, headers)
                result.success(true)
            }

            // 原生播放器当前是否还有可用的流（用于判断能否直接接管而不是重新取流）
            "hasActiveStream" -> result.success(hasActiveStream())

            // 小窗里正在播的房间。Dart 启动时读回，用于恢复 FloatingSession。
            "getFloatingRoom" -> {
                if (!isFloating || floatingSiteId == null || floatingRoomId == null) {
                    result.success(null)
                } else {
                    result.success(
                        mapOf(
                            "siteId" to floatingSiteId,
                            "roomId" to floatingRoomId,
                        )
                    )
                }
            }

            "setFloatingRoom" -> {
                val args = arguments as? Map<*, *>
                floatingSiteId = args?.get("siteId") as? String
                floatingRoomId = args?.get("roomId") as? String
                result.success(true)
            }

            // ------------------------------------------------------ 小窗弹幕
            //
            // 小窗是系统悬浮窗，进小窗时 Flutter 渲染树已经销毁，
            // 弹幕只能由原生绘制。这三个方法负责把「是否显示」「样式」「内容」
            // 从小窗播放期间仍存活的 Dart 侧（FloatingSession）送进来。
            "setFloatingDanmakuEnabled" -> {
                val args = arguments as? Map<*, *>
                val enabled = args?.get("enabled") as? Boolean ?: false
                val applied = floatingWindow?.setDanmakuEnabled(enabled) ?: false
                result.success(applied)
            }

            "setFloatingDanmakuOptions" -> {
                val args = arguments as? Map<*, *>
                val window = floatingWindow
                if (window == null) {
                    // 小窗还没建：静默成功，等窗口建好 Dart 侧会再同步一次
                    result.success(true)
                } else {
                    window.updateDanmakuOptions(
                        fontSize = (args?.get("fontSize") as? Number)?.toFloat() ?: 16f,
                        fontWeight = (args?.get("fontWeight") as? Number)?.toInt() ?: 4,
                        opacity = (args?.get("opacity") as? Number)?.toFloat() ?: 1f,
                        area = (args?.get("area") as? Number)?.toFloat() ?: 0.8f,
                        duration = (args?.get("duration") as? Number)?.toInt() ?: 10,
                        topMargin = (args?.get("topMargin") as? Number)?.toFloat() ?: 0f,
                        bottomMargin = (args?.get("bottomMargin") as? Number)?.toFloat() ?: 0f,
                        maxConcurrent = (args?.get("maxConcurrent") as? Number)?.toInt() ?: 8,
                    )
                    result.success(true)
                }
            }

            "addFloatingDanmaku" -> {
                val args = arguments as? Map<*, *>
                val window = floatingWindow
                if (window != null) {
                    // 一次可以送多条：直播弹幕是批量的，
                    // 每条一次 channel 往返会明显增加主线程开销。
                    val items = args?.get("items") as? List<*>
                    if (items != null) {
                        for (raw in items) {
                            val item = raw as? Map<*, *> ?: continue
                            val text = item["text"] as? String ?: continue
                            if (text.isEmpty()) continue
                            val color = (item["color"] as? Number)?.toInt()
                                ?: android.graphics.Color.WHITE
                            window.addDanmaku(text, color)
                        }
                    } else {
                        val text = args?.get("text") as? String
                        if (!text.isNullOrEmpty()) {
                            val color = (args?.get("color") as? Number)?.toInt()
                                ?: android.graphics.Color.WHITE
                            window.addDanmaku(text, color)
                        }
                    }
                }
                result.success(true)
            }

            "clearFloatingDanmaku" -> {
                floatingWindow?.clearDanmaku()
                result.success(true)
            }

            "pause" -> {
                player?.playWhenReady = false
                result.success(true)
            }

            // 「按 Home 键自动暂停」开关。
            //
            // 只有 Dart 侧把这个开关打开、且当前**不是小窗播放**时才生效，
            // 具体判断在 onUserLeaveHint()。
            "setPauseOnHome" -> {
                pauseOnHome = arguments as? Boolean ?: false
                result.success(true)
            }

            // 初始方向由点击决定，后续翻向由稳定的物理姿态决定。
            // arguments: "landscape" / "portrait" / "restore" / "auto"
            "setScreenOrientation" -> {
                setScreenOrientation(arguments as? String)
                result.success(true)
            }

            "stop" -> {
                stop()
                result.success(true)
            }

            "release" -> {
                release()
                result.success(true)
            }

            "releaseAll" -> {
                releaseAll()
                result.success(true)
            }

            "setVolume" -> {
                val volume = (arguments as? Number)?.toFloat() ?: 1f
                setPlaybackVolume(volume)
                result.success(true)
            }

            "getSystemVolumeState" -> {
                handleSystemVolume(null, result)
            }

            "setSystemVolumeIndex" -> {
                val index = arguments as? Int
                if (index == null) {
                    result.error("bad_args", "系统音量档位必须为整数", null)
                    return
                }
                handleSystemVolume(index, result)
            }

            "isPlaying" -> result.success(player?.isPlaying == true)

            // 当前正在播放的地址（播放信息面板展示、排障用）
            "getCurrentUrl" -> result.success(currentUrl)

            // 当前视频真实分辨率。
            //
            // videoSize 事件只在尺寸「变化」时发射，复用播放器
            // （小窗回页面、再次进同一主播）时新页面收不到事件，
            // 必须能被主动查询一次，否则 videoAspectRatio / isVertical
            // 会停在默认值，表现为「横屏视频双击全屏不转横屏」。
            "getVideoSize" -> {
                if (videoWidth <= 0 || videoHeight <= 0) {
                    result.success(null)
                } else {
                    result.success(
                        mapOf(
                            "width" to videoWidth,
                            "height" to videoHeight,
                            // 带上 SAR 修正后的真实宽高比，Dart 侧优先用它
                            // 参与布局，不要自己拿 width/height 相除。
                            "aspectRatio" to videoAspect,
                        )
                    )
                }
            }

            // 开关播放参数采集。
            //
            // 面板打开时传 true，原生侧开始采集并通过 EventChannel 推
            // "metrics" 事件；关闭时传 false，采集逻辑全部短路，
            // 不再有任何计算和回调（需求要求「关闭后不在后台继续监听」）。
            "setMetricsListening" -> {
                val listening = arguments as? Boolean ?: false
                setMetricsListening(listening)
                result.success(true)
            }

            // 主动读一次播放参数（面板刚打开、或事件还没到时用）
            "getPlaybackMetrics" -> result.success(readPlaybackMetrics())

            "setFloatingWindowSettings" -> {
                val args = arguments as? Map<*, *>
                floatingWindowEnabled = args?.get("enabled") as? Boolean ?: true
                val radius = (args?.get("cornerRadius") as? Number)?.toFloat() ?: 0f
                floatingWindowCornerRadius = if (radius.isFinite()) radius.coerceIn(0f, 16f) else 0f
                floatingWindowDockEnabled = args?.get("dockEnabled") as? Boolean ?: true
                // 百分比优先；兼容旧开关参数，100%时贴边也保持原音量。
                floatingWindowDockVolumePercent = (args?.get("dockVolumePercent") as? Number)
                    ?.toInt()?.coerceIn(10, 100)
                    ?: if (args?.get("dockVolumeEnabled") == false) 100 else 30
                floatingWindow?.updateSettings(
                    floatingWindowCornerRadius,
                    floatingWindowDockEnabled
                )
                updateFloatingVolumeGain()
                // 关闭正在播放的小窗时由现有会话回到直播页，不销毁播放器或断流。
                if (!floatingWindowEnabled && isFloating) onFloatingTap()
                result.success(true)
            }

            "enterFloating" -> {
                val args = arguments as? Map<*, *>
                val width = (args?.get("width") as? Number)?.toInt() ?: 480
                val height = (args?.get("height") as? Number)?.toInt() ?: 270
                result.success(enterFloating(width, height))
            }

            "exitFloating" -> {
                val handover = (arguments as? Map<*, *>)?.get("handoverToPage") == true
                exitFloating(handover)
                result.success(true)
            }

            "isFloating" -> result.success(isFloating)

            "hasOverlayPermission" -> result.success(hasOverlayPermission())

            "requestOverlayPermission" -> {
                requestOverlayPermission()
                result.success(true)
            }

            "isTvDevice" -> result.success(isTvDevice())

            "bringToFront" -> {
                bringAppToFront()
                result.success(true)
            }

            "moveToBack" -> {
                moveTaskToBack()
                result.success(true)
            }

            else -> result.notImplemented()
        }
    }

    /** 系统媒体音量与 ExoPlayer 增益独立；读取不创建或启动播放器。 */
    private fun handleSystemVolume(index: Int?, result: MethodChannel.Result) {
        val audioManager = appContext
            ?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        if (audioManager == null) {
            result.error("system_volume_unavailable", "系统音量服务不可用", null)
            return
        }
        try {
            val stream = AudioManager.STREAM_MUSIC
            var maxIndex = audioManager.getStreamMaxVolume(stream).coerceAtLeast(0)
            if (index != null) {
                val target = index.coerceIn(0, maxIndex)
                if (audioManager.getStreamVolume(stream) != target) {
                    audioManager.setStreamVolume(stream, target, 0)
                }
                // 输出设备可能发生变化，或音量被系统安全策略限制。
                maxIndex = audioManager.getStreamMaxVolume(stream).coerceAtLeast(0)
            }
            val currentIndex = audioManager.getStreamVolume(stream).coerceIn(0, maxIndex)
            result.success(mapOf("currentIndex" to currentIndex, "maxIndex" to maxIndex))
        } catch (e: Exception) {
            Log.w(TAG, "system volume failed: $e")
            result.error("system_volume_error", "无法读取或设置系统音量", null)
        }
    }

    private fun emit(type: String, payload: Map<String, Any?> = emptyMap()) {
        mainHandler.post {
            val sink = eventSink
            // 双保险：sink 可能属于已经销毁的引擎。
            // （normal 路径由 detachEngine 清干净，这里防的是漏清理的情况，
            //  或 post 到主线程执行前引擎刚好被销毁的竞态）
            if (sink == null || engine == null) {
                if (type == "floatingTap") {
                    // 事件没人收，记下来等新引擎订阅时补发
                    pendingFloatingTap = true
                }
                return@post
            }
            val data = HashMap<String, Any?>(payload)
            data["type"] = type
            try {
                sink.success(data)
            } catch (e: Exception) {
                // 引擎销毁过程中发送会抛，不能让它把进程带崩
                Log.w(TAG, "emit $type failed: $e")
                eventSink = null
                if (type == "floatingTap") {
                    pendingFloatingTap = true
                }
            }
        }
    }

    // ---------------------------------------------------------------- 播放控制

    private fun ensurePlayer(): ExoPlayer? {
        val context = appContext ?: return null
        player?.let { return it }

        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(
                3000,   // minBufferMs：直播不必囤太多，压低首开延迟
                15000,  // maxBufferMs
                800,    // bufferForPlaybackMs
                1200    // bufferForPlaybackAfterRebufferMs
            )
            .build()

        val exoPlayer = ExoPlayer.Builder(context)
            .setLoadControl(loadControl)
            .build()

        exoPlayer.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                when (playbackState) {
                    Player.STATE_BUFFERING -> emit("buffering", mapOf("value" to true))
                    Player.STATE_READY -> {
                        emit("buffering", mapOf("value" to false))
                        emit("playing", mapOf("value" to exoPlayer.isPlaying))
                    }
                    Player.STATE_ENDED -> emit("completed")
                    Player.STATE_IDLE -> {}
                }
            }

            override fun onIsPlayingChanged(isPlaying: Boolean) {
                emit("playing", mapOf("value" to isPlaying))
            }

            override fun onPlayerError(error: PlaybackException) {
                hasError = true
                emit(
                    "error",
                    mapOf("value" to (error.errorCodeName + ": " + (error.message ?: "")))
                )
            }

            override fun onVideoSizeChanged(videoSize: VideoSize) {
                if (videoSize.width <= 0 || videoSize.height <= 0) {
                    return
                }
                // 显示宽高比要带上 SAR：横屏变形宽银幕流（pixelWidthHeightRatio != 1）
                // 直接用 width/height 相除会明显偏窄或偏宽。
                val sarRaw = videoSize.pixelWidthHeightRatio.toDouble()
                // SAR 可能是脏数据（某些转码流会给出 0、负数、NaN 或大得离谱的值），
                // 直接乘上去会把 aspect 放大几十倍，Dart 侧按 `1000 / aspect`
                // 算高度就成了「一条线」。这里先自己挡一道：只接受
                // 0.5~2.0 这个合理区间，其余一律当 1 处理。
                //
                // Dart 侧还会用 w/h 做交叉验证，两层校验各管一段，
                // 因为「脏数据从哪来」不确定，不能只靠一边。
                val sar = if (sarRaw.isFinite() && sarRaw in 0.5..2.0) sarRaw else 1.0
                val newAspect = videoSize.width * sar / videoSize.height

                val sizeChanged =
                    videoWidth != videoSize.width || videoHeight != videoSize.height
                val aspectChanged = kotlin.math.abs(videoAspect - newAspect) > 0.0001

                videoWidth = videoSize.width
                videoHeight = videoSize.height
                videoAspect = newAspect.toDouble()

                if (sizeChanged || aspectChanged) {
                    // Media3 自行布局原生 PlayerView；尺寸变化不手动重绑输出。
                    emit(
                        "videoSize",
                        mapOf(
                            "width" to videoSize.width,
                            "height" to videoSize.height,
                            // Dart 侧优先用这个值算宽高比，避免自己相除时
                            // 忽略 SAR 与旋转。
                            "aspectRatio" to newAspect.toDouble(),
                        )
                    )
                }
            }
        })

        // 采集真实播放参数。
        //
        // 只用 Player.Listener 拿不到 Format；但拿到 Format 也没用——
        // 直播流的 bitrate / frameRate 绝大多数是 -1/0（未知）。
        // 所以这里分两路：
        // 1) Format 只用来取 codecs / 分辨率 / 声道这些**静态**信息；
        // 2) 码率、帧率一律靠实测（见 TransferListener 与 onRenderedFirstFrame）。
        exoPlayer.addAnalyticsListener(object : AnalyticsListener {
            override fun onVideoInputFormatChanged(
                eventTime: AnalyticsListener.EventTime,
                format: Format,
                decoderReuseEvaluation: androidx.media3.exoplayer.DecoderReuseEvaluation?
            ) {
                if (!metricsListening) {
                    return
                }
                videoCodec = format.codecs ?: format.sampleMimeType ?: ""
                // 标称值仅作兜底参考，实测值优先
                declaredBitrate = if (format.bitrate > 0) format.bitrate else 0
                declaredFrameRate = if (format.frameRate > 0f) format.frameRate else 0f
                if (format.width > 0 && format.height > 0) {
                    // ⚠️ 只写 metrics 专用的字段，**绝不能**碰 videoWidth/videoHeight。
                    // Format 里是编码尺寸（1080p = 1920×1088，按宏块对齐），
                    // 而布局要用的是 VideoSize 给的裁切后显示尺寸（1920×1080）。
                    // 写混了会让画面宽高比偏一点点，表现为「用一段时间后画面拉伸」。
                    metricsWidth = format.width
                    metricsHeight = format.height
                }
                emitMetrics()
            }

            override fun onAudioInputFormatChanged(
                eventTime: AnalyticsListener.EventTime,
                format: Format,
                decoderReuseEvaluation: androidx.media3.exoplayer.DecoderReuseEvaluation?
            ) {
                if (!metricsListening) {
                    return
                }
                audioCodec = format.codecs ?: format.sampleMimeType ?: ""
                audioChannels = format.channelCount
                audioSampleRate = format.sampleRate
                emitMetrics()
            }

            // 每渲染出一帧视频就计数：帧率 = 帧数 / 持续时间。
            // 这是唯一能拿到直播真实帧率的办法（Format.frameRate 基本不可用）。
            override fun onVideoFrameProcessingOffset(
                eventTime: AnalyticsListener.EventTime,
                totalProcessingOffsetUs: Long,
                frameCount: Int
            ) {
                if (!metricsListening) {
                    return
                }
                totalRenderedFrames += frameCount.toLong()
                if (frameCountStartTime == 0L) {
                    frameCountStartTime = System.currentTimeMillis()
                    frameCountBaseline = 0L
                    return
                }
                val elapsedMs = System.currentTimeMillis() - frameCountStartTime
                // 至少要采够 1 秒再算，否则抖动极大
                if (elapsedMs >= 1000) {
                    val frames = totalRenderedFrames - frameCountBaseline
                    measuredFrameRate = frames * 1000f / elapsedMs
                }
            }

            override fun onVideoSizeChanged(
                eventTime: AnalyticsListener.EventTime,
                videoSize: VideoSize
            ) {
                if (!metricsListening || videoSize.width <= 0 || videoSize.height <= 0) {
                    return
                }
                // 这两个字段已经由上面的 Player.Listener.onVideoSizeChanged 统一维护
                // （显示尺寸 + SAR 修正），这里不再重复写入，只把面板数据推出去，
                // 避免两套写入逻辑各自为政。
                emitMetrics()
            }
        })

        player = exoPlayer
        applyPlaybackVolume()
        boundSurface = null
        applySurface()
        return exoPlayer
    }

    /** 把当前实测到的播放参数推给 Dart 侧 */
    private fun emitMetrics() {
        if (!metricsListening) {
            return
        }
        // 码率优先用实测值；实测还没出来时才退回标称值
        val bitrate = if (measuredBitrate > 0) measuredBitrate else declaredBitrate.toLong()
        // 帧率同理
        val frameRate = if (measuredFrameRate > 0f) measuredFrameRate else declaredFrameRate
        emit("metrics", mapOf(
            // 面板要展示的是编码尺寸，用 metricsWidth/metricsHeight；
            // 布局用的 videoWidth/videoHeight 不能被宏块对齐值污染。
            "width" to metricsWidth,
            "height" to metricsHeight,
            "aspectRatio" to videoAspect,
            // videoBitrate 是**整条流**的实测码率（音视频合计，含容器开销），
            // 这正是用户在播放器里看到的那个数字
            "videoBitrate" to bitrate,
            "frameRate" to frameRate,
            "videoCodec" to videoCodec,
            "audioCodec" to audioCodec,
            "audioChannels" to audioChannels,
            "audioSampleRate" to audioSampleRate,
            // 实测还是标称，UI 上要能区分，否则数字来源不明
            "bitrateMeasured" to (measuredBitrate > 0),
            "frameRateMeasured" to (measuredFrameRate > 0f),
            "url" to (currentUrl ?: ""),
        ))
    }

    /**
     * 统计真实下载速率。
     *
     * 这是「码率」的可靠来源：直播流不断有新的媒体包进来，
     * 按「累计字节 / 累计时长」算出来的就是当前实际消费的带宽，
     * 也就是这条视频流真实的码率（含容器与音频开销）。
     *
     * 每次 onLoadCompleted 后重置基准，避免长时间播放后
     * 早期的高码率把当前值拉高（比如起播时缓冲了几十秒）。
     */
    private inner class BitrateTransferListener : TransferListener {
        override fun onTransferInitializing(
            source: DataSource,
            dataSpec: DataSpec,
            isNetwork: Boolean
        ) {}

        override fun onTransferStart(
            source: DataSource,
            dataSpec: DataSpec,
            isNetwork: Boolean
        ) {
            if (!metricsListening) {
                return
            }
            if (loadStartTime == 0L) {
                loadStartTime = System.currentTimeMillis()
                loadStartBytes = totalLoadedBytes
            }
        }

        override fun onBytesTransferred(
            source: DataSource,
            dataSpec: DataSpec,
            isNetwork: Boolean,
            bytesTransferred: Int
        ) {
            if (!metricsListening || !isNetwork) {
                return
            }
            totalLoadedBytes += bytesTransferred
            val now = System.currentTimeMillis()
            if (loadStartTime == 0L) {
                loadStartTime = now
                loadStartBytes = totalLoadedBytes
                return
            }
            val elapsed = now - loadStartTime
            // 采样窗口至少 2 秒：短窗口会把突发流量算成极高的码率
            if (elapsed >= 2000) {
                val bytes = totalLoadedBytes - loadStartBytes
                measuredBitrate = bytes * 8 * 1000 / elapsed
            }
        }

        override fun onTransferEnd(
            source: DataSource,
            dataSpec: DataSpec,
            isNetwork: Boolean
        ) {}
    }

    fun readPlaybackMetrics(): Map<String, Any> {
        reloadMetricsFromTracks()
        return mapOf(
            "width" to metricsWidth, "height" to metricsHeight,
            "aspectRatio" to videoAspect,
            "videoBitrate" to if (measuredBitrate > 0) measuredBitrate else declaredBitrate.toLong(),
            "frameRate" to if (measuredFrameRate > 0f) measuredFrameRate else declaredFrameRate,
            "videoCodec" to videoCodec, "audioCodec" to audioCodec,
            "audioChannels" to audioChannels, "audioSampleRate" to audioSampleRate,
            "bitrateMeasured" to (measuredBitrate > 0),
            "frameRateMeasured" to (measuredFrameRate > 0f),
            "url" to (currentUrl ?: ""),
        )
    }

    /** 开/关播放参数采集。关闭后不再采集也不再回调 Dart。 */
    fun setMetricsListening(listening: Boolean) {
        metricsListening = listening
        if (listening) {
            // 重新开始测量：清掉上一次打开面板时的累计值，
            // 否则「关掉再打开」会立刻显示一个旧的、与当前流无关的码率。
            resetMetricsSampling()
            reloadMetricsFromTracks()
            emitMetrics()
        } else {
            videoCodec = ""
            measuredBitrate = 0
            measuredFrameRate = 0f
            declaredBitrate = 0
            declaredFrameRate = 0f
            audioCodec = ""
            audioChannels = 0
            audioSampleRate = 0
            resetMetricsSampling()
        }
    }

    private fun resetMetricsSampling() {
        loadStartBytes = totalLoadedBytes
        loadStartTime = System.currentTimeMillis()
        frameCountBaseline = totalRenderedFrames
        frameCountStartTime = System.currentTimeMillis()
        measuredBitrate = 0
        measuredFrameRate = 0f
    }

    /**
     * 从当前已解码的轨道信息里读取**静态**参数（编码、分辨率、声道）。
     *
     * 用户打开面板时流往往已经播了很久，onVideoInputFormatChanged
     * 早就回调完了，必须回读一次 currentTracks，
     * 否则编码/分辨率会显示「未知」。
     *
     * 注意：这里**不**读 bitrate / frameRate —— 直播流的这两个字段
     * 绝大多数是 -1/0，读出来只会得到一个假的「未知」，
     * 真实的码率/帧率由 TransferListener 与帧计数实测得到。
     */
    private fun reloadMetricsFromTracks() {
        try {
            val tracks = player?.currentTracks ?: return
            // 视频分辨率取到一条就够了。用标记位而不是 return：
            // 视频组通常排在音频组前面，直接返回会把声道/采样率一起跳过。
            var videoResolved = false
            for (group in tracks.groups) {
                for (i in 0 until group.length) {
                    // 只看**当前选中**的轨。
                    // 不判断的话，HLS 多码率轨或切清晰度后残留的旧轨
                    // 会一起被遍历，最后一条覆盖前面的，
                    // 面板就显示成「非当前播放轨」的分辨率。
                    if (!group.isTrackSelected(i)) continue
                    val format = group.getTrackFormat(i) ?: continue
                    when (group.type) {
                        C.TRACK_TYPE_VIDEO -> {
                            if (videoResolved) continue
                            if (videoCodec.isEmpty()) {
                                videoCodec = format.codecs ?: format.sampleMimeType ?: ""
                            }
                            // 标称值只做兜底，实测值优先
                            if (declaredBitrate <= 0 && format.bitrate > 0) {
                                declaredBitrate = format.bitrate
                            }
                            if (declaredFrameRate <= 0f && format.frameRate > 0f) {
                                declaredFrameRate = format.frameRate
                            }
                            if (format.width > 0 && format.height > 0) {
                                // 只写 metrics 字段：这里的宽高是**编码**尺寸
                                // （1080p = 1920×1088），不能拿去算布局宽高比。
                                metricsWidth = format.width
                                metricsHeight = format.height
                                videoResolved = true
                            }
                        }
                        C.TRACK_TYPE_AUDIO -> {
                            audioCodec = format.codecs ?: format.sampleMimeType ?: ""
                            if (format.channelCount > 0) audioChannels = format.channelCount
                            if (format.sampleRate > 0) audioSampleRate = format.sampleRate
                        }
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "reloadMetricsFromTracks failed: $e")
        }
    }

    @SuppressLint("UnsafeOptInUsageError")
    fun open(url: String, headers: Map<String, String>?, forceReload: Boolean = false) {
        val exoPlayer = ensurePlayer() ?: return

        // ENDED 必须重新 prepare；停滞恢复也必须能强制重载同一个地址。
        if (!forceReload && url == currentUrl && !hasError &&
            (exoPlayer.playbackState == Player.STATE_READY ||
                exoPlayer.playbackState == Player.STATE_BUFFERING)) {
            exoPlayer.playWhenReady = true
            return
        }

        currentUrl = url
        hasError = false

        val context = appContext ?: return

        val httpFactory = DefaultHttpDataSource.Factory()
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(15000)
            .setReadTimeoutMs(15000)
            // 真实码率只能靠统计网络字节拿到，Format.bitrate 对直播流无效
            .setTransferListener(BitrateTransferListener())
            .setUserAgent(
                "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 " +
                    "(KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36"
            )

        if (!headers.isNullOrEmpty()) {
            httpFactory.setDefaultRequestProperties(headers)
        }

        val dataSourceFactory = DefaultDataSource.Factory(context, httpFactory)
        val mediaSource = DefaultMediaSourceFactory(dataSourceFactory)
            .createMediaSource(MediaItem.fromUri(Uri.parse(url)))

        exoPlayer.setMediaSource(mediaSource)
        exoPlayer.prepare()
        exoPlayer.playWhenReady = true
    }

    fun reload(url: String, headers: Map<String, String>?) {
        currentUrl = null
        hasError = false
        open(url, headers)
    }

    /**
     * 无缝换源：只替换媒体源，不销毁播放器、不重建 Surface。
     *
     * 保留 PlayerView 与输出绑定。换源仍需要重新缓冲，
     * PlayerView 在此期间保留上一帧，直到新源开始输出。
     *
     * 直播平台（斗鱼 wsSecret/wsTime、虎牙 txSecret 等）的取流地址带时效签名，
     * 播放十几分钟后地址失效，此时播放器既不报错也不 ended，只是卡住。
     * 上层重新取到新地址后应调本方法续播，而不是重新 open。
     */
    @SuppressLint("UnsafeOptInUsageError")
    fun switchSource(url: String, headers: Map<String, String>?) {
        val exoPlayer = player ?: return
        val context = appContext ?: return

        currentUrl = url
        hasError = false

        val httpFactory = DefaultHttpDataSource.Factory()
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(15000)
            .setReadTimeoutMs(15000)
            // 真实码率只能靠统计网络字节拿到，Format.bitrate 对直播流无效
            .setTransferListener(BitrateTransferListener())
            .setUserAgent(
                "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 " +
                    "(KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36"
            )

        if (!headers.isNullOrEmpty()) {
            httpFactory.setDefaultRequestProperties(headers)
        }

        val dataSourceFactory = DefaultDataSource.Factory(context, httpFactory)
        val mediaSource = DefaultMediaSourceFactory(dataSourceFactory)
            .createMediaSource(MediaItem.fromUri(Uri.parse(url)))

        // 换源：setMediaSource + prepare 会重新缓冲，但不释放解码器与 Surface。
        exoPlayer.setMediaSource(mediaSource)
        exoPlayer.prepare()
        exoPlayer.playWhenReady = true

        // Surface 可能因为在换源期间被重建过，重新确认一次绑定
        boundSurface = null
        applySurface()
    }

    /**
     * 原生播放器里是否还有一条「活着」的流。
     *
     * 用于「点小窗/点同一主播回到播放页」时判断：
     * 播放器还在跑就直接接管画面，不必重新取流，
     * 否则才会走完整的取流流程。
     */
    fun hasActiveStream(): Boolean {
        val exoPlayer = player ?: return false
        if (currentUrl.isNullOrEmpty() || hasError) {
            return false
        }
        return when (exoPlayer.playbackState) {
            Player.STATE_BUFFERING, Player.STATE_READY -> true
            else -> false
        }
    }

    private fun stop() {
        // 明确停止/换房才清旧画面，普通切线仍保留当前帧。
        fullscreenView?.setKeepContentOnPlayerReset(false)
        player?.stop()
        player?.clearMediaItems()
        fullscreenView?.setKeepContentOnPlayerReset(true)
        currentUrl = null
        hasError = false
    }

    fun release() {
        onFloatingDockStateChanged(false, animate = false)
        playbackVolume = 1f
        floatingReturnListener?.let { player?.removeListener(it) }
        floatingReturnListener = null
        returningFromFloating = false
        hasError = false
        currentUrl = null
        boundSurface = null
        floatingSurface = null
        // 播放器都释放了，小窗房间信息也没有意义了
        floatingSiteId = null
        floatingRoomId = null
        // 【必须重置这个标记】
        // 它表示「当前这一路播放是被自动暂停的」。播放器都销毁了，
        // 这个语义就不存在了。不重置的话：在暂停状态下换房间 / 关小窗，
        // 下一次回到前台会误把刚打开的播放当成「自己暂停的那次」拉起来，
        // 表现为「明明手动暂停了，切个房间回来自己播了」。
        pausedByHome = false
        stoppedPageInBackground = false
        player?.release()
        player = null
    }

    /** 关闭小窗时结束播放。 */
    fun releaseAll() {
        release()
    }

    // ---------------------------------------------------------------- Surface 调度

    fun attachFloatingSurface(surface: Surface, preservedFrame: android.graphics.Bitmap? = null) {
        floatingSurface = surface
        applySurface(preservedFrame)
    }

    fun detachFloatingSurface(surface: Surface) {
        if (floatingSurface !== surface) {
            return
        }
        floatingSurface = null
        applySurface()
    }

    /**
     * 按优先级选出输出目标并绑定。
     * 优先级：悬浮窗 > 原生播放页。
     * 这样「页面销毁」或「小窗关闭」任一事件发生时，输出都会自动落到另一方。
     */
    private fun applySurface(preservedFrame: android.graphics.Bitmap? = null) {
        val exoPlayer = player ?: return
        val fullscreen = fullscreenView
        if (fullscreen != null && (floatingSurface == null || returningFromFloating)) {
            boundSurface = null
            if (fullscreen.player !== exoPlayer) fullscreen.player = exoPlayer
            return
        }
        if (fullscreen?.player != null) {
            onHoldFullscreenFrame?.invoke(preservedFrame ?: captureFullscreenFrame())
            fullscreen.player = null
        }
        val target = floatingSurface
        if (target === boundSurface) {
            return
        }
        boundSurface = target
        if (target == null) {
            exoPlayer.clearVideoSurface()
        } else {
            exoPlayer.setVideoSurface(target)
        }
    }

    // ---------------------------------------------------------------- 悬浮窗

    private fun enterFloating(width: Int, height: Int): Boolean {
        floatingReturnListener?.let { player?.removeListener(it) }
        floatingReturnListener = null
        returningFromFloating = false
        if (!floatingWindowEnabled || isTvDevice()) {
            return false
        }
        if (!hasOverlayPermission()) {
            return false
        }
        val context = appContext ?: return false
        if (floatingWindow == null) {
            floatingWindow = FloatingPlayerWindow(context, this)
        }
        floatingWindow?.updateSettings(floatingWindowCornerRadius, floatingWindowDockEnabled)
        val shown = floatingWindow?.show(width, height) ?: false
        if (shown) {
            isFloating = true
        }
        return shown
    }

    private fun exitFloating(handoverToPage: Boolean = false) {
        if (!handoverToPage) { finishFloatingReturn(); return }
        if (!isFloatingVisible()) { isFloating = false; return }
        if (returningFromFloating) return
        returningFromFloating = true
        val exo = player
        if (exo == null) { finishFloatingReturn(); return }
        val listener = object : Player.Listener {
            override fun onRenderedFirstFrame() {
                fullscreenView?.postOnAnimation { if (floatingReturnListener === this) finishFloatingReturn() }
            }
            override fun onPlayerError(error: PlaybackException) { finishFloatingReturn() }
        }
        floatingReturnListener = listener
        exo.addListener(listener)
        // 页内输出可能还没创建，保持小窗和它的最后一帧，attachFullscreenView 会接续绑定。
        applySurface()
    }

    private fun finishFloatingReturn() {
        floatingReturnListener?.let { player?.removeListener(it) }
        floatingReturnListener = null
        // hide 的 Surface 回调仍应指向页内，不能先恢复“小窗优先”。
        floatingWindow?.hide()
        returningFromFloating = false
        isFloating = false
        applySurface()
    }

    fun hasOverlayPermission(): Boolean {
        val context = appContext ?: return false
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(context)
        } else {
            true
        }
    }

    private fun requestOverlayPermission() {
        val context = activity ?: appContext ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:" + context.packageName)
            )
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                context.startActivity(intent)
            } catch (_: Exception) {
            }
        }
    }

    /** 把 App 拉回前台。只做这一步，画面接管由 Dart 侧复用已有页面实例完成。 */
    private fun bringAppToFront() {
        val context = appContext ?: return
        try {
            val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            intent?.addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            )
            // 不要加 FLAG_ACTIVITY_RESET_TASK_IF_NEEDED：
            // 它会在需要时把任务栈清回初始状态，直播页被弹掉，
            // 用户看到的就是「点小窗只打开了 App 首页」。
            context.startActivity(intent)
        } catch (_: Exception) {
        }
    }

    /** 把 App 退到后台。
     *
     * 与「销毁直播页」不同：Activity 与 Flutter 引擎都保留，
     * 直播页的控制器实例、播放器实例全部存活，只是界面不可见。
     * 这样点击小窗回到前台时，原页面原样恢复，无需重建。
     */
    private fun moveTaskToBack() {
        val act = activity ?: return
        mainHandler.post {
            try {
                act.moveTaskToBack(true)
            } catch (_: Exception) {
            }
        }
    }

    /** 点击悬浮窗：先发事件让 Dart 侧准备，再把 App 拉回前台 */
    fun onFloatingTap() {
        onPrepareFloatingReturn?.invoke()
        // 没有监听者时（引擎已销毁）先记下来，等 Dart 侧订阅时补发。
        // 否则这次点击会彻底丢失，表现为「点小窗回不到播放页」。
        if (eventSink == null) {
            Log.d(TAG, "no event sink, cache pending floatingTap")
            pendingFloatingTap = true
        }
        emit("floatingTap")
        bringAppToFront()
    }

    fun onFloatingClosed() {
        isFloating = false
        // 小窗没了，房间信息一起清掉，避免下次进 App 误以为还在小窗播放
        floatingSiteId = null
        floatingRoomId = null
        releaseAll()
        emit("floatingClosed")
    }

    fun isTvDevice(): Boolean {
        val context = appContext ?: return false
        val pm = context.packageManager
        val leanback = pm.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
        val television = pm.hasSystemFeature(PackageManager.FEATURE_TELEVISION)
        val noTouch = !pm.hasSystemFeature(PackageManager.FEATURE_TOUCHSCREEN)
        return leanback || television || noTouch
    }
}
