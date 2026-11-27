package com.kk.simple_live.player

import android.app.Activity
import android.graphics.Color
import android.provider.Settings
import android.view.GestureDetector
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.ImageButton
import android.text.TextUtils
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import kotlin.math.abs
import kotlin.math.roundToInt

/** 竖屏与全屏共用 Android View；不嵌入 Flutter、PlatformView 或外部 Flutter 纹理。 */
class NativePlayerView(
    private val activity: Activity,
    private val player: ExoPlayer,
    private val onAction: (String, Any?) -> Unit,
) : FrameLayout(activity) {
    val video = android.view.LayoutInflater.from(activity)
        .inflate(com.kk.simple_live.R.layout.native_player_video, this, false) as NativeVideoView
    private val heldFrame = android.widget.ImageView(activity).apply {
        scaleType = android.widget.ImageView.ScaleType.FIT_CENTER
        visibility = GONE
    }
    private var heldBitmap: android.graphics.Bitmap? = null
    fun holdFrame(bitmap: android.graphics.Bitmap?) {
        heldBitmap = bitmap
        heldFrame.setImageBitmap(bitmap)
        heldFrame.visibility = if (bitmap == null) GONE else VISIBLE
    }
    fun captureFrame(): android.graphics.Bitmap? =
        heldBitmap ?: (video.videoSurfaceView as? android.view.TextureView)?.bitmap
    private val loading = NativePlayerLoading(activity).apply { visibility = GONE }
    private val danmaku = DanmakuOverlayView(activity)
    private val topBar = LinearLayout(activity).apply { visibility = GONE }
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
    private val lock = icon("unlock", "锁定控件") { setLocked(!locked) }.apply { visibility = GONE }
    private val danmakuButton = icon("danmaku", "弹幕开关") {
        onAction("danmaku", if (data["danmakuEnabled"] == true) 0 else 1)
    }
    private var data: Map<*, *> = emptyMap<Any, Any>()
    private var locked = false
    var onShowPanel: (String) -> Unit = {}
    private val originalBrightness = activity.window.attributes.screenBrightness
    private val hideControls = Runnable { setControlsVisible(false) }
    private val playerManager = NativePlayerManager.instance
    // 固定物理滑动尺度，横竖屏都以300dp对应完整范围，不随视频高度放大。
    private val gestureRange = dp(300).toFloat()
    private val gestureThreshold = maxOf(dp(16), ViewConfiguration.get(activity).scaledTouchSlop).toFloat()
    private var gestureX = 0f
    private var gestureY = 0f
    private var gestureVolume = 1f
    private var gestureVolumeChanged = false
    private var gestureBrightness = 0.5f
    private var dragging = false
    private var gestureActive = false
    private var topEdgeGestureBlocked = false
    private var gestureOnVolume = false
    private var roomBrightness: Float? = null
    private val playerListener = object : Player.Listener {
        override fun onRenderedFirstFrame() {
            postOnAnimation {
                // 小窗的首帧不能清掉仍遮住完整播放页的交接帧。
                if (video.player === player) holdFrame(null)
            }
        }
        override fun onEvents(player: Player, events: Player.Events) {
            updateLoading()
        }
    }

    init {
        setBackgroundColor(Color.BLACK)
        addView(video, LayoutParams(-1, -1))
        addView(heldFrame, LayoutParams(-1, -1))
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
        if (w != oldw || h != oldh) cancelGesture()
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
        cancelGesture()
        fullscreen = value
        locked = false
        expand.setImageDrawable(NativeIcons.drawable(if (value) "collapse" else "fullscreen"))
        expand.contentDescription = if (value) "退出全屏" else "全屏"
        lock.setImageDrawable(NativeIcons.drawable("unlock"))
        lock.contentDescription = "锁定控件"
        setControlsVisible(true, animate = false)
        danmaku.visibility = if (value && data["danmakuEnabled"] == true) VISIBLE else GONE
        qualityChip.visibility = if (value) VISIBLE else GONE
        danmakuSettings.visibility = VISIBLE
        info.visibility = if (value) VISIBLE else GONE
        durationText.visibility = if (value) VISIBLE else GONE
        lineChip.visibility = if (value) VISIBLE else GONE
        qualityChip.maxWidth = dp(if (value) 132 else 88)
        setSafeInsets(safeInsets[0], safeInsets[1], safeInsets[2], safeInsets[3])
        if (!value) { danmaku.clearAll(); clearSuperChat(); stopMetrics() }
        else updateSuperChat(data)
    }

    fun showMore() = onShowPanel("more")

    private fun setLocked(value: Boolean) {
        locked = value
        lock.setImageDrawable(NativeIcons.drawable(if (locked) "lock" else "unlock"))
        lock.contentDescription = if (locked) "解锁控件" else "锁定控件"
        setControlsVisible(!locked)
    }

    private fun setControlsVisible(visible: Boolean, animate: Boolean = true) {
        fun slide(view: View, shown: Boolean, x: Float = 0f, y: Float = 0f) {
            view.animate().withEndAction(null).cancel()
            // 初始化/已隐藏的控件不能为了播放“退出动画”而先变成可见。
            if (!animate || !isLaidOut || (!shown && view.visibility != VISIBLE)) {
                view.visibility = if (shown) VISIBLE else GONE
                view.translationX = 0f; view.translationY = 0f
                return
            }
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
        val previous = data
        fun changed(vararg keys: String) = previous.isEmpty() || keys.any { previous[it] != values[it] }
        val optionsChanged = changed("fontSize", "fontWeight", "opacity", "area", "duration", "topMargin", "bottomMargin")
        data = values
        if (changed("title", "userName")) title.text = "${values["title"] ?: "直播间"} - ${values["userName"] ?: ""}"
        if (changed("popularity")) subtitle.text = values["popularity"]?.toString() ?: "0"
        if (changed("durationText")) durationText.text = values["durationText"]?.toString() ?: "00:00:00"
        if (changed("qualityIndex", "qualities")) {
            val selected = (values["qualityIndex"] as? Number)?.toInt() ?: -1
            val qualities = values["qualities"] as? List<*> ?: emptyList<Any>()
            qualityChip.text = qualities.getOrNull(selected)?.toString() ?: "画质"
        }
        if (changed("lineIndex")) {
            val line = (values["lineIndex"] as? Number)?.toInt() ?: -1
            lineChip.text = if (line >= 0) "线路 ${line + 1}" else "线路"
        }
        if (changed("status")) {
            status.text = (values["status"]?.toString() ?: "").takeUnless { it.startsWith("正在加载") } ?: ""
            status.visibility = if (status.text.isEmpty()) GONE else VISIBLE
        }
        if (changed("status", "preparingPlayback", "playbackSuspended")) updateLoading()
        if (changed("floatingEnabled")) floating?.visibility = if (values["floatingEnabled"] == true) VISIBLE else GONE
        if (changed("danmakuEnabled")) {
            danmakuButton.setImageDrawable(NativeIcons.drawable(if (values["danmakuEnabled"] == true) "danmaku" else "danmakuOff"))
            danmaku.visibility = if (fullscreen && values["danmakuEnabled"] == true) VISIBLE else GONE
            if (danmaku.visibility == GONE) danmaku.clearAll()
        }
        if (changed("scaleMode")) video.setScaleMode((values["scaleMode"] as? Number)?.toInt() ?: 0)
        if (changed("superChats", "superChatEnabled", "playbackSuspended")) updateSuperChat(values)
        if (optionsChanged) danmaku.applyOptions(
            number("fontSize", 16f), number("fontWeight", 4f).toInt(),
            number("opacity", 1f), number("area", .8f), number("duration", 10f).toInt(),
            number("topMargin", 0f), number("bottomMargin", 0f), 80,
        )
    }

    private fun updateLoading() {
        val preparing = data["preparingPlayback"] == true
        loading.visibility = if (data["playbackSuspended"] != true && status.text.isEmpty() && (preparing || player.playbackState == Player.STATE_BUFFERING)) VISIBLE else GONE
    }

    private fun updateSuperChat(values: Map<*, *>) {
        if (!fullscreen || values["superChatEnabled"] != true || values["playbackSuspended"] == true) {
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

    private fun commitGestureVolume() {
        if (!gestureVolumeChanged) return
        gestureVolumeChanged = false
        // 实时调节留在原生，抬手/中断时才保存浮点基准，避免每帧跨桥写入设置。
        onAction("volume", playerManager.userPlaybackVolume.toDouble() * 100)
    }

    private fun currentBrightness(): Float {
        val windowValue = activity.window.attributes.screenBrightness
        if (windowValue.isFinite() && windowValue >= 0f) return windowValue.coerceIn(.01f, 1f)
        return runCatching {
            Settings.System.getInt(activity.contentResolver, Settings.System.SCREEN_BRIGHTNESS) / 255f
        }.getOrDefault(.5f).coerceIn(.01f, 1f)
    }

    private fun cancelGesture(force: Boolean = false) {
        commitGestureVolume()
        tip.visibility = GONE
        // 构造时 setFullscreen 也会走到这里，此时还未创建 GestureDetector。
        if (!force && !gestureActive && !dragging) return
        gestureActive = false; dragging = false
        val cancel = MotionEvent.obtain(0, 0, MotionEvent.ACTION_CANCEL, 0f, 0f, 0)
        detector.onTouchEvent(cancel); cancel.recycle()
    }

    override fun onConfigurationChanged(config: android.content.res.Configuration) {
        super.onConfigurationChanged(config)
        cancelGesture()
        // 亮度跟随房间、浮点音量由播放器管理，旋转只取消手势，不回放旧快照。
        roomBrightness?.let { value ->
            activity.window.attributes = activity.window.attributes.apply { screenBrightness = value }
        }
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (event.actionMasked == MotionEvent.ACTION_DOWN) {
            // 全屏顶部至少留出48dp，状态栏/刘海较高时再向下留16dp。
            // 使用忽略可见性的状态栏高度，沉浸模式下也保留稳定的下拉入口。
            val statusTop = ViewCompat.getRootWindowInsets(this)
                ?.getInsetsIgnoringVisibility(WindowInsetsCompat.Type.statusBars())?.top ?: 0
            val blockedHeight = maxOf(dp(48), maxOf(statusTop, safeInsets[1]) + dp(16))
            topEdgeGestureBlocked = fullscreen && event.y < blockedHeight
            if (topEdgeGestureBlocked) cancelGesture(force = true)
        }
        // 按起点屏蔽整段触摸，移出区域也不接手；直接点击子控件仍正常响应。
        if (topEdgeGestureBlocked) return true
        if (locked) return true
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                gestureActive = true
                gestureOnVolume = event.x >= width / 2f
                gestureX = event.x
                gestureY = event.y
                gestureVolumeChanged = false
                dragging = false
            }
            MotionEvent.ACTION_POINTER_DOWN -> {
                cancelGesture(force = true)
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                if (!gestureActive) return true
                val dy = gestureY - event.y
                if (!dragging && abs(dy) > gestureThreshold && abs(dy) > abs(event.x - gestureX) * 1.3f) {
                    dragging = true
                    // 触发前的位移仅用于判定意图，不计入调节，避免起步跳变。
                    gestureY = event.y
                    gestureVolume = playerManager.userPlaybackVolume
                    gestureBrightness = currentBrightness()
                    val cancel = MotionEvent.obtain(event)
                    cancel.action = MotionEvent.ACTION_CANCEL
                    detector.onTouchEvent(cancel)
                    cancel.recycle()
                    removeCallbacks(hideControls)
                }
                if (dragging) {
                    val delta = (gestureY - event.y) / gestureRange
                    if (gestureOnVolume) {
                        val value = (gestureVolume + delta).coerceIn(0f, 1f)
                        if (value != playerManager.userPlaybackVolume) {
                            playerManager.setPlaybackVolume(value)
                            gestureVolumeChanged = true
                        }
                        // 只有显示取整，实际音量始终保留浮点精度，不使用系统整数档位。
                        tip.text = "音量 ${(value * 100).roundToInt()}%"
                        if (value == 0f || value == 1f) {
                            gestureVolume = value; gestureY = event.y
                        }
                    } else {
                        val value = (gestureBrightness + delta).coerceIn(.01f, 1f)
                        if (value != (roomBrightness ?: gestureBrightness)) {
                            roomBrightness = value
                            activity.window.attributes = activity.window.attributes.apply { screenBrightness = value }
                        }
                        tip.text = "亮度 ${(value * 100).roundToInt()}%"
                        if (value == .01f || value == 1f) {
                            gestureBrightness = value; gestureY = event.y
                        }
                    }
                    tip.visibility = VISIBLE
                }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                if (!gestureActive) return true
                commitGestureVolume()
                gestureActive = false
                tip.visibility = GONE
                scheduleHide()
                if (dragging) { dragging = false; return true }
            }
        }
        if (!dragging) detector.onTouchEvent(event)
        return true
    }

    fun suspendPlaybackUi() {
        cancelGesture()
        stopMetrics()
        clearSuperChat()
        danmaku.clearAll()
        loading.visibility = GONE
        removeCallbacks(hideControls)
    }

    fun dispose() {
        cancelGesture()
        holdFrame(null)
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
