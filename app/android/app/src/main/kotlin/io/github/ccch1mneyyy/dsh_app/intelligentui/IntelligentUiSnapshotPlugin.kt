package io.github.ccch1mneyyy.dsh_app.intelligentui

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.webkit.JavascriptInterface
import android.webkit.RenderProcessGoneDetail
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.ceil
import kotlin.math.roundToInt

/**
 * Renders one intelligent-ui widget in an offscreen WebView and returns a PNG.
 *
 * The share preview and the exported share image are painted by Flutter, so a
 * WebView placed in the widget tree would not appear in `RepaintBoundary.toImage`.
 * This channel draws a WebView into a bitmap instead. The HTML is the same
 * bootstrap the live card uses, so typography and layout come from the same
 * renderer; only the finished bitmap crosses into Flutter.
 */
class IntelligentUiSnapshotPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var activity: Activity? = null
    private val main = Handler(Looper.getMainLooper())
    private val jobs = mutableSetOf<Capture>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also { it.setMethodCallHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        jobs.toList().forEach { it.finish(null) }
        jobs.clear()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "capture" -> {
                val html = call.argument<String>("html")
                val width = call.argument<Int>("width") ?: 0
                if (html.isNullOrBlank() || width <= 0) {
                    result.error("bad_args", "html and width are required", null)
                    return
                }
                val activity = activity
                if (activity == null) {
                    result.error("no_activity", "The app is not attached to an activity", null)
                    return
                }
                main.post {
                    val job = Capture(activity, html, width, result)
                    jobs.add(job)
                    job.start()
                }
            }
            else -> result.notImplemented()
        }
    }

    private inner class Capture(
        private val activity: Activity,
        private val html: String,
        private val logicalWidth: Int,
        private val result: MethodChannel.Result,
    ) {
        private val done = AtomicBoolean(false)
        private val web = WebView(activity)
        private var holder: FrameLayout? = null
        private val timeout = Runnable { finish(null) }

        fun start() {
            val density = activity.resources.displayMetrics.density
            val pxWidth = (logicalWidth * density).roundToInt().coerceIn(120, 2400)
            val parent = activity.findViewById<ViewGroup>(android.R.id.content) ?: return finish(null)
            val frame = FrameLayout(activity).apply {
                alpha = 0f
                translationX = -10000f
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            }
            holder = frame
            parent.addView(frame, ViewGroup.LayoutParams(1, 1))

            web.setBackgroundColor(Color.TRANSPARENT)
            web.setLayerType(View.LAYER_TYPE_SOFTWARE, null)
            web.settings.apply {
                javaScriptEnabled = true
                domStorageEnabled = false
                allowFileAccess = false
                allowContentAccess = false
                blockNetworkLoads = true
                mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
                javaScriptCanOpenWindowsAutomatically = false
                mediaPlaybackRequiresUserGesture = true
                textZoom = 100
                setSupportMultipleWindows(false)
            }
            web.webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean = true
                override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
                    finish(null)
                    return true
                }
            }
            web.addJavascriptInterface(
                object {
                    @JavascriptInterface
                    fun postMessage(raw: String) {
                        if (!raw.contains("\"captureReady\"")) return
                        main.post {
                            if (done.get()) return@post
                            measureAndDraw(pxWidth, density)
                        }
                    }
                },
                "Dsh",
            )
            frame.addView(web, FrameLayout.LayoutParams(pxWidth, 1))
            web.loadDataWithBaseURL(null, html, "text/html", "utf-8", null)
            main.postDelayed(timeout, TIMEOUT_MS)
        }

        private fun measureAndDraw(pxWidth: Int, density: Float) {
            web.evaluateJavascript("Math.ceil(document.documentElement.scrollHeight)") { value ->
                val cssHeight = value?.trim()?.trim('"')?.toFloatOrNull()
                if (cssHeight == null || cssHeight <= 0f) return@evaluateJavascript finish(null)
                val pxHeight = (ceil(cssHeight.toDouble() * density).toInt()).coerceIn(1, MAX_PX_HEIGHT)
                val params = web.layoutParams as FrameLayout.LayoutParams
                params.height = pxHeight
                web.layoutParams = params
                web.measure(
                    View.MeasureSpec.makeMeasureSpec(pxWidth, View.MeasureSpec.EXACTLY),
                    View.MeasureSpec.makeMeasureSpec(pxHeight, View.MeasureSpec.EXACTLY),
                )
                web.layout(0, 0, pxWidth, pxHeight)
                main.postDelayed({
                    if (done.get()) return@postDelayed
                    draw(pxWidth, pxHeight)
                }, DRAW_DELAY_MS)
            }
        }

        private fun draw(width: Int, height: Int) {
            val bitmap = try {
                Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            } catch (_: Throwable) {
                return finish(null)
            }
            try {
                val canvas = Canvas(bitmap)
                canvas.drawColor(Color.TRANSPARENT)
                web.draw(canvas)
                val output = ByteArrayOutputStream()
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)
                finish(output.toByteArray())
            } catch (_: Throwable) {
                finish(null)
            } finally {
                bitmap.recycle()
            }
        }

        fun finish(bytes: ByteArray?) {
            if (!done.compareAndSet(false, true)) return
            main.removeCallbacks(timeout)
            jobs.remove(this)
            runCatching {
                (web.parent as? ViewGroup)?.removeView(web)
                web.stopLoading()
                web.destroy()
            }
            holder?.let { (it.parent as? ViewGroup)?.removeView(it) }
            holder = null
            if (bytes == null) result.error("capture_failed", "Could not render the UI card", null) else result.success(bytes)
        }

        private fun runCatching(block: () -> Unit) {
            try {
                block()
            } catch (_: Throwable) {
            }
        }
    }

    companion object {
        private const val CHANNEL = "dsh/intelligent_ui_snapshot"
        private const val TIMEOUT_MS = 8000L
        private const val DRAW_DELAY_MS = 120L
        private const val MAX_PX_HEIGHT = 12000
    }
}
