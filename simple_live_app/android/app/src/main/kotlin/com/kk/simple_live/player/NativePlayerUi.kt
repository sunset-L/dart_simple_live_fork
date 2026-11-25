package com.kk.simple_live.player

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.view.*
import android.view.animation.DecelerateInterpolator
import android.widget.*
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout
import kotlin.math.abs
import kotlin.math.roundToInt

/** 与 Flutter Theme 同源，所有普通页面/面板统一使用它，视频控件单独保持白色。 */
class NativePlayerStyle(val context: Context, private val data: Map<*, *>) {
    private fun color(key: String, fallback: Int) = (data[key] as? Number)?.toInt() ?: fallback
    val dark = data["dark"] == true
    val background = color("backgroundColor", if (dark) 0xFF303030.toInt() else 0xFFFAFAFA.toInt())
    val surface = color("cardColor", if (dark) 0xFF424242.toInt() else Color.WHITE)
    val sheetSurface = color("sheetColor", surface)
    val foreground = color("foregroundColor", if (dark) Color.WHITE else 0xFF333333.toInt())
    val primary = color("primaryColor", 0xFF3498DB.toInt())
    val secondary = Color.GRAY
    val dialogSurface = color("dialogColor", sheetSurface)
    val inputSurface = color("inputColor", if (dark) 0xFF49454F.toInt() else 0xFFE7E0EC.toInt())
    val primaryContainer = color("primaryContainerColor", surface)
    val onPrimaryContainer = color("onPrimaryContainerColor", foreground)
    val error = color("errorColor", 0xFFB3261E.toInt())
    val divider = 0x339E9E9E
    fun dp(v: Int) = (v * context.resources.displayMetrics.density).roundToInt()
    fun text(value: String, size: Float = 14f, color: Int = foreground) = TextView(context).apply {
        text = value; textSize = size; setTextColor(color); gravity = Gravity.CENTER_VERTICAL
        includeFontPadding = false
    }
    fun line() = View(context).apply { setBackgroundColor(divider); layoutParams = LinearLayout.LayoutParams(-1, dp(1)) }
    fun click(view: View, action: () -> Unit) {
        view.background = android.graphics.drawable.RippleDrawable(android.content.res.ColorStateList.valueOf(0x229E9E9E), view.background, NativeIcons.background(Color.WHITE))
        view.setOnClickListener { action() }
    }
}

/** Android 原生分页：点击与拖动共用一个索引。只拦截横向拖动，不抢列表纵向滚动。
 * 关注页右滑的越界量交给整个面板；历史页右滑仍然只是返回关注页。 */
