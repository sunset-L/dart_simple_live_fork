package com.kk.simple_live.player

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.os.Build
import android.os.SystemClock
import android.view.MotionEvent
import android.view.View
import java.util.ArrayDeque
import kotlin.math.abs
import kotlin.math.max

/**
 * 小窗弹幕渲染层。
 *
 * 为什么要在原生侧重写一遍，而不是复用 Flutter 的 `canvas_danmaku`：
 * 小窗是**系统级悬浮窗**（`TYPE_APPLICATION_OVERLAY`）里的 `SurfaceView`，
 * 靠 `WindowManager` 直接贴在视频画面上。进小窗时直播页会被 pop，
 * 整棵 Flutter 渲染树（包括弹幕层）都没了，没有任何 Canvas 可以借用。
 *
 * 视觉属性来自「小窗弹幕设置」这一套独立配置（与小窗画面尺度匹配），
 * 与播放器弹幕的设置互不影响：字号、字重、不透明度、显示区域、
 * 滚动时长、描边、上下边距、同屏弹幕量。
 *
 * 只做**滚动弹幕**：小窗面积很小，顶部/底部固定弹幕会直接糊住画面，
 * 而直播弹幕绝大多数是滚动类型，这个取舍对观感几乎没有影响。
 *
 * 性能（用户明确要求关闭时不能有弹幕数据开销）：
 * - 关闭时这层是 `GONE` 且不请求任何帧，`onDraw` 根本不执行；
 * - 文本测量在入队时做一次并缓存，每帧只做坐标平移 + `drawText`；
 * - 同屏条数有硬上限（弹幕量设置），达到上限后新弹幕直接丢弃，
 *   既不叠轨也不无限排队——小窗轨道少，叠轨才是观感杀手。
 */
class DanmakuOverlayView(context: Context) : View(context) {

    companion object {
        /** 描边宽度与字号的比值，与 Flutter 侧观感对齐 */
        private const val STROKE_RATIO = 0.09f

        /** 行高与字号的比值，行与行之间留一点呼吸 */
        private const val LINE_HEIGHT_RATIO = 1.55f

        /**
         * 尺寸变化超过这个比例才认为是「结构变化」并清空重排。
         *
         * 双指缩放每帧只改几个像素，属于连续变化，不该清屏；
         * 「横向占满」切换、旋转屏幕这类是一次跳变，必须重建轨道。
         */
        private const val RESIZE_CLEAR_RATIO = 0.3f
    }

