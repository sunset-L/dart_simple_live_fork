package com.kk.simple_live.player

import kotlin.math.abs

/** 复用整页原生重构前的 GetX 4.7.3 + Flutter 3.47.1 Cupertino 路由运动参数。
 * GetPageRoute 默认 300ms，主路由先经过 easeOutQuad，再经过 Cupertino 的
 * fastEaseInToSlowEaseOut；返回使用 flipped 曲线。底层页单独使用 Cupertino 视差曲线。
 * 不影响播放器横竖屏切换动画。
 */
internal object NativePlayerNavigationMotion {
    const val DURATION_MS = 300L
    const val PARALLAX = 1f / 3f

    fun pageProgress(entering: Boolean, time: Float): Float {
        val t = time.coerceIn(0f, 1f)
        // easeOutQuad 在 Flutter 中是贝塞尔曲线，不是直接使用二次方公式。
        // 返回时先求 Q(1-t)，再按 flipped 曲线换算向右推出的距离 F(1-Q(1-t))。
        val routeValue = if (entering) t else 1f - t
        val eased = cubic(routeValue, .25f, .46f, .45f, .94f)
        return fastEaseInToSlowEaseOut(if (entering) eased else 1f - eased).coerceIn(0f, 1f)
    }

    /** 上一页被推开或回位的距离比例（0..1），不共用主页面的曲线。 */
    fun coveredProgress(entering: Boolean, time: Float): Float {
        val t = time.coerceIn(0f, 1f)
        return if (entering) cubic(t, .35f, .91f, .33f, .97f)
        else cubic(1f - t, .67f, .03f, .65f, .09f)
    }

    private fun fastEaseInToSlowEaseOut(t: Float): Float {
        // Flutter ThreePointCubic 的中点 (0.198, 0.541) 及两段归一化控制点。
        return if (t < .198f) {
            cubic(t / .198f, .056f / .198f, .024f / .541f,
                .108f / .198f, .3085f / .541f) * .541f
        } else {
            cubic((t - .198f) / .802f, (.3655f - .198f) / .802f,
                (1f - .541f) / .459f, (.5465f - .198f) / .802f,
                (.989f - .541f) / .459f) * .459f + .541f
        }
    }

    private fun cubic(t: Float, x1: Float, y1: Float, x2: Float, y2: Float): Float {
        if (t <= 0f) return 0f
        if (t >= 1f) return 1f
        fun evaluate(a: Float, b: Float, u: Float): Float {
            val inverse = 1f - u
            return 3f * a * inverse * inverse * u + 3f * b * inverse * u * u + u * u * u
        }
        var low = 0f
        var high = 1f
        var u = t
        // 与 Flutter Cubic 同样按 x 反求贝塞尔参数，误差阈值 0.001。
        repeat(24) {
            u = (low + high) / 2f
            val x = evaluate(x1, x2, u)
            if (abs(t - x) < .001f) return evaluate(y1, y2, u)
            if (x < t) low = u else high = u
        }
        return evaluate(y1, y2, u)
    }
}
