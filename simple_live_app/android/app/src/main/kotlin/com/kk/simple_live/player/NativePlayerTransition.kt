package com.kk.simple_live.player

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.view.View

/** 只在横竖屏交接的短动画中保留视频帧；真实播放器、声音和网络流一直运行。 */
internal class NativePlayerTransition(
    context: Context,
    private var frame: Bitmap?,
    private val source: RectF,
    private val sourceWidth: Int,
    private val sourceHeight: Int,
    private val sourceRotation: Int,
    private val entering: Boolean,
) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
    private var target: RectF? = null
    private var targetRotation = sourceRotation
    private var progress = 0f
    private var animator: ValueAnimator? = null
    init { isClickable = true; isFocusable = true }

    fun start(rect: RectF, rotation: Int, finished: () -> Unit) {
        if (animator != null) return
        target = rect; targetRotation = rotation
        animator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 320L
            // Smootherstep：首尾速度和加速度均为零，中段加速，不延长总时长。
            interpolator = android.animation.TimeInterpolator { input ->
                val t = input.coerceIn(0f, 1f)
                t * t * t * (t * (t * 6f - 15f) + 10f)
            }
            addUpdateListener { progress = it.animatedValue as Float; invalidate() }
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) { finished() }
            })
            start()
        }
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        // 回竖屏时渐露已按最终 insets 排好的页面，底栏不参与缩放或位移。
        paint.color = Color.BLACK
        paint.alpha = if (entering) 255 else ((1f - progress) * 255).toInt()
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), paint)
        paint.alpha = 255
        val bitmap = frame ?: return
        val delta = ((targetRotation - sourceRotation + 6) % 4) - 2
        val angle = -90f * delta
        val sx = source.centerX(); val sy = source.centerY()
        val rotatedX: Float
        val rotatedY: Float
        val rotatedWidth: Int
        val rotatedHeight: Int
        when (delta) {
            1 -> { rotatedX = sy; rotatedY = sourceWidth - sx; rotatedWidth = sourceHeight; rotatedHeight = sourceWidth }
            -1 -> { rotatedX = sourceHeight - sy; rotatedY = sx; rotatedWidth = sourceHeight; rotatedHeight = sourceWidth }
            -2 -> { rotatedX = sourceWidth - sx; rotatedY = sourceHeight - sy; rotatedWidth = sourceWidth; rotatedHeight = sourceHeight }
            else -> { rotatedX = sx; rotatedY = sy; rotatedWidth = sourceWidth; rotatedHeight = sourceHeight }
        }
        val xScale = width.toFloat() / rotatedWidth.coerceAtLeast(1)
        val yScale = height.toFloat() / rotatedHeight.coerceAtLeast(1)
        val startX = rotatedX * xScale; val startY = rotatedY * yScale
        val end = target ?: RectF(startX - source.width()/2, startY - source.height()/2,
            startX + source.width()/2, startY + source.height()/2)
        fun mix(a: Float, b: Float) = a + (b - a) * progress
        val drawWidth = mix(source.width(), end.width())
        val drawHeight = mix(source.height(), end.height())
        canvas.save()
        canvas.translate(mix(startX, end.centerX()), mix(startY, end.centerY()))
        canvas.rotate(angle * (1f - progress))
        canvas.drawBitmap(bitmap, null, RectF(-drawWidth/2, -drawHeight/2, drawWidth/2, drawHeight/2), paint)
        canvas.restore()
    }

    fun dispose() {
        animator?.removeAllListeners(); animator?.cancel(); animator = null
        frame = null
    }
}