class NativePlayerPager(context: Context) : ViewGroup(context) {
    var index = 0; private set
    var onSelected: (Int) -> Unit = {}
    var onScrollPosition: (Float) -> Unit = {}
    var onPanelDrag: ((Float, Float?) -> Unit)? = null
    private var downX = 0f
    private var downY = 0f
    private var initial = 0f
    private var offset = 0f
    private var panelOffset = 0f
    private var dragging = false
    private var fromFirst = false
    private var velocity: VelocityTracker? = null
    private var animation: ValueAnimator? = null
    private val slop = ViewConfiguration.get(context).scaledTouchSlop
    private fun applyOffset() {
        scrollTo(offset.roundToInt(), 0)
        onScrollPosition(if (width > 0) offset / width else index.toFloat())
    }
    fun select(value: Int, animate: Boolean = true) {
        val target = value.coerceIn(0, (childCount - 1).coerceAtLeast(0))
        index = target; onSelected(target)
        animation?.cancel()
        if (!animate || width == 0) { offset = target * width.toFloat(); applyOffset(); return }
        animation = ValueAnimator.ofFloat(offset, target * width.toFloat()).apply {
            duration = 220; interpolator = DecelerateInterpolator()
            addUpdateListener { offset = it.animatedValue as Float; applyOffset() }
            start()
        }
    }
    override fun onMeasure(w: Int, h: Int) {
        val width = MeasureSpec.getSize(w); val height = MeasureSpec.getSize(h)
        setMeasuredDimension(width, height)
        for (i in 0 until childCount) getChildAt(i).measure(MeasureSpec.makeMeasureSpec(width, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(height, MeasureSpec.EXACTLY))
    }
    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        for (i in 0 until childCount) getChildAt(i).layout(i * width, 0, (i + 1) * width, height)
        if (changed && !dragging) { animation?.cancel(); offset = index * width.toFloat(); applyOffset() }
    }
    private fun trackMovement(event: MotionEvent) {
        // 面板本身会跟手平移，局部坐标也会随之变化；位置和速度都必须以屏幕为基准。
        val screenEvent = MotionEvent.obtain(event)
        screenEvent.offsetLocation(event.rawX - event.x, event.rawY - event.y)
        velocity?.addMovement(screenEvent)
        screenEvent.recycle()
    }
    override fun onInterceptTouchEvent(e: MotionEvent): Boolean {
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                animation?.cancel(); downX = e.rawX; downY = e.rawY; initial = offset; fromFirst = offset <= 1; panelOffset = 0f; dragging = false
                velocity?.recycle(); velocity = VelocityTracker.obtain(); trackMovement(e)
            }
            MotionEvent.ACTION_MOVE -> if (abs(e.rawX - downX) > slop && abs(e.rawX - downX) > abs(e.rawY - downY)) {
                dragging = true; parent.requestDisallowInterceptTouchEvent(true); return true
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> { velocity?.recycle(); velocity = null }
        }
        return dragging
    }
    override fun onTouchEvent(e: MotionEvent): Boolean {
        trackMovement(e)
        when (e.actionMasked) {
            MotionEvent.ACTION_MOVE -> {
                val raw = initial - (e.rawX - downX)
                panelOffset = if (fromFirst && raw < 0 && onPanelDrag != null) -raw else 0f
                if (onPanelDrag != null) onPanelDrag?.invoke(panelOffset, null)
                offset = raw.coerceIn(0f, ((childCount - 1) * width).coerceAtLeast(0).toFloat())
                applyOffset()
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                dragging = false
                velocity?.computeCurrentVelocity(1000)
                val speed = if (e.actionMasked == MotionEvent.ACTION_CANCEL) 0f else velocity?.xVelocity ?: 0f
                if (panelOffset > 0) onPanelDrag?.invoke(if (e.actionMasked == MotionEvent.ACTION_CANCEL) 0f else panelOffset, speed)
                val target = if (width == 0) index else if (abs(speed) > 700 * resources.displayMetrics.density) {
                    if (speed < 0) (initial / width).toInt() + 1 else (initial / width).roundToInt() - 1
                } else (offset / width).roundToInt()
                select(target)
                velocity?.recycle(); velocity = null
            }
        }
        return true
    }
    fun dispose() { animation?.cancel(); velocity?.recycle(); velocity = null }
    override fun onDetachedFromWindow() { dispose(); super.onDetachedFromWindow() }
}

/** 与旧版一致：横屏右侧 320/360dp、透明遮罩、200ms滑入；竖屏底部圆角面板。 */
class NativePlayerSheet(
    context: Context, val style: NativePlayerStyle, private val side: Boolean,
    private val panelWidth: Int, private val panelHeight: Int,
    private val finished: () -> Unit,
) : FrameLayout(context) {
    val panel = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
    private var closing = false
    init {
        isClickable = true
        setBackgroundColor(if (side) Color.TRANSPARENT else 0x66000000)
        setOnClickListener { dismiss() }
        val shape = NativeIcons.background(style.sheetSurface).apply {
            cornerRadii = if (side) floatArrayOf(style.dp(4).toFloat(), style.dp(4).toFloat(), 0f, 0f, 0f, 0f, style.dp(4).toFloat(), style.dp(4).toFloat())
                else floatArrayOf(style.dp(12).toFloat(), style.dp(12).toFloat(), style.dp(12).toFloat(), style.dp(12).toFloat(), 0f, 0f, 0f, 0f)
        }
        panel.alpha = 0f; panel.background = shape; panel.clipToOutline = true; panel.isClickable = true
        addView(panel, LayoutParams(if (side) style.dp(panelWidth) else minOf(style.dp(600), resources.displayMetrics.widthPixels),
            if (side) -1 else panelHeight, if (side) Gravity.END else Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL))
    }
    fun header(title: String) {
        val row = LinearLayout(context).apply { gravity = Gravity.CENTER_VERTICAL; setPadding(style.dp(if (side) 0 else 16), 0, style.dp(4), 0) }
        val close = NativeIcons.button(context, if (side) "back" else "close", "关闭") { dismiss() }.apply { setImageDrawable(NativeIcons.drawable(if (side) "back" else "close", style.foreground)) }
        if (side) row.addView(close, LinearLayout.LayoutParams(style.dp(48), style.dp(48)))
        row.addView(style.text(title, 16f).apply { setTypeface(null, Typeface.BOLD) }, LinearLayout.LayoutParams(0, -1, 1f))
        if (!side) row.addView(close, LinearLayout.LayoutParams(style.dp(40), style.dp(48)))
        panel.addView(row, LinearLayout.LayoutParams(-1, style.dp(48)))
        panel.addView(style.line())
    }
    fun enter() {
        panel.post {
            if (closing) return@post
            if (side) panel.translationX = panel.width.toFloat() else panel.translationY = panel.height.toFloat()
            panel.alpha = 1f
            panel.animate().translationX(0f).translationY(0f).setDuration(200).setInterpolator(DecelerateInterpolator()).start()
        }
    }
    fun drag(value: Float, velocity: Float?) {
        if (closing) return
        panel.animate().cancel()
        if (velocity == null) { panel.translationX = value.coerceAtMost(panel.width.toFloat()); return }
        if (value > panel.width / 2 || velocity >= 700 * resources.displayMetrics.density) dismiss(true)
        else panel.animate().translationX(0f).setDuration(200).setInterpolator(DecelerateInterpolator(1.5f)).start()
    }
    fun dismiss(horizontal: Boolean = false) {
        if (closing) return
        closing = true
        panel.animate().cancel()
        panel.animate().setDuration(200).setInterpolator(DecelerateInterpolator(1.5f))
            .translationX(if (side || horizontal) panel.width.toFloat() else 0f)
            .translationY(if (!side && !horizontal) panel.height.toFloat() else 0f)
            .withEndAction { dispose(); finished() }.start()
    }
    fun dispose() {
        closing = true; panel.animate().cancel()
        (parent as? ViewGroup)?.removeView(this)
    }
}

