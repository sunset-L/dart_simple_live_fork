package com.kk.simple_live.player

import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.max

internal data class PinchPoint(val id: Int, val x: Float, val y: Float)

internal data class PinchBounds(
    val x: Float,
    val y: Float,
    val width: Float,
    val height: Float,
)

/**
 * 纯几何双指手势：屏幕坐标、稳定 pointer ID、触点中心锚定。
 * 不锁横/竖轴；平移不乘缩放增益，斜向张合与中途换指也不跳窗。
 */
internal class FloatingPinchGesture(
    initial: PinchBounds,
    points: List<PinchPoint>,
    minWidth: Float,
    maxWidth: Float,
    private val minSpan: Float,
    private val touchSlop: Float,
) {
    private val upper = maxWidth.coerceAtLeast(1f)
    private val lower = minWidth.coerceIn(1f, upper)
    private val shrinkAllowance = lower * 0.15f
    // 临时放大用于看清小字：允许最多额外一倍宽度，松手范围仍由 upper 决定。
    private val expansionAllowance = upper
    private var origin = initial
    private var first = points[0]
    private var second = points[1]
    private var activated = false
    var bounds = initial
        private set

    /** points 只包含仍按着的手指；多余手指不影响当前缩放。 */
    fun update(points: List<PinchPoint>): PinchBounds {
        if (points.size < 2) return bounds
        val a = points.firstOrNull { it.id == first.id }
        val b = points.firstOrNull { it.id == second.id }
        if (a == null || b == null) {
            // 主手指抬起：保留仍在场的手指，再补一根，重建基准不改画面。
            val remaining = a ?: b ?: points[0]
            first = remaining
            second = points.first { it.id != remaining.id }
            origin = bounds
            activated = false
            return bounds
        }
        val startSpan = hypot(second.x - first.x, second.y - first.y)
        val span = hypot(b.x - a.x, b.y - a.y)
        val startFocusX = (first.x + second.x) / 2f
        val startFocusY = (first.y + second.y) / 2f
        val focusX = (a.x + b.x) / 2f
        val focusY = (a.y + b.y) / 2f
        if (!activated) {
            if (abs(span - startSpan) < touchSlop &&
                hypot(focusX - startFocusX, focusY - startFocusY) < touchSlop
            ) return bounds
            activated = true
        }
        // 两指过近时只限制增益，不能直接替换起始距离，否则起手就会跳变。
        val deltaWidth = origin.width * (span - startSpan) / max(startSpan, minSpan)
        val width = resist(unresist(origin.width) + deltaWidth)
        val scale = width / origin.width
        bounds = PinchBounds(
            x = focusX - (startFocusX - origin.x) * scale,
            y = focusY - (startFocusY - origin.y) * scale,
            width = width,
            height = origin.height * scale,
        )
        return bounds
    }

    // 边界内完全线性；放大越界后柔和增阻，宽度渐近正常上限的两倍。
    // 同时保留缩小越界的反馈，反向捏合立即响应，不做硬截断。
    private fun resist(width: Float): Float = when {
        width < lower -> lower - rubber(lower - width, shrinkAllowance)
        width > upper -> upper + rubber(width - upper, expansionAllowance)
        else -> width
    }

    private fun rubber(distance: Float, limit: Float): Float =
        limit * distance / (limit + distance)

    // 换指或打断回弹时可能已在阻尼区，反算原始尺寸，避免重复阻尼导致跳变。
    private fun unresist(width: Float): Float = when {
        width < lower -> lower - unrubber(lower - width, shrinkAllowance)
        width > upper -> upper + unrubber(width - upper, expansionAllowance)
        else -> width
    }

    private fun unrubber(distance: Float, limit: Float): Float {
        val safeDistance = distance.coerceAtMost(limit * 0.999f)
        return limit * safeDistance / (limit - safeDistance)
    }
}