    /** 一条弹幕的运行状态 */
    private class Item(
        val text: String,
        val color: Int,
        /** 文本宽度（含描边余量），入队时算好，绘制期不再测量 */
        val width: Float,
    ) {
        /** 当前左上角 x，每帧按速度推进 */
        var x: Float = 0f

        /** 所在轨道序号，入轨时赋值 */
        var track: Int = -1
    }

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        textAlign = Paint.Align.LEFT
    }

    private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        textAlign = Paint.Align.LEFT
        strokeJoin = Paint.Join.ROUND
        color = Color.BLACK
    }

    // ------------------------------------------------------------------ 样式参数

    /**
     * 字号换算用的缩放密度。
     *
     * 用 `displayMetrics.scaledDensity`（已含用户在系统里调的字号倍率），
     * 与 Flutter 的 sp 语义一致，这样小窗和播放器弹幕看起来一样大。
     */
    @Suppress("DEPRECATION")
    private val scaledDensity: Float
        get() = resources.displayMetrics.scaledDensity

    private var fontSizePx: Float = 16f * scaledDensity
        set(value) {
            field = value
            // 必须同时改 paint 与 strokePaint 的 textSize：
            // 之前只改了 strokeWidth，字号永远是 Paint 默认的 12px，
            // 表现为「调大字号只有描边变粗、字没变大」。
            paint.textSize = value
            strokePaint.textSize = value
            strokePaint.strokeWidth = value * STROKE_RATIO
            reMeasurePending()
        }

    private var fontWeight: Int = 4
    private var opacity: Float = 1f
    private var area: Float = 0.8f
    private var durationSec: Int = 10
    private var topMarginDp: Float = 0f
    private var bottomMarginDp: Float = 0f

    /**
     * 弹幕量：同屏最多同时出现的条数。
     *
     * 小窗轨道本来就少（240dp 宽、显示区域 50%、20 号字只有三四轨），
     * 条数一多就只能往同一轨上叠，观感是两行字压在一起。
     *
     * 这里严格按条数封顶：达到上限后**新弹幕直接丢弃**，
     * 既不叠轨也不无限排队——小窗是副屏场景，少几条不影响，
     * 糊住画面才是真的影响。
     */
    private var maxConcurrent: Int = 8
        set(value) {
            field = value.coerceIn(1, 60)
            // 调小后立刻生效：把超出上限的在场弹幕收掉，
            // 否则要等它们各自滚出屏幕才看得出变化
            if (running.size > field) {
                while (running.size > field) {
                    val removed = running.removeAt(running.size - 1)
                    if (removed.track in trackTails.indices &&
                        trackTails[removed.track] === removed
                    ) {
                        trackTails[removed.track] = null
                    }
                }
            }
            // 排队区上限随弹幕量一起缩放：小窗不需要长队列
            val limit = pendingLimit()
            while (pending.size > limit) {
                pending.pollFirst()
            }
        }

    /** 排队区上限：与弹幕量挂钩，避免条数调小后队列还在空转 */
    private fun pendingLimit(): Int = (maxConcurrent * 2).coerceAtLeast(4)

    // ------------------------------------------------------------------ 运行状态

    /** 屏幕上正在跑的弹幕 */
    private val running = mutableListOf<Item>()

    /** 还没入场的弹幕（轨道都忙时先排队） */
    private val pending = ArrayDeque<Item>()

    /** 每条轨道最后入场的那条，用于判断能否接着插入而不追尾 */
    private val trackTails = mutableListOf<Item?>()

    private var lastFrameTime = 0L

    // ------------------------------------------------------------------ 外部设置

    /**
     * 按小窗专属的一套配置同步样式。
     *
     * 参数全部来自「我的 → 弹幕设置 → 小窗弹幕设置」，
     * 与播放器弹幕的设置互不影响（两套独立存储）。
     */
    fun applyOptions(
        fontSizeSp: Float,
        fontWeightValue: Int,
        opacityValue: Float,
        areaValue: Float,
        durationValueSec: Int,
        topMargin: Float,
        bottomMargin: Float,
        maxConcurrentValue: Int,
    ) {
        fontSizePx = max(6f, fontSizeSp * scaledDensity)
        val newWeight = fontWeightValue.coerceIn(1, 9)
        if (newWeight != fontWeight) {
            fontWeight = newWeight
            paint.typeface = typefaceFor(newWeight)
            strokePaint.typeface = paint.typeface
            reMeasurePending()
        }
        opacity = opacityValue.coerceIn(0.05f, 1f)
        area = areaValue.coerceIn(0.1f, 1f)
        durationSec = durationValueSec.coerceAtLeast(1)
        topMarginDp = topMargin
        bottomMarginDp = bottomMargin
        maxConcurrent = maxConcurrentValue
        invalidate()
    }

    /**
     * Flutter 的 `fontWeight` 是 1~9 的档位，Android 是 100~900，
     * 一一映射即可。
     */
    private fun typefaceFor(weight: Int): Typeface {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            Typeface.create(Typeface.DEFAULT, weight * 100, false)
        } else {
            // P 以下没有可变字重，只能粗/常二选一
            if (weight >= 6) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
        }
    }

    // ------------------------------------------------------------------ 弹幕数据

    /**
     * 追加一条弹幕。
     *
     * @param text 文本
     * @param color 文字颜色（ARGB）
     */
    fun addDanmaku(text: String, color: Int) {
        // 窗口还没测量出宽高时入队会让轨道计算全错，直接丢掉
        if (text.isEmpty() || width == 0) {
            return
        }
        // 已达弹幕量上限：直接丢弃，不进队列。
        // 小窗是副屏场景，少几条弹幕无感，叠轨糊住画面才是问题。
        if (running.size >= maxConcurrent) {
            return
        }
        val limit = pendingLimit()
        while (pending.size >= limit) {
            pending.pollFirst()
        }
        pending.addLast(
            Item(
                text = text,
                color = color,
                width = paint.measureText(text) + strokePaint.strokeWidth * 2,
            )
        )
        invalidate()
    }

    /** 清空所有弹幕：切换房间、关闭弹幕、窗口尺寸变化时调用 */
    fun clearAll() {
        running.clear()
        pending.clear()
        for (i in trackTails.indices) {
            trackTails[i] = null
        }
        lastFrameTime = 0L
        invalidate()
    }

    /** 字号或字重变了要重测排队弹幕的宽度，否则轨道会让位不准 */
    private fun reMeasurePending() {
        if (pending.isEmpty()) {
            // 只在场弹幕受影响时也要清掉：比例已经算不准了
            if (running.isNotEmpty()) {
                running.clear()
                for (i in trackTails.indices) {
                    trackTails[i] = null
                }
            }
            invalidate()
            return
        }
        val rebuilt = ArrayDeque<Item>(pending.size)
        for (item in pending) {
            rebuilt.addLast(
                Item(
                    text = item.text,
                    color = item.color,
                    width = paint.measureText(item.text) + strokePaint.strokeWidth * 2,
                )
            )
        }
        pending.clear()
        pending.addAll(rebuilt)
        running.clear()
        for (i in trackTails.indices) {
            trackTails[i] = null
        }
        invalidate()
    }

    // ------------------------------------------------------------------ 轨道计算

    private fun lineHeight(): Float = fontSizePx * LINE_HEIGHT_RATIO

    /** 弹幕可用高度：受「显示区域」与上下边距共同约束 */
    private fun usableHeight(): Float {
        val density = resources.displayMetrics.density
        val content = height - topMarginDp * density - bottomMarginDp * density
        if (content <= 0f) {
            return height.toFloat()
        }
        return content * area
    }

    private fun trackCount(): Int = max(1, (usableHeight() / lineHeight()).toInt())

    /**
     * 给一条弹幕分配轨道。
     *
     * 规则与播放器弹幕引擎一致：**优先选最靠上的空闲轨道**，
     * 并保证不与前一条追尾——前一条的尾部已经完全进入屏幕，
     * 且两者速度相同，只要那时右边缘离屏有「一条弹幕宽」就不会撞上。
     *
     * @return 轨道序号；没有可用轨道时返回 **-1**，由调用方决定排队还是丢弃。
     *   这里刻意不再「复用最后一轨」：那是重叠的直接来源，
     *   而小窗现在有独立的弹幕量上限，宁可少显示也不要两行字压在一起。
     */
    private fun assignTrack(itemWidth: Float): Int {
        val count = trackCount()
        while (trackTails.size < count) {
            trackTails.add(null)
        }
        while (trackTails.size > count) {
            trackTails.removeAt(trackTails.size - 1)
        }
        for (i in 0 until count) {
            val tail = trackTails[i]
            if (tail == null) {
                return i
            }
            // 前一条的右边缘距屏幕右边还有一条弹幕以上的余量
            val tailRight = tail.x + tail.width
            if (tailRight + itemWidth < width) {
                return i
            }
        }
        // 全忙：交由调用方排队
        return -1
    }

    // ------------------------------------------------------------------ 绘制

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        // 双指缩放会**每一帧**都改窗口尺寸。若每帧都 clearAll()，
        // 整个缩放过程弹幕层始终是空的，还白做一遍列表清空与重绘请求。
        // 只有大幅跳变（「横向占满」这类模式切换，尺寸变化超过 30%）
        // 才重建轨道；小步缩放让现有弹幕继续滚即可 ——
        // 它们的 x 是像素绝对坐标，缩小后只是从屏幕外滚进来，不会错位。
        val structural = oldw <= 0 || abs(w - oldw) > oldw * RESIZE_CLEAR_RATIO
        if (structural) {
            clearAll()
        } else {
            invalidate()
        }
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)

        val now = SystemClock.uptimeMillis()
        val dt = if (lastFrameTime == 0L) 0f else (now - lastFrameTime) / 1000f
        lastFrameTime = now

        val density = resources.displayMetrics.density
        val topBase = topMarginDp * density
        val lh = lineHeight()
        // 速度按「穿过整屏 + 自身宽度」均摊到滚动时长上
        val speed = (width + fontSizePx * 4) / durationSec.coerceAtLeast(1)

        // 1) 推进在场弹幕，移出左边界的回收
        val iterator = running.iterator()
        while (iterator.hasNext()) {
            val item = iterator.next()
            item.x -= speed * dt
            if (item.x + item.width < 0) {
                if (item.track in trackTails.indices &&
                    trackTails[item.track] === item
                ) {
                    trackTails[item.track] = null
                }
                iterator.remove()
            }
        }

        // 2) 排队弹幕尝试入场：
        //    同时受「弹幕量」与「空闲轨道」两个约束，
        //    任一不满足就留在队列里等下一帧——不叠轨，这是不重叠的关键
        while (pending.isNotEmpty() && running.size < maxConcurrent) {
            val next = pending.first()
            val track = assignTrack(next.width)
            if (track < 0) {
                break
            }
            pending.pollFirst()
            next.track = track
            next.x = width.toFloat()
            running.add(next)
            trackTails[track] = next
        }

        // 3) 绘制
        val alpha = (opacity * 255).toInt().coerceIn(0, 255)
        strokePaint.alpha = (alpha * 0.85f).toInt()
        for (item in running) {
            if (item.x > width || item.x + item.width < 0) {
                continue
            }
            val y = topBase + (item.track + 1) * lh
            if (y > height) {
                continue
            }
            // 透明度作用在文字颜色上，而不是 View 的 alpha：
            // View 级 alpha 会触发整层重新合成，代价高得多
            paint.color = item.color
            paint.alpha = alpha
            canvas.drawText(item.text, item.x, y, strokePaint)
            canvas.drawText(item.text, item.x, y, paint)
        }

        // 4) 还有内容就继续请求下一帧，否则停下来（零开销）
        if (running.isNotEmpty() || pending.isNotEmpty()) {
            postInvalidateOnAnimation()
        } else {
            lastFrameTime = 0L
        }
    }

    /**
     * 弹幕层不接收触摸。
     *
     * 拖动 / 双击 / 单击全部由外层 container 处理，
     * 这层必须对事件完全透明，否则会抢走拖动。
     */
    override fun onTouchEvent(event: MotionEvent): Boolean = false

    override fun onDetachedFromWindow() {
        clearAll()
        super.onDetachedFromWindow()
    }
}
