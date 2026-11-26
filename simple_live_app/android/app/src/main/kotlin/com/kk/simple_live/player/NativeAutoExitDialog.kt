package com.kk.simple_live.player

import android.app.Dialog
import android.content.Context
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.Gravity
import android.view.Window
import android.view.WindowManager
import android.widget.LinearLayout

/** 对照旧 AutoExitDialog：不可返回/点外部关闭，10 秒后退出应用，仅“关闭直播”和“延迟”。 */
internal class NativeAutoExitDialog(
    context: Context,
    private val style: NativePlayerStyle,
    private val selected: (String) -> Unit,
) : Dialog(context) {
    private val handler = Handler(Looper.getMainLooper())
    private val deadline = SystemClock.elapsedRealtime() + 10_000L
    private var finished = false
    private var focused = false
    private val countdown = style.text("10 秒后关闭应用", 16f)
    private val tick = object : Runnable {
        override fun run() {
            if (finished || !focused || !isShowing) return
            val remaining = deadline - SystemClock.elapsedRealtime()
            if (remaining <= 0) { finish("exitApplication"); return }
            countdown.text = "${(remaining + 999) / 1000} 秒后关闭应用"
            handler.postDelayed(this, minOf(remaining, 1000L))
        }
    }

    init {
        requestWindowFeature(Window.FEATURE_NO_TITLE)
        setCancelable(false)
        setCanceledOnTouchOutside(false)
        val card = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            background = NativeIcons.background(style.dialogSurface, style.dp(28).toFloat())
            setPadding(style.dp(24), style.dp(24), style.dp(24), style.dp(16))
        }
        card.addView(style.text("定时关闭", 24f))
        card.addView(countdown, LinearLayout.LayoutParams(-1, -2).apply {
            topMargin = style.dp(16); bottomMargin = style.dp(16)
        })
        val actions = LinearLayout(context).apply { gravity = Gravity.END }
        for ((label, action) in listOf("关闭直播" to "closeLive", "延迟" to "delay")) {
            val button = style.text(label, 14f, style.primary).apply {
                gravity = Gravity.CENTER; minWidth = style.dp(64)
                setPadding(style.dp(12), 0, style.dp(12), 0)
            }
            style.click(button) { finish(action) }
            actions.addView(button, LinearLayout.LayoutParams(-2, style.dp(48)))
        }
        card.addView(actions)
        setContentView(card)
        window?.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
        window?.addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
        window?.attributes = window?.attributes?.apply { dimAmount = .54f }
    }

    override fun onStart() {
        super.onStart()
        // 旧 AlertDialog 按内容收紧，这段短文案落在默认 280dp；不要按大屏上限撑满。
        window?.setLayout(minOf(style.dp(280),
            (context.resources.displayMetrics.widthPixels - style.dp(80)).coerceAtLeast(1)), -2)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        focused = hasFocus
        handler.removeCallbacks(tick)
        // 后台不跑倒计时刷新，回来按绝对截止时间恢复，不凭空延长 10 秒提示。
        if (hasFocus) tick.run()
    }

    private fun finish(action: String) {
        if (finished) return
        finished = true
        handler.removeCallbacks(tick)
        selected(action)
        dismiss()
    }

    override fun onStop() {
        focused = false
        handler.removeCallbacks(tick)
        super.onStop()
    }
}
