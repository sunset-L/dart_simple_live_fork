package com.kk.simple_live.player

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.app.Activity
import android.content.pm.ActivityInfo
import android.graphics.RectF
import android.view.View
import android.view.ViewTreeObserver
import android.view.animation.LinearInterpolator
import android.widget.FrameLayout
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.renderer.FlutterRenderer
import io.flutter.embedding.engine.renderer.FlutterUiDisplayListener
import io.flutter.plugin.common.MethodChannel

/** 进房到离房只有一个原生页面、一个 PlayerView。横竖屏不切换 Flutter Surface 或视频输出。 */
class NativePlayerHost(
    private val activity: Activity,
    private val renderer: FlutterRenderer,
    private val onBars: (Boolean) -> Unit,
    private val onAction: (String, Any?) -> Unit,
) {
    private val manager = NativePlayerManager.instance
    private val content = activity.findViewById<FrameLayout>(android.R.id.content)
    private var flutter: FlutterView? = null
    private var page: NativeLiveRoomPage? = null
    private var originalOrientation: Int? = null
    private var exitListener: FlutterUiDisplayListener? = null
    private var background = false
    private var entryCover: android.widget.ImageView? = null
    private var navigationAnimator: ValueAnimator? = null
    private var navigationPreDraw: ViewTreeObserver.OnPreDrawListener? = null

    /** 路由进出动画与横竖屏旋转独立；取消后不能让旧回调移除新页面。 */
    private fun finishNavigation() {
        navigationPreDraw?.let {
            if (content.viewTreeObserver.isAlive) content.viewTreeObserver.removeOnPreDrawListener(it)
        }
        navigationPreDraw = null
        navigationAnimator?.let {
            it.removeAllListeners()
            it.removeAllUpdateListeners()
            it.cancel()
        }
        navigationAnimator = null
        page?.translationX = 0f
        clearEntryCover()
    }

    private fun animateNavigation(roomPage: NativeLiveRoomPage, entering: Boolean) {
        val cover = entryCover
        val flutterView = flutter
        val animator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = NativePlayerNavigationMotion.DURATION_MS
            // 使用原始时间分别计算主页面/底层页的 Cupertino 曲线，不做对称慢进慢出。
            interpolator = LinearInterpolator()
            addUpdateListener { animation ->
                val time = animation.animatedValue as Float
                val progress = NativePlayerNavigationMotion.pageProgress(entering, time)
                // 每帧按当前宽度计算，配置变化时不留下旧屏幕宽度的偏移。
                val width = content.width.toFloat()
                roomPage.translationX = width * if (entering) 1f - progress else progress
                cover?.translationX = -width * NativePlayerNavigationMotion.PARALLAX *
                    NativePlayerNavigationMotion.coveredProgress(entering, time)
            }
        }
        navigationAnimator = animator
        animator.addListener(object : AnimatorListenerAdapter() {
            override fun onAnimationEnd(animation: Animator) {
                // 不在 View 绘制遍历中移除层级；同时检查动画和页面归属。
                content.post {
                    if (navigationAnimator !== animator || page !== roomPage) return@post
                    finishNavigation()
                    if (!entering) dispose()
                }
            }
        })
        val listener = object : ViewTreeObserver.OnPreDrawListener {
            override fun onPreDraw(): Boolean {
                if (page !== roomPage || navigationAnimator !== animator) return true
                if (content.width <= 0 || roomPage.isLayoutRequested ||
                    (!entering && flutterView?.isLayoutRequested == true)) return true
                content.viewTreeObserver.removeOnPreDrawListener(this)
                navigationPreDraw = null
                if (entering) roomPage.translationX = content.width.toFloat()
                else cover?.translationX = -content.width * NativePlayerNavigationMotion.PARALLAX
                animator.start()
                return true
            }
        }
        navigationPreDraw = listener
        content.viewTreeObserver.addOnPreDrawListener(listener)
        content.invalidate()
    }
    private var pendingFullscreen: Pair<Boolean, Boolean>? = null
    private var originalRotationAnimation: Int? = null
    // 当前先比较 Android/OEM 默认窗口旋转。自定义 320ms 单画面方案保留，暂不启用。
    private val useCustomFullscreenTransition = false
    private var transition: NativePlayerTransition? = null
    private var transitionResult: MethodChannel.Result? = null
    private var transitionPreDraw: ViewTreeObserver.OnPreDrawListener? = null
    private val transitionTimeout = Runnable {
        // 方向请求被系统拒绝或页面离开时兜底，不能永久遮屏或锁住 Dart 切换状态。
        if (transitionResult != null) finishTransition("切换方向未完成，请重试")
    }
    private fun videoRect(roomPage: NativeLiveRoomPage): RectF {
        val surface = roomPage.video.video.videoSurfaceView ?: roomPage.video
        val location = IntArray(2); val hostLocation = IntArray(2)
        surface.getLocationInWindow(location); content.getLocationInWindow(hostLocation)
        return RectF((location[0] - hostLocation[0]).toFloat(), (location[1] - hostLocation[1]).toFloat(),
            (location[0] - hostLocation[0] + surface.width).toFloat(),
            (location[1] - hostLocation[1] + surface.height).toFloat())
    }
    private fun finishTransition(error: String? = null) {
        content.removeCallbacks(transitionTimeout)
        transitionPreDraw?.let { if (content.viewTreeObserver.isAlive) content.viewTreeObserver.removeOnPreDrawListener(it) }
        transitionPreDraw = null
        transition?.let { it.dispose(); content.removeView(it) }; transition = null
        page?.alpha = 1f
        page?.setPageActionsTransitioning(false)
        val result = transitionResult; transitionResult = null
        if (error == null) result?.success(null) else result?.error("PLAYER_TRANSITION", error, null)
    }

    /** 小窗点击发生于路由跳转前，保留当前 Flutter 页面，挡住业务占位页的空白帧。 */
    fun prepareEntry() {
        if (page != null || entryCover != null) return
        captureNavigationCover()
    }
    private fun captureNavigationCover() {
        val bitmap = runCatching { renderer.bitmap }.getOrNull() ?: return
        entryCover = android.widget.ImageView(activity).apply {
            scaleType = android.widget.ImageView.ScaleType.FIT_XY
            setImageBitmap(bitmap)
            // 退出时截图放在原生页下面；移动截图，不移动 Flutter Surface。
            val index = page?.let { content.indexOfChild(it) } ?: content.childCount
            content.addView(this, index, FrameLayout.LayoutParams(-1, -1))
        }
    }
    fun cancelEntry() {
        if (page == null) clearEntryCover()
    }
    private fun clearEntryCover() {
        entryCover?.let { content.removeView(it); it.setImageDrawable(null) }
        entryCover = null
    }
    fun onConfigurationChanged(configuration: android.content.res.Configuration) {
        val pending = pendingFullscreen ?: return
        if ((configuration.orientation == android.content.res.Configuration.ORIENTATION_LANDSCAPE) != pending.second) return
        pendingFullscreen = null
        page?.setFullscreen(pending.first)
    }

    val fullscreen: Boolean get() = page?.fullscreen == true

    fun open(data: Map<*, *>, result: MethodChannel.Result) {
        if (exitListener != null) dispose()
        if (page != null) { update(data); result.success(null); return }
        val flutterView = (0 until content.childCount).map { content.getChildAt(it) }
            .filterIsInstance<FlutterView>().singleOrNull()
        val player = manager.fullscreenPlayer()
        if (flutterView == null || player == null) {
            clearEntryCover()
            result.error("PLAYER_UNAVAILABLE", "原生播放页尚未就绪", null); return
        }
        prepareEntry()
        originalOrientation = activity.requestedOrientation
        if (useCustomFullscreenTransition) {
            originalRotationAnimation = activity.window.attributes.rotationAnimation
            activity.window.attributes = activity.window.attributes.apply {
                // 自定义方案才设置窗口交接方式，默认模式不修改 Android 的旋转动画属性。
                rotationAnimation = android.view.WindowManager.LayoutParams.ROTATION_ANIMATION_SEAMLESS
            }
        }
        manager.clearFullscreenOrientation()
        activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        flutter = flutterView
        val roomPage = NativeLiveRoomPage(activity, player, onAction)
        page = roomPage
        roomPage.update(data)
        roomPage.video.holdFrame(manager.captureFloatingFrame())
        manager.onHoldFullscreenFrame = { bitmap -> roomPage.video.holdFrame(bitmap) }
        // 截图只作返回页的短暂底层，真实原生播放页从右侧进入。
        // 首帧不可用时直接展示页面，不在被隐藏的 Flutter Surface 上露空白。
        if (entryCover != null) roomPage.translationX = content.width.toFloat()
        content.addView(roomPage, FrameLayout.LayoutParams(-1, -1))
        manager.attachFullscreenView(roomPage.video.video)
        // 播放期间隔离 Flutter Surface，只在真正离房时恢复。
        // 视频 TextureView 与原生 UI 在同一次 View 合成中布局。
        flutterView.visibility = View.GONE
        onBars(false)
        roomPage.requestFocus()
        if (entryCover != null && !background) animateNavigation(roomPage, entering = true)
        else clearEntryCover()
        result.success(null)
    }

    fun setFullscreen(value: Boolean, landscape: Boolean, result: MethodChannel.Result) {
        val roomPage = page
        if (roomPage == null) { result.error("PLAYER_UNAVAILABLE", "播放页已关闭", null); return }
        if (exitListener != null) { result.success(null); return }
        if (transitionResult != null) { result.error("PLAYER_TRANSITION", "正在切换播放方向", null); return }
        finishNavigation()
        val targetLandscape = value && landscape
        val currentLandscape = activity.resources.configuration.orientation == android.content.res.Configuration.ORIENTATION_LANDSCAPE
        if (!useCustomFullscreenTransition) {
            // 仅请求目标布局、系统栏和方向；不截帧、不盖过渡层、不设置动画或隐藏操作栏。
            pendingFullscreen = if (currentLandscape != targetLandscape) Pair(value, targetLandscape) else null
            if (pendingFullscreen == null) roomPage.setFullscreen(value)
            onBars(value)
            requestFullscreenOrientation(value, landscape)
            result.success(null)
            return
        }
        val captured = roomPage.video.captureFrame()
        transitionResult = result
        val animation = NativePlayerTransition(activity, captured, videoRect(roomPage),
            content.width, content.height, content.display?.rotation ?: 0, value)
        transition = animation
        content.addView(animation, FrameLayout.LayoutParams(-1, -1))
        roomPage.alpha = 0f
        roomPage.setPageActionsTransitioning(true)
        pendingFullscreen = if (currentLandscape != targetLandscape) Pair(value, targetLandscape) else null
        if (pendingFullscreen == null) roomPage.setFullscreen(value)
        // 等目标方向和真实布局，不用定时延迟猜测 Android 配置变更何时结束。
        val listener = object : ViewTreeObserver.OnPreDrawListener {
            override fun onPreDraw(): Boolean {
                if (page !== roomPage || transition !== animation) return true
                val isLandscape = content.width > content.height
                if (pendingFullscreen != null || isLandscape != targetLandscape || roomPage.isLayoutRequested) return true
                content.viewTreeObserver.removeOnPreDrawListener(this)
                transitionPreDraw = null
                if (!value) roomPage.alpha = 1f
                animation.start(videoRect(roomPage), content.display?.rotation ?: 0) {
                    // Animator 回调不在绘制遍历中，下一帧一起移除遮罩与显示控件。
                    finishTransition()
                }
                return true
            }
        }
        transitionPreDraw = listener
        content.viewTreeObserver.addOnPreDrawListener(listener)
        content.postDelayed(transitionTimeout, 1800L)
        onBars(value)
        requestFullscreenOrientation(value, landscape)
    }

    private fun requestFullscreenOrientation(value: Boolean, landscape: Boolean) {
        if (value) manager.setScreenOrientation(if (landscape) "landscape" else "portrait")
        else {
            manager.clearFullscreenOrientation()
            activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        }
    }

    fun close(result: MethodChannel.Result) {
        finishTransition()
        val flutterView = flutter
        val roomPage = page
        if (roomPage == null || flutterView == null) { dispose(); result.success(null); return }
        if (exitListener != null) { result.success(null); return }
        finishNavigation()
        roomPage.video.holdFrame(roomPage.video.captureFrame())
        roomPage.video.suspendPlaybackUi()
        val listener = object : FlutterUiDisplayListener {
            override fun onFlutterUiDisplayed() {
                // 返回页真正出帧后才推出原生层，不能拿业务占位页作动画底层。
                // result 已回 Dart，路由退出和强制提交帧不会等待本动画造成死锁。
                content.post {
                    if (exitListener !== this || page !== roomPage) return@post
                    renderer.removeIsDisplayingFlutterUiListener(this)
                    if (background) dispose()
                    else if (navigationAnimator == null) {
                        captureNavigationCover()
                        animateNavigation(roomPage, entering = false)
                    }
                }
            }
            override fun onFlutterUiNoLongerDisplayed() = Unit
        }
        exitListener = listener
        renderer.addIsDisplayingFlutterUiListener(listener)
        onBars(false)
        flutterView.visibility = View.VISIBLE
        flutterView.requestLayout()
        result.success(null)
    }
    fun onBackground() {
        if (page == null || background || manager.isFloating) return
        background = true
        finishNavigation()
        finishTransition()
        if (exitListener != null) { dispose(); return }
        page?.video?.suspendPlaybackUi()
        onAction("background", null)
    }

    fun onForeground() {
        if (page == null || !background) return
        background = false
        onAction("foreground", null)
    }

    fun dismissOverlay(): Boolean = page?.dismissOverlay() == true

    fun update(data: Map<*, *>) { page?.update(data) }
    fun replaceMessages(items: List<*>) { page?.clearMessages(); page?.addMessages(items) }
    fun addMessages(items: List<*>) { page?.addMessages(items) }
    fun addDanmaku(items: List<*>) { page?.video?.addDanmaku(items) }
    fun clearDanmaku() { page?.video?.clearDanmaku() }
    fun showDialog(kind: String, data: Map<*, *>, result: MethodChannel.Result) {
        val roomPage = page
        if (roomPage == null) { result.error("PLAYER_UNAVAILABLE", "播放页已关闭", null); return }
        roomPage.showDialog(kind, data, result)
    }

    fun dispose() {
        finishNavigation()
        finishTransition()
        pendingFullscreen = null
        manager.onHoldFullscreenFrame = null
        originalRotationAnimation?.let { animation ->
            activity.window.attributes = activity.window.attributes.apply { rotationAnimation = animation }
        }
        originalRotationAnimation = null
        exitListener?.let { renderer.removeIsDisplayingFlutterUiListener(it) }; exitListener = null
        page?.let {
            manager.detachFullscreenView(it.video.video)
            it.dispose()
            content.removeView(it)
        }
        page = null
        background = false
        flutter?.visibility = View.VISIBLE
        flutter = null
        manager.clearFullscreenOrientation()
        originalOrientation?.let { activity.requestedOrientation = it }
        originalOrientation = null
        onBars(false)
    }
}