/** 保持旧 Material 开关的圆角轨道、圆形滑块，不使用各手机厂商不同的系统皮肤。 */
class NativePlayerSwitch(context: Context, private val style: NativePlayerStyle) : CompoundButton(context) {
    private val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG)
    init { buttonDrawable = null; isClickable = true; setWillNotDraw(false) }
    override fun onMeasure(w: Int, h: Int) { setMeasuredDimension(style.dp(52), style.dp(36)) }
    override fun onDraw(canvas: android.graphics.Canvas) {
        val d = resources.displayMetrics.density
        paint.color = if (isChecked) style.primary else if (style.dark) 0xFF60636B.toInt() else 0xFFE0E2E9.toInt()
        canvas.drawRoundRect(0f, 2*d, 52*d, 34*d, 16*d, 16*d, paint)
        paint.color = if (isChecked) Color.WHITE else 0xFF757B83.toInt()
        canvas.drawCircle((if (isChecked) 36 else 16)*d, 18*d, (if (isChecked) 12 else 8)*d, paint)
    }
    override fun setChecked(checked: Boolean) { super.setChecked(checked); invalidate() }
}

/** 图标与文字先组成紧邻的一组，再整体居中；不能把图标贴到等宽标签左边。 */
class NativePlayerAction(context: Context) : LinearLayout(context) {
    private val image = ImageView(context)
    private val label = TextView(context).apply { textSize = 14f; includeFontPadding = false; maxLines = 1 }
    private var icon = ""
    init {
        orientation = HORIZONTAL; gravity = Gravity.CENTER
        val d = resources.displayMetrics.density
        setPadding((8*d).roundToInt(), 0, (8*d).roundToInt(), 0)
        addView(image, LayoutParams((20*d).roundToInt(), (20*d).roundToInt()).apply { rightMargin = (6*d).roundToInt() })
        addView(label, LayoutParams(-2, -2))
    }
    fun bind(name: String, text: String, color: Int) {
        icon = name; label.text = text; contentDescription = text
        image.visibility = if (name.isEmpty()) GONE else VISIBLE
        setColor(color)
    }
    fun setColor(color: Int) { label.setTextColor(color); if (icon.isNotEmpty()) image.setImageDrawable(NativeIcons.drawable(icon, color)) }
    fun setSelectedStyle(selected: Boolean) { label.setTypeface(null, if (selected) Typeface.BOLD else Typeface.NORMAL); isSelected = selected }
}

