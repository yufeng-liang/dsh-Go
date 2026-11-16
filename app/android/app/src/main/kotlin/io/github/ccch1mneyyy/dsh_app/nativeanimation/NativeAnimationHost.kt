package io.github.ccch1mneyyy.dsh_app.nativeanimation

import android.annotation.SuppressLint
import android.app.Activity
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.PorterDuff
import android.graphics.RectF
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.SystemClock
import android.view.MotionEvent
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.VelocityTracker
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.widget.FrameLayout
import io.flutter.embedding.android.FlutterView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs
import kotlin.math.roundToInt

/** Activity-local surfaces above Flutter, with one worker owning their buffers and clocks. */
class NativeAnimationHost(private val activity: Activity, messenger: BinaryMessenger) {
    private val main = Handler(Looper.getMainLooper())
    private val thread = HandlerThread("dsh-animation").apply { start() }
    private val worker = Handler(thread.looper)
    private val channel = MethodChannel(messenger, "dsh/native_animation")
    private val layers = mutableMapOf<Int, Layer>()
    private var resumed = false
    private var closed = false
    private var firstResume = true

    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "isAvailable" -> result.success(true)
                    "upsert" -> upsert(call.arguments as Map<*, *>, result)
                    "remove" -> {
                        val id = (call.argument<Number>("id") ?: error("Missing surface id")).toInt()
                        layers[id]?.let { layer ->
                            layer.cancelTouch()
                            layers.remove(id)
                            (layer.parent as? ViewGroup)?.removeView(layer)
                            worker.post { layer.node.dispose() }
                        }
                        result.success(null)
                    }
                    "metrics" -> {
                        val nodes = layers.values.map { it.node }
                        worker.post { val metrics = nodes.map { it.metrics() }; main.post { result.success(metrics) } }
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                result.error("native_animation_config", "Invalid native animation configuration", null)
            }
        }
    }

    private fun flutterView(): FlutterView? {
        fun find(view: View): FlutterView? {
            if (view is FlutterView) return view
            if (view is ViewGroup) for (i in 0 until view.childCount) find(view.getChildAt(i))?.let { return it }
            return null
        }
        return find(activity.findViewById(android.R.id.content))
    }

    private fun upsert(config: Map<*, *>, result: MethodChannel.Result) {
        check(!closed)
        val id = config.number("id").toInt()
        // Occlusion can hide an existing layer without resending its image or restarting playback.
        if (config["kind"] == null && config["visible"] == false) {
            layers[id]?.let { layer ->
                layer.cancelTouch()
                layer.visibility = View.INVISIBLE
                worker.post { layer.node.setForeground(false) }
            }
            result.success(null)
            return
        }
        val width = config.number("width").roundToInt()
        val height = config.number("height").roundToInt()
        require(width > 0 && height > 0)
        val flutter = flutterView() ?: error("Flutter view is not attached")
        val content = activity.findViewById<ViewGroup>(android.R.id.content)
        val fp = IntArray(2)
        val cp = IntArray(2)
        flutter.getLocationInWindow(fp)
        content.getLocationInWindow(cp)
        val layer = layers.getOrPut(id) {
            Layer(id).also { activity.addContentView(it, FrameLayout.LayoutParams(1, 1)) }
        }
        val left = (config.number("x") + fp[0] - cp[0]).roundToInt()
        val top = (config.number("y") + fp[1] - cp[1]).roundToInt()
        val old = layer.layoutParams as FrameLayout.LayoutParams
        if (old.width != width || old.height != height || old.leftMargin != left || old.topMargin != top) {
            layer.layoutParams = FrameLayout.LayoutParams(width, height).apply { leftMargin = left; topMargin = top }
        }
        val visible = config.flag("visible", true) && config.number("alpha", 1.0) > 0
        if (!visible) layer.cancelTouch()
        layer.visibility = if (visible) View.VISIBLE else View.INVISIBLE
        layer.acceptsTouch = visible && config["hitRect"] != null
        val active = resumed && visible
        worker.post {
            try {
                layer.node.configure(config, active)
                main.post { result.success(null) }
            } catch (error: Exception) {
                layer.node.stop()
                val message = if (error is IllegalArgumentException || error is IllegalStateException) error.message else null
                main.post {
                    layer.visibility = View.INVISIBLE
                    result.error("native_animation_config", message ?: "Native animation could not be configured", mapOf("reason" to error.javaClass.simpleName))
                }
            }
        }
    }

    fun resume() {
        resumed = true
        if (firstResume) { firstResume = false; channel.invokeMethod("reset", null) }
        layers.values.forEach { layer -> val visible = layer.visibility == View.VISIBLE; worker.post { layer.node.setForeground(visible) } }
    }
    fun pause() {
        resumed = false
        layers.values.forEach { layer -> layer.cancelTouch(); worker.post { layer.node.setForeground(false) } }
    }
    fun close() {
        if (closed) return
        val removed = layers.values.toList()
        removed.forEach { it.cancelTouch() }
        closed = true
        channel.setMethodCallHandler(null)
        layers.clear()
        removed.forEach { (it.parent as? ViewGroup)?.removeView(it) }
        worker.post { removed.forEach { it.node.dispose() }; thread.quitSafely() }
    }

    private fun event(id: Int, type: String, values: Map<String, Any?> = emptyMap()) {
        val deliver = Runnable { if (!closed && layers.containsKey(id)) channel.invokeMethod("event", mapOf("id" to id, "type" to type) + values) }
        if (Looper.myLooper() == Looper.getMainLooper()) deliver.run() else main.post(deliver)
    }

    private data class Hit(val rect: RectF, val clip: RectF, val origin: MotionPoint, val offset: MotionPoint)

    private inner class Layer(val animationId: Int) : SurfaceView(activity), SurfaceHolder.Callback {
        val node = Node(this)
        @Volatile var hit: Hit? = null
        var acceptsTouch = false
        @Volatile var surfaceReady = false
        private var held = false
        private var dragging = false
        private var longPressed = false
        private var downX = 0f
        private var downY = 0f
        private var lastX = 0f
        private var lastY = 0f
        private var downEvent: MotionEvent? = null
        private var velocity: VelocityTracker? = null
        private val slop = 6 * resources.displayMetrics.density
        private val longPress = Runnable {
            if (held && !dragging) {
                longPressed = true
                downEvent?.let { sendTouch("longPress", it) }
            }
        }
        init {
            setZOrderOnTop(true)
            holder.setFormat(PixelFormat.TRANSLUCENT)
            holder.addCallback(this)
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            isFocusable = false
        }
        override fun surfaceCreated(holder: SurfaceHolder) { surfaceReady = true; worker.post { node.surfaceChanged(true) } }
        override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) { worker.post { node.surfaceChanged(true) } }
        override fun surfaceDestroyed(holder: SurfaceHolder) { surfaceReady = false; worker.post { node.surfaceChanged(false) } }

        private fun sendTouch(type: String, e: MotionEvent, extra: Map<String, Any?> = emptyMap()) {
            val state = hit ?: return
            val flutter = flutterView() ?: return
            val location = IntArray(2)
            flutter.getLocationOnScreen(location)
            event(animationId, type, mapOf(
                "localX" to e.x - state.offset.x - state.origin.x,
                "localY" to e.y - state.offset.y - state.origin.y,
                "globalX" to e.rawX - location[0], "globalY" to e.rawY - location[1],
            ) + extra)
        }
        // The Flutter pet owns semantics and accessibility actions; this view handles physical touches only.
        @SuppressLint("ClickableViewAccessibility")
        override fun onTouchEvent(e: MotionEvent): Boolean {
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    val h = hit ?: return false
                    if (!acceptsTouch || !h.clip.contains(e.x, e.y) || !h.rect.contains(e.x - h.offset.x, e.y - h.offset.y)) return false
                    held = true; dragging = false; longPressed = false
                    downX = e.rawX; downY = e.rawY; lastX = downX; lastY = downY
                    downEvent?.recycle(); downEvent = MotionEvent.obtain(e)
                    velocity = VelocityTracker.obtain().also { it.addMovement(e) }
                    main.postDelayed(longPress, ViewConfiguration.getLongPressTimeout().toLong())
                    return true
                }
                MotionEvent.ACTION_MOVE -> {
                    if (!held) return false
                    velocity?.addMovement(e)
                    if (!longPressed && !dragging && (abs(e.rawX - downX) > slop || abs(e.rawY - downY) > slop)) {
                        dragging = true; main.removeCallbacks(longPress)
                        sendTouch("dragStart", e)
                    }
                    if (dragging) sendTouch("dragUpdate", e, mapOf("deltaX" to e.rawX - lastX, "deltaY" to e.rawY - lastY))
                    lastX = e.rawX; lastY = e.rawY
                    return true
                }
                MotionEvent.ACTION_UP -> {
                    if (!held) return false
                    main.removeCallbacks(longPress)
                    velocity?.addMovement(e)
                    if (dragging) {
                        velocity?.computeCurrentVelocity(1000)
                        sendTouch("dragEnd", e, mapOf("velocityX" to (velocity?.xVelocity ?: 0f), "velocityY" to (velocity?.yVelocity ?: 0f)))
                    } else if (!longPressed) sendTouch("tap", e)
                    finishTouch()
                    return true
                }
                MotionEvent.ACTION_POINTER_DOWN, MotionEvent.ACTION_CANCEL -> { val consumed = held; cancelTouch(); return consumed }
            }
            return held
        }
        fun cancelTouch() { if (held) event(animationId, "cancel"); finishTouch() }
        private fun finishTouch() {
            main.removeCallbacks(longPress)
            held = false; dragging = false
            downEvent?.recycle(); downEvent = null
            velocity?.recycle(); velocity = null
        }
    }

    private inner class Node(private val layer: Layer) {
        private var scene: AnimationScene? = null
        private var kind: String? = null
        private var disposed = false
        private var foreground = false
        private var paused = false
        private var active = false
        private var accumulated = 0L
        private var started = 0L
        private var playbackAt = 0L
        private var alpha = 1f
        private var clip = RectF()
        private var hitRect: RectF? = null
        private var origin = MotionPoint(0f, 0f)
        private var motion: SpriteMotion? = null
        private var motionAt = 0L
        private var motionFinished = false
        private var ended = false
        private var ready = false
        private var playbackSerial: Any? = null
        private var draws = 0L
        private val tick = Runnable { draw() }
        private fun elapsed(now: Long = SystemClock.uptimeMillis()) = accumulated + if (active) now - started else 0L

        fun configure(config: Map<*, *>, activeWindow: Boolean) {
            if (disposed) return
            worker.removeCallbacks(tick)
            val nextKind = config["kind"] as String
            if (nextKind != kind) {
                scene?.close()
                scene = null
                scene = when (nextKind) {
                    "sprite" -> SpriteScene(activity.applicationContext)
                    "dot" -> DotScene()
                    "whale" -> WhaleScene(activity.applicationContext)
                    else -> error("Unknown native animation kind")
                }
                kind = nextKind
                accumulated = 0; started = SystemClock.uptimeMillis()
                playbackAt = 0; motion = null
                ready = false; ended = false
            }
            scene!!.configure(config)
            val sprite = scene as? SpriteScene
            if (sprite?.restarted == true) {
                playbackAt = elapsed()
                ready = false; ended = false
            }
            playbackSerial = config["playbackSerial"]
            // PetStage initially hides the sprite until onShown: decoding, not visibility, releases it.
            if (sprite != null && !ready) { ready = true; event(layer.animationId, "ready", mapOf("playbackSerial" to playbackSerial)) }
            alpha = config.number("alpha", 1.0).toFloat().coerceIn(0f, 1f)
            val c = config["clip"] as? List<*>
            clip = if (c == null) RectF(0f, 0f, config.number("width").toFloat(), config.number("height").toFloat())
                else RectF((c[0] as Number).toFloat(), (c[1] as Number).toFloat(), (c[2] as Number).toFloat(), (c[3] as Number).toFloat())
            hitRect = if (config["hitRect"] == null) null else config.rect("hitRect")
            origin = if (config["contentOrigin"] == null) MotionPoint(0f, 0f) else config.point("contentOrigin")
            val m = config["motion"] as? Map<*, *>
            var newMotion = false
            if (m == null) { motion = null; motionFinished = false }
            else if (motion?.serial != m["serial"]) {
                motion = SpriteMotion(m["serial"], m["kind"] as String, m.number("durationMs").toLong(), m.point("from"), m.point("to"), m.number("height").toFloat())
                motionAt = elapsed(); motionFinished = false; newMotion = true
            }
            paused = config.flag("paused")
            foreground = activeWindow
            val changed = updateActive()
            if (newMotion && !changed) sendMotionClock()
            draw()
        }
        fun setForeground(value: Boolean) { foreground = value; updateActive(); draw() }
        fun surfaceChanged(available: Boolean) {
            if (disposed) return
            if (!available) ready = false
            updateActive(); draw()
        }
        private fun updateActive(): Boolean {
            val next = !disposed && foreground && layer.surfaceReady && !paused
            if (next == active) return false
            val now = SystemClock.uptimeMillis()
            if (active) accumulated += now - started else started = now
            active = next
            if (!active) worker.removeCallbacks(tick)
            sendMotionClock()
            return true
        }
        private fun sendMotionClock() {
            val m = motion ?: return
            if (!motionFinished) event(layer.animationId, "motionClock", mapOf("serial" to m.serial, "elapsedMs" to (elapsed() - motionAt).coerceAtLeast(0), "active" to active))
        }
        fun stop() { foreground = false; updateActive() }
        private fun draw() {
            worker.removeCallbacks(tick)
            if (disposed || !foreground || !layer.surfaceReady || scene == null) return
            val t = elapsed()
            val sceneTime = t - playbackAt
            val m = motion
            val offset = m?.point(t - motionAt) ?: MotionPoint(0f, 0f)
            layer.hit = hitRect?.let { Hit(RectF(it), RectF(clip), origin, offset) }
            try {
                val canvas = layer.holder.lockCanvas() ?: return
                try {
                    canvas.drawColor(Color.TRANSPARENT, PorterDuff.Mode.CLEAR)
                    canvas.save()
                    canvas.clipRect(clip)
                    canvas.translate(offset.x, offset.y)
                    scene!!.draw(canvas, sceneTime, alpha)
                    canvas.restore()
                } finally { layer.holder.unlockCanvasAndPost(canvas) }
            } catch (_: IllegalStateException) {
                if (layer.surfaceReady) failSurface()
                return
            } catch (_: IllegalArgumentException) {
                if (layer.surfaceReady) failSurface()
                return
            }
            draws++
            if (!ready) { ready = true; event(layer.animationId, "ready", mapOf("playbackSerial" to playbackSerial)) }
            if (!ended && scene!!.ended(sceneTime)) { ended = true; event(layer.animationId, "ended", mapOf("playbackSerial" to playbackSerial)) }
            if (m != null && !motionFinished && t - motionAt >= m.duration) {
                motionFinished = true
                event(layer.animationId, "motionEnd", mapOf("serial" to m.serial))
            }
            if (active) {
                val delay = scene!!.nextDelay(sceneTime)
                val motionDelay = if (m != null && !motionFinished) continuousDelay(t - motionAt) else null
                val next = listOfNotNull(delay, motionDelay).minOrNull()
                if (next != null) worker.postAtTime(tick, SystemClock.uptimeMillis() + (next - (elapsed() - t)).coerceAtLeast(1))
            }
        }
        private fun failSurface() {
            stop()
            main.post { if (layers[layer.animationId] === layer) { layer.cancelTouch(); layer.visibility = View.INVISIBLE } }
            event(layer.animationId, "error", mapOf("code" to "native_animation_surface", "message" to "Native animation surface could not be drawn"))
        }
        fun dispose() { if (disposed) return; disposed = true; worker.removeCallbacks(tick); scene?.close(); scene = null; layer.hit = null }
        fun metrics(): Map<String, Any?> = mapOf("id" to layer.animationId, "kind" to kind, "draws" to draws, "elapsedMs" to elapsed(), "active" to active, "ready" to ready)
    }
}
