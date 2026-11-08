package com.kk.simple_live.player

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.TimeInterpolator
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.content.res.Configuration
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorFilter
import android.graphics.Matrix
import android.graphics.Outline
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.RadialGradient
import android.graphics.Rect
import android.graphics.Shader
import android.graphics.drawable.Drawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.VelocityTracker
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.view.ViewOutlineProvider
import android.view.WindowInsets
import android.view.WindowManager
import android.view.animation.DecelerateInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * 系统级悬浮窗（浮在桌面与其他应用之上，不是画中画）。
 *
 * 交互设计：
 * - 关闭图标是一个灰白色的叉，无底色，避免糊在画面上显得笨重；
 *   默认隐藏，触摸小窗时淡入，2 秒无操作后淡出。
 * - 轻点小窗 = 回到直播页；拖动 = 移动位置。
 * - 双击小窗 = 在「当前尺寸」与「横向占满」之间切换。
 * - 拖动**允许拖出屏幕边缘**（拖动期间不做边界钳制），松手时再判定：
 *   - 水平方向被拖出超过**一半宽度** → 震动提示 + 半透明蒙版，
 *     松手即关闭小窗并销毁播放实例；
 *   - 否则带动画弹回屏幕内并贴边。
 * - 贴边与横向占满都留出 [EDGE_PADDING_DP] 的边距，不顶到屏幕物理边缘。
 * - 位置在**进程内**记忆（[rememberedX] / [rememberedY]）：
 *   关掉小窗再打开会回到上次的位置；进程被杀后自然失效，无需持久化。
 * - 点击关闭图标 = 结束播放并销毁小窗（由 Dart 侧负责释放播放器实例）。
 */
