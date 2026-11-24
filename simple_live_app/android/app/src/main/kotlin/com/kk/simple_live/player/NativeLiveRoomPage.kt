package com.kk.simple_live.player

import android.app.Activity
import android.graphics.Color
import android.graphics.Typeface
import android.text.SpannableStringBuilder
import android.text.TextUtils
import android.text.style.ForegroundColorSpan
import android.view.*
import android.widget.*
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.media3.exoplayer.ExoPlayer
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

/** 播放页仍是完整 Android View；视觉与交互遵循重构前的 Flutter 页面。 */
class NativeLiveRoomPage(private val activity: Activity, player: ExoPlayer,
    private val onAction: (String, Any?) -> Unit) : FrameLayout(activity) {
    private var data: Map<*, *> = emptyMap<Any, Any>()
    private var style = NativePlayerStyle(activity, data)
    val video = NativePlayerView(activity, player, onAction)
    var fullscreen = false; private set
    private val header = LinearLayout(activity)
    private val title = TextView(activity)
    private val back = NativeIcons.button(activity, "back", "返回") { onAction("back", null) }
    private val menu = NativeIcons.button(activity, "more", "更多") { showPanel("more") }
    private val profile = LinearLayout(activity)
    private val avatar = ImageView(activity)
    private val user = TextView(activity)
    private val siteName = TextView(activity)
    private val siteLogo = ImageView(activity)
    private val popularity = TextView(activity)
    private val fire = ImageView(activity)
    private val tabs = LinearLayout(activity)
    private val pager = NativePlayerPager(activity)
    private val bottom = LinearLayout(activity)
    private val follow = NativePlayerAction(activity)
    private val latest = TextView(activity)
    private val chat = ArrayList<Map<*, *>>()
    private val lists = LinkedHashMap<String, ListView>()
    private val adapters = LinkedHashMap<String, RoomAdapter>()
    private val positions = HashMap<String, Pair<Int, Int>>()
    private var tabNames: List<String> = emptyList()
    private var activeTab = "聊天"
    private var autoScroll = true
    private var sheet: NativePlayerSheet? = null
    private var sheetResult: MethodChannel.Result? = null
    private var sheetRefresh: (() -> Unit)? = null
    private var roomPager: NativePlayerPager? = null
    private var disposed = false
    private var safeLeft = 0; private var safeTop = 0; private var safeRight = 0; private var safeBottom = 0

    init {
        isFocusableInTouchMode = true
        header.gravity = Gravity.CENTER_VERTICAL
        header.addView(back, LinearLayout.LayoutParams(dp(48), -1))
        title.gravity = Gravity.CENTER; title.textSize = 16f; title.maxLines = 1; title.ellipsize = TextUtils.TruncateAt.END
        header.addView(title, LinearLayout.LayoutParams(0, -1, 1f))
        header.addView(menu, LinearLayout.LayoutParams(dp(48), -1)); addView(header)
        addView(video); video.onShowPanel = { showPanel(it) }
        profile.gravity = Gravity.CENTER_VERTICAL; profile.setPadding(dp(12), dp(8), dp(12), dp(8))
        avatar.scaleType = ImageView.ScaleType.CENTER_CROP; avatar.clipToOutline = true
        avatar.background = NativeIcons.background(0x199E9E9E, dp(24).toFloat())
        profile.addView(avatar, LinearLayout.LayoutParams(dp(48), dp(48)))
        val names = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(12), 0, dp(8), 0) }
        user.textSize = 16f; user.maxLines = 1; user.ellipsize = TextUtils.TruncateAt.END
        names.addView(user, LinearLayout.LayoutParams(-1, dp(24)))
        val site = LinearLayout(activity).apply { gravity = Gravity.CENTER_VERTICAL }
        site.addView(siteLogo, LinearLayout.LayoutParams(dp(20), dp(20)).apply { rightMargin = dp(4) })
        siteName.textSize = 12f; siteName.setTextColor(Color.GRAY); site.addView(siteName)
        names.addView(site, LinearLayout.LayoutParams(-1, dp(20)))
        profile.addView(names, LinearLayout.LayoutParams(0, -2, 1f))
        fire.setImageDrawable(NativeIcons.drawable("fire", 0xFFFF9800.toInt()))
        profile.addView(fire, LinearLayout.LayoutParams(dp(20), dp(20)).apply { rightMargin = dp(4) })
        popularity.textSize = 14f; profile.addView(popularity); addView(profile)
        addView(tabs); addView(pager)
        pager.onSelected = { index -> tabNames.getOrNull(index)?.let { activeTab = it; bindVisibleList(); paintTabs() } }
        bottom.gravity = Gravity.CENTER_VERTICAL
        for (button in listOf(follow, action("refresh", "刷新") { onAction("refresh", null) }, action("share", "分享") { onAction("share", null) })) bottom.addView(button, LinearLayout.LayoutParams(0, -1, 1f))
        style.click(follow) { if (data["followed"] == true) confirmUnfollow() else onAction("follow", null) }; addView(bottom)
        latest.text = "最新消息"; latest.textSize = 12f; latest.gravity = Gravity.CENTER; latest.visibility = GONE
        latest.setOnClickListener { autoScroll = true; scrollLatest() }; addView(latest)
        ViewCompat.setOnApplyWindowInsetsListener(this) { _, insets ->
            val cutout = insets.getInsets(WindowInsetsCompat.Type.displayCutout()); val system = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            safeLeft = maxOf(cutout.left, if (fullscreen) 0 else system.left); safeTop = maxOf(cutout.top, if (fullscreen) 0 else system.top)
            safeRight = maxOf(cutout.right, if (fullscreen) 0 else system.right); safeBottom = maxOf(cutout.bottom, if (fullscreen) 0 else system.bottom)
            video.setSafeInsets(cutout.left, cutout.top, cutout.right, cutout.bottom); requestLayout(); insets
        }
    }
    private fun dp(value: Int) = (value * resources.displayMetrics.density).roundToInt()
    private fun action(icon: String, label: String, clicked: () -> Unit) = NativePlayerAction(activity).apply {
        bind(icon, label, style.primary)
        style.click(this, clicked)
    }
    override fun onMeasure(w: Int, h: Int) {
        val width = MeasureSpec.getSize(w); val height = MeasureSpec.getSize(h); setMeasuredDimension(width, height)
        fun measure(view: View, vw: Int, vh: Int) = view.measure(MeasureSpec.makeMeasureSpec(vw.coerceAtLeast(0), MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(vh.coerceAtLeast(0), MeasureSpec.EXACTLY))
        if (fullscreen) measure(video, width, height) else {
            val availableWidth = width - safeLeft - safeRight; val availableHeight = (height - safeTop - safeBottom).coerceAtLeast(0)
            val ratio = (data["aspectRatio"] as? Number)?.toDouble()?.takeIf { it.isFinite() && it in .2..4.0 } ?: 16.0 / 9
            val videoHeight = (availableWidth / ratio).roundToInt().coerceAtMost((availableHeight * .44).roundToInt())
            measure(header, availableWidth, dp(56)); measure(video, availableWidth, videoHeight); measure(profile, availableWidth, dp(65))
            measure(tabs, availableWidth, dp(48)); measure(bottom, availableWidth, dp(48)); measure(pager, availableWidth, availableHeight - videoHeight - dp(217)); measure(latest, dp(84), dp(32))
        }
        sheet?.let { measure(it, width, height) }
    }
    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        if (fullscreen) video.layout(0, 0, width, height) else {
            var y = safeTop
            for (view in listOf(header, video, profile, tabs, pager, bottom)) { view.layout(safeLeft, y, width - safeRight, y + view.measuredHeight); y += view.measuredHeight }
            latest.layout(width - safeRight - dp(100), pager.bottom - dp(48), width - safeRight - dp(16), pager.bottom - dp(16))
        }
        sheet?.layout(0, 0, width, height)
    }
    fun setFullscreen(value: Boolean) {
        if (fullscreen == value) return
        savePositions(); fullscreen = value; video.setFullscreen(value)
        for (view in listOf(header, profile, tabs, pager, bottom)) view.visibility = if (value) GONE else VISIBLE
        latest.visibility = GONE; bindVisibleList(); requestLayout(); ViewCompat.requestApplyInsets(this)
    }
    fun update(values: Map<*, *>) {
        val changedRoom = data["roomKey"] != values["roomKey"]
        val listChanged = listOf("title", "userName", "roomKey", "chatSize", "chatGap", "chatBubble", "superChatEnabled", "follows", "history", "superChats", "dark", "primaryColor", "autoExitEnabled", "autoExitCountdown").any { data[it] != values[it] }
        data = values; style = NativePlayerStyle(activity, data)
        if (changedRoom) { chat.clear(); positions.clear(); autoScroll = true }
        setBackgroundColor(style.background); header.setBackgroundColor(style.background); profile.setBackgroundColor(style.surface)
        title.text = values["title"]?.toString() ?: "直播间"; title.setTextColor(style.foreground)
        back.setImageDrawable(NativeIcons.drawable("back", style.foreground)); menu.setImageDrawable(NativeIcons.drawable("more", style.foreground))
        user.text = values["userName"]?.toString() ?: "直播间"; user.setTextColor(style.foreground)
        siteName.text = values["siteName"]?.toString() ?: ""; loadLogo(siteLogo, values["siteLogo"]?.toString() ?: "")
        popularity.text = values["popularity"]?.toString() ?: "0"; popularity.setTextColor(style.foreground)
        NativeAvatar.load(avatar, values["avatar"]?.toString() ?: "")
        for (i in 0 until bottom.childCount) (bottom.getChildAt(i) as NativePlayerAction).setColor(style.primary)
        follow.bind(if (values["followed"] == true) "followFilled" else "follow",
            if (values["followed"] == true) "取消关注" else "关注", style.primary)
        bottom.setBackgroundColor(style.surface); latest.setTextColor(style.primary); latest.background = NativeIcons.background(style.surface, dp(16).toFloat())
        video.update(values)
        val names = listOf("聊天") + (if (values["hasSC"] == true) listOf("SC") else emptyList()) + listOf("关注", "设置")
        if (names != tabNames) buildTabs(names)
        if (!fullscreen && listChanged) { adapters[activeTab]?.refresh(); paintTabs() }
        if (listChanged) sheetRefresh?.invoke(); requestLayout()
    }
    private fun buildTabs(names: List<String>) {
        pager.dispose(); pager.removeAllViews(); tabs.removeAllViews(); lists.clear(); adapters.clear(); tabNames = names
        if (activeTab !in names) activeTab = "聊天"
        for (name in names) {
            val cell = FrameLayout(activity); cell.addView(style.text(name).apply { gravity = Gravity.CENTER }, FrameLayout.LayoutParams(-1, -1))
            cell.addView(View(activity), FrameLayout.LayoutParams(-1, dp(1), Gravity.BOTTOM)); style.click(cell) { savePositions(); pager.select(names.indexOf(name)) }
            tabs.addView(cell, LinearLayout.LayoutParams(0, -1, 1f))
            val list = newList(); val adapter = RoomAdapter(name); lists[name] = list; adapters[name] = adapter
            if (name == "聊天") list.setOnScrollListener(object : AbsListView.OnScrollListener {
                override fun onScrollStateChanged(v: AbsListView, state: Int) { if (state != 0) autoScroll = false }
                override fun onScroll(v: AbsListView, first: Int, visible: Int, total: Int) {
                    if (total > 0 && first + visible >= total) autoScroll = true
                    latest.visibility = if (!fullscreen && activeTab == "聊天" && !autoScroll) VISIBLE else GONE
                }
            })
            list.setOnItemClickListener { _, _, index, _ -> adapter.items.getOrNull(index)?.let { item ->
                if (name == "关注") onAction("openRoom", item) else if (name == "设置") settingsAction(item["action"].toString())
            } }
            list.setOnItemLongClickListener { _, _, index, _ -> if (name == "聊天" && index > 0) {
                adapter.items.getOrNull(index)?.get("message")?.toString()?.let { text -> showMessageActions(text) }; true
            } else false }
            pager.addView(list)
        }
        pager.select(names.indexOf(activeTab), false); paintTabs()
    }
    private fun paintTabs() {
        tabs.setBackgroundColor(style.surface)
        for (i in tabNames.indices) {
            val cell = tabs.getChildAt(i) as FrameLayout; val selected = tabNames[i] == activeTab; val label = cell.getChildAt(0) as TextView
            val count = (data["superChats"] as? List<*>)?.size ?: 0
            label.text = if (tabNames[i] == "SC" && count > 0) "SC($count)" else tabNames[i]
            label.setTextColor(if (selected) style.primary else style.foreground); cell.getChildAt(1).setBackgroundColor(if (selected) style.primary else style.divider)
        }
    }
    private fun newList() = ListView(activity).apply { divider = null; isVerticalScrollBarEnabled = false; isHorizontalScrollBarEnabled = false; overScrollMode = OVER_SCROLL_NEVER; clipToPadding = false }
    private fun savePositions() { for ((name, list) in lists) if (list.adapter != null) positions[name] = Pair(list.firstVisiblePosition, list.getChildAt(0)?.top ?: 0) }
    private fun bindVisibleList() {
        for ((name, list) in lists) {
            if (fullscreen) { if (list.adapter != null) positions[name] = Pair(list.firstVisiblePosition, list.getChildAt(0)?.top ?: 0); list.adapter = null }
            else { if (name == activeTab || list.adapter == null) adapters[name]?.refresh(); if (list.adapter == null) { list.adapter = adapters[name]; positions[name]?.let { list.setSelectionFromTop(it.first, it.second) } } }
        }
        if (activeTab != "聊天") latest.visibility = GONE
        if (!fullscreen && activeTab == "聊天" && autoScroll) scrollLatest()
    }
    fun addMessages(items: List<*>) {
        items.filterIsInstance<Map<*, *>>().forEach { chat.add(it) }; if (chat.size > 200) chat.subList(0, chat.size - 200).clear()
        if (!fullscreen && activeTab == "聊天") { adapters["聊天"]?.refresh(); if (autoScroll) scrollLatest() }
    }
    fun clearMessages() { chat.clear(); if (!fullscreen) adapters["聊天"]?.refresh() }
    private fun scrollLatest() { latest.visibility = GONE; lists["聊天"]?.post { if (!fullscreen && activeTab == "聊天" && autoScroll) lists["聊天"]?.setSelection((adapters["聊天"]?.count ?: 1) - 1) } }
    private fun maps(key: String) = (data[key] as? List<*>)?.filterIsInstance<Map<*, *>>() ?: emptyList()
    private fun loadLogo(view: ImageView, path: String) {
        if (view.tag == path) return
        view.tag = path; view.setImageBitmap(runCatching { activity.assets.open("flutter_assets/$path").use { android.graphics.BitmapFactory.decodeStream(it) } }.getOrNull())
    }
    private inner class RoomAdapter(val mode: String) : BaseAdapter() {
        var items: List<Map<*, *>> = emptyList()
        fun refresh() {
            items = when (mode) {
                "聊天" -> listOf(mapOf("title" to (data["title"] ?: "直播间"))) + chat
                "SC" -> maps("superChats"); "关注" -> maps("follows"); "历史" -> maps("history")
                else -> (if (data["autoExitEnabled"] == true) listOf(mapOf("action" to "countdown")) else emptyList()) + listOf(
                    mapOf("text" to "聊天区", "action" to "heading"), mapOf("action" to "chatGroup"),
                    mapOf("text" to "更多设置", "action" to "heading"), mapOf("action" to "moreGroup"))
            }; notifyDataSetChanged()
        }
        override fun getCount() = items.size
        override fun getItem(position: Int) = items[position]
        override fun getItemId(position: Int) = position.toLong()
        override fun getView(position: Int, recycled: View?, parent: ViewGroup): View {
            val item = items[position]
            if (mode == "关注" || mode == "历史") return roomRow(item, recycled)
            if (mode == "设置") return settingsItem(item)
            val size = (data["chatSize"] as? Number)?.toFloat() ?: 14f; val text = (recycled as? TextView) ?: style.text("")
            text.setTextColor(style.foreground); text.textSize = size; text.setTypeface(null, Typeface.NORMAL)
            val gap = (data["chatGap"] as? Number)?.toInt() ?: 4
            text.setPadding(dp(12), dp(gap), dp(12), dp(gap)); text.background = null
            if (mode == "聊天" && position == 0) {
                return LinearLayout(activity).apply {
                    orientation = LinearLayout.VERTICAL; setPadding(dp(12), dp(12), dp(12), 0)
                    addView(style.text(data["title"]?.toString() ?: "直播间", size + 2).apply { setTypeface(null, Typeface.BOLD) })
                    val info = LinearLayout(activity).apply { gravity = Gravity.CENTER_VERTICAL; setPadding(0, dp(4), 0, dp(8)) }
                    info.addView(ImageView(activity).apply { loadLogo(this, data["siteLogo"]?.toString() ?: "") }, LinearLayout.LayoutParams(dp(14), dp(14)).apply { rightMargin = dp(4) })
                    info.addView(style.text("${data["userName"] ?: ""} · ${data["siteName"] ?: ""}", size - 2, Color.GRAY))
                    addView(info); addView(style.line().apply { (layoutParams as LinearLayout.LayoutParams).bottomMargin = dp(8) })
                }
            } else if (mode == "SC") {
                text.text = item["text"]?.toString() ?: ""; text.setPadding(dp(12), dp(12), dp(12), dp(12))
                text.background = NativeIcons.background((item["color"] as? Number)?.toInt() ?: style.surface, dp(8).toFloat())
            } else {
                val name = item["userName"]?.toString() ?: ""; val prefix = if (name.isEmpty() || name == "LiveSysMessage") "" else "$name："
                text.text = SpannableStringBuilder(prefix + (item["message"] ?: "")).apply { if (prefix.isNotEmpty()) setSpan(ForegroundColorSpan(Color.GRAY), 0, prefix.length, 0) }
                if (name == "LiveSysMessage") text.setTextColor(Color.GRAY)
                if (data["chatBubble"] == true && name != "LiveSysMessage") text.background = NativeIcons.background(0x1960788B, dp(12).toFloat())
            }; return text
        }
    }
    private fun roomRow(item: Map<*, *>, recycled: View?): View {
        val row = (recycled as? LinearLayout)?.takeIf { it.tag == "room" } ?: LinearLayout(activity).apply {
            tag = "room"; gravity = Gravity.CENTER_VERTICAL; setPadding(dp(16), dp(12), dp(12), dp(12))
            addView(ImageView(activity).apply { scaleType = ImageView.ScaleType.CENTER_CROP; background = NativeIcons.background(style.divider, dp(24).toFloat()); clipToOutline = true }, LinearLayout.LayoutParams(dp(48), dp(48)))
            val labels = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(16), 0, 0, 0) }
            val heading = LinearLayout(activity).apply { gravity = Gravity.CENTER_VERTICAL }
            heading.addView(style.text("", 16f), LinearLayout.LayoutParams(-2, -2)); heading.addView(style.text("", 12f))
            labels.addView(heading)
            val info = LinearLayout(activity).apply { gravity = Gravity.CENTER_VERTICAL; setPadding(0, dp(4), 0, 0) }
            info.addView(ImageView(activity), LinearLayout.LayoutParams(dp(20), dp(20)).apply { rightMargin = dp(4) })
            info.addView(style.text("", 12f, Color.GRAY)); info.addView(style.text("", 12f, Color.GRAY), LinearLayout.LayoutParams(0, -2, 1f).apply { leftMargin = dp(8) })
            labels.addView(info); addView(labels, LinearLayout.LayoutParams(0, -2, 1f))
            addView(ImageView(activity), LinearLayout.LayoutParams(dp(24), dp(24)))
        }
        NativeAvatar.load(row.getChildAt(0) as ImageView, item["avatar"]?.toString() ?: "")
        val playing = item["roomId"] == data["roomId"] && item["siteId"] == data["siteId"]
        val labels = row.getChildAt(1) as LinearLayout; val heading = labels.getChildAt(0) as LinearLayout
        (heading.getChildAt(0) as TextView).apply { text = item["userName"]?.toString() ?: ""; setTextColor(style.foreground); maxLines = 1; maxWidth = dp(if (fullscreen) 200 else 160); ellipsize = TextUtils.TruncateAt.END }
        (heading.getChildAt(1) as TextView).apply {
            visibility = if (!fullscreen && item["status"] != null) VISIBLE else GONE
            text = SpannableStringBuilder("  ● ${item["status"]}").apply { setSpan(ForegroundColorSpan(if (item["status"] == "直播中") 0xFF4CAF50.toInt() else Color.GRAY), 2, 3, 0) }; setTextColor(style.foreground)
        }
        val info = labels.getChildAt(1) as LinearLayout
        loadLogo(info.getChildAt(0) as ImageView, item["siteLogo"]?.toString() ?: "")
        (info.getChildAt(1) as TextView).apply { text = item["siteName"]?.toString() ?: ""; setTextColor(Color.GRAY) }
        val start = item["liveStartTime"]?.toString()?.toLongOrNull() ?: 0L
        val elapsed = if (start > 0) ((System.currentTimeMillis() / 1000 - start) / 60).coerceAtLeast(0) else -1L
        (info.getChildAt(2) as TextView).apply {
            text = if (playing) "正在观看" else if (elapsed < 0) "" else if (elapsed == 0L) "开播不足1分钟" else "开播了${if (elapsed >= 60) "${elapsed / 60}小时" else ""}${if (elapsed % 60 > 0) "${elapsed % 60}分钟" else ""}"
            setTextColor(if (playing) style.primary else Color.GRAY); setTypeface(null, if (playing) Typeface.BOLD else Typeface.NORMAL)
        }
        (row.getChildAt(2) as ImageView).apply { visibility = if (playing) VISIBLE else GONE; setImageDrawable(NativeIcons.drawable("play", style.foreground)) }
        return row
    }
    private fun settingsItem(item: Map<*, *>): View {
        val action = item["action"]?.toString() ?: ""
        if (action == "heading") return style.text(item["text"].toString(), 14f).apply { setPadding(dp(24), dp(16), dp(12), dp(12)); setTypeface(null, Typeface.BOLD) }
        if (action == "countdown") {
            val seconds = (data["autoExitCountdown"] as? Number)?.toInt() ?: 0
            return style.text("${seconds / 60}分钟${seconds % 60}秒后自动关闭", 16f).apply { setPadding(dp(24), dp(8), dp(12), dp(8)); val icon = NativeIcons.drawable("timer", style.foreground); icon.setBounds(0, 0, dp(24), dp(24)); setCompoundDrawables(icon, null, null, null); compoundDrawablePadding = dp(12) }
        }
        val entries = if (action == "chatGroup") listOf("文字大小" to "chatSize", "上下间隔" to "chatGap", "气泡样式" to "chatBubble", "播放器中显示SC" to "showSC")
            else listOf("关键词屏蔽" to "shieldSettings", "弹幕设置" to "danmakuSettings", "定时关闭" to "autoExitSettings", "画面尺寸" to "playerSettings")
        val wrapper = FrameLayout(activity).apply { setPadding(dp(12), 0, dp(12), 0) }
        val card = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL; clipToOutline = true; background = NativeIcons.background(if (style.dark) 0x329E9E9E else 0xB3FFFFFF.toInt(), dp(8).toFloat()).apply { setStroke(dp(1), style.divider) } }
        for ((index, entry) in entries.withIndex()) {
            val row = settingRow(mapOf("text" to entry.first, "action" to entry.second)); style.click(row) { settingsAction(entry.second) }; card.addView(row)
            if (index < entries.lastIndex) card.addView(style.line(), LinearLayout.LayoutParams(-1, dp(1)).apply { leftMargin = dp(16); rightMargin = dp(16) })
        }
        wrapper.addView(card); return wrapper
    }
    private fun settingRow(item: Map<*, *>): View {
        val name = item["action"]?.toString() ?: ""
        if (name == "heading") return style.text(item["text"].toString(), 14f).apply { setPadding(dp(24), dp(20), dp(12), dp(12)); setTypeface(null, Typeface.BOLD) }
        val row = LinearLayout(activity).apply { gravity = Gravity.CENTER_VERTICAL; setPadding(dp(16), 0, dp(12), 0); minimumHeight = dp(56) }
        row.addView(style.text(item["text"].toString(), 16f), LinearLayout.LayoutParams(0, -2, 1f))
        if (name == "chatBubble" || name == "showSC") {
            val toggle = NativePlayerSwitch(activity, style).apply { isChecked = data[if (name == "showSC") "superChatEnabled" else "chatBubble"] == true; contentDescription = item["text"].toString() }
            toggle.setOnCheckedChangeListener { _, checked -> onAction(if (name == "showSC") "showSC" else "chatBubble", checked) }; row.addView(toggle)
        } else if (name == "chatSize" || name == "chatGap") {
            val value = (data[name] as? Number)?.toInt() ?: if (name == "chatSize") 14 else 4
            val number = LinearLayout(activity).apply { gravity = Gravity.CENTER; background = NativeIcons.background(0x199E9E9E, dp(24).toFloat()) }
            number.addView(action("", "−") { onAction(name, (value - 1).coerceAtLeast(if (name == "chatSize") 8 else 0)) }, LinearLayout.LayoutParams(dp(40), dp(44)))
            number.addView(style.text(value.toString(), 14f, Color.GRAY).apply { gravity = Gravity.CENTER }, LinearLayout.LayoutParams(dp(32), dp(44)))
            number.addView(action("", "+") { onAction(name, (value + 1).coerceAtMost(if (name == "chatSize") 36 else 12)) }, LinearLayout.LayoutParams(dp(40), dp(36)))
            row.addView(number, LinearLayout.LayoutParams(-2, dp(36)))
        } else row.addView(ImageView(activity).apply { setImageDrawable(NativeIcons.drawable("chevron", Color.GRAY)) }, LinearLayout.LayoutParams(dp(24), dp(24)))
        return row
    }
    private fun settingsAction(name: String) { when (name) { "heading", "chatGroup", "moreGroup", "countdown", "chatSize", "chatGap", "chatBubble", "showSC" -> Unit; "playerSettings", "danmakuSettings" -> showPanel(name); else -> onAction(name, null) } }
    private fun beginSheet(title: String, side: Boolean = fullscreen && width > height, panelWidth: Int = 320,
        heightPx: Int = ((height - safeTop) * .56).toInt(), header: Boolean = true): NativePlayerSheet {
        clearSheet()
        lateinit var popup: NativePlayerSheet
        popup = NativePlayerSheet(activity, style, side, panelWidth, heightPx) { if (sheet === popup) clearSheet() }
        sheet = popup; popup.panel.setPadding(0, if (side) safeTop else 0, if (side) safeRight else 0, safeBottom)
        if (header) popup.header(title)
        addView(popup, LayoutParams(-1, -1)); requestLayout(); popup.enter(); return popup
    }
    private fun clearSheet() {
        sheetRefresh = null; roomPager?.dispose(); roomPager = null; sheet?.dispose(); sheet = null
        val result = sheetResult; sheetResult = null; result?.success(null)
    }
    fun dismissOverlay(): Boolean { val popup = sheet ?: return false; popup.dismiss(); return true }
    private fun answer(value: Any?) { val result = sheetResult; sheetResult = null; result?.success(value); sheet?.dismiss() }
    fun showDialog(kind: String, values: Map<*, *>, result: MethodChannel.Result) {
        when (kind) {
            "shield", "autoExitSettings", "autoExit" -> {
                val popup = beginSheet(if (kind == "shield") "关键词屏蔽" else "定时关闭", side = false, heightPx = dp(if (kind == "shield") 340 else 280) + safeBottom)
                sheetResult = result
                if (kind == "shield") {
                    val input = EditText(activity).apply { setText((values["keywords"] as? List<*>)?.joinToString("\n") ?: ""); hint = "每行一个关键词，正则使用 /表达式/"; setTextColor(style.foreground); setHintTextColor(Color.GRAY); textSize = 14f; gravity = Gravity.TOP; setPadding(dp(16), dp(12), dp(16), dp(12)) }
                    popup.panel.addView(input, LinearLayout.LayoutParams(-1, 0, 1f)); popup.panel.addView(action("", "保存") { answer(input.text.toString().lines().map { it.trim() }.filter { it.isNotEmpty() }) }, LinearLayout.LayoutParams(-1, dp(48)))
                } else if (kind == "autoExitSettings") {
                    val enabled = Switch(activity).apply { text = "启用定时关闭"; isChecked = values["enabled"] == true; setTextColor(style.foreground); setPadding(dp(16), 0, dp(16), 0) }
                    val minutes = EditText(activity).apply { inputType = android.text.InputType.TYPE_CLASS_NUMBER; setText((values["minutes"] ?: 60).toString()); hint = "分钟"; setTextColor(style.foreground); setPadding(dp(16), 0, dp(16), 0) }
                    popup.panel.addView(enabled, LinearLayout.LayoutParams(-1, dp(52))); popup.panel.addView(minutes, LinearLayout.LayoutParams(-1, dp(48)))
                    popup.panel.addView(action("", "保存") { answer(mapOf("enabled" to enabled.isChecked, "minutes" to (minutes.text.toString().toIntOrNull() ?: 60).coerceIn(1, 1440))) }, LinearLayout.LayoutParams(-1, dp(48)))
                } else {
                    popup.panel.addView(style.text("播放时间已到，是否关闭直播间？").apply { setPadding(dp(16), dp(12), dp(16), dp(12)) })
                    for ((label, value) in listOf("继续播放" to "delay", "关闭直播间" to "closeLive", "退出应用" to "exitApplication")) popup.panel.addView(action("", label) { answer(value) }, LinearLayout.LayoutParams(-1, dp(44)))
                }
            }
            else -> { showPanel(kind); result.success(null) }
        }
    }
    private fun choose(title: String, items: List<String>, selected: Int, clicked: (Int) -> Unit) {
        val popup = beginSheet(title, side = false, heightPx = (dp(56 + items.size.coerceIn(1, 4) * 48) + safeBottom).coerceAtMost((height * .85).toInt()))
        val box = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
        if (items.isEmpty()) box.addView(style.text("暂无$title，请刷新直播间").apply { setPadding(dp(16), dp(16), dp(16), dp(16)) })
        for ((index, label) in items.withIndex()) {
            val row = LinearLayout(activity).apply { gravity = Gravity.CENTER_VERTICAL; setPadding(dp(32), 0, dp(24), 0); isSelected = index == selected }
            row.addView(ImageView(activity).apply { setImageDrawable(NativeIcons.drawable(if (index == selected) "radioChecked" else "radioUnchecked", if (index == selected) style.primary else style.foreground)) }, LinearLayout.LayoutParams(dp(24), dp(24)).apply { rightMargin = dp(24) })
            row.addView(style.text(label, 16f), LinearLayout.LayoutParams(0, -2, 1f))
            row.accessibilityDelegate = object : View.AccessibilityDelegate() {
                override fun onInitializeAccessibilityNodeInfo(host: View, info: android.view.accessibility.AccessibilityNodeInfo) { super.onInitializeAccessibilityNodeInfo(host, info); info.className = "android.widget.RadioButton"; info.isCheckable = true; info.isChecked = index == selected; info.text = label }
            }
            style.click(row) { clicked(index); popup.dismiss() }; box.addView(row, LinearLayout.LayoutParams(-1, dp(48)))
        }
        popup.panel.addView(ScrollView(activity).apply { isVerticalScrollBarEnabled = false; addView(box) }, LinearLayout.LayoutParams(-1, 0, 1f))
    }
    fun showPanel(kind: String) { when (kind) {
        "rooms" -> showRooms(); "more" -> showMore()
        "quality" -> choose("切换清晰度", (data["qualities"] as? List<*>)?.map { it.toString() } ?: emptyList(), (data["qualityIndex"] as? Number)?.toInt() ?: -1) { onAction("quality", it) }
        "line" -> choose("切换线路", List(((data["lineCount"] as? Number)?.toInt() ?: 0).coerceIn(0, 100)) { "线路 ${it + 1}" }, (data["lineIndex"] as? Number)?.toInt() ?: -1) { onAction("line", it) }
        "metrics" -> video.showMetrics()
        "settings", "playerSettings" -> choose("画面尺寸", listOf("适应", "拉伸", "铺满", "16:9", "4:3"), (data["scaleMode"] as? Number)?.toInt() ?: 0) { onAction("scale", it) }
        "danmakuSettings" -> showDanmakuSettings()
    } }
    private fun showDanmakuSettings() {
        val popup = beginSheet("弹幕设置"); val box = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
        val entries = listOf(Triple("字号", "fontSize", 12..32), Triple("字重", "fontWeight", 1..9), Triple("不透明度", "opacity", 1..10), Triple("显示区域", "area", 1..10), Triple("滚动时长", "duration", 5..15), Triple("顶部边距", "topMargin", 0..72), Triple("底部边距", "bottomMargin", 0..72))
        for ((label, key, range) in entries) {
            val percent = key == "opacity" || key == "area"; val value = (data[key] as? Number)?.toFloat() ?: range.first.toFloat()
            val header = LinearLayout(activity).apply { gravity = Gravity.CENTER_VERTICAL; setPadding(dp(16), dp(12), dp(16), 0) }
            header.addView(style.text(label, 16f), LinearLayout.LayoutParams(0, -2, 1f))
            val heading = style.text("${if (percent) (value * 100).roundToInt() else value.toInt()}${if (percent) "%" else ""}", 16f)
            header.addView(heading); box.addView(header)
            val slider = NativePlayerSlider(activity, style).apply { contentDescription = label; max = range.last - range.first; progress = ((if (percent) value * 10 else value) - range.first).roundToInt().coerceIn(0, max) }
            slider.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(s: SeekBar, p: Int, user: Boolean) { heading.text = "${if (percent) (p + range.first) * 10 else p + range.first}${if (percent) "%" else ""}" }
                override fun onStartTrackingTouch(s: SeekBar) = Unit
                override fun onStopTrackingTouch(s: SeekBar) { onAction(key, if (percent) (s.progress + range.first) / 10.0 else s.progress + range.first) }
            }); box.addView(slider, LinearLayout.LayoutParams(-1, dp(40)))
        }
        box.addView(action("settings", "关键词屏蔽") { onAction("shieldSettings", null) }, LinearLayout.LayoutParams(-1, dp(48)))
        popup.panel.addView(ScrollView(activity).apply { isVerticalScrollBarEnabled = false; addView(box) }, LinearLayout.LayoutParams(-1, 0, 1f))
    }
    private fun showMore() {
        val entries = mutableListOf(Triple("refresh", "刷新", "refresh"), Triple("quality", "清晰度", "quality"), Triple("line", "线路", "line"), Triple("aspect", "画面尺寸", "playerSettings"), Triple("camera", "截图", "screenshot"))
        if (data["floatingEnabled"] == true) entries.add(Triple("floating", "悬浮小窗", "floating"))
        entries.addAll(listOf(Triple("timer", "定时关闭", "autoExitSettings"), Triple("share", "分享直播间", "share"), Triple("link", "复制链接", "copyRoom"), Triple("openApp", "APP中打开", "openApp"), Triple("info", "播放信息", "metrics")))
        val columns = ((minOf(width, dp(600)) - dp(16)) / dp(76)).coerceAtLeast(2); val rows = (entries.size + columns - 1) / columns
        val popup = beginSheet("更多操作", side = false, heightPx = dp(56 + rows * 84 + 16) + safeBottom)
        val grid = GridLayout(activity).apply { columnCount = columns; setPadding(dp(8), 0, dp(8), dp(8)) }
        for ((icon, label, key) in entries) {
            val cell = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER }
            cell.addView(ImageView(activity).apply { setPadding(dp(12), dp(12), dp(12), dp(12)); setImageDrawable(NativeIcons.drawable(icon, style.foreground)); background = NativeIcons.background(0x199E9E9E, dp(12).toFloat()) }, LinearLayout.LayoutParams(dp(42), dp(42)))
            cell.addView(style.text(label, 12f).apply { gravity = Gravity.CENTER }, LinearLayout.LayoutParams(-1, dp(28)))
            style.click(cell) { popup.dismiss(); postDelayed({ if (disposed || sheet != null) return@postDelayed; if (key in listOf("quality", "line", "playerSettings", "metrics")) showPanel(key) else onAction(key, null) }, 210) }
            grid.addView(cell, GridLayout.LayoutParams().apply { width = 0; height = dp(84); columnSpec = GridLayout.spec(GridLayout.UNDEFINED, 1f) })
        }; popup.panel.addView(grid)
    }
    private fun showRooms() {
        val popup = beginSheet("关注 / 历史", panelWidth = 360 + (safeRight / resources.displayMetrics.density).roundToInt(), header = false)
        val headings = LinearLayout(activity).apply { gravity = Gravity.CENTER_VERTICAL; setPadding(dp(8), 0, 0, 0) }
        val pages = NativePlayerPager(activity); roomPager = pages; pages.onPanelDrag = popup::drag
        val followList = newList(); val historyList = newList(); val followAdapter = RoomAdapter("关注"); val historyAdapter = RoomAdapter("历史")
        followList.adapter = followAdapter; historyList.adapter = historyAdapter; pages.addView(followList); pages.addView(historyList)
        var locked = data["roomListLocked"] != false
        for ((index, label) in listOf("关注", "历史").withIndex()) headings.addView(action(if (index == 0) "followTab" else "history", label) { pages.select(index) }, LinearLayout.LayoutParams(0, dp(48), 1f))
        val lock = NativeIcons.button(activity, if (locked) "lock" else "unlock", "切房后保持面板") { locked = !locked; onAction("roomListLocked", locked); (headings.getChildAt(2) as ImageView).setImageDrawable(NativeIcons.drawable(if (locked) "lock" else "unlock", style.foreground)) }
        lock.setImageDrawable(NativeIcons.drawable(if (locked) "lock" else "unlock", style.foreground)); headings.addView(lock, LinearLayout.LayoutParams(dp(48), dp(48)))
        pages.onSelected = { selected -> for (i in 0..1) (headings.getChildAt(i) as NativePlayerAction).apply { setColor(if (i == selected) style.primary else Color.GRAY); setSelectedStyle(i == selected) } }
        popup.panel.addView(headings, LinearLayout.LayoutParams(-1, dp(48))); popup.panel.addView(style.line()); popup.panel.addView(pages, LinearLayout.LayoutParams(-1, 0, 1f))
        for ((list, adapter) in listOf(followList to followAdapter, historyList to historyAdapter)) list.setOnItemClickListener { _, _, i, _ -> adapter.items.getOrNull(i)?.let { onAction("openRoom", it); if (!locked) popup.dismiss() } }
        sheetRefresh = { followAdapter.refresh(); historyAdapter.refresh() }; sheetRefresh?.invoke(); pages.select(0, false)
    }
    private fun confirmUnfollow() {
        val popup = beginSheet("取消关注", side = false, heightPx = dp(164) + safeBottom)
        popup.panel.addView(style.text("确定要取消关注该主播吗？").apply { setPadding(dp(16), dp(12), dp(16), dp(12)) })
        popup.panel.addView(action("followFilled", "确定取消") { onAction("unfollow", null); popup.dismiss() }, LinearLayout.LayoutParams(-1, dp(48)))
    }
    private fun showMessageActions(text: String) { choose("弹幕操作", listOf("复制", "屏蔽该关键词"), -1) { onAction(if (it == 0) "copyMessage" else "addShield", text) } }
    fun dispose() { disposed = true; clearSheet(); pager.dispose(); lists.values.forEach { it.adapter = null }; chat.clear(); NativeAvatar.clear(avatar); video.dispose() }
}
