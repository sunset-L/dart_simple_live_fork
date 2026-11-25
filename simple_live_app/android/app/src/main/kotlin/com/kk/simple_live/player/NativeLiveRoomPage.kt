package com.kk.simple_live.player

import android.app.Activity
import android.graphics.Color
import android.graphics.Path
import android.graphics.RectF
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
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin

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
    private var tabPosition = 0f
    private val tabPaint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG)
    private val tabIndicatorPath = Path()
    private var tabMotionFrom = 0f
    private var tabMotionTarget = 0
    private var tabMotionStart = RectF()
    private var tabMotionColors = IntArray(0)
    private val tabs = object : LinearLayout(activity) {
        override fun dispatchDraw(canvas: android.graphics.Canvas) {
            super.dispatchDraw(canvas)
            if (childCount == 0) return
            tabPaint.color = style.tabDivider
            canvas.drawRect(0f, height - dp(1).toFloat(), width.toFloat(), height.toFloat(), tabPaint)
            val bounds = tabIndicatorBounds(tabPosition)
            bounds.top = height - dp(3).toFloat(); bounds.bottom = height.toFloat()
            tabPaint.color = style.primary
            val radius = dp(3).toFloat()
            tabIndicatorPath.reset()
            tabIndicatorPath.addRoundRect(bounds,
                floatArrayOf(radius, radius, radius, radius, 0f, 0f, 0f, 0f), Path.Direction.CW)
            canvas.drawPath(tabIndicatorPath, tabPaint)
        }
    }
    private val pager = NativePlayerPager(activity).apply {
        settleDurationMs = 300L
        // 首页 TabController.animateTo 默认 300ms / Curves.ease。
        settleInterpolator = android.view.animation.PathInterpolator(.25f, .1f, .25f, 1f)
    }
    private val bottom = LinearLayout(activity)
    /** 关注/刷新/分享只在方向切换结束、最终布局稳定后出现，不参与视频缩放。 */
    fun setPageActionsTransitioning(value: Boolean) {
        bottom.alpha = if (value) 0f else 1f
        bottom.isEnabled = !value
        // 动画遮罩只保留一幅视频。保留真实 TextureView/输出，但落位前不露出第二幅画面。
        video.alpha = if (value) 0f else 1f
    }
    private val follow = NativePlayerAction(activity)
    private val latest = TextView(activity)
    private val chat = ArrayList<Map<*, *>>()
    // 阅读旧消息时冻结显示列表，新消息另存为有界队列，避免截断旧消息挤动视口。
    private val unreadChat = ArrayList<Map<*, *>>()
    private var chatScrollState = AbsListView.OnScrollListener.SCROLL_STATE_IDLE
    private val lists = LinkedHashMap<String, ListView>()
    private val adapters = LinkedHashMap<String, RoomAdapter>()
    private val positions = HashMap<String, Pair<Int, Int>>()
    private var tabNames: List<String> = emptyList()
    private var activeTab = "聊天"
    private var autoScroll = true
    private var sheet: NativePlayerSheet? = null
    private var durationDialog: android.app.Dialog? = null
    private var autoExitDialog: NativeAutoExitDialog? = null
    private var autoExitResult: MethodChannel.Result? = null
    private var sheetResult: MethodChannel.Result? = null
    private var sheetRefresh: (() -> Unit)? = null
    private var roomPager: NativePlayerPager? = null
    private var followRefresh: NativePlayerRefresh? = null
    private var disposed = false
    private var safeLeft = 0; private var safeTop = 0; private var safeRight = 0; private var safeBottom = 0

    init {
        isFocusableInTouchMode = true
        // 挂载前就用宿主的真实系统栏边距，不能先绘制零边距再跳到正确位置。
        ViewCompat.getRootWindowInsets(activity.window.decorView)?.let { updateInsets(it) }
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
        pager.onScrollPosition = { position ->
            tabPosition = position; paintTabColors(); tabs.invalidate()
            // 拖动时让相邻页有内容，不能等松手选中后才绑定空列表。
            if (!fullscreen) for (index in listOf(kotlin.math.floor(position).toInt(), kotlin.math.ceil(position).toInt()).distinct()) {
                val name = tabNames.getOrNull(index) ?: continue
                val list = lists[name] ?: continue
                if (list.adapter == null) {
                    adapters[name]?.refresh(); list.adapter = adapters[name]
                    positions[name]?.let { list.setSelectionFromTop(it.first, it.second) }
                }
            }
        }
        pager.onSelected = { index ->
            // 连续点击从当前实际形状接续，跨两个 Tab 不在中间标签处突然收缩。
            tabMotionStart = tabIndicatorBounds(tabPosition)
            tabMotionColors = IntArray(tabs.childCount) {
                ((tabs.getChildAt(it) as FrameLayout).getChildAt(0) as TextView).currentTextColor
            }
            tabMotionFrom = tabPosition; tabMotionTarget = index
            tabNames.getOrNull(index)?.let { activeTab = it; bindVisibleList(); paintTabs() }
        }
        bottom.gravity = Gravity.CENTER_VERTICAL
        for (button in listOf(follow, action("refresh", "刷新") { onAction("refresh", null) }, action("share", "分享") { onAction("share", null) })) bottom.addView(button, LinearLayout.LayoutParams(0, -1, 1f))
        style.click(follow) { if (data["followed"] == true) confirmUnfollow() else onAction("follow", null) }; addView(bottom)
        latest.text = "最新消息"; latest.textSize = 12f; latest.gravity = Gravity.CENTER; latest.visibility = GONE
        latest.setOnClickListener { autoScroll = true; scrollLatest() }; addView(latest)
        ViewCompat.setOnApplyWindowInsetsListener(this) { _, insets -> updateInsets(insets); insets }
    }
    private fun updateInsets(insets: WindowInsetsCompat) {
        val cutout = insets.getInsets(WindowInsetsCompat.Type.displayCutout())
        // 使用最终系统栏占位，不跟随显示/隐藏动画的中间值重排底栏。
        val system = insets.getInsetsIgnoringVisibility(WindowInsetsCompat.Type.systemBars())
        val left = maxOf(cutout.left, if (fullscreen) 0 else system.left)
        val top = maxOf(cutout.top, if (fullscreen) 0 else system.top)
        val right = maxOf(cutout.right, if (fullscreen) 0 else system.right)
        val bottom = maxOf(cutout.bottom, if (fullscreen) 0 else system.bottom)
        val changed = safeLeft != left || safeTop != top || safeRight != right || safeBottom != bottom
        safeLeft = left; safeTop = top; safeRight = right; safeBottom = bottom
        video.setSafeInsets(cutout.left, cutout.top, cutout.right, cutout.bottom)
        if (changed) requestLayout()
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
            measure(tabs, availableWidth, dp(48)); measure(bottom, availableWidth, dp(48)); measure(pager, availableWidth, availableHeight - videoHeight - dp(217)); measure(latest, dp(112), dp(36))
        }
        sheet?.let { measure(it, width, height) }
    }
    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        if (fullscreen) video.layout(0, 0, width, height) else {
            var y = safeTop
            for (view in listOf(header, video, profile, tabs)) { view.layout(safeLeft, y, width - safeRight, y + view.measuredHeight); y += view.measuredHeight }
            // 底部操作栏锚定页面安全区底部，不能随聊天页/播放器测量高度累加漂移。
            val bottomEdge = height - safeBottom
            val bottomTop = bottomEdge - bottom.measuredHeight
            bottom.layout(safeLeft, bottomTop, width - safeRight, bottomEdge)
            pager.layout(safeLeft, y, width - safeRight, bottomTop.coerceAtLeast(y))
            latest.layout(width - safeRight - dp(128), pager.bottom - dp(52), width - safeRight - dp(16), pager.bottom - dp(16))
        }
        sheet?.layout(0, 0, width, height)
    }
    fun setFullscreen(value: Boolean) {
        if (fullscreen == value) return
        savePositions(); fullscreen = value; video.setFullscreen(value)
        for (view in listOf(header, profile, tabs, pager, bottom)) view.visibility = if (value) GONE else VISIBLE
        latest.visibility = GONE; bindVisibleList()
        ViewCompat.getRootWindowInsets(this)?.let { updateInsets(it) }
        requestLayout(); ViewCompat.requestApplyInsets(this)
    }
    fun update(values: Map<*, *>) {
        val changedRoom = data["roomKey"] != values["roomKey"]
        val listChanged = listOf("title", "userName", "roomKey", "chatSize", "chatGap", "chatBubble", "superChatEnabled", "follows", "history", "superChats", "dark", "primaryColor", "autoExitEnabled", "autoExitCountdown", "followRefreshing", "historyRefreshing").any { data[it] != values[it] }
        data = values; style = NativePlayerStyle(activity, data)
        if (changedRoom) { chat.clear(); unreadChat.clear(); positions.clear(); autoScroll = true }
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
        bottom.setBackgroundColor(style.surface)
        latest.setTextColor(style.primary)
        latest.background = NativeIcons.background(
            androidx.core.graphics.ColorUtils.blendARGB(style.surface, style.primary, .16f), dp(18).toFloat()).apply {
            setStroke(dp(1), (style.primary and 0x00FFFFFF) or 0x88000000.toInt())
        }
        val latestArrow = NativeIcons.drawable("arrowDown", style.primary).apply { setBounds(0, 0, dp(18), dp(18)) }
        latest.setCompoundDrawables(latestArrow, null, null, null)
        latest.compoundDrawablePadding = dp(4); latest.setPadding(dp(10), 0, dp(10), 0)
        video.update(values)
        val names = listOf("聊天") + (if (values["hasSC"] == true) listOf("SC") else emptyList()) + listOf("关注", "设置")
        if (names != tabNames) buildTabs(names)
        if (!fullscreen && listChanged) { adapters[activeTab]?.refresh(); paintTabs() }
        if (listChanged) {
            followRefresh?.setRefreshing(values["followRefreshing"] == true)
            sheetRefresh?.invoke()
        }
        requestLayout()
    }
    private fun buildTabs(names: List<String>) {
        pager.dispose(); pager.removeAllViews(); tabs.removeAllViews(); followRefresh = null; lists.clear(); adapters.clear(); tabNames = names
        if (activeTab !in names) activeTab = "聊天"
        for (name in names) {
            val cell = FrameLayout(activity); cell.addView(style.text(name).apply {
                gravity = Gravity.CENTER; typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            }, FrameLayout.LayoutParams(-1, -1))
            style.click(cell) { savePositions(); pager.select(names.indexOf(name)) }
            tabs.addView(cell, LinearLayout.LayoutParams(0, -1, 1f))
            val list = newList(); val adapter = RoomAdapter(name); lists[name] = list; adapters[name] = adapter
            if (name == "聊天") list.setOnScrollListener(object : AbsListView.OnScrollListener {
                override fun onScrollStateChanged(v: AbsListView, state: Int) {
                    val wasScrolling = chatScrollState != AbsListView.OnScrollListener.SCROLL_STATE_IDLE
                    chatScrollState = state
                    if (state != AbsListView.OnScrollListener.SCROLL_STATE_IDLE) {
                        autoScroll = false
                    } else if (wasScrolling && !fullscreen && activeTab == "聊天" && list.adapter != null && list.childCount > 0) {
                        autoScroll = !list.canScrollVertically(1)
                        if (autoScroll) scrollLatest()
                    }
                    updateLatestButton()
                }
                override fun onScroll(v: AbsListView, first: Int, visible: Int, total: Int) {
                    // 不能在手指刚开始滑动、仍暂处底部时重新打开自动跟随。
                    updateLatestButton()
                }
            })
            list.setOnItemClickListener { _, _, index, _ -> adapter.items.getOrNull(index)?.let { item ->
                if (name == "关注") onAction("openRoom", item) else if (name == "设置") settingsAction(item["action"].toString())
            } }
            list.setOnItemLongClickListener { _, _, index, _ -> if (name == "聊天" && index > 0) {
                adapter.items.getOrNull(index)?.get("message")?.toString()?.let { text -> showMessageActions(text) }; true
            } else false }
            if (name == "关注") {
                followRefresh = NativePlayerRefresh(activity, list, style,
                    listWithEmpty(list, "暂无直播中的关注")) { onAction("reloadFollow", null) }
                pager.addView(followRefresh)
            } else pager.addView(list)
        }
        pager.select(names.indexOf(activeTab), false); paintTabs()
    }
    private fun paintTabs() {
        tabs.setBackgroundColor(style.surface); tabs.invalidate()
        for (i in tabNames.indices) {
            val cell = tabs.getChildAt(i) as FrameLayout; val label = cell.getChildAt(0) as TextView
            val count = (data["superChats"] as? List<*>)?.size ?: 0
            label.text = if (tabNames[i] == "SC" && count > 0) "SC($count)" else tabNames[i]
        }
        paintTabColors()
    }
    private fun paintTabColors() {
        val settling = !pager.isDragging && pager.isSettling &&
            tabMotionFrom != tabMotionTarget.toFloat() && tabMotionColors.size == tabs.childCount
        val progress = if (settling)
            ((tabPosition - tabMotionFrom) / (tabMotionTarget - tabMotionFrom)).coerceIn(0f, 1f) else 0f
        for (i in 0 until tabs.childCount) {
            val label = (tabs.getChildAt(i) as FrameLayout).getChildAt(0) as TextView
            val color = if (settling) {
                // 点击跨页只淡出原标签、淡入目标；中间标签不闪成选中状态。
                androidx.core.graphics.ColorUtils.blendARGB(tabMotionColors[i],
                    if (i == tabMotionTarget) style.primary else style.tabInactive, progress)
            } else {
                val selected = (1f - abs(tabPosition - i)).coerceIn(0f, 1f)
                androidx.core.graphics.ColorUtils.blendARGB(style.tabInactive, style.primary, selected)
            }
            label.setTextColor(color)
        }
    }
    private fun tabLabelBounds(index: Int): RectF {
        if (tabs.childCount == 0 || tabs.width <= 0) return RectF()
        val cell = tabs.getChildAt(index.coerceIn(0, tabs.childCount - 1)) as FrameLayout
        val label = cell.getChildAt(0) as TextView
        val labelWidth = label.paint.measureText(label.text.toString())
            .coerceAtMost((cell.width - dp(16)).coerceAtLeast(0).toFloat())
        val center = (cell.left + cell.right) / 2f
        return RectF(center - labelWidth / 2f, 0f, center + labelWidth / 2f, 0f)
    }
    private fun tabIndicatorBounds(position: Float): RectF {
        if (tabs.childCount == 0) return RectF()
        val from: RectF; val to: RectF; val progress: Float; val movingRight: Boolean
        if (!pager.isDragging && pager.isSettling && tabMotionFrom != tabMotionTarget.toFloat()) {
            from = tabMotionStart; to = tabLabelBounds(tabMotionTarget)
            progress = ((position - tabMotionFrom) / (tabMotionTarget - tabMotionFrom)).coerceIn(0f, 1f)
            movingRight = tabMotionTarget > tabMotionFrom
        } else {
            val current = position.coerceIn(0f, (tabs.childCount - 1).toFloat())
            val lower = kotlin.math.floor(current).toInt()
            from = tabLabelBounds(lower); to = tabLabelBounds((lower + 1).coerceAtMost(tabs.childCount - 1))
            progress = current - lower; movingRight = true
        }
        // 与首页 Material 3 label indicator 同源：前缘 sin，后缘 1-cos，先伸再收。
        val accelerate = (1 - cos(progress * Math.PI / 2)).toFloat()
        val decelerate = sin(progress * Math.PI / 2).toFloat()
        val leftProgress = if (movingRight) accelerate else decelerate
        val rightProgress = if (movingRight) decelerate else accelerate
        return RectF(from.left + (to.left - from.left) * leftProgress, 0f,
            from.right + (to.right - from.right) * rightProgress, 0f)
    }
    private fun listWithEmpty(list: ListView, message: String): FrameLayout {
        val content = FrameLayout(activity).apply { isClickable = true }
        content.addView(list, FrameLayout.LayoutParams(-1, -1))
        val empty = style.text(message, 14f, style.secondary).apply {
            gravity = Gravity.CENTER; setPadding(dp(16), dp(24), dp(16), dp(24))
        }
        content.addView(empty, FrameLayout.LayoutParams(-1, -1))
        list.emptyView = empty
        return content
    }
    private fun newList() = ListView(activity).apply { setSelector(android.graphics.drawable.ColorDrawable(Color.TRANSPARENT)); divider = null; isVerticalScrollBarEnabled = false; isHorizontalScrollBarEnabled = false; overScrollMode = OVER_SCROLL_NEVER; clipToPadding = false }
    private fun savePositions() { for ((name, list) in lists) if (list.adapter != null) positions[name] = Pair(list.firstVisiblePosition, list.getChildAt(0)?.top ?: 0) }
    private fun bindVisibleList() {
        for ((name, list) in lists) {
            if (fullscreen) { if (list.adapter != null) positions[name] = Pair(list.firstVisiblePosition, list.getChildAt(0)?.top ?: 0); list.adapter = null }
            else { if (name == activeTab || list.adapter == null) adapters[name]?.refresh(); if (list.adapter == null) { list.adapter = adapters[name]; positions[name]?.let { list.setSelectionFromTop(it.first, it.second) } } }
        }
        updateLatestButton()
        if (!fullscreen && activeTab == "聊天" && autoScroll) scrollLatest()
    }
    private fun updateLatestButton() {
        latest.visibility = if (!fullscreen && activeTab == "聊天" && !autoScroll) VISIBLE else GONE
    }
    private fun trimMessages(items: ArrayList<Map<*, *>>) {
        if (items.size > 200) items.subList(0, items.size - 200).clear()
    }
    fun addMessages(items: List<*>) {
        val messages = items.filterIsInstance<Map<*, *>>()
        if (!autoScroll) {
            unreadChat.addAll(messages); trimMessages(unreadChat)
            updateLatestButton()
            return
        }
        chat.addAll(messages); trimMessages(chat)
        if (!fullscreen && activeTab == "聊天") { adapters["聊天"]?.refresh(); scrollLatest() }
    }
    fun clearMessages() { chat.clear(); unreadChat.clear(); if (!fullscreen) adapters["聊天"]?.refresh() }
    private fun scrollLatest() {
        if (unreadChat.isNotEmpty()) {
            chat.addAll(unreadChat); unreadChat.clear(); trimMessages(chat)
            adapters["聊天"]?.refresh()
        }
        latest.visibility = GONE
        lists["聊天"]?.post { if (!fullscreen && activeTab == "聊天" && autoScroll) lists["聊天"]?.setSelection((adapters["聊天"]?.count ?: 1) - 1) }
    }
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
            visibility = if (item["status"] != null && (!fullscreen || item.containsKey("liveStartTime").not())) VISIBLE else GONE
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
        durationDialog?.dismiss(); durationDialog = null
        sheetRefresh = null; roomPager?.dispose(); roomPager = null; sheet?.dispose(); sheet = null
        val result = sheetResult; sheetResult = null; result?.success(null)
    }
    fun dismissOverlay(): Boolean {
        // 到期提示与旧版 PopScope 一样，返回键不能跳过自动关闭。
        if (autoExitDialog?.isShowing == true) return true
        durationDialog?.let { it.dismiss(); return true }
        val popup = sheet ?: return false
        popup.dismiss(); return true
    }
    private fun answer(value: Any?) { val result = sheetResult; sheetResult = null; result?.success(value); sheet?.dismiss() }
    fun showDialog(kind: String, values: Map<*, *>, result: MethodChannel.Result) {
        when (kind) {
            "playbackInfo" -> { showPlaybackInfo(values); result.success(null) }
            "autoExit" -> showAutoExitPrompt(result)
            "autoExitSettings" -> showAutoExitSettings(values, result)
            "shield" -> {
                val popup = beginSheet("关键词屏蔽", side = false, heightPx = dp(340) + safeBottom)
                sheetResult = result
                val input = NativePlayerInput(activity, style).apply {
                    setText((values["keywords"] as? List<*>)?.joinToString("\n") ?: "")
                    hint = "每行一个关键词，正则使用 /表达式/"
                    inputType = android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_FLAG_MULTI_LINE
                    textSize = 14f; gravity = Gravity.TOP
                }
                popup.panel.addView(input, LinearLayout.LayoutParams(-1, 0, 1f).apply { setMargins(dp(16), dp(12), dp(16), dp(8)) })
                popup.panel.addView(action("", "保存") {
                    answer(input.text.toString().lines().map { it.trim() }.filter { it.isNotEmpty() })
                }, LinearLayout.LayoutParams(-1, dp(48)))
            }
            else -> { showPanel(kind); result.success(null) }
        }
    }
    private fun showAutoExitSettings(values: Map<*, *>, result: MethodChannel.Result) {
        // 旧 Utils.showBottomSheet 是约半屏的底部面板，不是 180dp 的紧凑弹层。
        val popup = beginSheet("定时关闭", side = false)
        sheetResult = result
        (popup.panel.getChildAt(0) as? ViewGroup)?.let { header ->
            header.setPadding(dp(12), 0, dp(4), 0)
            (header.getChildAt(0) as? TextView)?.setTypeface(null, Typeface.NORMAL)
        }
        var enabled = values["enabled"] == true
        var minutes = (values["minutes"] as? Number)?.toInt()?.coerceIn(1, 1439) ?: 60
        val row = LinearLayout(activity).apply { gravity = Gravity.CENTER_VERTICAL; setPadding(dp(16), 0, dp(16), 0) }
        row.addView(style.text("启用定时关闭", 16f), LinearLayout.LayoutParams(0, -2, 1f))
        val toggle = NativePlayerSwitch(activity, style).apply { isChecked = enabled; contentDescription = "启用定时关闭" }
        row.addView(toggle)
        popup.panel.addView(row, LinearLayout.LayoutParams(-1, dp(56)))
        val timeRow = LinearLayout(activity).apply { gravity = Gravity.CENTER_VERTICAL; setPadding(dp(16), 0, dp(16), 0) }
        val time = style.text("", 16f)
        timeRow.addView(time, LinearLayout.LayoutParams(0, -2, 1f))
        timeRow.addView(ImageView(activity).apply { setImageDrawable(NativeIcons.drawable("chevron", style.foreground)) },
            LinearLayout.LayoutParams(dp(24), dp(24)))
        fun refreshTime() {
            time.text = "自动关闭时间：${minutes / 60}小时${minutes % 60}分钟"
            timeRow.isEnabled = enabled; timeRow.alpha = if (enabled) 1f else .38f
        }
        fun changed(durationSelected: Boolean = false) {
            refreshTime()
            onAction("autoExitChanged", mapOf("enabled" to enabled, "minutes" to minutes,
                "durationSelected" to durationSelected))
        }
        toggle.setOnCheckedChangeListener { _, checked -> enabled = checked; changed() }
        style.click(row) { toggle.isChecked = !toggle.isChecked }
        style.click(timeRow) {
            if (enabled) showDurationInput(minutes) { minutes = it; changed(true) }
        }
        popup.panel.addView(timeRow, LinearLayout.LayoutParams(-1, dp(56)))
        refreshTime()
    }
    private fun showDurationInput(minutes: Int, selected: (Int) -> Unit) {
        durationDialog?.dismiss()
        val popup = NativePlayerDurationDialog(activity, style, minutes, selected)
        durationDialog = popup
        popup.setOnDismissListener { if (durationDialog === popup) durationDialog = null }
        popup.show()
    }
    private fun clearAutoExitPrompt() {
        val popup = autoExitDialog; autoExitDialog = null
        val result = autoExitResult; autoExitResult = null
        popup?.dismiss(); result?.success(null)
    }
    private fun showAutoExitPrompt(result: MethodChannel.Result) {
        clearSheet(); clearAutoExitPrompt()
        lateinit var popup: NativeAutoExitDialog
        popup = NativeAutoExitDialog(activity, style) { action ->
            if (autoExitDialog === popup) {
                autoExitDialog = null
                val response = autoExitResult; autoExitResult = null
                response?.success(action)
            }
        }
        autoExitDialog = popup; autoExitResult = result
        popup.setOnDismissListener {
            if (autoExitDialog === popup) clearAutoExitPrompt()
        }
        popup.show()
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
    /** 更多菜单的播放信息是可复制地址的详情页，与视频实时指标浮层分开。 */
    private fun showPlaybackInfo(values: Map<*, *>) {
        val popup = beginSheet("播放信息", heightPx = ((height - safeTop) * .72).toInt())
        val box = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
        fun field(label: String, value: String, selectable: Boolean = false) {
            val row = LinearLayout(activity).apply {
                orientation = LinearLayout.VERTICAL; setPadding(dp(16), dp(14), dp(16), dp(14))
            }
            row.addView(style.text(label, 16f))
            row.addView(style.text(value, if (selectable) 12f else 14f, style.secondary).apply {
                setPadding(0, dp(8), 0, 0); setTextIsSelectable(selectable)
                if (selectable) highlightColor = Color.TRANSPARENT
            })
            box.addView(row); box.addView(style.line())
        }
        field("播放器", "Android native (ExoPlayer)")
        val url = values["url"]?.toString().orEmpty()
        field("播放地址", url.ifEmpty { "暂无（尚未取流）" }, selectable = url.isNotEmpty())
        if (url.isNotEmpty()) box.addView(action("copy", "复制播放地址") {
            val clipboard = activity.getSystemService(android.content.Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
            clipboard.setPrimaryClip(android.content.ClipData.newPlainText("播放地址", url))
            android.widget.Toast.makeText(activity, "播放地址已复制", android.widget.Toast.LENGTH_SHORT).show()
        }, LinearLayout.LayoutParams(-1, dp(48)))
        popup.panel.addView(ScrollView(activity).apply {
            isVerticalScrollBarEnabled = false; addView(box)
        }, LinearLayout.LayoutParams(-1, 0, 1f))
    }

    private fun showDanmakuSettings() {
        val popup = beginSheet("弹幕设置"); val box = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
        val entries = listOf(Triple("字号", "fontSize", 12..32), Triple("字重", "fontWeight", 1..9), Triple("不透明度", "opacity", 2..20), Triple("显示区域", "area", 2..20), Triple("滚动时长", "duration", 5..15), Triple("顶部边距", "topMargin", 0..72), Triple("底部边距", "bottomMargin", 0..72))
        for ((label, key, range) in entries) {
            val percent = key == "opacity" || key == "area"; val value = (data[key] as? Number)?.toFloat() ?: range.first.toFloat()
            val header = LinearLayout(activity).apply { gravity = Gravity.CENTER_VERTICAL; setPadding(dp(16), dp(12), dp(16), 0) }
            header.addView(style.text(label, 16f), LinearLayout.LayoutParams(0, -2, 1f))
            val heading = style.text("${if (percent) (value * 100).roundToInt() else value.toInt()}${if (percent) "%" else ""}", 16f)
            header.addView(heading); box.addView(header)
            val slider = NativePlayerSlider(activity, style).apply { contentDescription = label; max = range.last - range.first; progress = ((if (percent) value * 20 else value) - range.first).roundToInt().coerceIn(0, max) }
            slider.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(s: SeekBar, p: Int, user: Boolean) { heading.text = "${if (percent) (p + range.first) * 5 else p + range.first}${if (percent) "%" else ""}" }
                override fun onStartTrackingTouch(s: SeekBar) = Unit
                override fun onStopTrackingTouch(s: SeekBar) { onAction(key, if (percent) (s.progress + range.first) / 20.0 else s.progress + range.first) }
            }); box.addView(slider, LinearLayout.LayoutParams(-1, dp(40)))
        }
        box.addView(action("settings", "关键词屏蔽") { onAction("shieldSettings", null) }, LinearLayout.LayoutParams(-1, dp(48)))
        popup.panel.addView(ScrollView(activity).apply { isVerticalScrollBarEnabled = false; addView(box) }, LinearLayout.LayoutParams(-1, 0, 1f))
    }
    private fun showMore() {
        val entries = mutableListOf(Triple("quality", "清晰度", "quality"), Triple("line", "线路", "line"), Triple("aspect", "画面尺寸", "playerSettings"))
        entries.addAll(listOf(Triple("timer", "定时关闭", "autoExitSettings"), Triple("share", "分享直播间", "share"), Triple("link", "复制链接", "copyRoom"), Triple("openApp", "APP中打开", "openApp"), Triple("info", "播放信息", "playbackInfo")))
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
        followList.adapter = followAdapter; historyList.adapter = historyAdapter
        val followPull = NativePlayerRefresh(activity, followList, style,
            listWithEmpty(followList, "暂无直播中的关注")) { onAction("reloadFollow", null) }
        val historyPull = NativePlayerRefresh(activity, historyList, style,
            listWithEmpty(historyList, "暂无观看历史")) { onAction("reloadHistory", null) }
        pages.addView(followPull); pages.addView(historyPull)
        var locked = data["roomListLocked"] != false
        for ((index, label) in listOf("关注", "历史").withIndex()) headings.addView(action(if (index == 0) "followTab" else "history", label) { pages.select(index) }, LinearLayout.LayoutParams(0, dp(48), 1f))
        val lock = NativeIcons.button(activity, if (locked) "lock" else "unlock", "切房后保持面板") { locked = !locked; onAction("roomListLocked", locked); (headings.getChildAt(2) as ImageView).setImageDrawable(NativeIcons.drawable(if (locked) "lock" else "unlock", style.foreground)) }
        lock.setImageDrawable(NativeIcons.drawable(if (locked) "lock" else "unlock", style.foreground))
        // 48dp 点击区域不变；20dp 图标四边等距，始终与所在行居中对齐。
        lock.setPadding(dp(14), dp(14), dp(14), dp(14))
        lock.scaleType = ImageView.ScaleType.FIT_CENTER
        headings.addView(lock, LinearLayout.LayoutParams(dp(48), dp(48)).apply { gravity = Gravity.CENTER_VERTICAL })
        pages.onSelected = { selected -> for (i in 0..1) (headings.getChildAt(i) as NativePlayerAction).apply { setColor(if (i == selected) style.primary else Color.GRAY); setSelectedStyle(i == selected) } }
        popup.panel.addView(headings, LinearLayout.LayoutParams(-1, dp(48))); popup.panel.addView(style.line()); popup.panel.addView(pages, LinearLayout.LayoutParams(-1, 0, 1f))
        for ((list, adapter) in listOf(followList to followAdapter, historyList to historyAdapter)) list.setOnItemClickListener { _, _, i, _ -> adapter.items.getOrNull(i)?.let { onAction("openRoom", it); if (!locked) popup.dismiss() } }
        sheetRefresh = {
            followAdapter.refresh(); historyAdapter.refresh()
            followPull.setRefreshing(data["followRefreshing"] == true)
            historyPull.setRefreshing(data["historyRefreshing"] == true)
        }; sheetRefresh?.invoke(); pages.select(0, false)
    }
    private fun confirmUnfollow() {
        val popup = beginSheet("取消关注", side = false, heightPx = dp(164) + safeBottom)
        popup.panel.addView(style.text("确定要取消关注该主播吗？").apply { setPadding(dp(16), dp(12), dp(16), dp(12)) })
        popup.panel.addView(action("followFilled", "确定取消") { onAction("unfollow", null); popup.dismiss() }, LinearLayout.LayoutParams(-1, dp(48)))
    }
    private fun showMessageActions(text: String) { choose("弹幕操作", listOf("复制", "屏蔽该关键词"), -1) { onAction(if (it == 0) "copyMessage" else "addShield", text) } }
    fun dispose() { disposed = true; clearAutoExitPrompt(); clearSheet(); pager.dispose(); lists.values.forEach { it.adapter = null }; chat.clear(); unreadChat.clear(); NativeAvatar.clear(avatar); video.dispose() }
}
