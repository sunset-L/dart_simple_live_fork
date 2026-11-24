package com.kk.simple_live.player

import android.app.Activity
import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.os.Build
import android.view.View
import android.view.ViewTreeObserver
import android.widget.FrameLayout
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.renderer.FlutterRenderer
import io.flutter.embedding.engine.renderer.FlutterUiDisplayListener
import io.flutter.plugin.common.MethodChannel

/**
 * 在同一 Activity 里交接完整原生全屏页，不重建播放器，也不启动第二个 Flutter 引擎。
 * 旋转前隐藏 FlutterView 并等待原生窗口帧提交，隔离 Flutter 主 Surface 的尺寸交接。
 * 退出先让原生页回竖屏，再恢复 Flutter 的 Surface，等它的新首帧后撤下原生页。
 */
class NativeFullscreenHost(
    private val activity: Activity,
    private val renderer: FlutterRenderer,
    private val onBars: (Boolean) -> Unit,
    private val onAction: (String, Number?) -> Unit,
) {
    private val manager = NativePlayerManager.instance
    private val content = activity.findViewById<FrameLayout>(android.R.id.content)
    private var flutter: FlutterView? = null
    private var page: NativeFullscreenPlayer? = null
    private var pending: MethodChannel.Result? = null
    private var drawListener: ViewTreeObserver.OnPreDrawListener? = null
    private var frameListener: FlutterUiDisplayListener? = null
    private var commitCallback: Runnable? = null
    private var timeout: Runnable? = null
    private var originalOrientation: Int? = null
    private var inlineLandscape = false
    val active: Boolean get() = page != null

    fun setInline(active: Boolean) {
        if (active) {
            if (originalOrientation == null) originalOrientation = activity.requestedOrientation
            activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        } else {
            dispose()
            manager.clearFullscreenOrientation()
            originalOrientation?.let { activity.requestedOrientation = it }
            originalOrientation = null
        }
    }

    fun show(data: Map<*, *>, result: MethodChannel.Result) {
        if (pending != null) {
            result.error("FULLSCREEN_BUSY", "正在切换全屏", null)
            return
        }
        if (page != null) { update(data); result.success(null); return }
        val player = manager.fullscreenPlayer()
        val flutterView = (0 until content.childCount)
            .map { content.getChildAt(it) }.filterIsInstance<FlutterView>().singleOrNull()
        if (player == null || flutterView == null) {
            result.error("PLAYER_UNAVAILABLE", "播放器页面尚未就绪", null)
            return
        }
        flutter = flutterView
        inlineLandscape = activity.resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
        val nativePage = NativeFullscreenPlayer(activity, player, onAction)
        page = nativePage
        nativePage.isFocusableInTouchMode = true
        nativePage.update(data)
        content.addView(nativePage, FrameLayout.LayoutParams(-1, -1))
        manager.attachFullscreenView(nativePage.video)
        nativePage.requestFocus()
        flutterView.visibility = View.GONE
        onBars(true)
        startPending(result) {
            removePage()
            manager.setScreenOrientation("auto")
            onBars(false)
        }
        val landscape = data["landscape"] == true
        // API 29+ 等原生窗口帧提交后才请求旋转，而不是把 pre-draw 当作已经呈现。
        // 避免旋转请求抢在原生页第一次绘制之前；不假设视频 Surface 也已呈现首帧。
        drawListener = ViewTreeObserver.OnPreDrawListener {
            clearDrawListener()
            val rotate = Runnable {
                if (page === nativePage && pending === result) {
                    manager.setScreenOrientation(if (landscape) "landscape" else "portrait")
                    waitForLayout(landscape) { completePending() }
                }
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val committed = Runnable { nativePage.post(rotate) }
                commitCallback = committed
                nativePage.viewTreeObserver.registerFrameCommitCallback(committed)
            } else {
                // 老系统没有帧提交 API，使用 Android 常规绘制队列；仍不绘制 Flutter 全屏页。
                nativePage.post(rotate)
            }
            true
        }.also { nativePage.viewTreeObserver.addOnPreDrawListener(it) }
    }

    fun hide(result: MethodChannel.Result) {
        if (pending != null) {
            result.error("FULLSCREEN_BUSY", "正在切换全屏", null)
            return
        }
        val nativePage = page
        if (nativePage == null) { result.success(null); return }
        startPending(result) {
            // 系统拒绝退出时仍保留可操作的原生页，不能把横屏 Flutter 页面强行露出来。
            flutter?.visibility = View.GONE
            manager.attachFullscreenView(nativePage.video)
        }
        manager.setScreenOrientation("restore")
        // 大屏/TV 可以忽略竖屏请求，恢复进入时实际的窗口方向，不能因此困在全屏页。
        waitForLayout(inlineLandscape) {
            manager.setScreenOrientation("auto")
            clearDrawListener()
            if (renderer.isDisplayingFlutterUi) {
                // 不得把旧的 displayed 状态当作新 Surface 的首帧。
                clearListeners()
                pending = null
                result.error("FLUTTER_SURFACE_ACTIVE", "原页面渲染表面未完成隐藏", null)
                return@waitForLayout
            }
            // 隐藏时 SurfaceDestroyed 已让 renderer 清掉旧的 displayed 状态。
            // 此回调只监听重新创建 Surface 后的真实首帧，不用 endOfFrame 猜呈现时间。
            val listener = object : FlutterUiDisplayListener {
                override fun onFlutterUiDisplayed() {
                    if (page !== nativePage || pending !== result) return
                    removePage()
                    onBars(false)
                    completePending()
                }
                override fun onFlutterUiNoLongerDisplayed() = Unit
            }
            frameListener = listener
            renderer.addIsDisplayingFlutterUiListener(listener)
            flutter?.visibility = View.VISIBLE
            flutter?.requestLayout()
            // 输出切回页内纹理，但原生页留作遮挡，直到 Flutter 的新首帧就绪。
            manager.detachFullscreenView(nativePage.video)
        }
    }

    private fun waitForLayout(landscape: Boolean, ready: () -> Unit) {
        val nativePage = page ?: return
        clearDrawListener()
        drawListener = ViewTreeObserver.OnPreDrawListener {
            val orientation = activity.resources.configuration.orientation
            if (nativePage.width > 0 && nativePage.height > 0 &&
                (nativePage.width > nativePage.height) == landscape &&
                (orientation == Configuration.ORIENTATION_LANDSCAPE) == landscape) {
                clearDrawListener()
                ready()
            }
            true
        }.also { nativePage.viewTreeObserver.addOnPreDrawListener(it) }
        nativePage.requestLayout()
    }

    private fun startPending(result: MethodChannel.Result, failed: () -> Unit) {
        pending = result
        // 只用于系统拒绝请求或 Activity 失效后释放锁，不参与动画时长或尺寸推算。
        timeout = Runnable {
            if (pending !== result) return@Runnable
            clearListeners()
            failed()
            pending = null
            result.error("FULLSCREEN_TIMEOUT", "系统未完成全屏页面交接", null)
        }.also { content.postDelayed(it, 2000L) }
    }

    private fun completePending() {
        val result = pending ?: return
        clearListeners()
        pending = null
        result.success(null)
    }

    private fun clearDrawListener() {
        drawListener?.let {
            page?.viewTreeObserver?.takeIf { observer -> observer.isAlive }
                ?.removeOnPreDrawListener(it)
        }
        drawListener = null
    }

    private fun clearListeners() {
        clearDrawListener()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            commitCallback?.let { page?.viewTreeObserver?.unregisterFrameCommitCallback(it) }
        }
        commitCallback = null
        frameListener?.let { renderer.removeIsDisplayingFlutterUiListener(it) }
        frameListener = null
        timeout?.let { content.removeCallbacks(it) }
        timeout = null
    }

    private fun removePage() {
        val nativePage = page ?: return
        clearDrawListener()
        manager.detachFullscreenView(nativePage.video)
        nativePage.dispose()
        content.removeView(nativePage)
        page = null
        flutter?.visibility = View.VISIBLE
        flutter = null
    }

    fun update(data: Map<*, *>) { page?.update(data) }
    fun addDanmaku(items: List<*>) { page?.addDanmaku(items) }
    fun clearDanmaku() { page?.clearDanmaku() }

    fun dispose() {
        val result = pending
        clearListeners()
        pending = null
        removePage()
        result?.error("ACTIVITY_CLOSED", "播放页面已关闭", null)
        onBars(false)
    }
}
