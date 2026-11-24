package com.kk.simple_live.player

import android.app.Activity
import android.content.pm.ActivityInfo
import android.view.View
import android.widget.FrameLayout
import io.flutter.embedding.android.FlutterView
import io.flutter.plugin.common.MethodChannel

/** 进房到离房只有一个原生页面、一个 PlayerView。横竖屏不切换 Flutter Surface 或视频输出。 */
class NativePlayerHost(
    private val activity: Activity,
    private val onBars: (Boolean) -> Unit,
    private val onAction: (String, Any?) -> Unit,
) {
    private val manager = NativePlayerManager.instance
    private val content = activity.findViewById<FrameLayout>(android.R.id.content)
    private var flutter: FlutterView? = null
    private var page: NativeLiveRoomPage? = null
    private var originalOrientation: Int? = null
    val fullscreen: Boolean get() = page?.fullscreen == true

    fun open(data: Map<*, *>, result: MethodChannel.Result) {
        if (page != null) { update(data); result.success(null); return }
        val flutterView = (0 until content.childCount).map { content.getChildAt(it) }
            .filterIsInstance<FlutterView>().singleOrNull()
        val player = manager.fullscreenPlayer()
        if (flutterView == null || player == null) {
            result.error("PLAYER_UNAVAILABLE", "原生播放页尚未就绪", null); return
        }
        originalOrientation = activity.requestedOrientation
        manager.clearFullscreenOrientation()
        activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        flutter = flutterView
        val roomPage = NativeLiveRoomPage(activity, player, onAction)
        page = roomPage
        roomPage.update(data)
        content.addView(roomPage, FrameLayout.LayoutParams(-1, -1))
        manager.attachFullscreenView(roomPage.video.video)
        // 两个 SurfaceView 的层级不由普通 View 的前后顺序保证。
        // 播放期间始终隔离 Flutter Surface，只在真正离房时恢复。
        flutterView.visibility = View.GONE
        onBars(false)
        roomPage.requestFocus()
        result.success(null)
    }

    fun setFullscreen(value: Boolean, landscape: Boolean, result: MethodChannel.Result) {
        val roomPage = page
        if (roomPage == null) { result.error("PLAYER_UNAVAILABLE", "播放页已关闭", null); return }
        roomPage.setFullscreen(value)
        onBars(value)
        if (value) manager.setScreenOrientation(if (landscape) "landscape" else "portrait")
        else {
            manager.clearFullscreenOrientation()
            activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        }
        // 没有等待 Flutter 帧或重建 Surface：后续尺寸变化全部由 Android View 布局处理。
        result.success(null)
    }

    fun close(result: MethodChannel.Result) {
        // 不把返回绑在 Flutter 首帧事件上：Surface 已显示时不会再次触发该事件，
        // 旧方案会一直保留冻结的原生页直到 2 秒兜底超时。
        dispose()
        result.success(null)
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
        page?.let {
            manager.detachFullscreenView(it.video.video)
            it.dispose()
            content.removeView(it)
        }
        page = null
        flutter?.visibility = View.VISIBLE
        flutter = null
        manager.clearFullscreenOrientation()
        originalOrientation?.let { activity.requestedOrientation = it }
        originalOrientation = null
        onBars(false)
    }
}
