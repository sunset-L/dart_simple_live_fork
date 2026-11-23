package com.kk.simple_live

import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.kk.simple_live.player.NativePlayerManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    // 保留 Flutter 默认的 SurfaceView，让系统同步窗口与渲染表面的尺寸交接。
    // 视频仍是 Flutter 外部纹理，不需要把整页 UI 再放进 TextureView。
    private var playerSystemBarsHidden = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 初始化原生播放器（MethodChannel / EventChannel / 纹理输出）
        NativePlayerManager.instance.attach(this, flutterEngine)

        // 供 Dart 侧在 Activity 重建后重新绑定
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "simple_live/activity"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "attachPlayer" -> {
                    NativePlayerManager.instance.attach(this, flutterEngine)
                    result.success(true)
                }
                "setPlayerSystemBarsHidden" -> {
                    val hidden = call.arguments as? Boolean
                    if (hidden == null) {
                        result.error("INVALID_ARGUMENT", "系统栏隐藏状态必须为布尔值", null)
                    } else {
                        playerSystemBarsHidden = hidden
                        applyPlayerSystemBars()
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun applyPlayerSystemBars() {
        // 全屏只改变系统栏可见性，始终保持 edge-to-edge。
        // 不能切到旧式 SystemUiMode.manual：那会先把 decorFitsSystemWindows
        // 改回 true，在旋转期间额外改变 Flutter 窗口和渲染表面的尺寸。
        WindowCompat.setDecorFitsSystemWindows(window, false)
        val controller = WindowCompat.getInsetsController(window, window.decorView)
        if (playerSystemBarsHidden) {
            controller.systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            controller.hide(WindowInsetsCompat.Type.systemBars())
        } else {
            controller.show(WindowInsetsCompat.Type.systemBars())
        }
    }

    override fun onPostResume() {
        super.onPostResume()
        // Flutter 会在此时重应用系统栏配置；全屏回前台后补回隐藏状态。
        if (playerSystemBarsHidden) applyPlayerSystemBars()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        // 只解绑 Activity 引用，不释放播放器：
        // 悬浮窗播放时 Activity 可能重建，播放器必须继续存活。
        NativePlayerManager.instance.detachActivity()
        // 但同时必须把「绑定在这个引擎上」的 Channel / EventSink / 纹理全部清掉。
        // 引擎已经销毁，继续持有那个 sink 会在用户点小窗时往死引擎发消息，
        // 在部分机型上直接闪退。
        NativePlayerManager.instance.detachEngine()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    /**
     * Activity 即将离开前台。
     *
     * 【为什么用 onPause，而不是只认 onUserLeaveHint】
     * 需求是「进入后台就暂停」，只排除两种情况：小窗正在显示、拉通知栏。
     *
     * - 按 Home / 最近任务键：先走 onUserLeaveHint，紧接着走 onPause。
     * - 来电、锁屏：**不**走 onUserLeaveHint，只走 onPause ——
     *   所以只监听 onUserLeaveHint 会漏掉这两类，这正是
     *   「来电和锁屏没暂停」的原因。必须靠 onPause 兜住。
     * - 拉通知栏：不会让 Activity 离开前台，系统不回调 onPause，
     *   天然不受影响，不需要专门判断。
     *
     * 幂等由 NativePlayerManager.onBackground 保证（已暂停就直接返回），
     * 所以两个回调相继触发不会重复处理，也不影响用户手动暂停的状态。
     */
    override fun onPause() {
        super.onPause()
        NativePlayerManager.instance.onBackground()
    }

    /** 用户主动离开（按 Home 键 / 最近任务键），也接一次 */
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        NativePlayerManager.instance.onBackground()
    }

    /** 用户回到前台：把「按 Home 暂停」的播放恢复起来 */
    override fun onResume() {
        super.onResume()
        NativePlayerManager.instance.onUserReturn()
    }
}
