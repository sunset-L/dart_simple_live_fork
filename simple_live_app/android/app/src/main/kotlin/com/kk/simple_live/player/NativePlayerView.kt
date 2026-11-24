package com.kk.simple_live.player

import android.app.Activity
import android.content.Context
import android.graphics.Color
import android.media.AudioManager
import android.view.GestureDetector
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.ImageButton
import android.text.TextUtils
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import kotlin.math.abs
import kotlin.math.roundToInt

/** 竖屏与全屏共用 Android View；不嵌入 Flutter、PlatformView 或外部 Flutter 纹理。 */
class NativePlayerView(
    private val activity: Activity,
    private val player: ExoPlayer,
    private val onAction: (String, Any?) -> Unit,
) : FrameLayout(activity) {
    private var forcedAspect = 0f
    val video = object : PlayerView(activity) {
        override fun onContentAspectRatioChanged(frame: AspectRatioFrameLayout?, ratio: Float) {
            super.onContentAspectRatioChanged(frame, if (forcedAspect > 0f) forcedAspect else ratio)
        }
    }.apply {
        useController = false
        isClickable = false
        isFocusable = false
        setShowBuffering(PlayerView.SHOW_BUFFERING_NEVER)
        setKeepContentOnPlayerReset(true)
    }
    private val loading = NativePlayerLoading(activity).apply { visibility = GONE }
    private val danmaku = DanmakuOverlayView(activity)
    private val topBar = LinearLayout(activity)
    private val bottomBar = LinearLayout(activity)
    private var floating: ImageButton? = null
    private val subtitle = TextView(activity)
    private val durationText = TextView(activity)
    private val qualityChip = TextView(activity)
    private val lineChip = TextView(activity)
    private val danmakuSettings = icon("danmakuSettings", "弹幕设置") { onShowPanel("danmakuSettings") }
    private val info = icon("info", "播放信息") { showMetrics() }
    private var safeInsets = intArrayOf(0, 0, 0, 0)
    private var fullscreen = false
    private val expand = icon("fullscreen", "全屏") { onAction(if (fullscreen) "exit" else "fullscreen", null) }
    private val title = TextView(activity)
    private val tip = TextView(activity)
    private val status = TextView(activity)
    private var metricsText: TextView? = null
    private val superChat = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
    private val seenSC = linkedSetOf<String>()
    private val scTimers = mutableMapOf<String, Runnable>()
    private val lock = icon("unlock", "锁定控件") { setLocked(!locked) }
    private val danmakuButton = icon("danmaku", "弹幕开关") {
        onAction("danmaku", if (data["danmakuEnabled"] == true) 0 else 1)
    }
    private var data: Map<*, *> = emptyMap<Any, Any>()
    private var locked = false
    var onShowPanel: (String) -> Unit = {}
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
            updateLoading()
        }
    }

    init {
        setBackgroundColor(Color.BLACK)
        addView(video, LayoutParams(-1, -1))
        addView(danmaku, LayoutParams(-1, -1))
        addView(loading, LayoutParams(dp(36), dp(36), Gravity.CENTER))
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
        topBar.background = android.graphics.drawable.GradientDrawable(
            android.graphics.drawable.GradientDrawable.Orientation.TOP_BOTTOM,
            intArrayOf(0xBB000000.toInt(), 0x00000000))
        topBar.addView(icon("back", "返回") { onAction(if (fullscreen) "exit" else "back", null) }, LinearLayout.LayoutParams(dp(44), dp(44)))
        title.setTextColor(Color.WHITE); title.textSize = 16f; title.maxLines = 1
        title.ellipsize = TextUtils.TruncateAt.END; title.includeFontPadding = false
        topBar.addView(title, LinearLayout.LayoutParams(0, -2, 1f).apply { leftMargin = dp(12) })
        subtitle.setTextColor(Color.LTGRAY); subtitle.textSize = 12f; subtitle.maxLines = 1
        val flame = NativeIcons.drawable("fire", Color.LTGRAY); flame.setBounds(0, 0, dp(16), dp(16))
        subtitle.setCompoundDrawables(flame, null, null, null); subtitle.compoundDrawablePadding = dp(4)
        topBar.addView(subtitle, LinearLayout.LayoutParams(-2, -2).apply { leftMargin = dp(8); rightMargin = dp(8) })
        topBar.addView(icon("rooms", "关注 / 历史") { onAction("rooms", null) }, LinearLayout.LayoutParams(dp(44), dp(44)))
        floating = icon("floating", "小窗播放") { onAction("floating", null) }.also {
            topBar.addView(it, LinearLayout.LayoutParams(dp(44), dp(44))) }
        topBar.addView(icon("more", "播放设置") { showSettings() }, LinearLayout.LayoutParams(dp(44), dp(44)))
        addView(topBar, LayoutParams(-1, dp(64), Gravity.TOP))
        runCatching {
            val bitmap = activity.assets.open("flutter_assets/assets/icons/icon_danmaku_setting.png").use { android.graphics.BitmapFactory.decodeStream(it) }
            danmakuSettings.setImageDrawable(android.graphics.drawable.BitmapDrawable(resources, bitmap).apply { setTint(Color.WHITE) })
        }
        bottomBar.gravity = Gravity.CENTER_VERTICAL
        bottomBar.background = android.graphics.drawable.GradientDrawable(
            android.graphics.drawable.GradientDrawable.Orientation.TOP_BOTTOM,
            intArrayOf(0x00000000, 0xDD000000.toInt()))
        for (button in listOf(icon("refresh", "刷新") { onAction("refresh", null) }, danmakuButton, danmakuSettings, info)) {
            bottomBar.addView(button, LinearLayout.LayoutParams(dp(44), dp(44)))
        }
        durationText.textSize = 14f; durationText.setTextColor(Color.WHITE)
        durationText.gravity = Gravity.CENTER_VERTICAL
        bottomBar.addView(durationText, LinearLayout.LayoutParams(-2, dp(44)).apply { leftMargin = dp(8) })
        bottomBar.addView(View(activity), LinearLayout.LayoutParams(0, 1, 1f))
        setupChip(qualityChip, "quality", "画质") { showQuality() }
        setupChip(lineChip, "line", "线路") { showLines() }
        bottomBar.addView(qualityChip, LinearLayout.LayoutParams(-2, dp(32)).apply { rightMargin = dp(4) })
        bottomBar.addView(lineChip, LinearLayout.LayoutParams(-2, dp(32)).apply { rightMargin = dp(8) })
        bottomBar.addView(expand, LinearLayout.LayoutParams(dp(44), dp(44)))
        addView(bottomBar, LayoutParams(-1, dp(48), Gravity.BOTTOM))
        addView(lock, LayoutParams(dp(40), dp(40), Gravity.END or Gravity.CENTER_VERTICAL).apply { rightMargin = dp(12) })
        tip.setTextColor(Color.WHITE)
        tip.textSize = 18f
        tip.gravity = Gravity.CENTER
        tip.background = NativeIcons.background(0xFF212121.toInt(), dp(12).toFloat())
        tip.setPadding(dp(12), dp(12), dp(12), dp(12))
        tip.visibility = GONE
        addView(tip, LayoutParams(-2, -2, Gravity.CENTER))
        player.addListener(playerListener)
        setFullscreen(false)
    }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).roundToInt()

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        val wide = fullscreen && w > dp(560)
        durationText.visibility = if (wide) VISIBLE else GONE
        info.visibility = if (wide) VISIBLE else GONE
        danmakuSettings.visibility = VISIBLE
        lineChip.visibility = if (wide) VISIBLE else GONE
    }

    private fun setupChip(chip: TextView, name: String, label: String, action: () -> Unit) {
        chip.text = label; chip.contentDescription = label; chip.textSize = 12f
        chip.maxLines = 1; chip.ellipsize = TextUtils.TruncateAt.END; chip.gravity = Gravity.CENTER
        chip.setTextColor(Color.WHITE); chip.setPadding(dp(8), 0, dp(8), 0)
        val image = NativeIcons.drawable(name)
        image.setBounds(0, 0, dp(18), dp(18))
        chip.setCompoundDrawables(image, null, null, null); chip.compoundDrawablePadding = dp(4)
        chip.background = NativeIcons.background(0x55FFFFFF, dp(8).toFloat())
        chip.setOnClickListener { action(); scheduleHide() }
    }

    fun setSafeInsets(left: Int, top: Int, right: Int, bottom: Int) {
        safeInsets = intArrayOf(left, top, right, bottom)
        topBar.setPadding(left + dp(8), top, right + dp(8), 0)
        topBar.layoutParams = LayoutParams(-1, dp(64) + top, Gravity.TOP)
        bottomBar.setPadding(if (fullscreen) left + dp(12) else dp(4), 0,
            if (fullscreen) right + dp(12) else dp(4), if (fullscreen) bottom else 0)
        bottomBar.layoutParams = LayoutParams(-1, dp(48) + if (fullscreen) bottom else 0, Gravity.BOTTOM)
        lock.layoutParams = LayoutParams(dp(40), dp(40), Gravity.END or Gravity.CENTER_VERTICAL).apply { rightMargin = right + dp(12) }
    }

    fun showQuality() = onShowPanel("quality")
    fun showLines() = onShowPanel("line")
    private fun icon(name: String, label: String, action: () -> Unit) =
        NativeIcons.button(activity, name, label) { action(); scheduleHide() }.apply {
            val inset = dp(11)
            setPadding(inset, inset, inset, inset)
            scaleType = android.widget.ImageView.ScaleType.FIT_CENTER
        }

    fun setFullscreen(value: Boolean) {
        fullscreen = value
        locked = false
        expand.setImageDrawable(NativeIcons.drawable(if (value) "collapse" else "fullscreen"))
        expand.contentDescription = if (value) "退出全屏" else "全屏"
        lock.setImageDrawable(NativeIcons.drawable("lock"))
        setControlsVisible(true)
        danmaku.visibility = if (value && data["danmakuEnabled"] == true) VISIBLE else GONE
        qualityChip.visibility = if (value) VISIBLE else GONE
        danmakuSettings.visibility = VISIBLE
        info.visibility = if (value) VISIBLE else GONE
        durationText.visibility = if (value) VISIBLE else GONE
        lineChip.visibility = if (value) VISIBLE else GONE
        qualityChip.maxWidth = dp(if (value) 132 else 88)
        setSafeInsets(safeInsets[0], safeInsets[1], safeInsets[2], safeInsets[3])
        if (!value) { clearSuperChat(); stopMetrics() }
    }

    fun showMore() = onShowPanel("more")

    private fun setLocked(value: Boolean) {
        locked = value
        lock.setImageDrawable(NativeIcons.drawable(if (locked) "lock" else "unlock"))
        lock.contentDescription = if (locked) "解锁控件" else "锁定控件"
        setControlsVisible(!locked)
    }

    private fun setControlsVisible(visible: Boolean) {
        fun slide(view: View, shown: Boolean, x: Float = 0f, y: Float = 0f) {
            view.animate().cancel()
            if (shown && view.visibility != VISIBLE) { view.translationX = x; view.translationY = y }
            view.visibility = VISIBLE
            view.animate().translationX(if (shown) 0f else x).translationY(if (shown) 0f else y)
                .setDuration(200).withEndAction { if (!shown) view.visibility = GONE }.start()
        }
        slide(topBar, visible && !locked && fullscreen, y = -(dp(64) + safeInsets[1]).toFloat())
        slide(bottomBar, visible && !locked, y = (dp(64) + safeInsets[3]).toFloat())
        slide(lock, fullscreen && (visible || locked), x = dp(64).toFloat())
        if (visible) scheduleHide()
    }

    private fun scheduleHide() {
        removeCallbacks(hideControls)
        if (!locked) postDelayed(hideControls, 5000L)
    }

    fun update(values: Map<*, *>) {
        val optionsChanged = listOf("fontSize", "fontWeight", "opacity", "area", "duration", "topMargin", "bottomMargin").any { data[it] != values[it] }
        data = values
        title.text = "${values["title"] ?: "直播间"} - ${values["userName"] ?: ""}"
        subtitle.text = values["popularity"]?.toString() ?: "0"
        durationText.text = values["durationText"]?.toString() ?: "00:00:00"
        val selected = (values["qualityIndex"] as? Number)?.toInt() ?: -1
        val qualities = values["qualities"] as? List<*> ?: emptyList<Any>()
        qualityChip.text = qualities.getOrNull(selected)?.toString() ?: "画质"
        val line = (values["lineIndex"] as? Number)?.toInt() ?: -1
        lineChip.text = if (line >= 0) "线路 ${line + 1}" else "线路"
        status.text = (values["status"]?.toString() ?: "").takeUnless { it.startsWith("正在加载") } ?: ""
        status.visibility = if (status.text.isEmpty()) GONE else VISIBLE
        updateLoading()
        floating?.visibility = if (values["floatingEnabled"] == true) VISIBLE else GONE
        danmakuButton.setImageDrawable(NativeIcons.drawable(if (values["danmakuEnabled"] == true) "danmaku" else "danmakuOff"))
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
        danmaku.visibility = if (fullscreen && values["danmakuEnabled"] == true) VISIBLE else GONE
        if (danmaku.visibility == GONE) danmaku.clearAll()
        updateSuperChat(values)
        if (optionsChanged) danmaku.applyOptions(
            number("fontSize", 16f), number("fontWeight", 4f).toInt(),
            number("opacity", 1f), number("area", .8f), number("duration", 10f).toInt(),
            number("topMargin", 0f), number("bottomMargin", 0f), 80,
        )
    }

    private fun updateLoading() {
        val active = player.mediaItemCount > 0
        loading.visibility = if (player.playbackState == Player.STATE_BUFFERING || (!active && data["status"]?.toString()?.startsWith("正在加载") == true)) VISIBLE else GONE
    }

    private fun updateSuperChat(values: Map<*, *>) {
        if (!fullscreen || values["superChatEnabled"] != true) {
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

    private fun stopMetrics() {
        if (metricsText == null) return
        metricsText?.let { removeView(it) }
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

    fun showMetrics() {
        if (metricsText != null) { stopMetrics(); return }
        removeCallbacks(hideControls)
        val text = TextView(activity).apply {
            textSize = 12f; setTextColor(Color.WHITE)
            setPadding(dp(12), dp(10), dp(12), dp(10))
            background = NativeIcons.background(0xDD202020.toInt(), dp(8).toFloat())
        }
        metricsText = text
        addView(text, LayoutParams(dp(260), -2, Gravity.START or Gravity.BOTTOM).apply {
            leftMargin = safeInsets[0] + dp(12); bottomMargin = safeInsets[3] + dp(56) })
        NativePlayerManager.instance.setMetricsListening(true)
        refreshMetrics.run()
    }

    fun showSettings() = onShowPanel("playerSettings")

    private val detector = GestureDetector(activity,
        object : GestureDetector.SimpleOnGestureListener() {
            override fun onDown(e: MotionEvent) = true
            override fun onSingleTapConfirmed(e: MotionEvent): Boolean {
                setControlsVisible(bottomBar.visibility != VISIBLE)
                return true
            }
            override fun onLongPress(e: MotionEvent) {
                if (!locked) onAction("rooms", null)
            }
            override fun onDoubleTap(e: MotionEvent): Boolean {
                if (!locked) onAction(if (fullscreen) "exit" else "fullscreen", null)
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
        stopMetrics()
        clearSuperChat()
        removeCallbacks(hideControls)
        for (view in listOf(topBar, bottomBar, lock)) view.animate().cancel()
        player.removeListener(playerListener)
        danmaku.clearAll()
        activity.window.attributes = activity.window.attributes.apply {
            screenBrightness = originalBrightness
        }
    }
}
