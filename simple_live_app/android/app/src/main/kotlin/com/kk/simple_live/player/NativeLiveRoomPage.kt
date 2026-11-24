package com.kk.simple_live.player

import android.app.Activity
import android.app.AlertDialog
import android.graphics.Color
import android.text.SpannableStringBuilder
import android.text.TextUtils
import android.text.style.ForegroundColorSpan
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.*
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.media3.exoplayer.ExoPlayer
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

/** 原生房间页：视频、房间资料、聊天、SC、关注/历史、设置及弹窗都不嵌入 Flutter。 */
class NativeLiveRoomPage(
    private val activity: Activity,
    player: ExoPlayer,
    private val onAction: (String, Any?) -> Unit,
) : FrameLayout(activity) {
    val video = NativePlayerView(activity, player, onAction)
    var fullscreen = false
        private set
    private var data: Map<*, *> = emptyMap<Any, Any>()
    private val header = LinearLayout(activity)
    private val roomTitle = label("直播间", 18f)
    private val profile = LinearLayout(activity)
    private val avatar = ImageView(activity)
    private val user = label("", 16f)
    private val popularity = label("", 13f)
    private val follow = NativeIcons.button(activity, "follow", "关注主播") {
        if (data["followed"] == true) confirm("取消关注", "确定要取消关注该主播吗？") { onAction("unfollow", null) }
        else onAction("follow", null)
    }
    private val tabs = LinearLayout(activity)
    private val list = ListView(activity)
    private val bottom = LinearLayout(activity)
    private val chat = ArrayList<Map<*, *>>()
    private var rows: List<Map<*, *>> = emptyList()
    private var tab = "聊天"
    private var autoScroll = true
    private var restoredPosition = 0
    private var restoredOffset = 0
    private val latest = TextView(activity)
    private val adapter = RoomAdapter()
    private var dialog: AlertDialog? = null
    private var safeLeft = 0
    private var safeTop = 0
    private var safeRight = 0
    private var safeBottom = 0
    private var refreshRoomDialog: (() -> Unit)? = null
    private var accent = 0xFF3498DB.toInt()
    private var dark = true
    private val paletteForeground: Int get() = if (dark) Color.WHITE else 0xFF333333.toInt()

    init {
        setBackgroundColor(0xFF151515.toInt())
        isFocusableInTouchMode = true
        header.gravity = Gravity.CENTER_VERTICAL
        header.addView(icon("back", "返回") { onAction("back", null) }, LinearLayout.LayoutParams(dp(48), -1))
        roomTitle.maxLines = 1; roomTitle.ellipsize = TextUtils.TruncateAt.END
        header.addView(roomTitle, LinearLayout.LayoutParams(0, -1, 1f))
        header.addView(icon("more", "更多") { video.showMore() }, LinearLayout.LayoutParams(dp(48), -1))
        addView(header)
        addView(video)
        profile.gravity = Gravity.CENTER_VERTICAL
        profile.setPadding(dp(16), dp(8), dp(12), dp(8))
        avatar.scaleType = ImageView.ScaleType.CENTER_CROP
        avatar.background = NativeIcons.background(0xFF303030.toInt(), dp(22).toFloat())
        avatar.clipToOutline = true
        avatar.setImageDrawable(NativeIcons.drawable("rooms", Color.LTGRAY))
        profile.addView(avatar, LinearLayout.LayoutParams(dp(44), dp(44)))
        val names = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(12), 0, dp(8), 0)
            addView(user, LinearLayout.LayoutParams(-1, dp(26)))
            addView(popularity, LinearLayout.LayoutParams(-1, dp(22)))
        }
        profile.addView(names, LinearLayout.LayoutParams(0, -2, 1f))
        profile.addView(follow, LinearLayout.LayoutParams(dp(44), dp(44)))
        addView(profile)
        addView(tabs)
        list.adapter = adapter
        list.divider = null
        list.clipToPadding = false
        list.setPadding(dp(12), dp(8), dp(12), dp(8))
        list.setOnScrollListener(object : AbsListView.OnScrollListener {
            override fun onScrollStateChanged(view: AbsListView, state: Int) {
                if (tab == "聊天" && state != AbsListView.OnScrollListener.SCROLL_STATE_IDLE) autoScroll = false
            }
            override fun onScroll(view: AbsListView, first: Int, visible: Int, total: Int) {
                if (tab == "聊天" && first + visible >= total) autoScroll = true
                latest.visibility = if (!fullscreen && tab == "聊天" && !autoScroll) VISIBLE else GONE
            }
        })
        list.setOnItemClickListener { _, _, index, _ ->
            rows.getOrNull(index)?.let { row ->
                if (tab == "关注" || tab == "历史") onAction("openRoom", row)
                else if (tab == "设置") row["action"]?.toString()?.let { settingsAction(it) }
            }
        }
        list.setOnItemLongClickListener { _, _, index, _ ->
            val row = rows.getOrNull(index) ?: return@setOnItemLongClickListener false
            if (tab != "聊天") return@setOnItemLongClickListener false
            val text = row["message"]?.toString() ?: ""
            AlertDialog.Builder(activity).setItems(arrayOf("复制消息", "屏蔽此内容")) { _, which ->
                if (which == 0) {
                    val clip = activity.getSystemService(android.content.Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
                    clip.setPrimaryClip(android.content.ClipData.newPlainText("弹幕", text))
                    Toast.makeText(activity, "已复制消息", Toast.LENGTH_SHORT).show()
                } else onAction("addShield", text)
            }.show()
            true
        }
        addView(list)
        latest.text = "↓ 最新"; latest.textSize = 13f; latest.setTextColor(Color.WHITE)
        latest.gravity = Gravity.CENTER
        latest.background = NativeIcons.background(accent, dp(20).toFloat())
        latest.visibility = GONE
        latest.setOnClickListener { autoScroll = true; scrollLatest() }
        addView(latest)
        bottom.gravity = Gravity.CENTER_VERTICAL
        bottom.addView(actionButton("rooms", "关注 / 历史") { showRooms("关注") }, LinearLayout.LayoutParams(0, -1, 1f))
        bottom.addView(actionButton("settings", "设置") { selectTab("设置") }, LinearLayout.LayoutParams(0, -1, 1f))
        bottom.addView(actionButton("share", "分享") { onAction("share", null) }, LinearLayout.LayoutParams(0, -1, 1f))
        addView(bottom)
        ViewCompat.setOnApplyWindowInsetsListener(this) { _, insets ->
            val cutout = insets.getInsets(WindowInsetsCompat.Type.displayCutout())
            val system = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            safeLeft = maxOf(cutout.left, if (fullscreen) 0 else system.left)
            safeTop = maxOf(cutout.top, if (fullscreen) 0 else system.top)
            safeRight = maxOf(cutout.right, if (fullscreen) 0 else system.right)
            safeBottom = maxOf(cutout.bottom, if (fullscreen) 0 else system.bottom)
            video.setSafeInsets(cutout.left, cutout.top, cutout.right, cutout.bottom)
            requestLayout()
            insets
        }
        rebuildTabs()
    }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).roundToInt()
    private fun label(text: String, size: Float) = TextView(activity).apply {
        this.text = text; textSize = size; setTextColor(Color.WHITE); gravity = Gravity.CENTER_VERTICAL
    }
    private fun icon(name: String, text: String, action: () -> Unit) = NativeIcons.button(activity, name, text, action).apply {
        setPadding(dp(12), dp(12), dp(12), dp(12)); scaleType = ImageView.ScaleType.FIT_CENTER
    }
    private fun actionButton(name: String, text: String, action: () -> Unit) = TextView(activity).apply {
        this.text = text; textSize = 13f; gravity = Gravity.CENTER; setTextColor(Color.LTGRAY)
        val drawable = NativeIcons.drawable(name, Color.LTGRAY)
        drawable.setBounds(0, 0, dp(18), dp(18))
        setCompoundDrawables(drawable, null, null, null)
        compoundDrawablePadding = dp(6); setPadding(dp(16), 0, dp(8), 0)
        setOnClickListener { action() }
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = MeasureSpec.getSize(widthMeasureSpec)
        val height = MeasureSpec.getSize(heightMeasureSpec)
        setMeasuredDimension(width, height)
        fun measure(view: View, w: Int, h: Int) = view.measure(
            MeasureSpec.makeMeasureSpec(w.coerceAtLeast(0), MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(h.coerceAtLeast(0), MeasureSpec.EXACTLY))
        if (fullscreen) { measure(video, width, height); return }
        val availableWidth = width - safeLeft - safeRight
        val availableHeight = (height - safeTop - safeBottom).coerceAtLeast(0)
        val headerHeight = dp(52)
        val ratio = (data["aspectRatio"] as? Number)?.toDouble()?.takeIf { it.isFinite() && it in .2..4.0 } ?: (16.0 / 9)
        val videoHeight = (availableWidth / ratio).roundToInt().coerceAtMost((availableHeight * .44).roundToInt())
        measure(header, availableWidth, headerHeight)
        measure(video, availableWidth, videoHeight)
        measure(profile, availableWidth, dp(72)); measure(tabs, availableWidth, dp(44))
        measure(bottom, availableWidth, dp(48))
        measure(list, availableWidth, availableHeight - headerHeight - videoHeight - dp(164))
        measure(latest, dp(84), dp(40))
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottomEdge: Int) {
        if (fullscreen) { video.layout(0, 0, width, height); return }
        var y = safeTop
        for (view in listOf(header, video, profile, tabs, list, bottom)) {
            view.layout(safeLeft, y, width - safeRight, y + view.measuredHeight)
            y += view.measuredHeight
        }
        latest.layout(width - safeRight - dp(100), list.bottom - dp(56), width - safeRight - dp(16), list.bottom - dp(16))
    }

    fun setFullscreen(value: Boolean) {
        if (fullscreen == value) return
        if (value) {
            restoredPosition = list.firstVisiblePosition
            restoredOffset = list.getChildAt(0)?.top ?: 0
            list.adapter = null
            rows = emptyList()
        }
        fullscreen = value
        video.setFullscreen(value)
        for (view in listOf(header, profile, tabs, list, bottom)) view.visibility = if (value) GONE else VISIBLE
        latest.visibility = GONE
        if (!value) { list.adapter = adapter; rebuildTabs(); renderRows(); list.setSelectionFromTop(restoredPosition, restoredOffset) }
        requestLayout()
        ViewCompat.requestApplyInsets(this)
    }

    fun update(values: Map<*, *>) {
        val roomChanged = data["roomKey"] != values["roomKey"]
        val tabsChanged = roomChanged || data["hasSC"] != values["hasSC"] ||
            data["dark"] != values["dark"] || data["accent"] != values["accent"]
        data = values
        dark = values["dark"] == true
        accent = (values["accent"] as? Number)?.toInt() ?: 0xFF3498DB.toInt()
        setBackgroundColor(if (dark) 0xFF151515.toInt() else 0xFFFAFAFA.toInt())
        roomTitle.setTextColor(paletteForeground); user.setTextColor(paletteForeground)
        for (i in 0 until header.childCount) (header.getChildAt(i) as? ImageView)?.imageTintList = android.content.res.ColorStateList.valueOf(paletteForeground)
        if (roomChanged) { chat.clear(); autoScroll = true; restoredPosition = 0; restoredOffset = 0 }
        roomTitle.text = values["title"]?.toString() ?: "直播间"
        user.text = values["userName"]?.toString() ?: "直播间"
        user.maxLines = 1; user.ellipsize = TextUtils.TruncateAt.END
        popularity.text = "${values["siteName"] ?: ""}   ·   热度 ${values["popularity"] ?: "0"}"
        popularity.setTextColor(Color.GRAY)
        NativeAvatar.load(avatar, values["avatar"]?.toString() ?: "")
        follow.setImageDrawable(NativeIcons.drawable("follow", if (values["followed"] == true) accent else paletteForeground))
        follow.contentDescription = if (values["followed"] == true) "取消关注" else "关注主播"
        video.update(values)
        if (!fullscreen) { if (tabsChanged) rebuildTabs(); renderRows() }
        refreshRoomDialog?.invoke()
        requestLayout()
    }

    private fun rebuildTabs() {
        val names = listOf("聊天") + (if (data["hasSC"] == true) listOf("SC") else emptyList()) + listOf("关注", "设置")
        if (tab !in names) tab = "聊天"
        tabs.removeAllViews()
        for (name in names) {
            val item = label(name, 14f).apply {
                gravity = Gravity.CENTER
                setTextColor(if (name == tab) accent else paletteForeground)
                setOnClickListener { selectTab(name) }
            }
            tabs.addView(item, LinearLayout.LayoutParams(0, -1, 1f))
        }
    }

    private fun selectTab(name: String) {
        tab = name
        autoScroll = true
        rebuildTabs()
        renderRows()
        if (name == "关注") onAction("reloadFollow", null)
        if (name == "聊天") scrollLatest()
    }

    fun addMessages(items: List<*>) {
        for (item in items) (item as? Map<*, *>)?.let { chat.add(it) }
        if (chat.size > 200) chat.subList(0, chat.size - 200).clear()
        if (!fullscreen && tab == "聊天") { renderRows(); if (autoScroll) scrollLatest() }
    }
    fun clearMessages() { chat.clear(); if (!fullscreen) renderRows() }
    private fun scrollLatest() { list.post { if (!fullscreen && tab == "聊天" && autoScroll) list.setSelection(adapter.count - 1) } }

    private fun renderRows() {
        if (fullscreen) return
        rows = when (tab) {
            "聊天" -> listOf(mapOf("userName" to "", "message" to (data["title"] ?: "直播间"))) + chat
            "SC" -> (data["superChats"] as? List<*>)?.filterIsInstance<Map<*, *>>() ?: emptyList()
            "关注" -> (data["follows"] as? List<*>)?.filterIsInstance<Map<*, *>>() ?: emptyList()
            "设置" -> listOf("聊天文字大小" to "chatSize", "聊天上下间隔" to "chatGap", "气泡样式" to "chatBubble",
                "播放器显示SC" to "showSC", "关键词屏蔽" to "shieldSettings", "弹幕设置" to "danmakuSettings",
                "画面尺寸" to "playerSettings", "定时关闭" to "autoExitSettings")
                .map { mapOf("text" to it.first, "action" to it.second) }
            else -> emptyList()
        }
        adapter.notifyDataSetChanged()
    }

    private inner class RoomAdapter : BaseAdapter() {
        override fun getCount() = rows.size
        override fun getItem(position: Int) = rows[position]
        override fun getItemId(position: Int) = position.toLong()
        override fun getView(position: Int, recycled: View?, parent: ViewGroup): View {
            val text = (recycled as? TextView) ?: label("", 14f)
            val row = rows[position]
            val size = (data["chatSize"] as? Number)?.toFloat() ?: 14f
            val gap = (data["chatGap"] as? Number)?.toInt() ?: 4
            text.setTextColor(paletteForeground)
            text.textSize = if (tab == "聊天") size.coerceIn(8f, 36f) else 14f
            text.setPadding(dp(8), dp(if (tab == "聊天") gap.coerceIn(0, 12) + 4 else 12), dp(8), dp(8))
            text.background = if (tab == "聊天" && data["chatBubble"] == true)
                NativeIcons.background(if (dark) 0xFF252525.toInt() else 0xFFEEEEEE.toInt(), dp(8).toFloat()) else null
            text.text = when (tab) {
                "聊天" -> {
                    val name = row["userName"]?.toString() ?: ""
                    val prefix = if (name.isEmpty()) "" else "$name："
                    SpannableStringBuilder(prefix + (row["message"] ?: "")).apply {
                        if (prefix.isNotEmpty()) setSpan(ForegroundColorSpan(Color.GRAY), 0, prefix.length, 0)
                    }
                }
                "SC" -> row["text"]?.toString() ?: ""
                "关注", "历史" -> "${row["userName"] ?: ""}\n${row["siteName"] ?: ""} · ${row["status"] ?: ""}"
                else -> row["text"]?.toString() ?: ""
            }
            return text
        }
    }

    private fun settingsAction(action: String) {
        when (action) {
            "chatSize" -> chooseNumbers("聊天文字大小", "chatSize", listOf(10, 12, 14, 16, 18, 20, 24, 28, 32, 36))
            "chatGap" -> chooseNumbers("聊天上下间隔", "chatGap", listOf(0, 2, 4, 6, 8, 10, 12))
            "chatBubble" -> onAction("chatBubble", data["chatBubble"] != true)
            "showSC" -> onAction("showSC", data["superChatEnabled"] != true)
            "danmakuSettings", "playerSettings" -> video.showSettings()
            else -> onAction(action, null)
        }
    }
    private fun chooseNumbers(title: String, action: String, values: List<Int>) {
        dialog?.dismiss()
        val popup = AlertDialog.Builder(activity).setTitle(title)
            .setItems(values.map { it.toString() }.toTypedArray()) { _, index -> onAction(action, values[index]) }.create()
        dialog = popup
        popup.setOnDismissListener { if (dialog === popup) dialog = null }
        popup.show()
    }
    private fun confirm(title: String, message: String, yes: () -> Unit) {
        dialog?.dismiss()
        val popup = AlertDialog.Builder(activity).setTitle(title).setMessage(message).setNegativeButton("取消", null)
            .setPositiveButton("确定") { _, _ -> yes() }.create()
        dialog = popup
        popup.setOnDismissListener { if (dialog === popup) dialog = null }
        popup.show()
    }

    fun showDialog(kind: String, values: Map<*, *>, result: MethodChannel.Result) {
        dialog?.dismiss()
        var answered = false
        fun answer(value: Any?) { if (!answered) { answered = true; result.success(value) } }
        val builder = AlertDialog.Builder(activity)
        when (kind) {
            "rooms" -> { showRooms(values["tab"]?.toString() ?: "关注"); answer(null); return }
            "shield" -> {
                val input = EditText(activity).apply {
                    hint = "每行一个关键词，正则使用 /表达式/"
                    setText((values["keywords"] as? List<*>)?.joinToString("\n") ?: "")
                    setPadding(dp(20), dp(12), dp(20), dp(12)); minLines = 4; maxLines = 8
                }
                builder.setTitle("关键词屏蔽").setView(input).setNegativeButton("取消", null)
                    .setPositiveButton("保存") { _, _ -> answer(input.text.toString().split("\n").map { it.trim() }.filter { it.isNotEmpty() }) }
            }
            "autoExitSettings" -> {
                val box = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(20), dp(8), dp(20), dp(8)) }
                val enabled = Switch(activity).apply { text = "启用定时关闭"; isChecked = values["enabled"] == true }
                val minutes = EditText(activity).apply { inputType = android.text.InputType.TYPE_CLASS_NUMBER
                    hint = "分钟"; setText((values["minutes"] ?: 60).toString()) }
                box.addView(enabled); box.addView(minutes)
                builder.setTitle("定时关闭").setView(box).setNegativeButton("取消", null).setPositiveButton("保存") { _, _ ->
                    answer(mapOf("enabled" to enabled.isChecked, "minutes" to (minutes.text.toString().toIntOrNull() ?: 60).coerceIn(1, 1440))) }
            }
            "autoExit" -> builder.setTitle("定时关闭").setMessage("播放时间已到，是否关闭直播间？")
                .setPositiveButton("关闭直播间") { _, _ -> answer("closeLive") }
                .setNegativeButton("继续播放") { _, _ -> answer("delay") }
                .setNeutralButton("退出应用") { _, _ -> answer("exitApplication") }.setCancelable(false)
            "quality" -> { video.showQuality(); answer(null); return }
            "line" -> { video.showLines(); answer(null); return }
            "metrics" -> { video.showMetrics(); answer(null); return }
            else -> { video.showSettings(); answer(null); return }
        }
        val popup = builder.create()
        dialog = popup
        popup.setOnDismissListener { answer(null); if (dialog === popup) dialog = null }
        popup.show()
    }

    private fun showRooms(initial: String) {
        val box = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
        val roomTabs = LinearLayout(activity)
        val roomList = ListView(activity)
        val locked = Switch(activity).apply {
            text = "锁定列表（切房后保持打开）"
            isChecked = data["roomListLocked"] != false
            setOnCheckedChangeListener { _, checked -> onAction("roomListLocked", checked) }
        }
        box.addView(roomTabs, LinearLayout.LayoutParams(-1, dp(48)))
        box.addView(locked, LinearLayout.LayoutParams(-1, dp(44)))
        box.addView(roomList, LinearLayout.LayoutParams(-1, (height - dp(220)).coerceIn(dp(80), dp(360))))
        var targets: List<Map<*, *>> = emptyList()
        var selectedTab = initial
        fun load(tabName: String) {
            selectedTab = tabName
            targets = (data[if (tabName == "历史") "history" else "follows"] as? List<*>)?.filterIsInstance<Map<*, *>>() ?: emptyList()
            roomList.adapter = ArrayAdapter(activity, android.R.layout.simple_list_item_1,
                targets.map { "${it["userName"] ?: ""} · ${it["siteName"] ?: ""} ${it["status"] ?: ""}" })
        }
        for (name in listOf("关注", "历史")) roomTabs.addView(actionButton("rooms", name) { load(name) }, LinearLayout.LayoutParams(0, -1, 1f))
        roomList.setOnItemClickListener { _, _, index, _ -> targets.getOrNull(index)?.let { onAction("openRoom", it); if (!locked.isChecked) dialog?.dismiss() } }
        load(initial)
        dialog?.dismiss()
        val refresh = { load(selectedTab) }
        refreshRoomDialog = refresh
        val popup = AlertDialog.Builder(activity).setTitle("关注 / 历史").setView(box).setNegativeButton("关闭", null).create()
        dialog = popup
        popup.setOnDismissListener {
            if (dialog === popup) dialog = null
            if (refreshRoomDialog === refresh) refreshRoomDialog = null
        }
        popup.show()
        onAction("reloadFollow", null)
    }

    fun dispose() {
        refreshRoomDialog = null
        dialog?.dismiss(); dialog = null
        list.adapter = null
        chat.clear(); rows = emptyList()
        NativeAvatar.clear(avatar)
        video.dispose()
    }
}