/** 旧播放器 36dp、2.5dp 细线圆环，隐藏/卸载时停止动画。 */
class NativePlayerLoading(context: Context, color: Int = Color.WHITE) : View(context) {
    private val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
        this.color = color; style = android.graphics.Paint.Style.STROKE
        strokeWidth = 2.5f * resources.displayMetrics.density; strokeCap = android.graphics.Paint.Cap.ROUND
    }
    private var angle = 0f
    private val animation = ValueAnimator.ofFloat(0f, 360f).apply {
        duration = 1333; repeatCount = ValueAnimator.INFINITE
        interpolator = android.view.animation.LinearInterpolator()
        addUpdateListener { angle = (it.animatedValue as Float) % 360f; invalidate() }
    }
    override fun onDraw(canvas: android.graphics.Canvas) {
        val inset = paint.strokeWidth / 2
        canvas.drawArc(inset, inset, width - inset, height - inset, angle - 90f, 260f, false, paint)
    }
    override fun onVisibilityAggregated(visible: Boolean) {
        super.onVisibilityAggregated(visible)
        if (visible && isAttachedToWindow) {
            if (!animation.isStarted) {
                // 隐藏/重挂只暂停旋转，继续上次角度，不从零再转一遍。
                animation.setFloatValues(angle, angle + 360f)
                animation.start()
            }
        } else animation.cancel()
    }
    override fun onDetachedFromWindow() { animation.cancel(); super.onDetachedFromWindow() }
}

/** 滑动输入条保留 SeekBar 的触摸/无障碍，统一为细轨道与圆形滑块，去除厂商皮肤。 */
class NativePlayerSlider(context: Context, style: NativePlayerStyle) : SeekBar(context) {
    init {
        fun track(color: Int) = NativeIcons.background(color, style.dp(2).toFloat())
        val active = android.graphics.drawable.ClipDrawable(track(style.primary), Gravity.LEFT, android.graphics.drawable.ClipDrawable.HORIZONTAL)
        progressDrawable = android.graphics.drawable.LayerDrawable(arrayOf(track(if (style.dark) 0xFF60636B.toInt() else 0xFFE0E2E9.toInt()), active)).apply {
            setId(0, android.R.id.background); setId(1, android.R.id.progress)
        }
        thumb = android.graphics.drawable.GradientDrawable().apply {
            shape = android.graphics.drawable.GradientDrawable.OVAL; setColor(style.primary); setSize(style.dp(20), style.dp(20))
        }
        thumbOffset = style.dp(10); splitTrack = false; background = null
        minHeight = style.dp(4); maxHeight = style.dp(4)
        setPadding(style.dp(24), 0, style.dp(24), 0)
    }
}

/** 使用标准下拉进度、回弹和刷新动画；方向锁只负责让出横向分页手势。 */
class NativePlayerRefresh(context: Context, val list: ListView, style: NativePlayerStyle,
    content: View = list, refresh: () -> Unit) : SwipeRefreshLayout(context) {
    private var downX = 0f
    private var downY = 0f
    private var horizontal = false
    private val slop = ViewConfiguration.get(context).scaledTouchSlop
    init {
        addView(content, LayoutParams(-1, -1))
        setColorSchemeColors(style.primary)
        setProgressBackgroundColorSchemeColor(style.surface)
        setOnChildScrollUpCallback { _, _ -> list.canScrollVertically(-1) }
        setOnRefreshListener { refresh() }
    }
    override fun onInterceptTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downX = event.rawX; downY = event.rawY; horizontal = false
            }
            MotionEvent.ACTION_MOVE -> {
                val dx = abs(event.rawX - downX); val dy = abs(event.rawY - downY)
                if (dx > slop && dx > dy) horizontal = true
                if (horizontal) return false
            }
        }
        val intercept = super.onInterceptTouchEvent(event)
        if (intercept) parent?.requestDisallowInterceptTouchEvent(true)
        return intercept
    }
}

/** 输入能力仍由 EditText 提供，外观不继承 Activity/OEM 的下划线和黄色选择高亮。 */
class NativePlayerInput(context: Context, style: NativePlayerStyle) : EditText(context) {
    init {
        setTextColor(style.foreground); setHintTextColor(Color.GRAY)
        highlightColor = Color.TRANSPARENT
        background = NativeIcons.background(style.background, style.dp(8).toFloat())
        setPadding(style.dp(16), style.dp(12), style.dp(16), style.dp(12))
        if (android.os.Build.VERSION.SDK_INT >= 29) {
            textCursorDrawable = NativeIcons.background(style.primary).apply { setSize(style.dp(2), style.dp(24)) }
            fun handle() = android.graphics.drawable.GradientDrawable().apply {
                shape = android.graphics.drawable.GradientDrawable.OVAL
                setColor(style.primary); setSize(style.dp(16), style.dp(16))
            }
            setTextSelectHandle(handle()); setTextSelectHandleLeft(handle()); setTextSelectHandleRight(handle())
        }
    }
}