@SuppressLint("ViewConstructor")
class FloatingPlayerWindow(
    private val context: Context,
    private val manager: NativePlayerManager,
) {

    private enum class EdgeAction { NONE, DOCK, DISMISS }
    private enum class DockSide { LEFT, RIGHT }

    companion object {
        private const val TAG = "FloatingPlayerWindow"

        /** 关闭图标的自动隐藏延时 */
        private const val CLOSE_BUTTON_HIDE_DELAY = 2000L

        /**
         * 按下后延迟多久才显示关闭图标。
         *
         * 双指缩放必然是「第一根手指先落、第二根再落」，两指间隔通常
         * 60~200ms。按下即显示会让叉号在缩放前闪一下，
         * 且淡入动画 + 随即 GONE 的重排会在手势开始的那一刻造成卡顿。
         * 延迟到 180ms 之后，缩放开始时把它取消，叉号就完全不出现。
         */
        private const val CLOSE_BUTTON_SHOW_DELAY = 180L

        /** 双击判定窗口。与播放页 Dart 侧的双击阈值（280ms）保持一致 */
        private const val DOUBLE_TAP_TIMEOUT = 280L

        /** 贴边 / 横向占满时与屏幕边缘保留的间隙 */
        private const val EDGE_PADDING_DP = 6f

        /**
         * 底部最小间隙。
         *
         * 有些系统上报的底部 inset 是 0（手势导航下常见），
         * 此时若只按 [EDGE_PADDING_DP] 摆位，小窗会压在手势条上。
         * 用一个固定下限兜住，保证底部永远有一条缝。
         */
        private const val MIN_BOTTOM_GAP_DP = 24f

        /** 弹回边缘的动画时长 */
        private const val SNAP_ANIM_DURATION = 220L

        /** 判定为拖动的位移阈值 */
        private const val DRAG_SLOP_DP = 6f

        /**
         * 判定为「甩动」的最小松手速度（dp/s）。
         *
         * 低于它就算是普通拖动：松手即停，不做任何惯性。
         * 400dp/s 大致相当于「随手一甩」，比正常拖动收尾的残余速度高得多，
         * 所以慢速挪位不会被误判成甩动。
         */
        private const val FLING_MIN_VELOCITY_DP = 400f

        /** 停住即放置：忽略触点微抖，80ms 无有效位移就不再甩动。 */
        private const val DRAG_STILL_SLOP_DP = 2f
        private const val FLING_HOLD_TIMEOUT_MS = 80L
        /** 正常采样间隔内不衰减；再长的松手间隔逐渐撤销惯性。 */
        private const val FLING_RELEASE_GRACE_MS = 24L

        /**
         * 惯性滑行的距离系数：松手速度每 1 dp/s 对应多少 dp 位移。
         *
         * **必须用 dp/s 而不是 px/s 来算**：VelocityTracker 给的是 px/s，
         * 直接乘系数会让高密度屏滑得离谱（同一台手机上旧写法 1000px/s 就滑 330dp，
         * 一甩就撞到屏幕边，完全没有「扔一点」的中间档）。
         * 0.12 的量级：400dp/s → 48dp（一小段），1500dp/s → 180dp，
         * 3000dp/s 以上才接近半屏。
         */
        private const val FLING_DISTANCE_PER_DP_PER_SEC = 0.12f

        /** 惯性可短暂越界；低于四分之一收起线，且不随大屏无限增加。 */
        private const val FLING_OVERSHOOT_RATIO = 0.18f
        private const val FLING_MAX_OVERSHOOT_DP = 64f

        /**
         * 惯性滑行的动画时长。
         *
         * 按滑行距离伸缩：扔得近就短（才像「滑一下停住」），
         * 扔得远才拉长；固定时长会让短距离显得很拖沓。
         */
        private const val FLING_DURATION_MIN = 160L
        private const val FLING_DURATION_MAX = 520L

        /** 松手后的最小宽度；手势中允许少量阻尼越界。 */
        private const val MIN_WIDTH_DP = 120f
        private const val MIN_PINCH_SPAN_DP = 24f
        private const val PINCH_SLOP_DP = 2f

        /**
         * 拖出边缘多少比例后判定为「要关闭」。
         *
         * 0.5 = 被拖出屏幕外的宽度超过自身宽度的一半。用比例而不是固定 px，
         * 是因为小窗还有「横向占满」形态，固定像素在不同尺寸下松紧不一致。
         */
        private const val DISMISS_THRESHOLD = 0.5f
        private const val DOCK_THRESHOLD = 0.25f
        private const val DOCK_VISIBLE_WIDTH_DP = 28f
        private const val DOCK_RESTORE_DRAG_DP = 24f
        private const val DOCK_ANIM_DURATION = 260L

        /**
         * 提示渐变最浓处的不透明度。
         *
         * 0xCC 而不是 FF：纯红压满会很刺眼，
         * 带一点透明度看起来更像系统级的拖拽提示而不是弹窗。
         * 用户要求「效果不用太重能感知到即可」，这里配合径向扩散，
         * 只有中心一小片是这个浓度，整体观感很轻。
         */
        private const val EDGE_HINT_MAX_ALPHA = 0xCC

        /** 提示渐变淡入 / 淡出时长 */
        private const val EDGE_HINT_ANIM_MS = 120L

        /**
         * 提示光晕的**横向**半径（相对小窗高度）。
         *
         * 光晕是一团**竖椭圆**的径向渐变：圆心贴在屏幕边缘，
         * 横向只往屏幕内扩 0.30 倍小窗高度，纵向拉长到 0.55。
         * 这样它是「从边缘的上下中点向四周扩散」的一团软红晕，
         * 而不是一条等宽的竖条 —— 用户明确说固定宽度不好看。
         */
        private const val EDGE_HINT_RADIUS_X_RATIO = 0.30f

        /** 提示光晕的**纵向**半径（相对小窗高度），比横向长，形成竖椭圆 */
        private const val EDGE_HINT_RADIUS_Y_RATIO = 0.55f

        /** 边缘提示的红色（偏警示但不刺眼，#FF3B30） */
        private const val EDGE_HINT_COLOR = 0xFFFF3B30.toInt()
        private const val EDGE_DOCK_COLOR = 0xFF34C759.toInt()

        /** 越界提示的震动时长（毫秒） */
        private const val VIBRATE_MS = 40L

        /**
         * 上次关闭时的小窗位置（像素）。
         *
         * 放在 companion（静态）里而不是实例字段：`hide()` 之后实例会被
         * [NativePlayerManager] 复用或丢弃，而位置要跨实例保留。
         * 生命周期跟随进程——App 被系统杀掉后自然清零，
         * 这正是需求里「关闭应用后台后位置信息不用处理」的意思。
         */
        private var rememberedX: Int? = null
        private var rememberedY: Int? = null
        private var rememberedDockSide: DockSide? = null

        /**
         * 上次双指缩放后的宽度（像素）。
         *
         * 与位置一样放在静态里，跨实例保留；高度每次按视频比例重新算，
         * 所以只记宽度一个值。null 表示还没缩放过，用调用方给的默认宽度。
         * 生命周期跟随进程——App 进程被杀后自然回到默认尺寸。
         */
        private var rememberedWidthPx: Int? = null
    }

    private val windowManager =
        context.getSystemService(Context.WINDOW_SERVICE) as WindowManager

    private val mainHandler = Handler(Looper.getMainLooper())

    private val density: Float
        get() = context.resources.displayMetrics.density

    private var rootView: FrameLayout? = null
    private var surfaceView: SurfaceView? = null
    private var closeButton: ImageView? = null
    private var dockHandle: ImageView? = null
    private var dockedSide: DockSide? = null
    private var edgeHintColorAnimator: ValueAnimator? = null
    private var edgeHintColor = EDGE_DOCK_COLOR
    private var edgeHintTargetColor = EDGE_DOCK_COLOR
    private var pendingEdgeAction: EdgeAction? = null

    /**
     * 拖动速度采样器，用于松手时的「甩动」判定。
     *
     * 每次 show() 重新 obtain 一份，hide() 时 recycle：
     * 轨迹只在一次手势内有意义，跨手势复用会带着旧样本。
     */
    private var velocityTracker: VelocityTracker? = null

    /**
     * 小窗弹幕层。
     *
     * 只有「我的 → 弹幕设置 → 小窗显示弹幕」打开时才是 `VISIBLE`，
     * 关闭时保持 `GONE`——不绘制、不请求帧，配合 Dart 侧不下发数据，
     * 整条弹幕链路都是零开销（用户明确要求）。
     */
    private var danmakuView: DanmakuOverlayView? = null

    /**
     * 拖出边缘时的绿色收起 / 红色关闭光晕提示。
     *
     * 它是**独立的第二个悬浮窗**，叠在小窗**上层**：
     * - 之所以要独立窗口：光晕要贴到**屏幕**边缘并向外扩散，
     *   而小窗窗口只有小窗那么大，贴不到屏幕边框；且小窗的圆角裁剪会切出硬边。
     * - 之所以要在上层：小窗拖出屏幕边缘时仍有一半留在屏内，
     *   提示在下层就会被小窗画面完全遮住（曾出现过「拖出一半什么都看不到」）。
     *
     * 几何：窗口是一个 **2rx × 2ry 的矩形**（椭圆外接矩形），圆心落在
     * 「屏幕左/右边界 × 小窗竖直中点」上，一半在屏幕外被自然裁掉，
     * 可见部分就是一个从边缘中点向屏幕内扩散的**半椭圆**光晕。
     */
    private var edgeHintView: View? = null
    private var edgeHintParams: WindowManager.LayoutParams? = null

    /** 光晕当前贴哪一侧（null 表示还没定过） */
    private var edgeHintOnLeft: Boolean? = null

    /**
     * 光晕是否处于「已显示」逻辑状态。
     *
     * 用标记位而不是读 `alpha` / `visibility`：`updateEdgeHint()` 每个 MOVE 都调，
     * 淡入途中 alpha 一直 < 1，靠它判断会每帧 cancel 重启动画，淡入永远走不完。
     */
    private var edgeHintShown: Boolean = false

    /** 上次生成渐变时的窗口尺寸，尺寸变了要重建 drawable（半径依赖它） */
    private var edgeHintWidth: Int = 0
    private var edgeHintHeight: Int = 0

    private var params: WindowManager.LayoutParams? = null

    private var screenArea: FloatingWindowArea? = null

    private val screenChangeRunnable = Runnable { repositionAfterScreenChange() }

    private var isShowing: Boolean = false

    /**
     * 小窗当前是否真的挂在屏幕上了。
     *
     * 【为什么需要这个 getter】
     * `NativePlayerManager.floatingWindow` 只在第一次进小窗时创建、
     * 之后**不会再置空**（它是个可复用对象）。所以判断「现在是不是小窗播放」
     * 只看 `floatingWindow != null` 是错的——用户进过一次小窗之后，
     * 那个判断永远为真，导致「离开前台自动暂停」从那一刻起彻底失效。
     * 必须问窗口自己：现在到底显示着没有。
     *
     * 【为什么叫 isWindowShowing 而不是 isShowing】
     * Kotlin 里 `private var isShowing: Boolean` 会自动生成一个
     * 名为 `isShowing()` 的 getter，再声明同名的 `fun isShowing()`
     * 会触发 JVM 签名冲突（Platform declaration clash），编译直接失败。
     */
    fun isWindowShowing(): Boolean = isShowing

    /** 「当前尺寸」模式下的小窗宽高（像素），由 show() 传入的尺寸确定 */
    private var baseWidthPx: Int = 0
    private var baseHeightPx: Int = 0

    /** 是否处于「横向占满」模式 */
    private var isFullWidth: Boolean = false

    /** 正在执行的弹回动画，新的拖动开始时要取消，避免和手指抢位置 */
    private var snapAnimator: ValueAnimator? = null

    /** 拖动 / 缩放的布局更新是否已合并到下一帧 */
    private var pinchLayoutScheduled: Boolean = false

    private val pinchLayoutRunnable = Runnable {
        pinchLayoutScheduled = false
        applyWindowLayout()
    }

    /** 等待确认的单次点击（用于区分双击） */
    private var pendingSingleTap: Runnable? = null

    private val hideCloseRunnable = Runnable {
        closeButton?.animate()?.alpha(0f)?.setDuration(200)?.withEndAction {
            closeButton?.visibility = View.GONE
        }?.start()
    }

    /**
     * 延迟显示关闭按钮。
     *
     * 双指缩放必然是「先一根手指落下、再落第二根」，如果按下就立刻显示，
     * 叉号会在缩放开始前闪一下（并且触发一次淡入动画 + 一次 GONE 重排），
     * 观感就是「显示一下就卡一下」。延迟到第二根手指通常会落下的时间之后，
     * 缩放开始时把它取消掉，叉号就完全不会出现。
     */
    private val showCloseRunnable = Runnable { showCloseButton() }

    fun show(width: Int, height: Int): Boolean {
        if (isShowing) {
            return true
        }
        if (rootView != null) {
            hide()
        }

        val w = (width * density).toInt()
        val h = (height * density).toInt()
        // 上次双指缩放过的尺寸优先：用宽度按当前视频比例反推高度，
        // 保证记住尺寸的同时画面比例永远是对的（换房间换比例也不会变形）。
        val ratio = if (h > 0) w.toFloat() / h.toFloat() else 16f / 9f
        val restoredW = rememberedWidthPx?.let { fitWidth(it) }
        if (restoredW != null && ratio > 0f) {
            baseWidthPx = restoredW
            baseHeightPx = (restoredW / ratio).toInt().coerceAtLeast(1)
        } else {
            baseWidthPx = w
            baseHeightPx = h
        }
        isFullWidth = false
        dockedSide = rememberedDockSide

        screenArea = currentScreenArea()
        val container = object : FrameLayout(context) {
            override fun onConfigurationChanged(newConfig: Configuration) {
                super.onConfigurationChanged(newConfig)
                mainHandler.removeCallbacks(screenChangeRunnable)
                mainHandler.post(screenChangeRunnable)
            }
        }
        container.setBackgroundColor(Color.TRANSPARENT)

        // 视频输出
        val sv = SurfaceView(context)
        // 用不透明格式：视频内容本身不透明，TRANSLUCENT 会让画面偏灰
        sv.holder.setFormat(PixelFormat.OPAQUE)
        sv.setZOrderMediaOverlay(true)
        val svLp = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        )
        container.addView(sv, svLp)

        sv.holder.addCallback(object : SurfaceHolder.Callback {
            override fun surfaceCreated(holder: SurfaceHolder) {
                Log.d(TAG, "floating surfaceCreated")
                manager.attachFloatingSurface(holder.surface)
            }

            override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
                manager.attachFloatingSurface(holder.surface)
            }

            override fun surfaceDestroyed(holder: SurfaceHolder) {
                Log.d(TAG, "floating surfaceDestroyed")
                manager.detachFloatingSurface(holder.surface)
            }
        })

        // 圆角裁切
        container.clipToOutline = true
        container.outlineProvider = object : ViewOutlineProvider() {
            override fun getOutline(view: View, outline: Outline) {
                outline.setRoundRect(0, 0, view.width, view.height, 12f * density)
            }
        }

        // 弹幕层：叠在视频画面之上、关闭按钮之下。
        //
        // 【为什么加在这里】小窗是系统悬浮窗里的 SurfaceView，进小窗时
        // 直播页已经被 pop，Flutter 的弹幕层不复存在，所以弹幕只能在原生画。
        // 见 [DanmakuOverlayView] 的说明。
        //
        // 初始 GONE：是否显示由「我的 → 弹幕设置 → 小窗显示弹幕」决定，
        // 由 [setDanmakuEnabled] 打开。关闭状态下这层不绘制、不请求帧，
        // 也不会有任何弹幕数据被送进来。
        val danmaku = DanmakuOverlayView(context).apply {
            visibility = View.GONE
        }
        val danmakuLp = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        )
        container.addView(danmaku, danmakuLp)
        danmakuView = danmaku

        // 关闭按钮：只有一个灰白色的叉，无底色
        val closeBtn = ImageView(context).apply {
            setImageDrawable(CrossDrawable())
            visibility = View.GONE
            alpha = 0f
            scaleType = ImageView.ScaleType.CENTER_INSIDE
            contentDescription = "关闭小窗"
            setOnClickListener {
                mainHandler.removeCallbacks(hideCloseRunnable)
                manager.onFloatingClosed()
                hide()
            }
        }
        val closeSize = (26 * density).toInt()
        val closeLp = FrameLayout.LayoutParams(
            closeSize,
            closeSize,
            Gravity.TOP or Gravity.END
        )
        val closeMargin = (6 * density).toInt()
        closeLp.setMargins(0, closeMargin, closeMargin, 0)
        container.addView(closeBtn, closeLp)
        closeButton = closeBtn

        // 只覆盖露在屏内的窄条。不可点击的子视图把触摸交给同一套拖动手势。
        val handle = ImageView(context).apply {
            setImageDrawable(DockHandleDrawable())
            setBackgroundColor(0x66202020)
            scaleType = ImageView.ScaleType.CENTER
            visibility = View.GONE
            isClickable = false
            contentDescription = "展开小窗"
        }
        container.addView(handle, FrameLayout.LayoutParams(
            (DOCK_VISIBLE_WIDTH_DP * density).roundToInt(),
            ViewGroup.LayoutParams.MATCH_PARENT,
            Gravity.TOP or Gravity.END,
        ))
        dockHandle = handle

        val windowType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        // 拖出边缘时的绿 / 红光晕提示，**加在小窗上层**。
        //
        // 【为什么必须在上面】
        // 小窗被拖出左/右边缘时，它还有一半留在屏幕内，正好盖住
        // 屏幕边缘那块区域 —— 提示如果在下层，就完全被小窗画面遮住，
        // 表现为「拖出一半却什么都看不到」。
        // 提示本身是 FLAG_NOT_TOUCHABLE，压在小窗上不会影响拖动与点击。
        //
        // 尺寸：先给个占位（椭圆外接矩形），真实宽高在
        // [updateEdgeHint] 里按小窗高度重算。它会被摆在屏幕边缘、
        // 一半跑到屏幕外，留在屏内的半椭圆就是扩散光晕。
        // addView 要等小窗先加上（见下面），才能保证叠在它上面。
        val hintSize = (h * EDGE_HINT_RADIUS_Y_RATIO * 2).toInt()
            .coerceAtLeast((48 * density).toInt())
        val hintLp = WindowManager.LayoutParams(
            hintSize,
            hintSize,
            windowType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 0
            y = 0
        }
        val hint = View(context).apply {
            // 初始不可见：不占绘制，也完全不参与合成
            visibility = View.GONE
            alpha = 0f
        }

        val pad = edgePadding()
        val lp = WindowManager.LayoutParams(
            baseWidthPx,
            baseHeightPx,
            windowType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            // 优先恢复上次的位置（同进程内有效）。
            // 没有记录时才用默认值：**屏幕正中**（水平、垂直都居中）。
            // 以前是「左边贴边 + 距顶 120dp」，一打开就在左上角，观感上像没摆好；
            // 居中更符合「刚进入小窗」的预期，用户拖走后就会记住新位置。
            val rx = rememberedX
            val ry = rememberedY
            val (screenW, screenH) = screenSize()
            // 可用区域：左右各留 pad，底部让开导航栏 / 手势条。
            // 居中是相对**可用区域**居中，而不是相对整屏，
            // 否则在带小白条的机器上会整体偏下。
            val availW = (screenW - pad * 2).coerceAtLeast(baseWidthPx)
            val availH = (screenH - pad - bottomGap()).coerceAtLeast(baseHeightPx)
            x = rx ?: (pad + (availW - baseWidthPx) / 2)
            y = ry ?: (pad + (availH - baseHeightPx) / 2)
        }
        // 初始位置也收敛到屏幕内（上次可能是在「横向占满」形态下关掉的，
        // 现在尺寸变小了，位置要跟着修正）
        clampIntoScreen(lp, animate = false)
        dockedSide?.let { positionAtDock(lp, it) }
        // 收敛后的位置就是本次的实际起点，直接记为「当前记住的位置」，
        // 免得中途异常退出时记的还是旧值
        rememberPosition(lp)

        // 拖动 + 点击 + 双击
        var downX = 0f
        var downY = 0f
        var startX = 0
        var startY = 0
        var dragging = false
        // 只有跨入新的有效档位才震动，不在每个 MOVE 上重复触发。
        var edgeAction = EdgeAction.NONE
        // 收起态本来就超过半宽：恢复操作不能因此直接触发关闭。
        var dragFromDock: DockSide? = null
        val dragSlop = DRAG_SLOP_DP * density

        // 速度采样器：只在一次手势内有意义，每次 show() 换一份新的
        velocityTracker?.recycle()
        val tracker = VelocityTracker.obtain()
        velocityTracker = tracker
        var dragDownTime = 0L
        var lastDragSampleTime = -1L
        var lastDragMotionTime = 0L
        var motionAnchorX = 0f
        var motionAnchorY = 0f
        var lastMotionDx = 0f
        var lastMotionDy = 0f
        val stillSlop = DRAG_STILL_SLOP_DP * density

        fun addDragSample(time: Long, x: Float, y: Float, action: Int = MotionEvent.ACTION_MOVE) {
            if (time <= lastDragSampleTime || velocityTracker !== tracker) return
            lastDragSampleTime = time
            // 停住后再轻微移动，必须从新轨迹起算，不能唤醒停留前的高速样本。
            if (time - lastDragMotionTime >= FLING_HOLD_TIMEOUT_MS) {
                tracker.clear()
                lastMotionDx = 0f
                lastMotionDy = 0f
            }
            val dx = x - motionAnchorX
            val dy = y - motionAnchorY
            if (hypot(dx, dy) >= stillSlop) {
                lastDragMotionTime = time
                motionAnchorX = x
                motionAnchorY = y
                lastMotionDx = dx
                lastMotionDy = dy
            }
            // 新建仅含屏幕坐标的采样事件：窗口跟手移动不会改变速度参考系。
            val sample = MotionEvent.obtain(dragDownTime, time, action, x, y, 0)
            try {
                tracker.addMovement(sample)
            } finally {
                sample.recycle()
            }
        }

        fun recordDragMove(event: MotionEvent) {
            val originX = event.rawX - event.x
            val originY = event.rawY - event.y
            // 保留合批事件中的轨迹，避免低帧率时只剩几个末端采样点。
            for (i in 0 until event.historySize) {
                addDragSample(event.getHistoricalEventTime(i),
                    event.getHistoricalX(i) + originX, event.getHistoricalY(i) + originY)
            }
            addDragSample(event.eventTime, event.rawX, event.rawY)
        }

        // 双指从第二根手指落下时建立基准，只经过一次轻量防抖。
        // 即使只是双指轻触，也不能在抬手时误触单击返回或双击放大。
        var multiTouch = false
        var pinch: FloatingPinchGesture? = null

        fun rawPoints(event: MotionEvent, omitLifted: Boolean = false): List<PinchPoint> {
            val originX = event.rawX - event.getX(0)
            val originY = event.rawY - event.getY(0)
            return (0 until event.pointerCount)
                .filterNot { omitLifted && it == event.actionIndex }
                .map {
                    PinchPoint(event.getPointerId(it), event.getX(it) + originX,
                        event.getY(it) + originY)
                }
        }

        fun beginPinch(points: List<PinchPoint>) {
            cancelSnapAnimation()
            cancelPendingLayoutUpdate()
            if (dockedSide != null) restoreDockedWindow(animate = false)
            dragFromDock = null
            applyWindowLayout()
            val ratio = lp.width.toFloat() / lp.height.coerceAtLeast(1)
            pinch = FloatingPinchGesture(
                PinchBounds(lp.x.toFloat(), lp.y.toFloat(),
                    lp.width.toFloat(), lp.height.toFloat()),
                points, minWindowWidth().toFloat(),
                min(maxWindowWidth().toFloat(), maxWindowHeight() * ratio),
                MIN_PINCH_SPAN_DP * density, PINCH_SLOP_DP * density,
            )
            dragging = false
            edgeAction = EdgeAction.NONE
            tracker.clear()
            cancelShowCloseButton()
            hideCloseButtonImmediately()
            hideEdgeHint()
            cancelPendingSingleTap()
        }

        fun updatePinch(points: List<PinchPoint>) {
            val bounds = pinch?.update(points) ?: return
            val width = bounds.width.roundToInt().coerceAtLeast(1)
            val height = bounds.height.roundToInt().coerceAtLeast(1)
            val x = bounds.x.roundToInt()
            val y = bounds.y.roundToInt()
            if (lp.width == width && lp.height == height && lp.x == x && lp.y == y) return
            if (isFullWidth) {
                isFullWidth = false
                baseWidthPx = lp.width
                baseHeightPx = lp.height
            }
            lp.width = width
            lp.height = height
            lp.x = x
            lp.y = y
            scheduleWindowLayoutUpdate()
        }

        fun finishPinch() {
            if (pinch == null) return
            pinch = null
            cancelPendingLayoutUpdate()
            settleAfterPinch(lp)
        }

        container.setOnTouchListener { _, event ->
            if (event.actionMasked == MotionEvent.ACTION_POINTER_DOWN) {
                multiTouch = true
                if (pinch == null) beginPinch(rawPoints(event))
                return@setOnTouchListener true
            }
            if (multiTouch) {
                when (event.actionMasked) {
                    MotionEvent.ACTION_MOVE -> updatePinch(rawPoints(event))
                    MotionEvent.ACTION_POINTER_UP -> {
                        updatePinch(rawPoints(event))
                        val remaining = rawPoints(event, omitLifted = true)
                        if (remaining.size >= 2) updatePinch(remaining) else finishPinch()
                    }
                    MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                        finishPinch()
                        multiTouch = false
                        scheduleHideCloseButton()
                    }
                }
                return@setOnTouchListener true
            }

            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    // 先接管正在运动的窗口，再捕获拖动基准，避免旧动画抢回位置。
                    cancelSnapAnimation()
                    cancelPendingLayoutUpdate()
                    dragFromDock = dockedSide
                    updateDockHandle()
                    downX = event.rawX
                    downY = event.rawY
                    startX = lp.x
                    startY = lp.y
                    dragging = false
                    edgeAction = EdgeAction.NONE
                    tracker.clear()
                    dragDownTime = event.downTime
                    lastDragSampleTime = event.eventTime - 1
                    lastDragMotionTime = event.eventTime
                    motionAnchorX = event.rawX
                    motionAnchorY = event.rawY
                    lastMotionDx = 0f
                    lastMotionDy = 0f
                    // DOWN 也保留为基准；不能先采样再 clear 掉它。
                    addDragSample(event.eventTime, event.rawX, event.rawY, MotionEvent.ACTION_DOWN)
                    // 不立刻显示叉号：双指缩放必然是「一指先落、第二指再落」，
                    // 立刻显示会在缩放开始前闪一下（淡入动画 + GONE 重排各一次，
                    // 观感就是「显示一下就卡一下」）。延迟一点，缩放开始时取消即可。
                    if (dragFromDock == null) scheduleShowCloseButton()
                    true
                }

                MotionEvent.ACTION_MOVE -> {
                    recordDragMove(event)
                    val dx = event.rawX - downX
                    val dy = event.rawY - downY
                    if (!dragging && (abs(dx) > dragSlop || abs(dy) > dragSlop)) {
                        dragging = true
                        cancelPendingSingleTap()
                        if (dragFromDock == null) showCloseButton()
                    }
                    if (dragging) {
                        // 拖动期间**不做任何边界钳制**：手指可以自由把小窗拖到
                        // 屏幕外，这样靠近边缘时不会「拉不动」。
                        // 越界的后果交给松手时判定（弹回 / 关闭）。
                        lp.x = startX + dx.roundToInt()
                        lp.y = startY + dy.roundToInt()
                        scheduleWindowLayoutUpdate()

                        val originSide = dragFromDock
                        if (originSide != null && edgeOverflow(lp, originSide) < lp.width * DOCK_THRESHOLD) {
                            // 已经拉出到正常拖动区域，之后重新按四分之一 / 二分之一判断。
                            dragFromDock = null
                            dockedSide = null
                            updateDockHandle()
                            showCloseButton()
                        }
                        val nextAction = if (dragFromDock == null) edgeActionFor(lp) else EdgeAction.NONE
                        if (nextAction != edgeAction) {
                            edgeAction = nextAction
                            if (nextAction != EdgeAction.NONE) vibrateDismissHint()
                        }
                        pendingEdgeAction = nextAction
                    }
                    true
                }

                MotionEvent.ACTION_UP -> {
                    if (dragging) {
                        // 松手先落实最后坐标，并撤掉排队的布局，旧帧不能在之后拉回窗口。
                        // UP 的触点离开抖动不参与速度估计。
                        lp.x = startX + (event.rawX - downX).roundToInt()
                        lp.y = startY + (event.rawY - downY).roundToInt()
                        val originSide = dragFromDock
                        if (originSide != null && edgeOverflow(lp, originSide) < lp.width * DOCK_THRESHOLD) {
                            dragFromDock = null
                            dockedSide = null
                            updateDockHandle()
                        }
                        cancelPendingLayoutUpdate()
                        applyWindowLayout()
                    }
                    if (!dragging) {
                        handleTap()
                    } else {
                        edgeAction = EdgeAction.NONE
                        hideEdgeHint()
                        val originSide = dragFromDock
                        if (originSide != null) {
                            val inward = if (originSide == DockSide.LEFT) event.rawX - downX
                                else downX - event.rawX
                            if (inward >= DOCK_RESTORE_DRAG_DP * density) {
                                restoreDockedWindow()
                            } else {
                                dockWindow(lp, originSide)
                            }
                        } else {
                            when (edgeActionFor(lp)) {
                                EdgeAction.DISMISS -> dismissByDrag()
                                EdgeAction.DOCK -> dockWindow(lp, overflowingSide(lp))
                                EdgeAction.NONE -> {
                                    if (!flingByVelocity(lp, tracker,
                                            event.eventTime - lastDragMotionTime, lastMotionDx, lastMotionDy)) {
                                        clampIntoScreen(lp, animate = true)
                                        if (snapAnimator == null) rememberPosition(lp)
                                    }
                                    scheduleHideCloseButton()
                                }
                            }
                        }
                    }
                    dragFromDock = null
                    dragging = false
                    if (velocityTracker === tracker) tracker.clear()
                    true
                }

                MotionEvent.ACTION_CANCEL -> {
                    // 系统打断不触发甩动或关闭，只收回越界部分。
                    edgeAction = EdgeAction.NONE
                    hideEdgeHint()
                    if (dragging || dragFromDock != null) {
                        cancelPendingLayoutUpdate()
                        applyWindowLayout()
                        val originSide = dragFromDock
                        if (originSide != null) {
                            dockWindow(lp, originSide)
                        } else {
                            clampIntoScreen(lp, animate = true)
                            if (snapAnimator == null) rememberPosition(lp)
                            scheduleHideCloseButton()
                        }
                    }
                    dragFromDock = null
                    dragging = false
                    if (velocityTracker === tracker) tracker.clear()
                    true
                }

                else -> false
            }
        }

        return try {
            windowManager.addView(container, lp)
            rootView = container
            surfaceView = sv
            params = lp
            isShowing = true
            updateDockHandle()
            // 提示条在小窗**之后**加，才能叠在它上面（见 hintLp 处的说明）
            try {
                windowManager.addView(hint, hintLp)
                edgeHintView = hint
                edgeHintParams = hintLp
            } catch (e: Exception) {
                Log.w(TAG, "addView edge hint failed: $e")
            }
            true
        } catch (e: Exception) {
            Log.e(TAG, "addView failed: $e")
            surfaceView = null
            rootView = null
            closeButton = null
            dockHandle = null
            dockedSide = null
            params = null
            isShowing = false
            // 小窗没加上，提示条窗口也不能留着
            removeEdgeHint()
            false
        }
    }

    // ------------------------------------------------------------ 点击 / 双击

    /**
     * 处理一次「未拖动」的抬手，区分单击与双击。
     *
     * 单击要等 [DOUBLE_TAP_TIMEOUT] 才能确定不是双击的第一下，
     * 所以回页面这个动作会有 280ms 的延迟——这是支持双击的必然代价。
     */
    private fun handleTap() {
        if (dockedSide != null) {
            restoreDockedWindow()
            return
        }
        val pending = pendingSingleTap
        if (pending != null) {
            // 第二下：双击，取消待执行的单击
            mainHandler.removeCallbacks(pending)
            pendingSingleTap = null
            toggleSize()
            return
        }
        val runnable = Runnable {
            pendingSingleTap = null
            mainHandler.removeCallbacks(hideCloseRunnable)
            hideCloseButtonImmediately()
            manager.onFloatingTap()
        }
        pendingSingleTap = runnable
        mainHandler.postDelayed(runnable, DOUBLE_TAP_TIMEOUT)
    }

    private fun cancelPendingSingleTap() {
        pendingSingleTap?.let { mainHandler.removeCallbacks(it) }
        pendingSingleTap = null
    }

    // ------------------------------------------------------------ 尺寸切换

    /** 在「当前尺寸」与「横向占满」之间切换 */
    private fun toggleSize() {
        if (dockedSide != null) {
            restoreDockedWindow()
            return
        }
        val lp = params ?: return
        val view = rootView ?: return
        if (baseWidthPx <= 0 || baseHeightPx <= 0) {
            return
        }

        val pad = edgePadding()

        if (isFullWidth) {
            lp.width = baseWidthPx
            lp.height = baseHeightPx
        } else {
            val ratio = baseWidthPx.toFloat() / baseHeightPx.toFloat()
            var w = maxWindowWidth()
            var h = (w / ratio).toInt()
            // 竖屏视频铺满宽度后会超出屏幕可用高度，此时改为按高度反推宽度，
            // 保证画面比例不变（比例变了视频会被拉伸变形）。
            // 底部同样要扣掉导航栏 / 手势条，否则铺满形态会压住小白条。
            val maxH = maxWindowHeight()
            if (h > maxH) {
                h = maxH
                w = (h * ratio).toInt()
            }
            lp.width = w.coerceAtLeast(1)
            lp.height = h.coerceAtLeast(1)
        }
        isFullWidth = !isFullWidth

        // 变宽后原来的 x 可能把窗口推到屏幕外，先按新尺寸摆正
        if (isFullWidth) {
            lp.x = pad
        }
        clampIntoScreen(lp, animate = false)

        try {
            windowManager.updateViewLayout(view, lp)
        } catch (e: Exception) {
            Log.w(TAG, "resize failed: $e")
        }
        rememberPosition(lp)
    }

    // ------------------------------------------------------------ 边界处理

    private fun edgePadding(): Int = (EDGE_PADDING_DP * density).toInt()

    /** 窗口允许的最小宽度（像素），见 [MIN_WIDTH_DP] */
    private fun minWindowWidth(): Int = (MIN_WIDTH_DP * density).toInt()

    /**
     * 窗口能占的最大宽度（像素）：屏幕宽度去掉左右边距，就是「横向占满」。
     *
     * 这是松手后要回弹到的目标值，**不是**缩放途中的钳制值——
     * 双指放大过程中允许带阻尼地超出，松手后再弹回来。
     */
    private fun maxWindowWidth(): Int {
        val (screenW, _) = screenSize()
        return (screenW - edgePadding() * 2).coerceAtLeast(minWindowWidth())
    }

    /**
     * 窗口能占的最大高度（像素）：屏幕高度去掉顶部边距与底部手势条。
     *
     * 竖屏视频按宽度放大后会高出屏幕，这时画面再怎么挪都装不下，
     * 所以高度同样有个「最宽松」边界，超出后松手回弹。
     */
    private fun maxWindowHeight(): Int {
        val (_, screenH) = screenSize()
        return (screenH - edgePadding() - bottomGap()).coerceAtLeast(1)
    }

    /**
     * 把宽度收进屏幕可容纳的范围（像素）。
     *
     * 只用在「恢复记忆尺寸 / 换视频比例重算高度」这类需要一次算准的场景；
     * 双指缩放途中**不走这里**，否则放大就被卡在屏幕宽度上、永远看不到回弹。
     */
    private fun fitWidth(px: Int): Int {
        return px.coerceIn(minWindowWidth(), maxWindowWidth())
    }

    /**
     * 底部实际需要让出的高度（导航栏 / 手势条，如魅族小白条）。
     *
     * 本窗口带 [WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS]，
     * 系统**不会**替它避让系统栏，底部完全靠自己让位；只留 [EDGE_PADDING_DP]
     * 那 6dp 的话，小白条会直接压在小窗画面上。
     *
     * 取值来源：
     * - Android 11+：取 navigationBars 与 systemGestures 两类 inset 的较大者。
     *   三键导航只报前者；全屏手势部分 ROM 只在后者里报底部手势区。
     * - 更低版本：读 `navigation_bar_height` 资源（拿不到就当 0）。
     * - 都取不到时退化为 [MIN_BOTTOM_GAP_DP] 的固定间距，
     *   保证底部始终留出一条可见的缝，不会贴死屏幕物理边缘。
     */
    private fun bottomGap(): Int {
        val fromSystem = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val insets = windowManager.currentWindowMetrics.windowInsets
            max(
                insets.getInsetsIgnoringVisibility(WindowInsets.Type.navigationBars()).bottom,
                insets.getInsetsIgnoringVisibility(WindowInsets.Type.systemGestures()).bottom
            )
        } else {
            val res = context.resources
            val resId = res.getIdentifier("navigation_bar_height", "dimen", "android")
            if (resId > 0) res.getDimensionPixelSize(resId) else 0
        }
        val fixed = (MIN_BOTTOM_GAP_DP * density).toInt()
        return max(fromSystem + edgePadding(), fixed)
    }

    /** 屏幕可用尺寸（含系统栏区域，悬浮窗坐标以此为基准） */
    private fun screenSize(): Pair<Int, Int> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bounds = windowManager.currentWindowMetrics.bounds
            bounds.width() to bounds.height()
        } else {
            val dm = context.resources.displayMetrics
            dm.widthPixels to dm.heightPixels
        }
    }

    private fun currentScreenArea(): FloatingWindowArea {
        val (screenWidth, screenHeight) = screenSize()
        val padding = edgePadding()
        return FloatingWindowArea(
            left = padding,
            top = padding,
            width = (screenWidth - padding * 2).coerceAtLeast(1),
            height = (screenHeight - padding - bottomGap()).coerceAtLeast(1),
        )
    }

    private fun repositionAfterScreenChange() {
        if (!isShowing) {
            return
        }
        val lp = params ?: return
        val previousArea = screenArea ?: return
        val area = currentScreenArea()
        if (area == previousArea) {
            return
        }
        cancelPendingLayoutUpdate()
        cancelPendingSingleTap()
        cancelSnapAnimation()
        hideEdgeHint()
        val placement = repositionFloatingWindow(
            FloatingWindowPlacement(lp.x, lp.y, lp.width, lp.height),
            previousArea,
            area,
            isFullWidth,
        )
        lp.x = placement.x
        lp.y = placement.y
        lp.width = placement.width
        lp.height = placement.height
        if (!isFullWidth) {
            baseWidthPx = placement.width
            baseHeightPx = placement.height
        }
        screenArea = area
        dockedSide?.let { positionAtDock(lp, it) }
        updateDockHandle()
        applyWindowLayout()
        rememberPosition(lp)
    }

    private fun edgeOverflow(lp: WindowManager.LayoutParams, side: DockSide): Int {
        val (screenW, _) = screenSize()
        return if (side == DockSide.LEFT) (-lp.x).coerceAtLeast(0)
            else (lp.x + lp.width - screenW).coerceAtLeast(0)
    }

    private fun overflowingSide(lp: WindowManager.LayoutParams): DockSide =
        if (edgeOverflow(lp, DockSide.LEFT) >= edgeOverflow(lp, DockSide.RIGHT)) DockSide.LEFT
        else DockSide.RIGHT

    /** 松手时用精确阈值：四分之一（含）到一半（含）收起，超过一半关闭。 */
    private fun edgeActionFor(lp: WindowManager.LayoutParams): EdgeAction {
        val out = edgeOverflow(lp, overflowingSide(lp))
        return when {
            out > lp.width * DISMISS_THRESHOLD -> EdgeAction.DISMISS
            out >= lp.width * DOCK_THRESHOLD -> EdgeAction.DOCK
            else -> EdgeAction.NONE
        }
    }

    private fun dockVisibleWidth(lp: WindowManager.LayoutParams): Int =
        (DOCK_VISIBLE_WIDTH_DP * density).roundToInt().coerceIn(1, lp.width.coerceAtLeast(1))

    private fun dockX(lp: WindowManager.LayoutParams, side: DockSide): Int {
        val (screenW, _) = screenSize()
        val visible = dockVisibleWidth(lp)
        return if (side == DockSide.LEFT) visible - lp.width else screenW - visible
    }

    private fun dockY(lp: WindowManager.LayoutParams): Int {
        val (_, screenH) = screenSize()
        val pad = edgePadding()
        return lp.y.coerceIn(pad, (screenH - lp.height - bottomGap()).coerceAtLeast(pad))
    }

    private fun positionAtDock(lp: WindowManager.LayoutParams, side: DockSide) {
        lp.x = dockX(lp, side)
        lp.y = dockY(lp)
    }

    private fun dockWindow(lp: WindowManager.LayoutParams, side: DockSide) {
        cancelPendingLayoutUpdate()
        cancelPendingSingleTap()
        hideCloseButtonImmediately()
        hideEdgeHint()
        dockedSide = side
        updateDockHandle(animate = true)
        animateTo(lp, dockX(lp, side), dockY(lp), DOCK_ANIM_DURATION, DecelerateInterpolator(1.6f))
    }

    private fun restoreDockedWindow(animate: Boolean = true) {
        val lp = params ?: return
        val side = dockedSide ?: return
        cancelPendingLayoutUpdate()
        cancelPendingSingleTap()
        hideCloseButtonImmediately()
        hideEdgeHint()
        val (screenW, _) = screenSize()
        val pad = edgePadding()
        val x = if (side == DockSide.LEFT) pad else (screenW - lp.width - pad).coerceAtLeast(pad)
        val y = dockY(lp)
        if (!animate) {
            cancelSnapAnimation()
            lp.x = x
            lp.y = y
            dockedSide = null
            updateDockHandle()
            applyWindowLayout()
            rememberPosition(lp)
            return
        }
        // 动画完成前仍保留收起态；中途再按住也不能把半露出的窗口误判为关闭。
        dockHandle?.animate()?.cancel()
        dockHandle?.animate()?.alpha(0f)?.setDuration(EDGE_HINT_ANIM_MS)?.start()
        animateTo(lp, x, y, DOCK_ANIM_DURATION, DecelerateInterpolator(1.6f)) {
            dockedSide = null
            updateDockHandle()
        }
    }

    private fun updateDockHandle(animate: Boolean = false) {
        val handle = dockHandle ?: return
        val side = dockedSide
        handle.animate().cancel()
        if (side == null) {
            handle.visibility = View.GONE
            handle.alpha = 0f
            return
        }
        hideCloseButtonImmediately()
        val layout = handle.layoutParams as FrameLayout.LayoutParams
        layout.width = params?.let { dockVisibleWidth(it) }
            ?: (DOCK_VISIBLE_WIDTH_DP * density).roundToInt()
        layout.gravity = Gravity.TOP or (if (side == DockSide.LEFT) Gravity.END else Gravity.START)
        handle.layoutParams = layout
        handle.rotation = if (side == DockSide.LEFT) 0f else 180f
        val wasVisible = handle.visibility == View.VISIBLE
        handle.visibility = View.VISIBLE
        if (animate && !wasVisible) {
            handle.alpha = 0f
            handle.animate().alpha(1f).setDuration(EDGE_HINT_ANIM_MS).start()
        } else {
            handle.alpha = 1f
        }
    }

    /** 进程内记住当前位置，供下次 show() 恢复 */
    private fun rememberPosition(lp: WindowManager.LayoutParams) {
        rememberedX = lp.x
        rememberedY = lp.y
        rememberedDockSide = dockedSide
    }

    /**
     * 越界时的震动提示。
     *
     * 优先用系统 Vibrator（带 VIBRATE 权限，力度可感知）：
     * 悬浮窗是没有用户交互焦点的窗口，`View.performHapticFeedback`
     * 在这种窗口里经常被系统忽略（尤其是 MIUI / EMUI 这类定制 ROM）。
     * 拿不到 Vibrator 时再退回 haptic feedback 兜底。
     */
    private fun vibrateDismissHint() {
        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE)
                as? android.os.VibratorManager)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as? android.os.Vibrator
        }
        if (vibrator != null && vibrator.hasVibrator()) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    vibrator.vibrate(
                        android.os.VibrationEffect.createOneShot(
                            VIBRATE_MS,
                            android.os.VibrationEffect.DEFAULT_AMPLITUDE
                        )
                    )
                } else {
                    @Suppress("DEPRECATION")
                    vibrator.vibrate(VIBRATE_MS)
                }
                return
            } catch (e: Exception) {
                Log.w(TAG, "vibrate failed: $e")
            }
        }
        val view = rootView ?: return
        try {
            view.performHapticFeedback(
                HapticFeedbackConstants.LONG_PRESS,
                HapticFeedbackConstants.FLAG_IGNORE_GLOBAL_SETTING
            )
        } catch (e: Exception) {
            Log.w(TAG, "haptic feedback failed: $e")
        }
    }

    /**
     * 更新拖出边缘时的绿色收起 / 红色关闭光晕提示。
     *
     * 几何关系（用户明确定义）：
     * - 光晕中心 = **屏幕边缘这条线的上下中点**（不是小窗中心）；
     * - 从该中心向上下、向屏幕内侧一起扩散，形成一个**竖的半椭圆**光晕；
     * - 纵向跟小窗一起移动（中心取小窗的竖直中点，与小窗高度重合）。
     *
     * 【为什么窗口要按椭圆外接矩形开，而不是贴一条窄带】
     * 径向渐变是按窗口矩形铺的。如果窗口只有十几 dp 宽，
     * 渐变会被这个窄条裁成一根竖线，看起来就是「固定宽度的条」——
     * 这正是上一版不好看的原因。
     * 现在窗口按**椭圆的外接矩形**（2rx × 2ry）开，圆心放在
     * 「屏幕左/右边界、小窗竖直中点」，椭圆一半跑到屏幕外被自然裁掉，
     * 留在屏内的那半就是「从边缘中点向四周扩散」的软红晕。
     *
     * @param action 松手动作：绿色收起、红色关闭，NONE 时淡出。
     */
    private fun updateEdgeHint(lp: WindowManager.LayoutParams, action: EdgeAction) {
        val hint = edgeHintView ?: return
        val hintLp = edgeHintParams ?: return
        if (action == EdgeAction.NONE) {
            hideEdgeHint()
            return
        }
        val (screenW, _) = screenSize()

        // 浓的一侧 = 小窗露出去更多的那一边。
        // 两侧都没越界时按小窗中心预判，这样刚开始拖就能定好方向（但不显示）。
        val outLeft = -lp.x
        val outRight = lp.x + lp.width - screenW
        val onLeft = when {
            outLeft > 0 || outRight > 0 -> outLeft >= outRight
            else -> lp.x + lp.width / 2 < screenW / 2
        }

        // 椭圆半径按小窗高度算，跟着小窗尺寸走：
        // 横向窄、纵向长 —— 竖椭圆，观感是「一团晕」而不是「一根条」。
        val rx = (lp.height * EDGE_HINT_RADIUS_X_RATIO)
            .toInt().coerceAtLeast((24 * density).toInt())
        val ry = (lp.height * EDGE_HINT_RADIUS_Y_RATIO)
            .toInt().coerceAtLeast(rx)

        // 窗口就是椭圆的外接矩形，圆心正好落在窗口中心
        hintLp.width = rx * 2
        hintLp.height = ry * 2
        // 纵向：圆心对准小窗竖直中点（跟随小窗上下移动）
        hintLp.y = lp.y + lp.height / 2 - ry
        // 横向：圆心落在屏幕左边界 / 右边界上 ——
        // 于是椭圆有一半在屏幕外，可见的那半就是向屏幕内扩散的光晕。
        hintLp.x = if (onLeft) -rx else (screenW - rx)

        val targetColor = if (action == EdgeAction.DISMISS) EDGE_HINT_COLOR else EDGE_DOCK_COLOR
        val changedSide = edgeHintOnLeft != null && edgeHintOnLeft != onLeft
        // 第一次亮起直接使用当前档位颜色；绿 / 红切换从正在显示的颜色续接。
        setEdgeHintColor(targetColor, animate = hint.alpha > 0.01f && !changedSide)
        // 方向或尺寸变了才重建 drawable
        if (edgeHintOnLeft != onLeft ||
            edgeHintWidth != hintLp.width ||
            edgeHintHeight != hintLp.height
        ) {
            edgeHintOnLeft = onLeft
            edgeHintWidth = hintLp.width
            edgeHintHeight = hintLp.height
            hint.background = buildEdgeHintDrawable(rx.toFloat(), ry.toFloat())
        }

        try {
            windowManager.updateViewLayout(hint, hintLp)
        } catch (e: Exception) {
            Log.w(TAG, "updateViewLayout edge hint failed: $e")
            return
        }

        showEdgeHint()
    }

    /**
     * 造一个**竖椭圆**的可变色径向渐变，作为向四周扩散的光晕。
     *
     * 做法：先在正圆上建 [RadialGradient]，再用 [Matrix] 对 shader 做
     * **非等比缩放**（仅 Y 轴放大 ry/rx），圆就被拉成竖椭圆。
     * 不用 `GradientDrawable` 的 OVAL：它的径向 shader 半径只按单一方向算，
     * 椭圆的长轴会超出半径而整段透明，只剩中间一块 —— 等于又退回「一根条」。
     *
     * 三档不透明度：圆心 0xCC，中途约 0x51，边缘全透明。
     * 两档会在过渡上留一圈生硬的边界，中间那档不能省。
     *
     * @param rx 横向半径（像素）
     * @param ry 纵向半径（像素）
     */
    private fun buildEdgeHintDrawable(rx: Float, ry: Float): Drawable {
        return EdgeGlowDrawable(edgeHintColor, EDGE_HINT_MAX_ALPHA, rx, ry)
    }

    /**
     * 贴边光晕：竖椭圆径向渐变。
     *
     * 独立成 Drawable 而不是用 `GradientDrawable`，是因为后者没法把
     * 径向渐变拉成椭圆（见 [buildEdgeHintDrawable] 的说明）。
     */
    private class EdgeGlowDrawable(
        private var color: Int,
        private val maxAlpha: Int,
        private val radiusX: Float,
        private val radiusY: Float,
    ) : Drawable() {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG)

        fun setGlowColor(value: Int) {
            if (color == value) return
            color = value
            onBoundsChange(bounds)
            invalidateSelf()
        }

        override fun onBoundsChange(bounds: Rect) {
            val cx = bounds.exactCenterX()
            val cy = bounds.exactCenterY()
            val sx = radiusX.coerceAtLeast(1f)
            val sy = radiusY.coerceAtLeast(sx)

            val rgb = color and 0x00FFFFFF
            val midAlpha = (maxAlpha * 0.35f).toInt()
            val shader = RadialGradient(
                cx, cy, sx,
                intArrayOf(
                    (maxAlpha shl 24) or rgb,
                    (midAlpha shl 24) or rgb,
                    rgb, // alpha = 0，最外圈完全透明
                ),
                floatArrayOf(0f, 0.45f, 1f),
                Shader.TileMode.CLAMP
            )
            // 只放大 Y 轴：圆 → 竖椭圆
            val matrix = Matrix()
            matrix.setScale(1f, sy / sx, cx, cy)
            shader.setLocalMatrix(matrix)
            paint.shader = shader
        }

        override fun draw(canvas: Canvas) {
            val b = bounds
            canvas.drawOval(b.left.toFloat(), b.top.toFloat(), b.right.toFloat(), b.bottom.toFloat(), paint)
        }

        override fun setAlpha(alpha: Int) {
            paint.alpha = alpha
        }

        override fun setColorFilter(colorFilter: ColorFilter?) {
            paint.colorFilter = colorFilter
        }

        @Deprecated("Deprecated in Java")
        override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
    }

    private fun setEdgeHintColor(target: Int, animate: Boolean) {
        if (!animate) {
            edgeHintColorAnimator?.cancel()
            edgeHintColorAnimator = null
            edgeHintColor = target
            edgeHintTargetColor = target
            (edgeHintView?.background as? EdgeGlowDrawable)?.setGlowColor(target)
            return
        }
        if (edgeHintTargetColor == target) return
        edgeHintColorAnimator?.cancel()
        edgeHintTargetColor = target
        val start = edgeHintColor
        val animator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = EDGE_HINT_ANIM_MS
            addUpdateListener { animation ->
                val t = animation.animatedValue as Float
                fun channel(from: Int, to: Int) = (from + (to - from) * t).roundToInt()
                edgeHintColor = Color.rgb(
                    channel(Color.red(start), Color.red(target)),
                    channel(Color.green(start), Color.green(target)),
                    channel(Color.blue(start), Color.blue(target)),
                )
                (edgeHintView?.background as? EdgeGlowDrawable)?.setGlowColor(edgeHintColor)
            }
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    if (edgeHintColorAnimator === animation) edgeHintColorAnimator = null
                }
            })
        }
        edgeHintColorAnimator = animator
        animator.start()
    }

    private fun showEdgeHint() {
        val hint = edgeHintView ?: return
        // 幂等：本方法每个 MOVE 都会被调用一次，用标记位挡住重复触发。
        // 不能拿 alpha 判断——淡入过程中 alpha 一直 < 1，
        // 每帧 cancel + 重启会让淡入永远走不完。
        if (edgeHintShown) return
        edgeHintShown = true
        hint.animate()?.cancel()
        if (hint.visibility != View.VISIBLE) {
            hint.visibility = View.VISIBLE
            hint.alpha = 0f
        }
        hint.animate().alpha(1f).setDuration(EDGE_HINT_ANIM_MS).start()
    }

    private fun hideEdgeHint() {
        pendingEdgeAction = null
        val hint = edgeHintView ?: return
        if (!edgeHintShown) return
        edgeHintShown = false
        hint.animate()?.cancel()
        hint.animate().alpha(0f).setDuration(EDGE_HINT_ANIM_MS).withEndAction {
            // 期间可能又被重新拖出边缘，重新显示过就别藏了
            if (!edgeHintShown) {
                hint.visibility = View.GONE
                edgeHintColorAnimator?.cancel()
                edgeHintColorAnimator = null
            }
        }.start()
    }

    private fun removeEdgeHint() {
        pendingEdgeAction = null
        edgeHintColorAnimator?.cancel()
        edgeHintColorAnimator = null
        val hint = edgeHintView ?: return
        try {
            windowManager.removeView(hint)
        } catch (e: Exception) {
            Log.w(TAG, "removeView edge hint failed: $e")
        }
        edgeHintView = null
        edgeHintParams = null
        edgeHintOnLeft = null
        edgeHintShown = false
        // 尺寸缓存一起清掉：下次 show() 尺寸可能不同，必须重建 drawable
        edgeHintWidth = 0
        edgeHintHeight = 0
    }

    /**
     * 被拖出边缘后松手：关闭小窗并销毁播放实例。
     *
     * 执行顺序很重要：
     * 1. 先 hide() 把窗口和蒙版拆掉——播放器还要往 SurfaceView 上送帧，
     *    窗口先走可以让 detachFloatingSurface 正常生效；
     * 2. 再 onFloatingClosed() 让播放器与 Dart 侧一起收尾。
     * 反过来会让已移除的表面还挂着输出，出现一帧灰屏。
     */
    private fun dismissByDrag() {
        cancelPendingSingleTap()
        hideCloseButtonImmediately()
        // 拖丢时窗口坐标在屏幕外，不能当「上次的位置」记住，
        // 否则下次打开会贴在边缘而不是用户上次的可见位置。
        hide(rememberPos = false)
        manager.onFloatingClosed()
    }

    /**
     * 把窗口位置收敛到屏幕内，并留出边距。
     *
     * 左右与顶部用 [EDGE_PADDING_DP]；底部用 [bottomGap]，
     * 额外让开导航栏 / 手势条，否则小窗会盖住小白条。
     *
     * 超出边缘时「贴边」——正好停在边距线上，而不是弹回原来位置。
     */
    private fun clampIntoScreen(lp: WindowManager.LayoutParams, animate: Boolean) {
        val (screenW, screenH) = screenSize()
        val pad = edgePadding()
        val bottom = bottomGap()

        val maxX = (screenW - lp.width - pad).coerceAtLeast(pad)
        val maxY = (screenH - lp.height - bottom).coerceAtLeast(pad)

        val targetX = lp.x.coerceIn(pad, maxX)
        val targetY = lp.y.coerceIn(pad, maxY)
        if (lp.x == targetX && lp.y == targetY) {
            return
        }
        if (!animate) {
            lp.x = targetX
            lp.y = targetY
            return
        }
        animateTo(lp, targetX, targetY)
    }

    /**
     * 双指缩放松手后的收尾：把窗口收敛回「最宽松」的可容纳范围。
     *
     * 缩放途中允许带阻尼的临时放大，所以松手这一刻
     * 窗口很可能比屏幕还宽/还高，或者整体伸到了屏幕外。这里统一收敛：
     * - 尺寸超过 [maxWindowWidth] / [maxWindowHeight]：按手势开始时的宽高比缩回来，
     *   比例不变，画面不会变形；
     * - 位置以缩放后的中心点为基准收回去（观感像从中间缩进来），再钳进边距；
     * - 有变化就走一次动画，不瞬跳——瞬跳在视觉上就是「闪一下」。
     */
    private fun settleAfterPinch(lp: WindowManager.LayoutParams) {
        val pad = edgePadding()
        val (screenW, screenH) = screenSize()
        val maxW = maxWindowWidth()
        val maxH = maxWindowHeight()

        val ratio = if (lp.height > 0) lp.width.toFloat() / lp.height.toFloat() else 16f / 9f
        // 先同时满足宽/高上限，再设置下限；极端竖屏比例也不能挤出安全区。
        val fitMaxW = min(maxW, (maxH * ratio).toInt()).coerceAtLeast(1)
        val tw = lp.width.coerceIn(minWindowWidth().coerceAtMost(fitMaxW), fitMaxW)
        val th = (tw / ratio).roundToInt().coerceAtLeast(1)

        var tx = lp.x + (lp.width - tw) / 2
        var ty = lp.y + (lp.height - th) / 2
        tx = tx.coerceIn(pad, (screenW - tw - pad).coerceAtLeast(pad))
        ty = ty.coerceIn(pad, (screenH - th - bottomGap()).coerceAtLeast(pad))

        if (tw == lp.width && th == lp.height && tx == lp.x && ty == lp.y) {
            // 没越界：直接落定，不做动画（本来就没动，动画反而多一帧抖动）
            commitPinchSettle(lp)
            return
        }
        animateBounds(lp, tw, th, tx, ty)
    }

    /** 缩放收尾「不需要动画」时的一次性落定 */
    private fun commitPinchSettle(lp: WindowManager.LayoutParams) {
        val view = rootView ?: return
        cancelSnapAnimation()
        // 落定后这一刻的尺寸就是用户认可的尺寸：
        // 同时写进静态记忆（下次打开沿用）与 base（双击切换的基准）。
        rememberedWidthPx = lp.width
        baseWidthPx = lp.width
        baseHeightPx = lp.height
        try {
            windowManager.updateViewLayout(view, lp)
        } catch (e: Exception) {
            Log.w(TAG, "pinch settle failed: $e")
        }
        rememberPosition(lp)
    }

    /**
     * 尺寸 + 位置一起做缓动，用于「放大超出屏幕后回弹」。
     *
     * 不能只动位置：越界的本质是尺寸太大，只挪位置还是装不下。
     * 也不能只动尺寸：以左上角为基准收缩会让窗口整体往上左跑，
     * 所以位置要同步插值到收敛后的目标点。
     *
     * 时长按超出比例略微拉长（最多两倍 [SNAP_ANIM_DURATION]）：
     * 只超一点点时应该「啪」地弹回，超得越多才越需要一点过程感。
     */
    private fun animateBounds(
        lp: WindowManager.LayoutParams,
        targetW: Int,
        targetH: Int,
        targetX: Int,
        targetY: Int,
    ) {
        val view = rootView ?: return
        cancelSnapAnimation()
        val startW = lp.width
        val startH = lp.height
        val startX = lp.x
        val startY = lp.y
        val over = max(
            (startW - targetW).toFloat() / targetW.coerceAtLeast(1),
            (startH - targetH).toFloat() / targetH.coerceAtLeast(1)
        ).coerceIn(0f, 1f)
        val animator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = (SNAP_ANIM_DURATION * (1f + over)).toLong()
            interpolator = DecelerateInterpolator(1.6f)
            addUpdateListener { a ->
                val f = a.animatedValue as Float
                lp.width = (startW + (targetW - startW) * f).toInt()
                lp.height = (startH + (targetH - startH) * f).toInt()
                lp.x = (startX + (targetX - startX) * f).toInt()
                lp.y = (startY + (targetY - startY) * f).toInt()
                try {
                    windowManager.updateViewLayout(view, lp)
                } catch (_: Exception) {
                    // 动画途中窗口被移除是正常情况
                }
            }
            addListener(object : AnimatorListenerAdapter() {
                // 动画途中被用户按下打断（ACTION_DOWN 会 cancel）：此时窗口停在
                // 插值中间态，lp 里就是那一帧的尺寸，**不能**再强推成目标值，
                // 否则下一次 updateViewLayout 会让窗口毫无过渡地跳一下。
                var canceled = false

                override fun onAnimationCancel(animation: Animator) {
                    canceled = true
                }

                override fun onAnimationEnd(animation: Animator) {
                    if (snapAnimator === animation) {
                        snapAnimator = null
                    }
                    if (rootView == null) {
                        return
                    }
                    if (canceled) {
                        // 中间态已经是合法范围（收敛只会变小），直接拿它当记忆值
                        rememberedWidthPx = lp.width
                        baseWidthPx = lp.width
                        baseHeightPx = lp.height
                        rememberPosition(lp)
                        return
                    }
                    // 动画最后一帧可能因为取整差一两像素，这里补成精确值
                    lp.width = targetW
                    lp.height = targetH
                    lp.x = targetX
                    lp.y = targetY
                    rememberedWidthPx = targetW
                    baseWidthPx = targetW
                    baseHeightPx = targetH
                    rememberPosition(lp)
                }
            })
        }
        snapAnimator = animator
        animator.start()
    }

    /** 带缓动的位移，做出「弹回」的手感 */
    private fun animateTo(
        lp: WindowManager.LayoutParams,
        targetX: Int,
        targetY: Int,
        durationMs: Long = SNAP_ANIM_DURATION,
        interpolator: TimeInterpolator? = null,
        onComplete: (() -> Unit)? = null,
    ) {
        val view = rootView ?: return
        cancelSnapAnimation()
        val startX = lp.x
        val startY = lp.y
        val animator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = durationMs
            // 不传就用 ValueAnimator 默认的加速减速曲线（弹回手感）
            if (interpolator != null) {
                this.interpolator = interpolator
            }
            addUpdateListener { a ->
                val f = a.animatedValue as Float
                lp.x = startX + ((targetX - startX) * f).toInt()
                lp.y = startY + ((targetY - startY) * f).toInt()
                try {
                    windowManager.updateViewLayout(view, lp)
                } catch (_: Exception) {
                    // 窗口可能已被移除，忽略
                }
            }
            // 弹回结束后的落点才是「用户认可的位置」，记下来供下次 show() 恢复
            addListener(object : android.animation.AnimatorListenerAdapter() {
                private var canceled = false
                override fun onAnimationCancel(animation: Animator) {
                    canceled = true
                }

                override fun onAnimationEnd(animation: android.animation.Animator) {
                    if (snapAnimator === animation) {
                        snapAnimator = null
                    }
                    if (rootView != null) {
                        if (!canceled) {
                            lp.x = targetX
                            lp.y = targetY
                            applyWindowLayout()
                            onComplete?.invoke()
                        }
                        rememberPosition(lp)
                    }
                }
            })
        }
        snapAnimator = animator
        animator.start()
    }

    private fun cancelSnapAnimation() {
        snapAnimator?.cancel()
        snapAnimator = null
    }

    /**
     * 把窗口布局更新推迟到下一个渲染帧，且每帧最多一次。
     *
     * 触摸采样率普遍高于刷新率（120~240Hz，部分机型更高），
     * 而单指拖动和双指缩放都是**每个触摸事件**回调一次。
     * 若在回调里直接 `updateViewLayout`，一帧内会做两到四次
     * measure/layout/draw，主线程被塞满，缩放就永远慢半拍——
     * 这正是「不跟手」的来源，而不是坐标算错。
     *
     * 这里只在第一帧排一次任务，后续回调刷新 [params] 里的目标值即可，
     * 帧回调拿到的永远是最新值，中间值本来也不需要画出来。
     */
    private fun scheduleWindowLayoutUpdate() {
        if (pinchLayoutScheduled) {
            return
        }
        val view = rootView
        if (view == null) {
            return
        }
        pinchLayoutScheduled = true
        view.postOnAnimation(pinchLayoutRunnable)
    }

    private fun applyWindowLayout() {
        val p = params ?: return
        val view = rootView ?: return
        try {
            windowManager.updateViewLayout(view, p)
            // 光晕跟小窗使用同一帧的几何，避免快速拖动时颜色与位置错开。
            pendingEdgeAction?.let { updateEdgeHint(p, it) }
        } catch (e: Exception) {
            // 手势途中窗口被移除（拖出关闭 / 退出播放）是正常情况
            Log.w(TAG, "pinch layout failed: $e")
        }
    }

    private fun cancelPendingLayoutUpdate() {
        if (pinchLayoutScheduled) {
            rootView?.removeCallbacks(pinchLayoutRunnable)
            pinchLayoutScheduled = false
        }
    }

    /**
     * 按松手速度做惯性滑行。
     *
     * 需求语义：
     * - **快速甩动**松手 → 沿甩动方向继续滑一段距离再停下；
     * - **普通拖动或停留后**松手 → 原地放置，仅越界时返回合法范围。
     *
     * 实现要点：
     * - 速度用统一屏幕坐标采样，停留超时直接取消，末端停顿先衰减再判阈值；
     *   低于阈值就当普通拖动，避免慢速收尾也被判成甩动；
     * - 滑行距离与速度成正比，方向取松手时的速度矢量，
     *   斜着甩就斜着滑，符合直觉；
     * - 每条轴独立计算惯性落点，允许短暂越界，再回到合法停留范围。
     *   最大化时横向没有停留空间，也不能因此取消纵向惯性。
     * - 惯性不触发边缘提示、收起或关闭，这些动作仍只看手指松手位置。
     *
     * @return true 表示已开始滑行动画
     */
    private fun flingByVelocity(
        lp: WindowManager.LayoutParams,
        tracker: VelocityTracker,
        idleMillis: Long,
        recentDx: Float,
        recentDy: Float,
    ): Boolean {
        // 停留意图优先于速度估计，即使没有新的 MOVE 事件也照常识别。
        if (idleMillis >= FLING_HOLD_TIMEOUT_MS) return false
        val (screenW, screenH) = screenSize()
        val pad = edgePadding()
        val maxX = (screenW - lp.width - pad).coerceAtLeast(pad)
        val maxY = (screenH - lp.height - bottomGap()).coerceAtLeast(pad)
        val releaseFactor = 1f - (
            (idleMillis - FLING_RELEASE_GRACE_MS).coerceAtLeast(0L).toFloat() /
                (FLING_HOLD_TIMEOUT_MS - FLING_RELEASE_GRACE_MS)
            ).coerceIn(0f, 1f)
        val maxVelocity =
            ViewConfiguration.get(context).scaledMaximumFlingVelocity.toFloat()
        tracker.computeCurrentVelocity(1000, maxVelocity)
        val vx = tracker.xVelocity * releaseFactor * releaseFactor
        val vy = tracker.yVelocity * releaseFactor * releaseFactor
        // VelocityTracker 在样本不足时可能给出 NaN
        if (!vx.isFinite() || !vy.isFinite()) {
            return false
        }
        // 速度方向必须与最后一段有效位移一致，拒绝末端拟合出的反向速度。
        if (vx * recentDx + vy * recentDy <= 0f) return false
        val speed = hypot(vx, vy)
        if (speed < FLING_MIN_VELOCITY_DP * density) {
            return false
        }
        // 速度先换成 dp/s 再算距离：px/s 直接乘系数会随屏幕密度放大，
        // 高密度屏上一甩就飞到底（这正是「扔不出一小段」的根因）。
        val speedDp = speed / density
        val distancePx = speedDp * FLING_DISTANCE_PER_DP_PER_SEC * density
        // 方向取单位速度矢量，斜甩斜滑
        val dirX = vx / speed
        val dirY = vy / speed
        // 合法停留范围和惯性途中的活动范围分开。铺满宽度时 pad == maxX，
        // 若直接把目标钳在这里，横向速度会消失，轻微斜拖还会连纵向一起被拦截。
        val overshootX = min(lp.width * FLING_OVERSHOOT_RATIO,
            FLING_MAX_OVERSHOOT_DP * density).roundToInt()
        val overshootY = min(lp.height * FLING_OVERSHOOT_RATIO,
            FLING_MAX_OVERSHOOT_DP * density).roundToInt()
        val edgeLimit = (lp.width * DOCK_THRESHOLD).toInt().minus(1).coerceAtLeast(0)
        // 始终包含当前点：已经略越界时，不能把惯性的第一段反向拉回去。
        // 新增的横向惯性位移不越过四分之一线；当前点更靠外则先不再向外扩。
        val minFlingX = max(pad - overshootX, -edgeLimit).coerceAtMost(lp.x)
        val maxFlingX = min(maxX + overshootX, screenW - lp.width + edgeLimit)
            .coerceAtLeast(lp.x)
        val minFlingY = (pad - overshootY).coerceAtMost(lp.y)
        val maxFlingY = (maxY + overshootY).coerceAtLeast(lp.y)
        val targetX = (lp.x + dirX * distancePx).roundToInt().coerceIn(minFlingX, maxFlingX)
        val targetY = (lp.y + dirY * distancePx).roundToInt().coerceIn(minFlingY, maxFlingY)
        if (targetX == lp.x && targetY == lp.y) {
            return false
        }
        // 按实际滑行距离计算时长，不让被边界裁掉的距离拖长动画。
        val actualDistance = hypot((targetX - lp.x).toFloat(), (targetY - lp.y).toFloat())
        val duration =
            (FLING_DURATION_MIN + actualDistance / density * 0.9f).toLong().coerceIn(
                FLING_DURATION_MIN,
                FLING_DURATION_MAX,
            )
        // 减速曲线：一开始快、越滑越慢，最后停住
        animateTo(
            lp,
            targetX,
            targetY,
            duration,
            DecelerateInterpolator(1.6f),
        ) {
            // 同一次惯性先沿释放方向滑行，再收回越界部分；不调用收起/关闭判定。
            // 用户重新按住时 animateTo 会取消后续回弹，继续从当前画面跟手移动。
            if (dockedSide == null) clampIntoScreen(lp, animate = true)
        }
        return true
    }

    // ------------------------------------------------------------ 关闭图标

    /** 显示关闭图标（淡入）并安排自动隐藏 */
    private fun showCloseButton() {
        if (dockedSide != null) return
        val btn = closeButton ?: return
        mainHandler.removeCallbacks(showCloseRunnable)
        mainHandler.removeCallbacks(hideCloseRunnable)
        if (btn.visibility != View.VISIBLE) {
            btn.visibility = View.VISIBLE
            btn.alpha = 0f
        }
        btn.animate().alpha(1f).setDuration(150).start()
        scheduleHideCloseButton()
    }

    /**
     * 延迟显示关闭图标。
     *
     * 只在按下时排一次，第二根手指落下（缩放）或手势结束时取消，
     * 这样普通点击 / 拖动仍然会看到叉号，双指缩放则完全不闪。
     */
    private fun scheduleShowCloseButton() {
        mainHandler.removeCallbacks(showCloseRunnable)
        mainHandler.postDelayed(showCloseRunnable, CLOSE_BUTTON_SHOW_DELAY)
    }

    private fun cancelShowCloseButton() {
        mainHandler.removeCallbacks(showCloseRunnable)
    }

    private fun scheduleHideCloseButton() {
        mainHandler.removeCallbacks(hideCloseRunnable)
        mainHandler.postDelayed(hideCloseRunnable, CLOSE_BUTTON_HIDE_DELAY)
    }

    private fun hideCloseButtonImmediately() {
        mainHandler.removeCallbacks(showCloseRunnable)
        mainHandler.removeCallbacks(hideCloseRunnable)
        closeButton?.animate()?.cancel()
        closeButton?.alpha = 0f
        closeButton?.visibility = View.GONE
    }

    fun hide(rememberPos: Boolean = true) {
        mainHandler.removeCallbacks(screenChangeRunnable)
        mainHandler.removeCallbacks(hideCloseRunnable)
        mainHandler.removeCallbacks(showCloseRunnable)
        // 还排着的缩放帧更新必须撤掉：窗口马上要被移除，
        // 让它跑一次只会撞上「View not attached to window manager」
        cancelPendingLayoutUpdate()
        cancelPendingSingleTap()
        cancelSnapAnimation()
        // 速度采样器跟着窗口一起归还：窗口没了就不再需要轨迹
        velocityTracker?.recycle()
        velocityTracker = null
        // 位置要在窗口真正移除**之前**记下来：
        // 关闭小窗（点叉 / 退回页面）都要能回到同一位置，
        // 这正是需求「应用打开的周期内，小窗应保留关闭时的位置」。
        // 拖出边缘丢弃时传 false——那个坐标在屏幕外，不能当地点用。
        if (rememberPos) {
            params?.let { rememberPosition(it) }
        }
        // 提示条是独立窗口，必须跟着一起移除，否则会在屏幕边缘留一条红边
        removeEdgeHint()
        val view = rootView ?: return
        try {
            surfaceView?.let { manager.detachFloatingSurface(it.holder.surface) }
            windowManager.removeView(view)
        } catch (e: Exception) {
            Log.w(TAG, "removeView failed: $e")
        }
        rootView = null
        surfaceView = null
        closeButton = null
        dockHandle = null
        dockedSide = null
        danmakuView = null
        params = null
        isShowing = false
        isFullWidth = false
    }

    // ---------------------------------------------------------------- 小窗弹幕

    /**
     * 开关小窗弹幕显示。
     *
     * 关闭时把视图置 `GONE` 并清空已在跑的弹幕：
     * `GONE` 的 View 不参与绘制、`onDraw` 不会被调用，
     * 配合 Dart 侧停止下发数据，整条链路零开销。
     *
     * @return 真实生效的开关状态（视图还没建时返回 false）
     */
    fun setDanmakuEnabled(enabled: Boolean): Boolean {
        val view = danmakuView ?: return false
        view.visibility = if (enabled) View.VISIBLE else View.GONE
        if (!enabled) {
            view.clearAll()
        }
        return true
    }

    /** 是否有可用的弹幕层（小窗已显示且视图已创建） */
    fun hasDanmakuView(): Boolean = danmakuView != null

    /**
     * 同步弹幕样式。
     *
     * 参数全部来自「我的 → 弹幕设置 → 小窗弹幕设置」，
     * 与播放器弹幕是两套互不影响的配置
     * （小窗画面小、轨道少，播放器那套值搬进来会糊满画面）。
     */
    fun updateDanmakuOptions(
        fontSize: Float,
        fontWeight: Int,
        opacity: Float,
        area: Float,
        duration: Int,
        topMargin: Float,
        bottomMargin: Float,
        maxConcurrent: Int,
    ) {
        danmakuView?.applyOptions(
            fontSizeSp = fontSize,
            fontWeightValue = fontWeight,
            opacityValue = opacity,
            areaValue = area,
            durationValueSec = duration,
            topMargin = topMargin,
            bottomMargin = bottomMargin,
            maxConcurrentValue = maxConcurrent,
        )
    }

    /**
     * 追加一条弹幕。
     *
     * 关闭小窗弹幕时直接丢弃——这里再挡一次，
     * 避免 Dart 侧与原生侧的开关状态因为时序问题出现短暂不一致时白跑测量。
     */
    fun addDanmaku(text: String, color: Int) {
        val view = danmakuView ?: return
        if (view.visibility != View.VISIBLE) {
            return
        }
        view.addDanmaku(text, color)
    }

    /** 清空当前所有弹幕（切换房间、拖出边缘前等场景） */
    fun clearDanmaku() {
        danmakuView?.clearAll()
    }

    fun updateSize(width: Int, height: Int) {
        val lp = params ?: return
        val view = rootView ?: return
        cancelSnapAnimation()
        cancelPendingLayoutUpdate()
        val w = (width * density).toInt()
        val h = (height * density).toInt()
        // 用户双指缩放过就以那次为准：这里只是「按新视频比例重算高度」，
        // 不能把宽度也一起打回调用方给的默认值，否则缩放白做了。
        val ratio = if (h > 0) w.toFloat() / h.toFloat() else 16f / 9f
        val restored = rememberedWidthPx?.let { fitWidth(it) }
        if (restored != null && ratio > 0f) {
            baseWidthPx = restored
            baseHeightPx = (restored / ratio).toInt().coerceAtLeast(1)
        } else {
            baseWidthPx = w
            baseHeightPx = h
        }
        if (!isFullWidth) {
            lp.width = baseWidthPx
            lp.height = baseHeightPx
        }
        clampIntoScreen(lp, animate = false)
        dockedSide?.let { positionAtDock(lp, it) }
        updateDockHandle()
        try {
            windowManager.updateViewLayout(view, lp)
        } catch (e: Exception) {
            Log.w(TAG, "resize failed: $e")
        }
        rememberPosition(lp)
    }

    private class DockHandleDrawable : Drawable() {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            style = Paint.Style.STROKE
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }
        override fun draw(canvas: Canvas) {
            val cx = bounds.exactCenterX()
            val cy = bounds.exactCenterY()
            val size = bounds.width() * 0.14f
            paint.strokeWidth = (bounds.width() * 0.075f).coerceAtLeast(1f)
            canvas.drawLine(cx - size, cy - size * 1.8f, cx + size, cy, paint)
            canvas.drawLine(cx + size, cy, cx - size, cy + size * 1.8f, paint)
        }
        override fun setAlpha(alpha: Int) { paint.alpha = alpha; invalidateSelf() }
        override fun setColorFilter(filter: ColorFilter?) { paint.colorFilter = filter; invalidateSelf() }
        @Deprecated("Deprecated in Java")
        override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
    }

    /**
     * 一个灰白色的叉。
     *
     * 之前是一个深色实心圆（GradientDrawable OVAL），既没有叉的形状，
     * 又像个黑点糊在画面上。这里改回最朴素的叉形：
     * 先用深灰画一条略粗的底线，再叠一条浅灰白色的线，
     * 形成一圈细描边——这样在亮画面（白墙、雪景）和暗画面上都看得清。
     * 不用 setShadowLayer：它需要软件层渲染，在硬件加速的悬浮窗里不生效。
     */
    private inner class CrossDrawable : Drawable() {

        private val stroke = 2f * density

        private val shadowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeCap = Paint.Cap.ROUND
            strokeWidth = stroke + 2f * density
            color = Color.parseColor("#80000000")
        }

        private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeCap = Paint.Cap.ROUND
            strokeWidth = stroke
            color = Color.parseColor("#E8EAED")
        }

        override fun draw(canvas: Canvas) {
            val inset = stroke + 3f * density
            val l = bounds.left + inset
            val t = bounds.top + inset
            val r = bounds.right - inset
            val b = bounds.bottom - inset
            if (r <= l || b <= t) {
                return
            }
            canvas.drawLine(l, t, r, b, shadowPaint)
            canvas.drawLine(r, t, l, b, shadowPaint)
            canvas.drawLine(l, t, r, b, paint)
            canvas.drawLine(r, t, l, b, paint)
        }

        override fun setAlpha(alpha: Int) {
            paint.alpha = alpha
            shadowPaint.alpha = (alpha * 0.5f).toInt()
            invalidateSelf()
        }

        override fun setColorFilter(colorFilter: ColorFilter?) {
            paint.colorFilter = colorFilter
            shadowPaint.colorFilter = colorFilter
            invalidateSelf()
        }

        @Deprecated("Deprecated in Java")
        override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
    }
}
