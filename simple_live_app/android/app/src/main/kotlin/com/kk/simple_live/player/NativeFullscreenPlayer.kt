package com.kk.simple_live.player

import android.app.Activity
import android.app.AlertDialog
import android.content.Context
import android.graphics.Color
import android.media.AudioManager
import android.view.GestureDetector
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import kotlin.math.abs
import kotlin.math.roundToInt

/** 全屏页只有 Android View；不嵌入 Flutter、PlatformView 或外部 Flutter 纹理。 */
class NativeFullscreenPlayer(
    private val activity: Activity,
    private val player: ExoPlayer,
    private val onAction: (String, Number?) -> Unit,
) : FrameLayout(activity) {
    private var forcedAspect = 0f
    val video = object : PlayerView(activity) {
        override fun onContentAspectRatioChanged(frame: AspectRatioFrameLayout?, ratio: Float) {
            super.onContentAspectRatioChanged(frame, if (forcedAspect > 0f) forcedAspect else ratio)
        }
    }.apply {
        useController = false
        setShowBuffering(PlayerView.SHOW_BUFFERING_WHEN_PLAYING)
        setKeepContentOnPlayerReset(true)
    }
    private val danmaku = DanmakuOverlayView(activity)
    private val topBar = LinearLayout(activity)
    private val bottomBar = LinearLayout(activity)
    private var floating: TextView? = null
    private val title = TextView(activity)
    private val tip = TextView(activity)
    private val status = TextView(activity)
    private var metricsText: TextView? = null
    private val superChat = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
    private val seenSC = linkedSetOf<String>()
    private val scTimers = mutableMapOf<String, Runnable>()
    private val lock = button("锁定") { setLocked(!locked) }
    private val play = button("暂停") {
        player.playWhenReady = !player.playWhenReady
    }
    private val danmakuButton = button("弹幕") {
        onAction("danmaku", if (data["danmakuEnabled"] == true) 0 else 1)
    }
    private var data: Map<*, *> = emptyMap<Any, Any>()
    private var locked = false
    private var dialog: AlertDialog? = null
    private val originalBrightness = activity.window.attributes.screenBrightness
    private val hideControls = Runnable { setControlsVisible(false) }
    private val audio = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var gestureX = 0f
    private var gestureY = 0f
    private var gestureVolume = 0
    private var gestureBrightness = 0.5f
    private var dragging = false
    private val playerListener = object : Player.Listener {
        override fun onEvents(player: Player, events: Player.Events) {
            play.text = if (player.playWhenReady) "暂停" else "播放"
        }
    }

    init {
        setBackgroundColor(Color.BLACK)
        addView(video, LayoutParams(-1, -1))
        addView(danmaku, LayoutParams(-1, -1))
        addView(superChat, LayoutParams(dp(240), -2, Gravity.START or Gravity.BOTTOM).apply {
            leftMargin = dp(24); bottomMargin = dp(64)
        })
        status.setTextColor(Color.WHITE)
        status.textSize = 16f
        status.gravity = Gravity.CENTER
        status.setBackgroundColor(0xBB000000.toInt())
        status.visibility = GONE
        addView(status, LayoutParams(-1, dp(72), Gravity.CENTER))
        topBar.gravity = Gravity.CENTER_VERTICAL
        topBar.setBackgroundColor(0x99000000.toInt())
        topBar.addView(button("返回") { onAction("exit", null) })
        title.setTextColor(Color.WHITE)
        title.textSize = 16f
        title.maxLines = 1
        topBar.addView(title, LinearLayout.LayoutParams(0, dp(48), 1f))
        addView(topBar, LayoutParams(-1, dp(48), Gravity.TOP))
        bottomBar.gravity = Gravity.CENTER_VERTICAL
        bottomBar.setBackgroundColor(0x99000000.toInt())
        bottomBar.addView(play)
        bottomBar.addView(button("刷新") { onAction("refresh", null) })
        bottomBar.addView(danmakuButton)
        bottomBar.addView(button("画质") {
            choose("画质", (data["qualities"] as? List<*>)?.map { it.toString() }
                ?: emptyList(), (data["qualityIndex"] as? Number)?.toInt() ?: -1) {
                onAction("quality", it)
            }
        })
        bottomBar.addView(button("线路") {
            val count = (data["lineCount"] as? Number)?.toInt() ?: 0
            choose("线路", List(count.coerceIn(0, 100)) { "线路 ${it + 1}" },
                (data["lineIndex"] as? Number)?.toInt() ?: -1) { onAction("line", it) }
        })
        bottomBar.addView(button("参数") { showMetrics() })
        bottomBar.addView(button("设置") { settings() })
        bottomBar.addView(button("直播间（竖屏）") { onAction("rooms", null) })
        floating = button("小窗") { onAction("floating", null) }.also { bottomBar.addView(it) }
        bottomBar.addView(button("退出全屏") { onAction("exit", null) })
        val scroll = HorizontalScrollView(activity).apply {
            isHorizontalScrollBarEnabled = false
            addView(bottomBar)
        }
        addView(scroll, LayoutParams(-1, dp(48), Gravity.BOTTOM))
        lock.setBackgroundColor(0x88000000.toInt())
        addView(lock, LayoutParams(dp(64), dp(48), Gravity.START or Gravity.CENTER_VERTICAL))
        tip.setTextColor(Color.WHITE)
        tip.textSize = 18f
        tip.gravity = Gravity.CENTER
        tip.setBackgroundColor(0x99000000.toInt())
        tip.visibility = GONE
        addView(tip, LayoutParams(dp(220), dp(54), Gravity.CENTER))
        // 系统旋转和刘海安全区交给原生窗口；没有手动旋转/缩放矩阵。
        ViewCompat.setOnApplyWindowInsetsListener(this) { _, insets ->
            val safe = insets.getInsets(WindowInsetsCompat.Type.displayCutout()
                or WindowInsetsCompat.Type.systemBars())
            setPadding(safe.left, safe.top, safe.right, safe.bottom)
            insets
        }
        player.addListener(playerListener)
        setControlsVisible(true)
    }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).roundToInt()

    private fun button(text: String, action: () -> Unit) = TextView(activity).apply {
        this.text = text
        setTextColor(Color.WHITE)
        textSize = 14f
        gravity = Gravity.CENTER
        minWidth = dp(64)
        minHeight = dp(48)
        setPadding(dp(8), 0, dp(8), 0)
        setOnClickListener { action(); scheduleHide() }
    }

    private fun setLocked(value: Boolean) {
        locked = value
        lock.text = if (locked) "解锁" else "锁定"
        setControlsVisible(!locked)
    }

    private fun setControlsVisible(visible: Boolean) {
        topBar.visibility = if (visible && !locked) VISIBLE else GONE
        (bottomBar.parent as View).visibility = topBar.visibility
        lock.visibility = if (visible || locked) VISIBLE else GONE
        if (visible) scheduleHide()
    }

    private fun scheduleHide() {
        removeCallbacks(hideControls)
        if (!locked) postDelayed(hideControls, 5000L)
    }

    fun update(values: Map<*, *>) {
        data = values
        title.text = values["title"]?.toString() ?: "直播间"
        status.text = values["status"]?.toString() ?: ""
        status.visibility = if (status.text.isEmpty()) GONE else VISIBLE
        floating?.visibility = if (values["floatingEnabled"] == true) VISIBLE else GONE
        danmakuButton.text = if (values["danmakuEnabled"] == true) "关弹幕" else "开弹幕"
        val mode = (values["scaleMode"] as? Number)?.toInt() ?: 0
        video.resizeMode = when (mode) {
            1 -> AspectRatioFrameLayout.RESIZE_MODE_FILL
            2 -> AspectRatioFrameLayout.RESIZE_MODE_ZOOM
            else -> AspectRatioFrameLayout.RESIZE_MODE_FIT
        }
        // Media3 按 SAR 后的视频尺寸处理 FIT。固定比例模式只调整原生视频容器。
        val ratio = when (mode) { 3 -> 16f / 9f; 4 -> 4f / 3f; else -> 0f }
        forcedAspect = ratio
        video.findViewById<AspectRatioFrameLayout>(androidx.media3.ui.R.id.exo_content_frame)
            ?.setAspectRatio(if (ratio > 0f) ratio else player.videoSize.let {
                if (it.height > 0) it.width * it.pixelWidthHeightRatio / it.height else 0f
            })
        danmaku.visibility = if (values["danmakuEnabled"] == true) VISIBLE else GONE
        if (danmaku.visibility == GONE) danmaku.clearAll()
        updateSuperChat(values)
        danmaku.applyOptions(
            number("fontSize", 16f), number("fontWeight", 4f).toInt(),
            number("opacity", 1f), number("area", .8f), number("duration", 10f).toInt(),
            number("topMargin", 0f), number("bottomMargin", 0f), 80,
        )
    }

    private fun updateSuperChat(values: Map<*, *>) {
        if (values["superChatEnabled"] != true) {
            clearSuperChat()
            return
        }
        val entries = values["superChats"] as? List<*> ?: return
        val keys = entries.mapNotNull { (it as? Map<*, *>)?.get("key")?.toString() }.toSet()
        for (key in scTimers.keys.toList()) {
            if (key !in keys) removeSuperChat(key)
        }
        for (raw in entries) {
            val item = raw as? Map<*, *> ?: continue
            val key = item["key"]?.toString() ?: continue
            if (key in seenSC) continue
            val remain = (item["endTime"] as? Number)?.toLong()?.minus(System.currentTimeMillis()) ?: 0L
            if (remain <= 0) continue
            seenSC.add(key)
            if (seenSC.size > 128) seenSC.remove(seenSC.first())
            if (superChat.childCount >= 4) removeSuperChat(scTimers.keys.first())
            val card = TextView(activity).apply {
                tag = key
                text = item["text"]?.toString() ?: ""
                textSize = 14f
                maxLines = 4
                setTextColor(Color.WHITE)
                setPadding(dp(10), dp(6), dp(10), dp(6))
                setBackgroundColor(runCatching { Color.parseColor(item["color"]?.toString()) }
                    .getOrDefault(0xCC37566B.toInt()))
            }
            superChat.addView(card, LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = dp(6) })
            val expire = Runnable { removeSuperChat(key) }
            scTimers[key] = expire
            postDelayed(expire, remain.coerceAtMost(15000L))
        }
    }

    private fun removeSuperChat(key: String) {
        scTimers.remove(key)?.let { removeCallbacks(it) }
        for (i in superChat.childCount - 1 downTo 0) {
            if (superChat.getChildAt(i).tag == key) superChat.removeViewAt(i)
        }
    }

    private fun clearSuperChat() {
        scTimers.values.forEach { removeCallbacks(it) }
        scTimers.clear()
        seenSC.clear()
        superChat.removeAllViews()
    }

    private fun number(key: String, fallback: Float) =
        (data[key] as? Number)?.toFloat() ?: fallback

    fun addDanmaku(items: List<*>) {
        if (danmaku.visibility != VISIBLE || !isShown) return
        for (entry in items) {
            val item = entry as? Map<*, *> ?: continue
            danmaku.addDanmaku(item["text"]?.toString() ?: "",
                (item["color"] as? Number)?.toInt() ?: Color.WHITE)
        }
    }

    fun clearDanmaku() { danmaku.clearAll() }

    private fun choose(title: String, items: List<String>, selected: Int,
                       onSelect: (Int) -> Unit) {
        if (items.isEmpty()) {
            tip.text = "暂无$title，请刷新直播间"
            tip.visibility = VISIBLE
            return
        }
        removeCallbacks(hideControls)
        dialog?.dismiss()
        dialog = AlertDialog.Builder(activity).setTitle(title)
            .setSingleChoiceItems(items.toTypedArray(), selected.coerceIn(-1, items.lastIndex)) { popup, index ->
                popup.dismiss()
                onSelect(index)
            }.setNegativeButton("取消", null).create()
        dialog?.setOnDismissListener { dialog = null; scheduleHide() }
        dialog?.show()
    }

    private fun stopMetrics() {
        if (metricsText == null) return
        metricsText = null
        removeCallbacks(refreshMetrics)
        NativePlayerManager.instance.setMetricsListening(false)
    }

    private val refreshMetrics = object : Runnable {
        override fun run() {
            val text = metricsText ?: return
            val m = NativePlayerManager.instance.readPlaybackMetrics()
            val fps = if (m["frameRateMeasured"] == true) "${m["frameRate"]} fps" else "采样中…"
            val bitrate = if (m["bitrateMeasured"] == true)
                "${(m["videoBitrate"] as Number).toLong() / 1000} kbps" else "采样中…"
            text.text = "分辨率：${m["width"]} × ${m["height"]}\n帧率：$fps\n码率：$bitrate" +
                "\n视频编码：${m["videoCodec"]}\n音频编码：${m["audioCodec"]}" +
                "\n声道：${m["audioChannels"]}\n采样率：${m["audioSampleRate"]} Hz"
            postDelayed(this, 1000L)
        }
    }

    private fun showMetrics() {
        removeCallbacks(hideControls)
        dialog?.dismiss()
        val text = TextView(activity).apply {
            textSize = 16f
            setPadding(dp(24), dp(16), dp(24), dp(16))
        }
        metricsText = text
        NativePlayerManager.instance.setMetricsListening(true)
        dialog = AlertDialog.Builder(activity).setTitle("播放参数").setView(text)
            .setPositiveButton("关闭", null).create()
        dialog?.setOnDismissListener { dialog = null; stopMetrics(); scheduleHide() }
        dialog?.show()
        refreshMetrics.run()
    }

    private fun settings() {
        choose("播放设置", listOf("画面比例", "弹幕字号", "弹幕区域", "弹幕透明度", "弹幕速度", "高级弹幕设置（竖屏）"), -1) {
            when (it) {
                0 -> choose("画面比例", listOf("适应", "拉伸", "铺满", "16:9", "4:3"),
                    number("scaleMode", 0f).toInt()) { value -> onAction("scale", value) }
                1 -> chooseNumber("弹幕字号", "fontSize", listOf(12, 16, 20, 24, 28, 32))
                2 -> chooseNumber("弹幕区域（百分比）", "area", listOf(25, 50, 75, 100), true)
                3 -> chooseNumber("弹幕透明度（百分比）", "opacity", listOf(25, 50, 75, 100), true)
                4 -> chooseNumber("弹幕滚动时长（秒）", "duration", listOf(5, 8, 10, 12, 15))
                5 -> onAction("danmakuSettings", null)
            }
        }
    }

    private fun chooseNumber(title: String, key: String, values: List<Int>, percent: Boolean = false) {
        choose(title, values.map { it.toString() }, -1) {
            onAction(key, if (percent) values[it] / 100.0 else values[it])
        }
    }

    private val detector = GestureDetector(activity,
        object : GestureDetector.SimpleOnGestureListener() {
            override fun onDown(e: MotionEvent) = true
            override fun onSingleTapConfirmed(e: MotionEvent): Boolean {
                setControlsVisible(topBar.visibility != VISIBLE)
                return true
            }
            override fun onLongPress(e: MotionEvent) {
                if (!locked) onAction("rooms", null)
            }
            override fun onDoubleTap(e: MotionEvent): Boolean {
                if (!locked) onAction("exit", null)
                return true
            }
        })

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (locked) return true
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                gestureX = event.x
                gestureY = event.y
                gestureVolume = audio.getStreamVolume(AudioManager.STREAM_MUSIC)
                gestureBrightness = activity.window.attributes.screenBrightness.takeIf { it >= 0 }
                    ?: 0.5f
                dragging = false
            }
            MotionEvent.ACTION_MOVE -> {
                val dy = gestureY - event.y
                if (!dragging && abs(dy) > dp(12) && abs(dy) > abs(event.x - gestureX)) {
                    dragging = true
                    val cancel = MotionEvent.obtain(event)
                    cancel.action = MotionEvent.ACTION_CANCEL
                    detector.onTouchEvent(cancel)
                    cancel.recycle()
                    removeCallbacks(hideControls)
                }
                if (dragging && height > 0) {
                    if (gestureX >= width / 2f) {
                        val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                        val value = (gestureVolume + dy / height * max * 2).roundToInt().coerceIn(0, max)
                        audio.setStreamVolume(AudioManager.STREAM_MUSIC, value, 0)
                        tip.text = "音量 ${if (max > 0) value * 100 / max else 0}%"
                    } else {
                        val value = (gestureBrightness + dy / height * 2).coerceIn(.01f, 1f)
                        activity.window.attributes = activity.window.attributes.apply { screenBrightness = value }
                        tip.text = "亮度 ${(value * 100).roundToInt()}%"
                    }
                    tip.visibility = VISIBLE
                }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                tip.visibility = GONE
                scheduleHide()
                if (dragging) { dragging = false; return true }
            }
        }
        if (!dragging) detector.onTouchEvent(event)
        return true
    }

    fun dispose() {
        dialog?.dismiss()
        stopMetrics()
        clearSuperChat()
        removeCallbacks(hideControls)
        player.removeListener(playerListener)
        danmaku.clearAll()
        activity.window.attributes = activity.window.attributes.apply {
            screenBrightness = originalBrightness
        }
    }
}
