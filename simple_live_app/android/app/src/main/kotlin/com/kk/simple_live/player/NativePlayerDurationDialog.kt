package com.kk.simple_live.player

import android.app.Dialog
import android.content.Context
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.StateListDrawable
import android.text.InputFilter
import android.text.InputType
import android.view.Gravity
import android.view.Window
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView

/** 旧 Flutter Material 3 的 24 小时 inputOnly 形态，不使用系统时间选择器或 OEM 错误弹层。 */
internal class NativePlayerDurationDialog(
    context: Context, private val style: NativePlayerStyle, minutes: Int,
    private val selected: (Int) -> Unit,
) : Dialog(context) {
    private val hour: EditText
    private val minute: EditText
    private val error = style.text("", 12f, style.error).apply { visibility = android.view.View.GONE }

    init {
        requestWindowFeature(Window.FEATURE_NO_TITLE)
        val card = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            background = NativeIcons.background(style.dialogSurface, style.dp(28).toFloat())
            setPadding(style.dp(24), style.dp(24), style.dp(24), style.dp(16))
        }
        card.addView(style.text("输入时间", 14f))
        val inputs = LinearLayout(context).apply { gravity = Gravity.TOP }
        fun number(value: Int, label: String): EditText {
            val field = NativePlayerInput(context, style).apply {
                inputType = InputType.TYPE_CLASS_NUMBER
                filters = arrayOf(InputFilter.LengthFilter(2))
                setText(value.toString().padStart(2, '0'))
                textSize = 45f; gravity = Gravity.CENTER
                setPadding(0, 0, 0, 0); setSelectAllOnFocus(true)
                contentDescription = label
                val focus = NativeIcons.background(style.primaryContainer, style.dp(8).toFloat()).apply {
                    setStroke(style.dp(2), style.primary)
                }
                background = StateListDrawable().apply {
                    addState(intArrayOf(android.R.attr.state_focused), focus)
                    addState(intArrayOf(), NativeIcons.background(style.inputSurface, style.dp(8).toFloat()))
                }
                setOnFocusChangeListener { _, focused ->
                    setTextColor(if (focused) style.onPrimaryContainer else style.foreground)
                }
            }
            inputs.addView(LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                addView(field, LinearLayout.LayoutParams(-1, style.dp(72)))
                addView(style.text(label, 12f, style.secondary).apply {
                    setPadding(style.dp(12), style.dp(8), 0, 0)
                }, LinearLayout.LayoutParams(-1, style.dp(28)))
            }, LinearLayout.LayoutParams(0, -2, 1f))
            return field
        }
        hour = number(minutes / 60, "小时")
        inputs.addView(style.text(":", 45f).apply { gravity = Gravity.CENTER },
            LinearLayout.LayoutParams(style.dp(28), style.dp(72)))
        minute = number(minutes % 60, "分钟")
        card.addView(inputs, LinearLayout.LayoutParams(-1, -2).apply { topMargin = style.dp(20) })
        card.addView(error)
        hour.imeOptions = EditorInfo.IME_ACTION_NEXT
        hour.setOnEditorActionListener { _, action, _ ->
            if (action == EditorInfo.IME_ACTION_NEXT) { minute.requestFocus(); true } else false
        }
        minute.imeOptions = EditorInfo.IME_ACTION_DONE
        minute.setOnEditorActionListener { _, action, _ ->
            if (action == EditorInfo.IME_ACTION_DONE) { confirm(); true } else false
        }
        val actions = LinearLayout(context).apply { gravity = Gravity.END }
        for ((label, accept) in listOf("取消" to false, "确定" to true)) {
            val button = style.text(label, 14f, style.primary).apply {
                gravity = Gravity.CENTER; minWidth = style.dp(64)
                setPadding(style.dp(12), 0, style.dp(12), 0)
            }
            style.click(button) { if (accept) confirm() else dismiss() }
            actions.addView(button, LinearLayout.LayoutParams(-2, style.dp(48)))
        }
        card.addView(actions, LinearLayout.LayoutParams(-1, -2).apply { topMargin = style.dp(12) })
        setContentView(ScrollView(context).apply { isFillViewport = false; addView(card) })
        window?.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
        window?.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE or
            WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_VISIBLE)
        window?.addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
        window?.attributes = window?.attributes?.apply { dimAmount = .54f }
    }

    override fun onStart() {
        super.onStart()
        window?.setLayout(minOf(style.dp(328), context.resources.displayMetrics.widthPixels - style.dp(32)), -2)
        hour.requestFocus()
    }

    private fun confirm() {
        val h = hour.text.toString().toIntOrNull()
        val m = minute.text.toString().toIntOrNull()
        if (h == null || h !in 0..23 || m == null || m !in 0..59) {
            error.text = "请输入有效时间（小时 0–23，分钟 0–59）"
            error.visibility = android.view.View.VISIBLE
            if (h == null || h !in 0..23) hour.requestFocus() else minute.requestFocus()
            return
        }
        // 与旧版相同：00:00 只关闭选择器，不修改时长，也不重启倒计时。
        if (h != 0 || m != 0) selected(h * 60 + m)
        dismiss()
    }
}
